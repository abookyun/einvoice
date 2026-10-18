# frozen_string_literal: true

require "date"

module Einvoice
  module Amego
    # Maps the unified value model onto Amego's JSON payloads, and checks the
    # rules from docs/providers/amego/api.md locally, so a bad request fails
    # before the network.
    module Payload
      # 課稅別 → Amego TaxType. 9 (混合) is derived from the items.
      TAX_TYPE = {
        TaxType::TAXABLE => "1",
        TaxType::ZERO_RATED => "2",
        TaxType::TAX_FREE => "3"
      }.freeze
      MIXED_TAX_CODE = "9"

      CARRIER_TYPE = {
        CarrierType::MOBILE_BARCODE => "3J0002",
        CarrierType::CITIZEN_CERTIFICATE => "CQ0001",
        CarrierType::MEMBER => "amego" # Amego's own member carrier
      }.freeze

      CONSUMER_ID = "0000000000"
      CONSUMER_NAME = "消費者"
      ALLOWANCE_TYPE = "2" # 賣方開立. Amego rejects 1 since 2025-01-01
      TAX_RATE = Rational(5, 100)
      MOBILE_MEMBER = /\A09\d{8}\z/

      MAX_ORDER_ID = 40
      MAX_REMARK = 200
      MAX_DESCRIPTION = 256
      MAX_ITEM_REMARK = 120
      MAX_UNIT = 6
      MAX_REASON = 20
      MAX_ALLOWANCE_NUMBER = 16

      # provider_options key => f0401 field, for fields with no unified home.
      ISSUE_OPTIONS = {
        "track_api_code" => "TrackApiCode",
        "customs_clearance_mark" => "CustomsClearanceMark",
        "zero_tax_rate_reason" => "ZeroTaxRateReason",
        "brand_name" => "BrandName",
        "detail_amount_round" => "DetailAmountRound",
        "tax_adjustment" => "TaxAdjustment"
      }.freeze

      module_function

      # +f0401+ data from a parsed {IssueInvoiceInput}.
      def issue(parsed)
        b2b = parsed.resolved_category == InvoiceCategory::B2B
        exclusive = parsed.price_mode == PriceMode::TAX_EXCLUSIVE
        options = string_keys(parsed.provider_options)
        check_issue!(parsed, b2b, exclusive, options)

        types = parsed.items.map { |item| item.tax_type || parsed.tax_type }
        totals = issue_totals(parsed.items, types, b2b: b2b, exclusive: exclusive)
        check_totals!(parsed.amount, totals, b2b)

        data = {
          "OrderId" => parsed.order_id.to_s,
          "BuyerIdentifier" => b2b ? parsed.buyer.ubn.to_s : CONSUMER_ID,
          "BuyerName" => buyer_name(parsed.buyer, b2b),
          "BuyerAddress" => parsed.buyer&.address.to_s,
          "BuyerTelephoneNumber" => parsed.buyer&.phone.to_s,
          "BuyerEmailAddress" => parsed.buyer&.email.to_s,
          "MainRemark" => parsed.remark.to_s,
          **carrier_fields(parsed.carrier, parsed.buyer),
          "NPOBAN" => parsed.donation&.npoban.to_s,
          "ProductItem" => parsed.items.zip(types).map { |item, type| issue_item(item, type) },
          "SalesAmount" => totals[:sales],
          "FreeTaxSalesAmount" => totals[:free],
          "ZeroTaxSalesAmount" => totals[:zero],
          "TaxType" => types.uniq.size > 1 ? MIXED_TAX_CODE : TAX_TYPE.fetch(types.first),
          "TaxRate" => "0.05",
          "TaxAmount" => totals[:tax],
          "TotalAmount" => totals[:total],
          "DetailVat" => exclusive ? "0" : "1"
        }
        ISSUE_OPTIONS.each { |key, field| data[field] = options[key].to_s if options.key?(key) }
        data
      end

      # +f0501+ data: one invoice per call (see docs, open question 6).
      def void(parsed)
        reason = parsed.reason.to_s
        max!(reason, MAX_REASON, "reason")
        [{ "CancelInvoiceNumber" => parsed.invoice_number.to_s, "CancelReason" => reason }]
      end

      # +g0401+ data. +original+ carries the facts about the original invoice
      # that {AllowanceInput} does not: +buyer_identifier+, +buyer_name+ and
      # +invoice_date+ (a Date or Time).
      def allowance(parsed, original, allowance_date)
        number = parsed.allowance_id.to_s
        max!(number, MAX_ALLOWANCE_NUMBER, "allowance_id")
        lines = allowance_lines(parsed.items, parsed.amount)

        [{
          "AllowanceNumber" => number,
          "AllowanceDate" => ymd(allowance_date),
          "AllowanceType" => ALLOWANCE_TYPE,
          "BuyerIdentifier" => original[:buyer_identifier].to_s,
          "BuyerName" => original[:buyer_name].to_s,
          "ProductItem" => lines[:items].map do |line|
            line.merge("OriginalInvoiceNumber" => parsed.invoice_number.to_s,
                       "OriginalInvoiceDate" => ymd(original[:invoice_date]))
          end,
          "TaxAmount" => lines[:tax],
          "TotalAmount" => lines[:sales]
        }]
      end

      # +g0501+ data.
      def void_allowance(parsed)
        [{ "CancelAllowanceNumber" => parsed.allowance_number.to_s }]
      end

      # +invoice_query+ data. The order id wins when both are given.
      def query(parsed)
        if parsed.order_id.to_s.empty?
          { "type" => "invoice", "invoice_number" => parsed.invoice_number.to_s }
        else
          { "type" => "order", "order_id" => parsed.order_id.to_s }
        end
      end

      # --- issue -------------------------------------------------------------

      def check_issue!(parsed, b2b, exclusive, options)
        max!(parsed.order_id.to_s, MAX_ORDER_ID, "order_id")
        max!(parsed.remark.to_s, MAX_REMARK, "remark")
        if exclusive && !b2b
          invalid!("Amego takes tax-exclusive prices only for a B2B invoice")
        end
        check_tax_rate!(parsed.tax_rate)

        types = parsed.items.map { |item| item.tax_type || parsed.tax_type }
        if types.include?(TaxType::SPECIAL)
          raise UnsupportedError.new("Amego adapter does not support special tax (特種稅額)",
                                     provider: Client::PROVIDER)
        end
        return unless types.include?(TaxType::ZERO_RATED)
        return if options.key?("customs_clearance_mark") && options.key?("zero_tax_rate_reason")

        invalid!("a zero-rated sale needs provider_options customs_clearance_mark and zero_tax_rate_reason")
      end

      # The core does not define the unit of +tax_rate+, so accept only the
      # general 5% rate, written as 0.05 or as 5.
      def check_tax_rate!(rate)
        return if rate.nil?

        # Through a String, so that the Float 0.05 reads as exactly 5/100.
        value = Rational(rate.to_s)
        return if value == TAX_RATE || value == 5

        raise UnsupportedError.new("Amego adapter only supports a 5% tax rate, got #{rate.inspect}",
                                   provider: Client::PROVIDER)
      rescue ArgumentError, ZeroDivisionError
        invalid!("tax_rate must be a number, got #{rate.inspect}")
      end

      # The totals from Amego's formula (docs, section 4.3).
      def issue_totals(items, types, b2b:, exclusive:)
        sum = ->(type) { items.zip(types).sum(Rational(0)) { |item, t| t == type ? item.amount.to_r : 0 } }
        sales = sum.call(TaxType::TAXABLE).round
        free = sum.call(TaxType::TAX_FREE).round
        zero = sum.call(TaxType::ZERO_RATED).round

        tax = 0
        if exclusive
          tax = (sales * TAX_RATE).round
        elsif b2b
          tax = sales - (sales / (1 + TAX_RATE)).round
          sales -= tax
        end
        { sales: sales, free: free, zero: zero, tax: tax, total: sales + free + zero + tax }
      end

      def check_totals!(amount, totals, b2b)
        if totals[:total] != amount.total_amount
          invalid!("items add up to #{totals[:total]}, but amount.total_amount is #{amount.total_amount}")
        end
        return unless b2b && totals[:tax] != amount.tax_amount

        invalid!("Amego computes a tax of #{totals[:tax]}, but amount.tax_amount is #{amount.tax_amount}")
      end

      def buyer_name(buyer, b2b)
        name = buyer&.name.to_s
        invalid!("buyer name must not be #{name.inspect}") if name.match?(/\A0{1,4}\z/)
        return name unless name.empty?

        b2b ? buyer.ubn.to_s : CONSUMER_NAME
      end

      # Visible and hidden codes are the same. A member carrier without a code
      # uses the buyer's email, else +a+ and the buyer's mobile number.
      def carrier_fields(carrier, buyer)
        return { "CarrierType" => "", "CarrierId1" => "", "CarrierId2" => "" } unless carrier

        code = carrier.code.to_s
        code = member_code(buyer) if code.empty? && carrier.type == CarrierType::MEMBER
        invalid!("a #{carrier.type} carrier needs a code") if code.empty?

        { "CarrierType" => CARRIER_TYPE.fetch(carrier.type), "CarrierId1" => code, "CarrierId2" => code }
      end

      def member_code(buyer)
        email = buyer&.email.to_s
        return email unless email.empty?

        phone = buyer&.phone.to_s.delete("- ")
        phone.match?(MOBILE_MEMBER) ? "a#{phone}" : ""
      end

      def issue_item(item, type)
        description = item.description.to_s
        max!(description, MAX_DESCRIPTION, "item description")
        max!(item.remark.to_s, MAX_ITEM_REMARK, "item remark")
        max!(item.unit.to_s, MAX_UNIT, "item unit")
        {
          "Description" => description,
          "Quantity" => number(item.quantity),
          "Unit" => item.unit.to_s,
          "UnitPrice" => number(item.unit_price),
          "Amount" => number(item.amount),
          "Remark" => item.remark.to_s,
          "TaxType" => TAX_TYPE.fetch(type)
        }
      end

      # --- allowance ---------------------------------------------------------

      # Amego wants allowance amounts without tax, and an integer +Tax+ on each
      # item (docs, section 4.3).
      #
      # The unified +amount+ has two shapes, and the core does not say which
      # one an allowance uses (docs, open question 7):
      #
      # - +tax_amount+ 0 (the contract's B2C shape): the item amounts include
      #   the tax. Split it out of each taxable item.
      # - +tax_amount+ above 0: the caller split it already. The item amounts
      #   exclude tax, and the item taxes must add up to +tax_amount+.
      #
      # Either way, the rounding difference goes on the last taxable item.
      def allowance_lines(items, amount)
        split = amount.tax_amount.to_i.zero?
        taxes = items.map do |item|
          next 0 unless taxable?(item)

          value = item.amount.to_r
          split ? (value - (value / (1 + TAX_RATE))).round : (value * TAX_RATE).round
        end

        target = split ? split_tax(items) : amount.tax_amount.to_i
        last = items.rindex { |item| taxable?(item) }
        taxes[last] += target - taxes.sum if last

        lines = items.zip(taxes).map { |item, tax| allowance_item(item, tax, split) }
        sales = lines.sum(Rational(0)) { |line| line["Amount"].to_r }
        { items: lines, tax: target, sales: sales.round }
      end

      def split_tax(items)
        total = items.select { |item| taxable?(item) }.sum(Rational(0)) { |item| item.amount.to_r }
        (total - (total / (1 + TAX_RATE)).round).round
      end

      def allowance_item(item, tax, split)
        description = item.description.to_s
        max!(description, MAX_DESCRIPTION, "item description")
        amount = split ? item.amount.to_r - tax : item.amount.to_r
        quantity = item.quantity.to_r
        unit_price = quantity.zero? ? amount : amount / quantity
        {
          "OriginalDescription" => description,
          "Quantity" => number(item.quantity),
          "UnitPrice" => number(unit_price),
          "Amount" => number(amount),
          "Tax" => tax,
          "TaxType" => TAX_TYPE.fetch(item.tax_type || TaxType::TAXABLE)
        }
      end

      def taxable?(item)
        (item.tax_type || TaxType::TAXABLE) == TaxType::TAXABLE
      end

      # --- helpers -----------------------------------------------------------

      # Amego takes up to 7 decimals. Whole numbers go out without a point.
      def number(value)
        rational = value.to_r
        return rational.to_i.to_s if rational.denominator == 1

        format("%.7f", rational.round(7)).sub(/0+\z/, "")
      end

      # Date, Time or "Ymd" → "Ymd" in Taipei time.
      def ymd(value)
        case value
        when Time then value.getlocal("+08:00").strftime("%Y%m%d")
        when Date then value.strftime("%Y%m%d")
        else
          string = value.to_s.delete("-/")
          invalid!("invoice date must be a Date, a Time or YYYYMMDD, got #{value.inspect}") unless
            string.match?(/\A\d{8}\z/)
          string
        end
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
