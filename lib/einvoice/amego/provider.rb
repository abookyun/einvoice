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
    # - An allowance needs the original invoice's buyer and date, which
    #   {AllowanceInput} does not carry. The adapter queries the invoice for
    #   them, unless +provider_options+ gives +buyer_identifier+, +buyer_name+
    #   and +invoice_date+. The query only works within 180 days.
    class Provider < ::Einvoice::Provider
      CAPABILITIES = Set[
        Capability::ISSUE,
        Capability::VOID,
        Capability::ALLOWANCE,
        Capability::VOID_ALLOWANCE,
        Capability::QUERY,
        Capability::QUERY_BY_ORDER_ID,
        Capability::B2B,
        Capability::MIXED_TAX
      ].freeze

      VOID_TYPES = %w[C0501 A0501 A0201 A0202].freeze
      ISSUE_TYPES = %w[C0401 A0401 A0101 A0102].freeze
      LIVE_ALLOWANCE_TYPES = %w[D0401 G0401 B0401 B0101 B0102].freeze

      attr_reader :capabilities, :client

      def initialize(ban:, app_key:, endpoint: Client::ENDPOINT, timeout: 30, clock: -> { Time.now })
        super()
        @client = Client.new(ban: ban, app_key: app_key, endpoint: endpoint, timeout: timeout, clock: clock)
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
          invoice_date: unix_time(result["invoice_time"]),
          random_code: result["random_number"].to_s,
          order_id: parsed.order_id,
          total_amount: parsed.amount.total_amount,
          status: InvoiceStatus::ISSUED,
          raw: result
        )
      end

      # 作廢發票 (+f0501+). The void is queued: see the class comment.
      def void(input)
        parsed = Input.void(input, provider: name)
        result = @client.request("/json/f0501", Payload.void(parsed))
        VoidInvoiceResult.new(invoice_number: parsed.invoice_number, status: InvoiceStatus::VOIDED, raw: result)
      end

      # 開立折讓 (+g0401+). The seller assigns the allowance number, so the
      # result's +allowance_number+ is the input's +allowance_id+.
      #
      # +AllowanceInput#date+ is not used: the core does not say yet whether it
      # is the allowance date or the invoice date. Pass +allowance_date+ in
      # +provider_options+ to set the allowance date. It defaults to today in
      # Taipei.
      def allowance(input)
        parsed = Input.allowance(input, provider: name)
        options = (parsed.provider_options || {}).to_h.transform_keys(&:to_s)
        allowance_date = options["allowance_date"] || today
        data = Payload.allowance(parsed, original_invoice(parsed.invoice_number, options), allowance_date)
        result = @client.request("/json/g0401", data)

        AllowanceResult.new(
          allowance_number: parsed.allowance_id.to_s,
          invoice_number: parsed.invoice_number,
          allowance_date: taipei_midnight(data.first["AllowanceDate"]),
          total_amount: parsed.amount.total_amount,
          raw: result
        )
      end

      # 作廢折讓 (+g0501+). Amego takes no reason here.
      def void_allowance(input)
        parsed = Input.void_allowance(input, provider: name)
        result = @client.request("/json/g0501", Payload.void_allowance(parsed))
        VoidAllowanceResult.new(allowance_number: parsed.allowance_number, raw: result)
      end

      # 查詢發票 (+invoice_query+), by order id or by invoice number, within 180
      # days of the invoice.
      def query(input)
        parsed = Input.query(input, provider: name)
        build_query_result(fetch_invoice(Payload.query(parsed)))
      end

      private

      def fetch_invoice(payload)
        data = @client.request("/json/invoice_query", payload)["data"]
        return data if data.is_a?(Hash)

        raise ProviderError.new("Amego returned no invoice data", provider: name, raw: data)
      end

      # The original invoice's buyer and date, from +provider_options+ when it
      # has all three, else from a query.
      def original_invoice(invoice_number, options)
        keys = %w[buyer_identifier buyer_name invoice_date]
        if keys.all? { |key| options.key?(key) }
          return keys.to_h { |key| [key.to_sym, options[key]] }
        end

        data = fetch_invoice({ "type" => "invoice", "invoice_number" => invoice_number.to_s })
        { buyer_identifier: data["buyer_identifier"], buyer_name: data["buyer_name"],
          invoice_date: data["invoice_date"] }
      end

      def build_query_result(data)
        tax = data["tax_amount"].to_i
        total = data["total_amount"].to_i
        QueryInvoiceResult.new(
          invoice_number: data["invoice_number"].to_s,
          invoice_date: taipei_time(data["invoice_date"], data["invoice_time"]),
          random_code: data["random_number"].to_s,
          order_id: presence(data["order_id"]),
          status: status_of(data),
          amount: AmountSummary.new(sales_amount: total - tax, tax_amount: tax, total_amount: total),
          buyer: build_buyer(data),
          items: Array(data["product_item"]).map { |row| build_item(row) },
          raw: data
        )
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

      def taipei_midnight(ymd)
        taipei_time(ymd, nil)
      end

      def today
        @clock.call.getlocal("+08:00").strftime("%Y%m%d")
      end
    end
  end
end
