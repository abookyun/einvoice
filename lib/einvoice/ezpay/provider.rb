# frozen_string_literal: true

require "set"

module Einvoice
  module EzPay
    # {Einvoice::Provider} over ezPay 簡單行動支付's e-invoice API (the 標準版
    # manual, EZP_INVI 1.2.2).
    #
    # **Experimental.** It is built from docs/providers/ezpay/invoice.md alone.
    # ezPay has no shared test account, and nobody has run this adapter against
    # ezPay yet. Test it against your own test shop first.
    #
    # ezPay needs facts that the unified inputs do not carry:
    #
    # - A query needs a second key: <tt>provider_options: { random_code: }</tt>
    #   with an invoice number, or <tt>{ total_amount: }</tt> with an order id.
    #   Both are in the {IssueInvoiceResult}.
    # - An allowance needs the invoice's order id:
    #   <tt>provider_options: { order_id: }</tt>.
    #
    # An invoice can only be voided after ezPay uploads it, which happens the
    # next day.
    class Provider < ::Einvoice::Provider
      CAPABILITIES = Set[
        Capability::ISSUE,
        Capability::VOID,
        Capability::ALLOWANCE,
        Capability::VOID_ALLOWANCE,
        Capability::QUERY,
        Capability::B2B,
        Capability::MIXED_TAX
      ].freeze

      VERSION = { issue: "1.5", allowance: "1.3", query: "1.3", other: "1.0" }.freeze
      STATUS = { "1" => InvoiceStatus::ISSUED, "2" => InvoiceStatus::VOIDED }.freeze

      attr_reader :capabilities, :client

      def initialize(merchant_id:, hash_key:, hash_iv:, mode: ProviderMode::TEST, base_url: nil, timeout: 30)
        super()
        @client = Client.new(merchant_id: merchant_id, hash_key: hash_key, hash_iv: hash_iv, mode: mode,
                             base_url: base_url, timeout: timeout)
        @capabilities = CAPABILITIES
      end

      def name
        Client::PROVIDER
      end

      # Call any ezPay path with raw fields, for example
      #
      #   provider.raw("/Api/invoice_touch_issue", "1.0", { InvoiceTransNo: "…", … })
      #
      # The encryption and the error mapping are applied as usual. Brace the
      # Hash: an unbraced one is read as keyword arguments.
      def raw(path, version, fields)
        @client.request(path, version, fields)
      end

      # 開立發票 (+invoice_issue+, issued now).
      def issue(input)
        parsed = Input.issue(input, provider: name)
        assert_currency_supported!(parsed.currency)
        result = @client.request("/Api/invoice_issue", VERSION[:issue], Payload.issue(parsed), operation: :issue)
        @client.verify_check_code!(result)

        IssueInvoiceResult.new(
          invoice_number: result["InvoiceNumber"].to_s,
          invoice_date: taipei_time(result["CreateTime"]),
          random_code: result["RandomNum"].to_s,
          order_id: result["MerchantOrderNo"].to_s,
          total_amount: result["TotalAmt"].to_i,
          status: InvoiceStatus::ISSUED,
          raw: result
        )
      end

      # 作廢發票 (+invoice_invalid+). Only after the next day's upload.
      def void(input)
        parsed = Input.void(input, provider: name)
        result = @client.request("/Api/invoice_invalid", VERSION[:other], Payload.void(parsed), operation: :void)
        VoidInvoiceResult.new(invoice_number: result.fetch("InvoiceNumber", parsed.invoice_number).to_s,
                              status: InvoiceStatus::VOIDED, raw: result)
      end

      # 開立折讓 (+allowance_issue+, confirmed now). ezPay assigns the
      # allowance number, so +allowance_id+ is not sent. The result has no date.
      def allowance(input)
        parsed = Input.allowance(input, provider: name)
        result = @client.request("/Api/allowance_issue", VERSION[:allowance], Payload.allowance(parsed),
                                 operation: :allowance)
        AllowanceResult.new(
          allowance_number: result["AllowanceNo"].to_s,
          invoice_number: result.fetch("InvoiceNumber", parsed.invoice_number).to_s,
          allowance_date: nil,
          total_amount: result["AllowanceAmt"].to_i,
          raw: result
        )
      end

      # 作廢折讓 (+allowanceInvalid+).
      def void_allowance(input)
        parsed = Input.void_allowance(input, provider: name)
        result = @client.request("/Api/allowanceInvalid", VERSION[:other], Payload.void_allowance(parsed),
                                 operation: :void_allowance)
        VoidAllowanceResult.new(allowance_number: result.fetch("AllowanceNo", parsed.allowance_number).to_s,
                                raw: result)
      end

      # 查詢發票 (+invoice_search+). See the class comment for the second key.
      #
      # The result has no allowance data, so +status+ is never +ALLOWANCE+.
      def query(input)
        parsed = Input.query(input, provider: name)
        result = @client.request("/Api/invoice_search", VERSION[:query], Payload.query(parsed), operation: :query)
        @client.verify_check_code!(result)
        build_query_result(result)
      end

      private

      def build_query_result(result)
        QueryInvoiceResult.new(
          invoice_number: result["InvoiceNumber"].to_s,
          invoice_date: taipei_time(result["CreateTime"]),
          random_code: result["RandomNum"].to_s,
          order_id: presence(result["MerchantOrderNo"]),
          status: STATUS[result["InvoiceStatus"].to_s],
          amount: AmountSummary.new(sales_amount: result["Amt"].to_i, tax_amount: result["TaxAmt"].to_i,
                                    total_amount: result["TotalAmt"].to_i),
          buyer: Buyer.new(name: presence(result["BuyerName"]), ubn: presence(result["BuyerUBN"]),
                           email: presence(result["BuyerEmail"]), address: presence(result["BuyerAddress"]),
                           phone: presence(result["BuyerPhone"])),
          items: item_detail(result["ItemDetail"]).map { |row| build_item(row) },
          raw: result
        )
      end

      # +ItemDetail+ is a JSON string inside +Result+.
      def item_detail(value)
        rows = value.is_a?(String) && !value.strip.empty? ? JSON.parse(value) : value
        Array(rows).select { |row| row.is_a?(Hash) }
      rescue JSON::ParserError => e
        raise ProviderError.new("ezPay returned an ItemDetail that is not JSON", provider: name, raw: value,
                                                                               cause: e)
      end

      def build_item(row)
        InvoiceItem.new(
          description: row["ItemName"].to_s,
          quantity: numeric(row["ItemCount"]),
          unit_price: numeric(row["ItemPrice"]),
          amount: numeric(row["ItemAmount"]),
          unit: presence(row["ItemWord"]),
          tax_type: Payload::TAX_TYPE.invert[row["ItemTaxType"].to_s],
          remark: nil
        )
      end

      def numeric(value)
        rational = value.to_s.to_r
        rational.denominator == 1 ? rational.to_i : rational.to_f
      end

      def presence(value)
        string = value.to_s
        string.empty? ? nil : string
      end

      # "2015-11-03 17:58:36" (UTC+8) → Time, or nil.
      def taipei_time(value)
        match = /\A(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\z/.match(value.to_s)
        match && Time.new(*match.captures.map(&:to_i), "+08:00")
      end
    end
  end
end
