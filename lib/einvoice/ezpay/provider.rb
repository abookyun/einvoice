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
    # ezPay needs facts that a plain invoice number does not carry. The
    # reference from #issue or #query has them:
    #
    # - A query needs the number with +random_code+. ezPay can also find an
    #   invoice by order id, but only with its total, so the adapter does not
    #   declare QUERY_BY_ORDER_ID.
    # - An allowance needs the invoice's +order_id+, and +buyer_ubn+ to pick
    #   prices with or without tax. Without an order id, the adapter queries
    #   the invoice by number first.
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
      # InvoiceStatus 1 is "not voided", with or without an allowance, so it
      # has no unified status (docs, section 4.4).
      STATUS = { "2" => InvoiceStatus::VOIDED }.freeze

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
          invoice_datetime: taipei_time(result["CreateTime"]),
          random_code: result["RandomNum"].to_s,
          order_id: result["MerchantOrderNo"].to_s,
          total_amount: result["TotalAmt"].to_i,
          buyer_ubn: parsed.buyer&.ubn,
          tax_type: TaxType.of(parsed.items, parsed.tax_type),
          tax_rate: parsed.tax_rate,
          status: InvoiceStatus::ISSUED,
          raw: result
        )
      end

      # 作廢發票 (+invoice_invalid+). Only after the next day's upload.
      def void(input)
        parsed = Input.void(input, provider: name)
        result = @client.request("/Api/invoice_invalid", VERSION[:other], Payload.void(parsed), operation: :void)
        VoidInvoiceResult.new(invoice_number: result.fetch("InvoiceNumber", parsed.invoice.number).to_s,
                              status: InvoiceStatus::VOIDED, raw: result)
      end

      # 開立折讓 (+allowance_issue+, confirmed now). ezPay assigns the
      # allowance number, so +allowance_id+ is not sent. The result has no date.
      # The allowance is confirmed at once, so its date is today in Taipei.
      def allowance(input)
        parsed = Input.allowance(input, provider: name)
        data = Payload.allowance(parsed, original_invoice(parsed.invoice))
        result = @client.request("/Api/allowance_issue", VERSION[:allowance], data, operation: :allowance)
        AllowanceResult.new(
          allowance_number: result["AllowanceNo"].to_s,
          invoice_number: result.fetch("InvoiceNumber", parsed.invoice.number).to_s,
          allowance_date: Taipei.today,
          total_amount: result["AllowanceAmt"].to_i,
          raw: result
        )
      end

      # 作廢折讓 (+allowanceInvalid+).
      def void_allowance(input)
        parsed = Input.void_allowance(input, provider: name)
        result = @client.request("/Api/allowanceInvalid", VERSION[:other], Payload.void_allowance(parsed),
                                 operation: :void_allowance)
        VoidAllowanceResult.new(allowance_number: result.fetch("AllowanceNo", parsed.allowance.allowance_number).to_s,
                                raw: result)
      end

      # 查詢發票 (+invoice_search+). See the class comment for the second key.
      #
      # The result has no allowance data, so +status+ is never +ALLOWANCE+.
      def query(input)
        reference = Input.query(input, provider: name).invoice
        assert_supports!(Capability::QUERY_BY_ORDER_ID) if reference.number.nil?
        search(reference)
      end

      private

      def search(reference)
        result = @client.request("/Api/invoice_search", VERSION[:query], Payload.query(reference), operation: :query)
        @client.verify_check_code!(result)
        build_query_result(result)
      end

      # The invoice's order id, and whether its buyer is a business (docs,
      # section 4.1). From the reference when it has the order id, else from a
      # query by number. A failed query is the provider's error, not the
      # invoice's: a NotFoundError would read as "the invoice of this call does
      # not exist".
      def original_invoice(reference)
        return { order_id: reference.order_id, business: !reference.buyer_ubn.nil? } if reference.order_id
        unless Payload.queryable?(reference)
          raise ValidationError.new("an ezPay allowance needs invoice.order_id, or invoice.random_code to look it up",
                                    provider: name)
        end

        found = begin
          search(reference)
        rescue Error => e
          raise ProviderError.new("allowance needs the invoice's order id; looking it up failed: #{e.message}",
                                  provider: name, reason: Reason::LOOKUP_FAILED, cause: e)
        end
        if found.order_id.nil?
          raise ProviderError.new("allowance needs the invoice's order id; the invoice found has none",
                                  provider: name, reason: Reason::LOOKUP_FAILED)
        end
        { order_id: found.order_id, business: !found.buyer.ubn.nil? }
      end

      def build_query_result(result)
        QueryInvoiceResult.new(
          invoice_number: result["InvoiceNumber"].to_s,
          invoice_datetime: taipei_time(result["CreateTime"]),
          random_code: result["RandomNum"].to_s,
          order_id: presence(result["MerchantOrderNo"]),
          status: STATUS[result["InvoiceStatus"].to_s],
          amount: AmountSummary.new(sales_amount: result["Amt"].to_i, tax_amount: result["TaxAmt"].to_i,
                                    total_amount: result["TotalAmt"].to_i),
          buyer: Buyer.new(name: presence(result["BuyerName"]), ubn: presence(result["BuyerUBN"]),
                           email: presence(result["BuyerEmail"]), address: presence(result["BuyerAddress"]),
                           phone: presence(result["BuyerPhone"])),
          items: item_detail(result["ItemDetail"]).map { |row| build_item(row) },
          tax_type: TAX_TYPE[result["TaxType"].to_s],
          tax_rate: query_rate(result["TaxRate"]),
          raw: result
        )
      end

      # ezPay TaxType → unified 課稅別. 9 is mixed.
      TAX_TYPE = Payload::TAX_TYPE.invert.merge(Payload::MIXED_TAX_CODE => TaxType::MIXED).freeze

      # The query returns the rate as a fraction, for example "0.05000". A rate
      # that is not a MIG rate reads as nil.
      def query_rate(reported)
        Input.mig_rate!(reported, "TaxRate", name)
      rescue ValidationError
        nil
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
