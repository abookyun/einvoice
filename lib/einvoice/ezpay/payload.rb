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
      TAX_RATE = Rational(5, 100)
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
        check_issue!(parsed, b2b, types, mixed, options)

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
          "TaxRate" => mixed || types.first == TaxType::TAXABLE ? "5" : "0"
        }
        fields["CustomsClearance"] = options["customs_clearance"].to_s if types.include?(TaxType::ZERO_RATED)
        fields.merge!(issue_amounts(parsed, types, b2b, mixed))
        fields.merge!(item_fields(parsed.items))
        fields["ItemTaxType"] = types.map { |type| TAX_TYPE.fetch(type) }.join(ITEM_SEPARATOR) if mixed
        fields["Comment"] = parsed.remark.to_s
        fields
      end

      # +invoice_invalid+ fields.
      def void(parsed)
        { "InvoiceNumber" => parsed.invoice_number.to_s, "InvalidReason" => reason!(parsed.reason) }
      end

      # +allowance_issue+ fields. Confirmed at once (+Status+ 1).
      def allowance(parsed)
        options = string_keys(parsed.provider_options)
        order_id = options["order_id"].to_s
        invalid!("an ezPay allowance needs provider_options[:order_id], the invoice's order id") if order_id.empty?

        fields = { "InvoiceNo" => parsed.invoice_number.to_s, "MerchantOrderNo" => order_id }
        fields.merge!(item_fields(parsed.items))
        fields.merge!(allowance_amounts(parsed.items, parsed.amount))
        fields["TaxTypeForMixed"] = options["tax_type_for_mixed"].to_s if options.key?("tax_type_for_mixed")
        fields["BuyerEmail"] = options["buyer_email"].to_s if options.key?("buyer_email")
        fields["Status"] = "1"
        fields
      end

      # +allowanceInvalid+ fields.
      def void_allowance(parsed)
        { "AllowanceNo" => parsed.allowance_number.to_s,
          "InvalidReason" => reason!(parsed.reason || VOID_ALLOWANCE_REASON) }
      end

      # +invoice_search+ fields. ezPay always needs a second key: the random
      # code with the number, or the total with the order id.
      def query(parsed)
        options = string_keys(parsed.provider_options)
        number = parsed.invoice_number.to_s
        order_id = parsed.order_id.to_s

        if !number.empty? && options.key?("random_code")
          { "SearchType" => "0", "InvoiceNumber" => number, "RandomNum" => options["random_code"].to_s }
        elsif !order_id.empty? && options.key?("total_amount")
          { "SearchType" => "1", "MerchantOrderNo" => order_id, "TotalAmt" => options["total_amount"].to_s }
        else
          invalid!("ezPay needs provider_options[:random_code] with an invoice number, " \
                   "or provider_options[:total_amount] with an order id")
        end
      end

      # --- issue -------------------------------------------------------------

      def check_issue!(parsed, b2b, types, mixed, options)
        invalid!("order_id must be 1 to 20 letters, digits or _") unless parsed.order_id.to_s.match?(ORDER_ID)
        max!(parsed.remark.to_s, 200, "remark")
        max!(parsed.buyer&.email.to_s, 50, "buyer email")
        max!(parsed.buyer&.address.to_s, 100, "buyer address")
        expected = b2b ? PriceMode::TAX_EXCLUSIVE : PriceMode::TAX_INCLUSIVE
        unless parsed.price_mode == expected
          invalid!("ezPay takes #{b2b ? 'tax-exclusive' : 'tax-inclusive'} prices for a #{b2b ? 'B2B' : 'B2C'} invoice")
        end
        if types.include?(TaxType::SPECIAL)
          raise UnsupportedError.new("ezPay adapter does not support special tax (特種稅額)",
                                     provider: Client::PROVIDER)
        end
        invalid!("ezPay allows mixed tax only on a B2C invoice") if mixed && b2b
        invalid!("ezPay allows a carrier or a donation only on a B2C invoice") if b2b && (parsed.carrier || parsed.donation)
        if types.include?(TaxType::ZERO_RATED) && !options.key?("customs_clearance")
          invalid!("a zero-rated sale needs provider_options[:customs_clearance]")
        end
        check_tax_rate!(parsed.tax_rate)
      end

      # The core does not define the unit of +tax_rate+. Like the note, read it
      # as a fraction (0.05), and also accept a percent (5). Only 5% is allowed.
      def check_tax_rate!(rate)
        return if rate.nil?

        value = Rational(rate.to_s)
        return if value == TAX_RATE || value == 5

        raise UnsupportedError.new("ezPay adapter only supports a 5% tax rate, got #{rate.inspect}",
                                   provider: Client::PROVIDER)
      rescue ArgumentError, ZeroDivisionError
        invalid!("tax_rate must be a number, got #{rate.inspect}")
      end

      # ezPay always splits the tax out: +Amt+ excludes it (section 4.3).
      def issue_amounts(parsed, types, b2b, mixed)
        amount = parsed.amount
        sums = Hash.new(0)
        parsed.items.zip(types).each { |item, type| sums[type] += integer!(item.amount, "item amount") }
        total = sums.values.sum

        if b2b
          # B2B item prices exclude tax, so the items add up to the sales amount.
          invalid!("items add up to #{total}, but amount.sales_amount is #{amount.sales_amount}") if
            total != amount.sales_amount
          return { "Amt" => total, "TaxAmt" => amount.tax_amount, "TotalAmt" => amount.total_amount }
        end

        invalid!("items add up to #{total}, but amount.total_amount is #{amount.total_amount}") if
          total != amount.total_amount
        taxable = sums[TaxType::TAXABLE]
        tax = if amount.tax_amount.to_i.zero?
                taxable - (taxable / (1 + TAX_RATE)).round
              else
                amount.tax_amount
              end
        fields = { "Amt" => total - tax, "TaxAmt" => tax, "TotalAmt" => total }
        if mixed
          fields["AmtSales"] = taxable - tax
          fields["AmtZero"] = sums[TaxType::ZERO_RATED]
          fields["AmtFree"] = sums[TaxType::TAX_FREE]
        end
        fields
      end

      def buyer_name(buyer, b2b)
        name = buyer&.name.to_s
        if b2b
          return name if !name.empty? && name.length <= 60

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

      # Each item field is one string, items separated by +|+.
      def item_fields(items)
        rows = items.map { |item| item_row(item) }
        %w[ItemName ItemCount ItemUnit ItemPrice ItemAmt].to_h do |field|
          [field, rows.map { |row| row[field] }.join(ITEM_SEPARATOR)]
        end
      end

      def item_row(item)
        name = item.description.to_s
        unit = item.unit.to_s.empty? ? DEFAULT_UNIT : item.unit.to_s
        [name, unit].each { |text| invalid!("item text must not contain |: #{text.inspect}") if text.include?("|") }
        max!(name, 30, "item description")
        limited!(unit, UNIT_LIMIT, "item unit")

        count = integer!(item.quantity, "item quantity")
        price = integer!(item.unit_price, "item unit_price")
        amount = integer!(item.amount, "item amount")
        invalid!("item amount #{amount} is not quantity × unit_price (#{count * price})") if amount != count * price

        { "ItemName" => name, "ItemCount" => count, "ItemUnit" => unit, "ItemPrice" => price, "ItemAmt" => amount }
      end

      # --- allowance ---------------------------------------------------------

      # The note proposes tax-inclusive prices for B2C and tax-exclusive ones
      # for B2B (section 4.3). {AllowanceInput} has no buyer, so the adapter
      # reads the amount instead:
      #
      # - +tax_amount+ 0 (the contract's B2C shape): prices include tax, and
      #   every +ItemTaxAmt+ is 0.
      # - +tax_amount+ above 0: prices exclude tax, and the item taxes add up
      #   to +tax_amount+. The rounding difference goes on the last item.
      def allowance_amounts(items, amount)
        amounts = items.map { |item| integer!(item.amount, "item amount") }
        if amount.tax_amount.to_i.zero?
          invalid!("items add up to #{amounts.sum}, but amount.total_amount is #{amount.total_amount}") if
            amounts.sum != amount.total_amount
          taxes = amounts.map { 0 }
        else
          invalid!("items add up to #{amounts.sum}, but amount.sales_amount is #{amount.sales_amount}") if
            amounts.sum != amount.sales_amount
          taxes = amounts.map { |value| (value * TAX_RATE).round }
          taxes[-1] += amount.tax_amount - taxes.sum
        end
        { "ItemTaxAmt" => taxes.join(ITEM_SEPARATOR), "TotalAmt" => amounts.sum + taxes.sum }
      end

      # --- helpers -----------------------------------------------------------

      def reason!(reason)
        text = reason.to_s
        invalid!("reason is required") if text.empty?
        limited!(text, REASON_LIMIT, "reason")
        text
      end

      # ezPay counts "2 Chinese or 6 English characters". A text with any
      # non-ASCII character gets the Chinese limit.
      def limited!(text, (ascii, other), field)
        limit = text.ascii_only? ? ascii : other
        max!(text, limit, field)
      end

      # The core does not check item numbers, so a String like "lots" gets here.
      def integer!(value, field)
        return value if value.is_a?(Integer)
        return value.to_i if value.is_a?(Numeric) && value.finite? && value == value.to_i
        return value.to_i if value.is_a?(String) && value.match?(/\A-?\d+\z/)

        invalid!("ezPay needs a whole number for #{field}, got #{value.inspect}")
      end

      def max!(value, limit, field)
        invalid!("#{field} is longer than #{limit} characters") if value.length > limit
      end

      def invalid!(message)
        raise ValidationError.new(message, provider: Client::PROVIDER)
      end

      def string_keys(hash)
        (hash || {}).to_h.transform_keys(&:to_s)
      end
    end
  end
end
