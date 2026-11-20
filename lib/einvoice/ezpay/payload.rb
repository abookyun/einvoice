# frozen_string_literal: true

module Einvoice
  module EzPay
    # Maps the unified value model onto ezPay's payload fields, and checks the
    # rules from docs/providers/ezpay/invoice.md locally, so a bad request fails
    # before the network.
    module Payload
      TAX_TYPE = {
        TaxType::TAXABLE => "1",
        TaxType::ZERO_RATED => "2",
        TaxType::TAX_FREE => "3"
      }.freeze
      MIXED_TAX_CODE = "9"

      CARRIER_TYPE = {
        CarrierType::MOBILE_BARCODE => "0",
        CarrierType::CITIZEN_CERTIFICATE => "1",
        CarrierType::MEMBER => "2" # ezPay's own member carrier
      }.freeze

      CONSUMER_NAME = "消費者"
      DEFAULT_UNIT = "個"
      VOID_ALLOWANCE_REASON = "作廢折讓"
      # The rates TaxRate takes, as a percent (docs, section 4.2).
      TAX_RATES = { 0r => "0", Rational(5, 100) => "5" }.freeze
      ITEM_SEPARATOR = "|"
      ORDER_ID = /\A[A-Za-z0-9_]{1,20}\z/

      # [limit when the text is all ASCII, limit when it is not]
      UNIT_LIMIT = [6, 2].freeze
      REASON_LIMIT = [20, 6].freeze

      module_function

      # +invoice_issue+ fields from a parsed {IssueInvoiceInput}.
      def issue(parsed)
        b2b = parsed.resolved_category == InvoiceCategory::B2B
        options = string_keys(parsed.provider_options)
        types = parsed.items.map { |item| item.tax_type || parsed.tax_type }
        mixed = types.uniq.size > 1
        check_issue!(parsed, b2b, types, mixed)

        breakdown = parsed.tax_breakdown(provider: Client::PROVIDER)

        fields = {
          "MerchantOrderNo" => parsed.order_id.to_s,
          "Status" => "1",
          "Category" => b2b ? "B2B" : "B2C",
          "BuyerName" => buyer_name(parsed.buyer, b2b),
          "BuyerUBN" => b2b ? parsed.buyer.ubn.to_s : "",
          "BuyerAddress" => parsed.buyer&.address.to_s,
          "BuyerEmail" => parsed.buyer&.email.to_s,
          **carrier_fields(parsed.carrier, parsed.buyer),
          "LoveCode" => parsed.donation&.npoban.to_s,
          "PrintFlag" => b2b || (parsed.carrier.nil? && parsed.donation.nil?) ? "Y" : "N",
          "TaxType" => mixed ? MIXED_TAX_CODE : TAX_TYPE.fetch(types.first),
          "TaxRate" => TAX_RATES.fetch(parsed.tax_rate)
        }
        # ezPay has no field for zero_tax_rate_reason (docs, section 4.6).
        fields["CustomsClearance"] = parsed.customs_clearance_mark if parsed.zero_rated?
        fields.merge!(issue_amounts(breakdown, mixed))
        fields.merge!(item_fields(parsed.items, breakdown.lines, net: b2b))
        fields["ItemTaxType"] = types.map { |type| TAX_TYPE.fetch(type) }.join(ITEM_SEPARATOR) if mixed
        fields["Comment"] = parsed.remark.to_s
        fields
      end

      # +invoice_invalid+ fields.
      def void(parsed)
        { "InvoiceNumber" => parsed.invoice.number.to_s, "InvalidReason" => reason!(parsed.reason) }
      end

      # +allowance_issue+ fields. Confirmed at once (+Status+ 1). +original+
      # has the invoice's +order_id+, and +business+ says if its buyer has a
      # 統一編號 (section 4.3).
      def allowance(parsed, original)
        options = string_keys(parsed.provider_options)
        check_rate!(parsed.tax_rate)
        breakdown = parsed.tax_breakdown(provider: Client::PROVIDER)
        refuse_special!(breakdown.lines.map(&:tax_type))

        fields = { "InvoiceNo" => parsed.invoice.number.to_s, "MerchantOrderNo" => original[:order_id].to_s }
        fields.merge!(item_fields(parsed.items, breakdown.lines, net: original[:business]))
        fields["ItemTaxAmt"] = breakdown.lines.map { |line| original[:business] ? line.tax : 0 }.join(ITEM_SEPARATOR)
        fields["TotalAmt"] = parsed.amount.total_amount
        fields["TaxTypeForMixed"] = options["tax_type_for_mixed"].to_s if options.key?("tax_type_for_mixed")
        fields["BuyerEmail"] = options["buyer_email"].to_s if options.key?("buyer_email")
        fields["Status"] = "1"
        fields
      end

      # +allowanceInvalid+ fields.
      def void_allowance(parsed)
        { "AllowanceNo" => parsed.allowance.allowance_number.to_s,
          "InvalidReason" => reason!(parsed.reason || VOID_ALLOWANCE_REASON) }
      end

      # +invoice_search+ fields, by number. ezPay needs the random code with
      # it. A query by order id needs the total, so the adapter does not offer
      # it (section 4.6).
      def query(reference)
        invalid!("an ezPay query needs invoice.random_code with the number") unless queryable?(reference)

        { "SearchType" => "0", "InvoiceNumber" => reference.number.to_s, "RandomNum" => reference.random_code.to_s }
      end

      # Whether +reference+ has the two keys of a query by number.
      def queryable?(reference)
        !reference.number.nil? && !reference.random_code.nil?
      end

      # --- issue -------------------------------------------------------------

      def check_issue!(parsed, b2b, types, mixed)
        unless parsed.order_id.to_s.match?(ORDER_ID)
          unsupported!("ezPay takes an order_id of 1 to 20 letters, digits or _")
        end
        max!(parsed.buyer&.email.to_s, 50, "buyer email")
        refuse_special!(types)
        unsupported!("ezPay allows mixed tax only on a B2C invoice") if mixed && b2b
        # The MIG allows a carrier and a donation on a B2B invoice, and a carrier
        # with a donation. ezPay refuses all three.
        unsupported!("ezPay takes a donation only on a B2C invoice") if b2b && parsed.donation
        unsupported!("ezPay takes a carrier only on a B2C invoice") if b2b && parsed.carrier
        unsupported!("ezPay does not take a carrier together with a donation") if parsed.carrier && parsed.donation
        check_rate!(parsed.tax_rate)
      end

      def refuse_special!(types)
        return unless types.include?(TaxType::SPECIAL)

        raise UnsupportedError.new("ezPay adapter does not support special tax (特種稅額)", provider: Client::PROVIDER)
      end

      # The core has checked that +rate+ is a MIG rate. ezPay takes two of them.
      def check_rate!(rate)
        return if TAX_RATES.key?(rate)

        raise UnsupportedError.new("ezPay takes a tax rate of 0 or 0.05 only, got #{rate.to_f}",
                                   provider: Client::PROVIDER)
      end

      # ezPay always splits the tax out: +Amt+ excludes it (section 4.3). The
      # split is the core's.
      def issue_amounts(breakdown, mixed)
        fields = { "Amt" => breakdown.sales_amount, "TaxAmt" => breakdown.tax_amount,
                   "TotalAmt" => breakdown.total_amount }
        if mixed
          fields["AmtSales"] = breakdown.taxable_amount
          fields["AmtZero"] = breakdown.zero_rated_amount
          fields["AmtFree"] = breakdown.tax_free_amount
        end
        fields
      end

      def buyer_name(buyer, b2b)
        name = buyer&.name.to_s
        if b2b
          return name unless name.empty?

          return buyer.ubn.to_s
        end
        return CONSUMER_NAME if name.empty?

        max!(name, 30, "buyer name")
        name
      end

      # +CarrierNum+ is +rawurlencode+d before the query string encodes it again
      # (section 2.2). A member carrier without a code uses the buyer's email.
      def carrier_fields(carrier, buyer)
        return { "CarrierType" => "", "CarrierNum" => "" } unless carrier

        code = carrier.code.to_s
        code = buyer&.email.to_s if code.empty? && carrier.type == CarrierType::MEMBER
        invalid!("a #{carrier.type} carrier needs a code") if code.empty?
        max!(code, 50, "carrier code")

        { "CarrierType" => CARRIER_TYPE.fetch(carrier.type), "CarrierNum" => Crypto.rawurlencode(code) }
      end

      # --- items -------------------------------------------------------------

      # Each item field is one string, items separated by +|+. ezPay fixes the
      # prices by the buyer (section 4.3): without tax for a business (+net+),
      # with tax for a consumer. Both come from the core's lines, so the
      # input's +price_mode+ does not matter.
      def item_fields(items, lines, net:)
        rows = items.zip(lines).map { |item, line| item_row(item, net ? line.net_amount : line.gross_amount) }
        %w[ItemName ItemCount ItemUnit ItemPrice ItemAmt].to_h do |field|
          [field, rows.map { |row| row[field] }.join(ITEM_SEPARATOR)]
        end
      end

      # ezPay wants +ItemAmt = ItemCount × ItemPrice+ in whole numbers, so the
      # price is the amount over the count, and it has to divide.
      def item_row(item, amount)
        name = item.description.to_s
        unit = item.unit.to_s.empty? ? DEFAULT_UNIT : item.unit.to_s
        [name, unit].each do |text|
          unsupported!("ezPay item text must not contain |: #{text.inspect}") if text.include?("|")
        end
        max!(name, 30, "item description")
        limited!(unit, UNIT_LIMIT, "item unit")

        count = integer!(item.quantity, "item quantity")
        unsupported!("ezPay needs an item quantity above 0, got #{count}") unless count.positive?
        amount = integer!(amount, "item amount")
        unless (amount % count).zero?
          unsupported!("ezPay needs a whole unit price, but the item amount #{amount} does not divide by #{count}")
        end

        { "ItemName" => name, "ItemCount" => count, "ItemUnit" => unit, "ItemPrice" => amount / count,
          "ItemAmt" => amount }
      end

      # --- allowance ---------------------------------------------------------

      # --- helpers -----------------------------------------------------------

      def reason!(reason)
        text = reason.to_s
        invalid!("reason is required") if text.empty?
        limited!(text, REASON_LIMIT, "reason")
        text
      end

      # ezPay counts "2 Chinese or 6 English characters". A text with any
      # non-ASCII character gets the Chinese limit. The ASCII limits are the
      # MIG's, which the core checks, so only the shorter limit is left here.
      def limited!(text, (ascii, other), field)
        max!(text, text.ascii_only? ? ascii : other, field)
      end

      # The core reads every number as exact, but allows decimals. ezPay does
      # not.
      def integer!(value, field)
        rational = value.to_r
        return rational.to_i if rational.denominator == 1

        unsupported!("ezPay needs a whole number for #{field}, got #{Number.plain(rational)}")
      end

      # The core checks the MIG lengths. A shorter limit of ezPay's own is
      # UnsupportedError: another provider may take the value
      # (docs/providers/README.md, "The unified model").
      def max!(value, limit, field)
        return if value.length <= limit

        unsupported!("ezPay takes a #{field} of at most #{limit} characters")
      end

      # The input breaks a MIG rule, or lacks what the call needs.
      def invalid!(message)
        raise ValidationError.new(message, provider: Client::PROVIDER)
      end

      # The MIG allows the input, but ezPay does not take it.
      def unsupported!(message)
        raise UnsupportedError.new(message, provider: Client::PROVIDER)
      end

      def string_keys(hash)
        (hash || {}).to_h.transform_keys(&:to_s)
      end
    end
  end
end
