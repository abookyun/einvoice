# frozen_string_literal: true

require "set"

module Einvoice
  module Amego
    # {Einvoice::Provider} over Amego 光貿's JSON API, with 自動配號: Amego picks
    # the invoice number.
    #
    # docs/providers/amego/api.md describes the API and the choices below.
    #
    # Two behaviours to know:
    #
    # - A void is queued. Amego accepts it at once, but a query right after it
    #   can still report the invoice as issued.
    # - An allowance needs the original invoice's buyer and date. The reference
    #   has the date and the 統一編號, but not the buyer's name, so the adapter
    #   queries the invoice for it, unless +provider_options+ gives +buyer_name+
    #   and the reference has +invoice_datetime+. The query only works within
    #   180 days.
    class Provider < ::Einvoice::Provider
      CAPABILITIES = Set[
        Capability::ISSUE,
        Capability::VOID,
        Capability::ALLOWANCE,
        Capability::VOID_ALLOWANCE,
        Capability::QUERY,
        Capability::QUERY_BY_ORDER_ID,
        Capability::B2B,
        Capability::MIXED_TAX,
        Capability::CARRIER_VALIDATION
      ].freeze

      # The barcode code for a mobile barcode that is not registered.
      UNREGISTERED_BARCODE = "9000113"

      VOID_TYPES = %w[C0501 A0501 A0201 A0202].freeze
      ISSUE_TYPES = %w[C0401 A0401 A0101 A0102].freeze
      LIVE_ALLOWANCE_TYPES = %w[D0401 G0401 B0401 B0101 B0102].freeze

      attr_reader :capabilities, :client

      def initialize(ban:, app_key:, base_url: Client::BASE_URL, timeout: 30, clock: -> { Time.now })
        super()
        @client = Client.new(ban: ban, app_key: app_key, base_url: base_url, timeout: timeout, clock: clock)
        @clock = clock
        @capabilities = CAPABILITIES
      end

      def name
        Client::PROVIDER
      end

      # Call any Amego path with a raw payload, for example
      #
      #   provider.raw("/json/barcode", { barCode: "/ABC1234" })
      #
      # The signing and the error mapping are applied as usual. Brace the Hash:
      # an unbraced one is read as keyword arguments.
      def raw(path, payload)
        @client.request(path, payload)
      end

      # 開立發票 (+f0401+).
      def issue(input)
        parsed = Input.issue(input, provider: name)
        assert_currency_supported!(parsed.currency)
        result = @client.request("/json/f0401", Payload.issue(parsed))

        IssueInvoiceResult.new(
          invoice_number: result["invoice_number"].to_s,
          invoice_datetime: unix_time(result["invoice_time"]),
          random_code: result["random_number"].to_s,
          order_id: parsed.order_id,
          total_amount: parsed.amount.total_amount,
          buyer_ubn: parsed.buyer&.ubn,
          tax_type: TaxType.of(parsed.items, parsed.tax_type),
          tax_rate: parsed.tax_rate,
          status: InvoiceStatus::ISSUED,
          raw: result
        )
      end

      # 作廢發票 (+f0501+). The void is queued: see the class comment.
      def void(input)
        parsed = Input.void(input, provider: name)
        result = @client.request("/json/f0501", Payload.void(parsed))
        VoidInvoiceResult.new(invoice_number: parsed.invoice.number, status: InvoiceStatus::VOIDED, raw: result)
      end

      # 開立折讓 (+g0401+). The seller assigns the allowance number, so the
      # result's +allowance_number+ is the input's +allowance_id+. The allowance
      # date is today in Taipei.
      def allowance(input)
        parsed = Input.allowance(input, provider: name)
        allowance_date = Taipei.date(@clock.call)
        data = Payload.allowance(parsed, original_invoice(parsed), allowance_date)
        result = @client.request("/json/g0401", data)

        AllowanceResult.new(
          allowance_number: parsed.allowance_id.to_s,
          invoice_number: parsed.invoice.number,
          allowance_date: allowance_date,
          total_amount: parsed.amount.total_amount,
          raw: result
        )
      end

      # 作廢折讓 (+g0501+). Amego takes no reason here.
      def void_allowance(input)
        parsed = Input.void_allowance(input, provider: name)
        result = @client.request("/json/g0501", Payload.void_allowance(parsed))
        VoidAllowanceResult.new(allowance_number: parsed.allowance.allowance_number, raw: result)
      end

      # 查詢發票 (+invoice_query+), by order id when the reference has one, else
      # by invoice number. Within 180 days of the invoice.
      def query(input)
        reference = Input.query(input, provider: name).invoice
        assert_supports!(Capability::QUERY_BY_ORDER_ID) if reference.order_id
        build_query_result(fetch_invoice(Payload.query(reference)))
      end

      # Whether a carrier is registered (+barcode+). Amego can check a 手機條碼
      # only. For a donation code, use {Einvoice::MOF::DonationCodes}.
      def validate_carrier(carrier)
        parsed = Input.carrier(carrier, provider: name)
        unless parsed.type == CarrierType::MOBILE_BARCODE
          raise UnsupportedError.new("Amego can check a mobile barcode only, not #{parsed.type}", provider: name)
        end

        begin
          @client.request("/json/barcode", { "barCode" => parsed.code })
        rescue Error => e
          return false if e.raw_code == UNREGISTERED_BARCODE

          raise
        end
        true
      end

      private

      def fetch_invoice(payload)
        data = @client.request("/json/invoice_query", payload)["data"]
        return data if data.is_a?(Hash)

        raise ProviderError.new("Amego returned no invoice data", provider: name, raw: data)
      end

      # The original invoice's buyer and date (docs, section 4.1). The reference
      # has the date and the 統一編號. The buyer's name comes from
      # +provider_options+, else from a query. A failed query is the provider's
      # error, not the invoice's: a NotFoundError would read as "the invoice of
      # this call does not exist".
      def original_invoice(parsed)
        reference = parsed.invoice
        buyer_name = Payload.string_keys(parsed.provider_options)["buyer_name"]
        if buyer_name && reference.invoice_datetime
          return { buyer_identifier: reference.buyer_ubn || Payload::CONSUMER_ID, buyer_name: buyer_name,
                   invoice_datetime: reference.invoice_datetime }
        end

        found = lookup(reference.number)
        if found.invoice_datetime.nil?
          raise ProviderError.new("allowance needs the invoice date; the invoice found by number has none",
                                  provider: name, reason: Reason::LOOKUP_FAILED)
        end
        { buyer_identifier: reference.buyer_ubn || found.buyer.ubn || Payload::CONSUMER_ID,
          buyer_name: buyer_name || found.buyer.name.to_s,
          invoice_datetime: reference.invoice_datetime || found.invoice_datetime }
      end

      def lookup(number)
        build_query_result(fetch_invoice(Payload.query(InvoiceReference.new(number: number))))
      rescue Error => e
        raise ProviderError.new("allowance needs the invoice's buyer and date; looking them up failed: #{e.message}",
                                provider: name, reason: Reason::LOOKUP_FAILED, cause: e)
      end

      def build_query_result(data)
        tax = data["tax_amount"].to_i
        total = data["total_amount"].to_i
        items = Array(data["product_item"]).map { |row| build_item(row) }
        QueryInvoiceResult.new(
          invoice_number: data["invoice_number"].to_s,
          invoice_datetime: taipei_time(data["invoice_date"], data["invoice_time"]),
          random_code: data["random_number"].to_s,
          order_id: presence(data["order_id"]),
          status: status_of(data),
          amount: AmountSummary.new(sales_amount: total - tax, tax_amount: tax, total_amount: total),
          buyer: build_buyer(data),
          items: items,
          tax_type: items.empty? || items.any? { |item| item.tax_type.nil? } ? nil : TaxType.of(items, nil),
          tax_rate: query_rate(data["tax_rate"]),
          raw: data
        )
      end

      # A rate that is not a MIG rate reads as nil, so an allowance has to give
      # one.
      def query_rate(reported)
        Input.mig_rate!(reported, "tax_rate", name)
      rescue ValidationError
        nil
      end

      # docs, section 4.4. A cancelled (+C0701+) or rejected (+A0301+, +A0302+)
      # invoice has no unified status, so it is nil. The raw type stays in
      # +raw["invoice_type"]+.
      def status_of(data)
        type = data["invoice_type"].to_s
        return InvoiceStatus::VOIDED if VOID_TYPES.include?(type)
        return nil unless ISSUE_TYPES.include?(type)

        live = Array(data["allowance"]).any? { |row| LIVE_ALLOWANCE_TYPES.include?(row["invoice_type"].to_s) }
        live ? InvoiceStatus::ALLOWANCE : InvoiceStatus::ISSUED
      end

      def build_buyer(data)
        id = data["buyer_identifier"].to_s
        Buyer.new(name: presence(data["buyer_name"]),
                  ubn: id.empty? || id == Payload::CONSUMER_ID ? nil : id,
                  email: presence(data["buyer_email_address"]),
                  address: presence(data["buyer_address"]),
                  phone: presence(data["buyer_telephone_number"]))
      end

      def build_item(row)
        InvoiceItem.new(
          description: row["description"].to_s,
          quantity: numeric(row["quantity"]),
          unit_price: numeric(row["unit_price"]),
          amount: numeric(row["amount"]),
          unit: presence(row["unit"]),
          tax_type: Payload::TAX_TYPE.invert[row["tax_type"].to_s],
          remark: presence(row["remark"])
        )
      end

      # Keep whole numbers integral.
      def numeric(value)
        rational = value.to_s.to_r
        rational.denominator == 1 ? rational.to_i : rational.to_f
      end

      def presence(value)
        string = value.to_s
        string.empty? ? nil : string
      end

      def unix_time(value)
        seconds = Integer(value.to_s, exception: false)
        seconds && Time.at(seconds).getlocal("+08:00")
      end

      # "20221201" and "09:56:38" (UTC+8) → Time, or nil without a date.
      def taipei_time(date, time)
        match = /\A(\d{4})(\d{2})(\d{2})\z/.match(date.to_s)
        return nil unless match

        hour, minute, second = time.to_s.split(":").map(&:to_i)
        Time.new(*match.captures.map(&:to_i), hour.to_i, minute.to_i, second.to_i, "+08:00")
      end
    end
  end
end
