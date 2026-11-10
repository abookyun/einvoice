# frozen_string_literal: true

require "set"

module Einvoice
  module ECPay
    # {Einvoice::Provider} over ECPay's (綠界科技) B2C 電子發票 2.0 API.
    #
    #   provider = Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX)
    #   result = provider.issue(order_id: "ORDER_1", ...)
    #
    # Credentials are per-instance, so a multi-merchant application holds one
    # provider per merchant. +mode+ selects the stage (+:test+) or live
    # (+:production+) host.
    #
    # Only the five unified operations plus carrier validation are mapped. ECPay
    # has ~25 further B2C endpoints (延遲開立, 字軌設定, 列印, 通知 …); reach those
    # through {#raw}, which handles the envelope and error mapping for any path.
    class Provider < ::Einvoice::Provider
      CAPABILITIES = Set[
        Capability::ISSUE,
        Capability::VOID,
        Capability::ALLOWANCE,
        Capability::VOID_ALLOWANCE,
        Capability::QUERY,
        Capability::B2B,
        Capability::MIXED_TAX,
        Capability::QUERY_BY_ORDER_ID,
        Capability::CARRIER_VALIDATION
      ].freeze

      # ECPay ItemTaxType → unified 課稅別, for reading a queried invoice back.
      TAX_CODE_TO_TYPE = Payload::TAX_TYPE.invert.freeze
      # The only rate ECPay applies to a taxable line.
      TAXABLE_RATE = Rational(5, 100)

      attr_reader :capabilities, :client

      # @param merchant_id [String] 特店編號
      # @param hash_key [String] 16-byte AES HashKey — server-side only
      # @param hash_iv [String] 16-byte AES HashIV — server-side only
      # @param mode [Symbol] +:test+ (stage) or +:production+
      # @param base_url [String, nil] override the host, e.g. in tests
      # @param timeout [Integer] open/read timeout in seconds
      # @param validate_payload [Boolean] check field rules locally before sending
      def initialize(merchant_id:, hash_key:, hash_iv:, mode: ProviderMode::TEST,
                     base_url: nil, timeout: 30, validate_payload: true)
        super()
        @client = Client.new(merchant_id: merchant_id, hash_key: hash_key, hash_iv: hash_iv,
                             mode: mode, base_url: base_url, timeout: timeout)
        @validate_payload = validate_payload
        @capabilities = CAPABILITIES
      end

      def name
        Client::PROVIDER
      end

      # Call any B2C endpoint with a raw Data payload — the envelope, encryption
      # and error mapping are applied as usual:
      #
      #   provider.raw("/B2CInvoice/InvoicePrint", { "InvoiceNo" => "LA25000001" })
      #
      # Brace the payload: an unbraced hash would be read as this method's own
      # keyword arguments.
      def raw(path, data, success_codes: [], plain_data: false)
        @client.request(path, data, success_codes: success_codes, plain_data: plain_data)
      end

      # 開立發票.
      def issue(input)
        parsed = Input.issue(input, provider: name)
        assert_currency_supported!(parsed.currency)
        assert_rate_supported!(parsed)
        data = Payload.issue(parsed, validate: @validate_payload)
        result = @client.request("/B2CInvoice/Issue", data)

        IssueInvoiceResult.new(
          invoice_number: result["InvoiceNo"].to_s,
          invoice_datetime: parse_time(result["InvoiceDate"]),
          random_code: result["RandomNumber"].to_s,
          order_id: parsed.order_id,
          total_amount: parsed.amount.total_amount,
          buyer_ubn: parsed.buyer&.ubn,
          tax_type: TaxType.of(parsed.items, parsed.tax_type),
          tax_rate: parsed.tax_rate,
          status: InvoiceStatus::ISSUED,
          raw: result
        )
      end

      # 作廢發票. ECPay keys the void on the invoice's issue date, so the reference
      # needs invoice_datetime, or an order_id to look it up (see invoice_date).
      #
      # An invoice with a live 折讓 cannot be voided (+:void_blocked_by_allowance+);
      # void the allowance first.
      def void(input)
        parsed = Input.void(input, provider: name)

        result = @client.request("/B2CInvoice/Invalid", {
                                   "InvoiceNo" => parsed.invoice.number,
                                   "InvoiceDate" => invoice_date(parsed.invoice, "void"),
                                   "Reason" => parsed.reason
                                 })
        VoidInvoiceResult.new(invoice_number: parsed.invoice.number,
                              status: InvoiceStatus::VOIDED, raw: result)
      end

      # 開立折讓 (紙本). Returns the 折讓單號 immediately; it can be voided right away.
      # Defaults to notifying nobody — pass
      # <tt>provider_options: { allowance_notify: "E", notify_mail: "..." }</tt> to
      # have ECPay tell the buyer (S 簡訊 / E 信箱 / A 兩者 / N 不通知).
      def allowance(input)
        parsed = Input.allowance(input, provider: name)
        assert_rate_supported!(parsed)
        options = Payload.string_keys(parsed.provider_options)

        data = {
          "InvoiceNo" => parsed.invoice.number,
          "AllowanceNotify" => options["allowance_notify"] || "N",
          "CustomerName" => options["customer_name"],
          "NotifyMail" => options["notify_mail"],
          "NotifyPhone" => options["notify_phone"],
          "AllowanceAmount" => parsed.amount.total_amount,
          "Reason" => options["reason"],
          "Items" => Payload.allowance_items(parsed)
        }.compact
        Payload.check_allowance!(data) if @validate_payload
        data["InvoiceDate"] = invoice_date(parsed.invoice, "allowance")
        result = @client.request("/B2CInvoice/Allowance", data)

        AllowanceResult.new(
          allowance_number: result["IA_Allow_No"].to_s,
          invoice_number: result["IA_Invoice_No"] || parsed.invoice.number,
          allowance_date: parse_time(result["IA_Date"])&.to_date,
          total_amount: parsed.amount.total_amount,
          raw: result
        )
      end

      # 作廢折讓. Voids one 折讓單, not the invoice. ECPay needs the invoice number
      # too, so a plain allowance number is not enough.
      def void_allowance(input)
        parsed = Input.void_allowance(input, provider: name)
        allowance = parsed.allowance
        if allowance.invoice_number.nil?
          raise ValidationError.new("void_allowance needs allowance.invoice_number", provider: name)
        end

        result = @client.request("/B2CInvoice/AllowanceInvalid", {
                                   "InvoiceNo" => allowance.invoice_number,
                                   "AllowanceNo" => allowance.allowance_number,
                                   "Reason" => parsed.reason
                                 })
        VoidAllowanceResult.new(allowance_number: allowance.allowance_number, raw: result)
      end

      # 查詢發票. By 自訂編號 when the reference has an order_id. Otherwise by
      # invoice number, which ECPay pairs with the issue date.
      def query(input)
        reference = Input.query(input, provider: name).invoice
        if reference.order_id
          assert_supports!(Capability::QUERY_BY_ORDER_ID)
          return query_by_order_id(reference.order_id)
        end

        if reference.invoice_datetime.nil?
          raise ValidationError.new("query by number needs invoice.invoice_datetime", provider: name)
        end

        result = @client.request("/B2CInvoice/GetIssue", {
                                   "InvoiceNo" => reference.number,
                                   "InvoiceDate" => format_date(reference.invoice_datetime)
                                 })
        build_query_result(result, reference)
      end

      # Whether a carrier is registered. ECPay can check a 手機條碼 only.
      def validate_carrier(carrier)
        parsed = Input.carrier(carrier, provider: name)
        unless parsed.type == CarrierType::MOBILE_BARCODE
          raise UnsupportedError.new("ECPay can check a mobile barcode only, not #{parsed.type}", provider: name)
        end

        @client.request("/B2CInvoice/CheckBarcode", { "BarCode" => parsed.code })["IsExist"] == "Y"
      end

      # 愛心碼驗證 — whether a donation code is registered.
      def validate_love_code(love_code)
        !love_code_organ_name(love_code).nil?
      end

      # The receiving organisation's name for a 愛心碼, or +nil+ when unregistered.
      def love_code_organ_name(love_code)
        if @validate_payload && !love_code.to_s.match?(/\A\d{3,7}\z/)
          raise ValidationError.new("Invalid love code: #{love_code.inspect}", provider: name)
        end

        result = @client.request("/B2CInvoice/CheckLoveCode", { "LoveCode" => love_code })
        return nil unless result["IsExist"] == "Y"

        name = result["OrganName"].to_s
        name.empty? ? nil : name
      end

      private

      # ECPay fixes the rate by TaxType. A taxable line is always 5%.
      def assert_rate_supported!(parsed)
        taxable = parsed.items.any? { |item| (item.tax_type || parsed.tax_type) == TaxType::TAXABLE }
        return unless taxable && parsed.tax_rate != TAXABLE_RATE

        raise UnsupportedError.new("ECPay taxes a taxable invoice at 0.05 only, got #{parsed.tax_rate.to_f}",
                                   provider: name)
      end

      def build_query_result(result, reference)
        total = result["IIS_Sales_Amount"].to_i
        tax = result["IIS_Tax_Amount"].to_i
        items = build_items(result["Items"])
        tax_type = items.empty? ? nil : TaxType.of(items, nil)

        QueryInvoiceResult.new(
          invoice_number: result["IIS_Number"] || reference.number.to_s,
          invoice_datetime: parse_time(result["IIS_Create_Date"]),
          random_code: result["IIS_Random_Number"].to_s,
          order_id: result["IIS_Relate_Number"] || reference.order_id,
          status: derive_status(result),
          amount: AmountSummary.new(sales_amount: total - tax, tax_amount: tax,
                                    total_amount: total),
          buyer: build_buyer(result),
          items: items,
          tax_type: tax_type,
          tax_rate: query_rate(tax_type, result["IIS_Tax_Rate"]),
          raw: result
        )
      end

      # ECPay fixes the rate of a taxable, zero-rated or tax-free invoice. A
      # special-tax invoice has its own rate, which GetIssue returns. A rate
      # that is not a MIG rate reads as nil, so an allowance has to give one.
      def query_rate(tax_type, reported)
        case tax_type
        when TaxType::TAXABLE, TaxType::MIXED then TAXABLE_RATE
        when TaxType::ZERO_RATED, TaxType::TAX_FREE then 0r
        when TaxType::SPECIAL
          begin
            Input.mig_rate!(reported, "IIS_Tax_Rate", name)
          rescue ValidationError
            nil
          end
        end
      end

      def build_buyer(result)
        Buyer.new(
          name: presence(result["IIS_Customer_Name"]),
          # ECPay fills a B2C invoice's 統編 with a zero placeholder.
          ubn: presence(result["IIS_Identifier"], placeholder: "0000000000"),
          email: presence(result["IIS_Customer_Email"]),
          address: presence(result["IIS_Customer_Addr"]),
          phone: presence(result["IIS_Customer_Phone"])
        )
      end

      def build_items(rows)
        Array(rows).map do |row|
          InvoiceItem.new(
            description: row["ItemName"].to_s,
            quantity: numeric(row["ItemCount"]),
            unit_price: numeric(row["ItemPrice"]),
            amount: numeric(row["ItemAmount"]),
            unit: presence(row["ItemWord"]),
            tax_type: TAX_CODE_TO_TYPE[row["ItemTaxType"].to_s],
            remark: presence(row["ItemRemark"])
          )
        end
      end

      # ECPay reports the lifecycle across two fields: an explicit void flag, and
      # the remaining creditable amount falling below the sales total once a 折讓
      # exists.
      def derive_status(result)
        # 註銷 (cancelled) has no unified status.
        return nil if result["IIS_Issue_Status"].to_s == "0"
        return InvoiceStatus::VOIDED if result["IIS_Invalid_Status"].to_s == "1"

        sales = result["IIS_Sales_Amount"].to_i
        remaining = result.fetch("IIS_Remain_Allowance_Amt", sales).to_i
        return InvoiceStatus::ALLOWANCE if sales.positive? && remaining < sales

        InvoiceStatus::ISSUED
      end

      # ECPay returns amounts as JSON numbers; keep integers integral.
      def numeric(value)
        float = value.to_f
        float == float.to_i ? float.to_i : float
      end

      def presence(value, placeholder: nil)
        string = value.to_s
        string.empty? || string == placeholder ? nil : string
      end

      # "2026-08-15 23:02:23" (Asia/Taipei) → Time. Falls back to nil so a missing
      # date never masquerades as "now".
      def parse_time(value)
        match = /\A(\d{4})[-\/](\d{2})[-\/](\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?/.match(value.to_s.strip)
        return nil unless match

        year, month, day, hour, minute, second = match.captures
        Time.new(year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i, second.to_i, "+08:00")
      end

      def query_by_order_id(order_id)
        result = @client.request("/B2CInvoice/GetIssue", { "RelateNumber" => order_id })
        build_query_result(result, InvoiceReference.new(order_id: order_id))
      end

      # The issue date that Invalid, Allowance and GetIssue ask for. Taken from the
      # reference, else looked up by order id. A failed lookup is the provider's
      # error, not the invoice's: a NotFoundError would read as "the invoice of
      # this call does not exist".
      def invoice_date(reference, operation)
        return format_date(reference.invoice_datetime) if reference.invoice_datetime

        if reference.order_id.nil?
          raise ValidationError.new("#{operation} needs invoice.invoice_datetime, or invoice.order_id to look it up",
                                    provider: name)
        end

        found = begin
          query_by_order_id(reference.order_id)
        rescue Error => e
          raise ProviderError.new("#{operation} needs invoice.invoice_datetime; looking it up by order id failed: " \
                                  "#{e.message}", provider: name, reason: Reason::LOOKUP_FAILED, cause: e)
        end
        if found.invoice_datetime.nil?
          raise ProviderError.new("#{operation} needs invoice.invoice_datetime; the invoice found by order id has " \
                                  "no issue date", provider: name, reason: Reason::LOOKUP_FAILED)
        end
        format_date(found.invoice_datetime)
      end

      # ECPay dates are Taipei-local.
      def format_date(time)
        Taipei.date(time, provider: name).strftime("%Y-%m-%d")
      end
    end
  end
end
