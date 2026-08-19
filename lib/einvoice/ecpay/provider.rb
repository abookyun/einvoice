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
        assert_twd!(parsed.currency)
        data = Payload.issue(parsed, validate: @validate_payload)
        result = @client.request("/B2CInvoice/Issue", data)

        IssueInvoiceResult.new(
          invoice_number: result["InvoiceNo"].to_s,
          invoice_date: parse_time(result["InvoiceDate"]),
          random_code: result["RandomNumber"].to_s,
          order_id: parsed.order_id,
          total_amount: parsed.amount.total_amount,
          status: InvoiceStatus::ISSUED,
          raw: result
        )
      end

      # 作廢發票. ECPay keys the void on the invoice's own issue date, which the
      # unified input does not carry — it defaults to today (Asia/Taipei). For an
      # older invoice pass <tt>provider_options: { invoice_date: "2026-08-01" }</tt>.
      #
      # An invoice with a live 折讓 cannot be voided (+:void_blocked_by_allowance+);
      # void the allowance first.
      def void(input)
        parsed = Input.void(input, provider: name)
        Payload.check_reason!(parsed.reason, "Reason") if @validate_payload
        options = Payload.string_keys(parsed.provider_options)

        result = @client.request("/B2CInvoice/Invalid", {
                                   "InvoiceNo" => parsed.invoice_number,
                                   "InvoiceDate" => options["invoice_date"] || taipei_date(parsed.date),
                                   "Reason" => parsed.reason
                                 })
        VoidInvoiceResult.new(invoice_number: parsed.invoice_number,
                              status: InvoiceStatus::VOIDED, raw: result)
      end

      # 開立折讓 (紙本). Returns the 折讓單號 immediately; it can be voided right away.
      # Defaults to notifying nobody — pass
      # <tt>provider_options: { allowance_notify: "E", notify_mail: "..." }</tt> to
      # have ECPay tell the buyer (S 簡訊 / E 信箱 / A 兩者 / N 不通知).
      def allowance(input)
        parsed = Input.allowance(input, provider: name)
        options = Payload.string_keys(parsed.provider_options)

        result = @client.request("/B2CInvoice/Allowance", {
                                   "InvoiceNo" => parsed.invoice_number,
                                   "InvoiceDate" => options["invoice_date"] || taipei_date(parsed.date),
                                   "AllowanceNotify" => options["allowance_notify"] || "N",
                                   "CustomerName" => options["customer_name"],
                                   "NotifyMail" => options["notify_mail"],
                                   "NotifyPhone" => options["notify_phone"],
                                   "AllowanceAmount" => parsed.amount.total_amount,
                                   "Reason" => options["reason"],
                                   "Items" => Payload.items(parsed.items)
                                 }.compact)

        AllowanceResult.new(
          allowance_number: result["IA_Allow_No"].to_s,
          invoice_number: result["IA_Invoice_No"] || parsed.invoice_number,
          allowance_date: parse_time(result["IA_Date"]),
          total_amount: parsed.amount.total_amount,
          raw: result
        )
      end

      # 作廢折讓. Voids one 折讓單, not the invoice.
      def void_allowance(input)
        parsed = Input.void_allowance(input, provider: name)
        reason = parsed.reason || "作廢折讓"
        Payload.check_reason!(reason, "Reason") if @validate_payload

        result = @client.request("/B2CInvoice/AllowanceInvalid", {
                                   "InvoiceNo" => parsed.invoice_number,
                                   "AllowanceNo" => parsed.allowance_number,
                                   "Reason" => reason
                                 })
        VoidAllowanceResult.new(allowance_number: parsed.allowance_number, raw: result)
      end

      # 查詢發票. Looks up by 自訂編號 when given an +order_id+, otherwise by invoice
      # number — which ECPay pairs with the issue date, defaulting to today
      # (Asia/Taipei). For an older invoice either query by +order_id+ or pass
      # <tt>provider_options: { invoice_date: "2026-08-01" }</tt>.
      def query(input)
        parsed = Input.query(input, provider: name)
        options = Payload.string_keys(parsed.provider_options)
        order_id = parsed.order_id || options["relate_number"]

        data = if order_id
                 { "RelateNumber" => order_id }
               else
                 { "InvoiceNo" => parsed.invoice_number,
                   "InvoiceDate" => options["invoice_date"] || taipei_date }
               end
        result = @client.request("/B2CInvoice/GetIssue", data)
        build_query_result(result, parsed)
      end

      # 手機條碼驗證 — whether a 手機條碼 is registered with the tax authority.
      def validate_mobile_barcode(barcode)
        if @validate_payload && !barcode.to_s.match?(%r{\A/[0-9A-Z.+-]{7}\z})
          raise ValidationError.new("Invalid mobile barcode: #{barcode.inspect}", provider: name)
        end

        @client.request("/B2CInvoice/CheckBarcode", { "BarCode" => barcode })["IsExist"] == "Y"
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

      # ECPay's B2C API files everything in TWD and has no foreign-currency field,
      # so refuse rather than silently dropping the annotation.
      def assert_twd!(currency)
        return if currency.nil? || currency == "TWD"

        assert_supports!(Capability::FOREIGN_CURRENCY)
      end

      def build_query_result(result, parsed)
        total = result["IIS_Sales_Amount"].to_i
        tax = result["IIS_Tax_Amount"].to_i

        QueryInvoiceResult.new(
          invoice_number: result["IIS_Number"] || parsed.invoice_number.to_s,
          invoice_date: parse_time(result["IIS_Create_Date"]),
          random_code: result["IIS_Random_Number"].to_s,
          order_id: result["IIS_Relate_Number"] || parsed.order_id,
          status: derive_status(result),
          amount: AmountSummary.new(sales_amount: total - tax, tax_amount: tax,
                                    total_amount: total),
          buyer: build_buyer(result),
          items: build_items(result["Items"]),
          raw: result
        )
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

      # ECPay dates are Taipei-local, so format in +08:00 rather than the host's
      # zone. A string is taken as already-formatted and passed through.
      def taipei_date(date = nil)
        return date if date.is_a?(String)

        time = date.respond_to?(:to_time) ? date.to_time : date
        (time || Time.now).getlocal("+08:00").strftime("%Y-%m-%d")
      end
    end
  end
end
