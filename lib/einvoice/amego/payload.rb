# frozen_string_literal: true

require "date"

module Einvoice
  module Amego
    # Maps the unified value model onto Amego's JSON payloads, and checks the
    # rules from docs/providers/amego/api.md locally, so a bad request fails
    # before the network. The core has already checked the input and computed
    # the tax, so this module only translates.
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
      # The only rates TaxRate takes (docs, section 4.2).
      TAX_RATES = [0r, Rational(5, 100)].freeze
      MOBILE_MEMBER = /\A09\d{8}\z/

      MAX_ORDER_ID = 40
      MAX_REMARK = 200
      MAX_DESCRIPTION = 256
      MAX_ITEM_REMARK = 120
      MAX_UNIT = 6
      MAX_ALLOWANCE_NUMBER = 16

      # provider_options key => f0401 field, for fields with no unified home.
      ISSUE_OPTIONS = {
        "track_api_code" => "TrackApiCode",
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
        types = parsed.items.map { |item| item.tax_type || parsed.tax_type }
        check_issue!(parsed, types, b2b, exclusive)
        breakdown = parsed.tax_breakdown(provider: Client::PROVIDER)

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
          **issue_totals(breakdown, b2b),
          "TaxType" => types.uniq.size > 1 ? MIXED_TAX_CODE : TAX_TYPE.fetch(types.first),
          "TaxRate" => number(parsed.tax_rate),
          "DetailVat" => exclusive ? "0" : "1"
        }
        if parsed.zero_rated?
          data["CustomsClearanceMark"] = parsed.customs_clearance_mark
          data["ZeroTaxRateReason"] = parsed.zero_tax_rate_reason
        end
        ISSUE_OPTIONS.each { |key, field| data[field] = options[key].to_s if options.key?(key) }
        data
      end

      # +f0501+ data: one invoice per call. The core checks the reason's length.
      def void(parsed)
        [{ "CancelInvoiceNumber" => parsed.invoice.number.to_s, "CancelReason" => parsed.reason.to_s }]
      end

      # +g0401+ data. +original+ carries the facts about the original invoice
      # that the reference may not have: +buyer_identifier+, +buyer_name+ and
      # +invoice_datetime+.
      def allowance(parsed, original, allowance_date)
        number = parsed.allowance_id.to_s
        max!(number, MAX_ALLOWANCE_NUMBER, "allowance_id", mig: true)
        breakdown = parsed.tax_breakdown(provider: Client::PROVIDER)
        refuse_special!(breakdown.lines.map(&:tax_type))
        check_rate!(parsed.tax_rate)
        invoice_date = ymd(original[:invoice_datetime])

        [{
          "AllowanceNumber" => number,
          "AllowanceDate" => allowance_date.strftime("%Y%m%d"),
          "AllowanceType" => ALLOWANCE_TYPE,
          "BuyerIdentifier" => original[:buyer_identifier].to_s,
          "BuyerName" => original[:buyer_name].to_s,
          "ProductItem" => parsed.items.zip(breakdown.lines).map do |item, line|
            allowance_item(item, line).merge("OriginalInvoiceNumber" => parsed.invoice.number.to_s,
                                             "OriginalInvoiceDate" => invoice_date)
          end,
          "TaxAmount" => breakdown.tax_amount,
          "TotalAmount" => breakdown.sales_amount
        }]
      end

      # +g0501+ data.
      def void_allowance(parsed)
        [{ "CancelAllowanceNumber" => parsed.allowance.allowance_number.to_s }]
      end

      # +invoice_query+ data. The order id wins when the reference has both.
      def query(reference)
        if reference.order_id.nil?
          { "type" => "invoice", "invoice_number" => reference.number.to_s }
        else
          { "type" => "order", "order_id" => reference.order_id.to_s }
        end
      end

      # --- issue -------------------------------------------------------------

      def check_issue!(parsed, types, b2b, exclusive)
        max!(parsed.order_id.to_s, MAX_ORDER_ID, "order_id")
        max!(parsed.remark.to_s, MAX_REMARK, "remark", mig: true)
        unsupported!("Amego takes tax-exclusive prices only for a B2B invoice") if exclusive && !b2b
        refuse_special!(types)
        check_rate!(parsed.tax_rate)
        # The core asks for the clearance mark. The MIG asks for the reason too,
        # and so does Amego.
        return unless parsed.zero_rated? && parsed.zero_tax_rate_reason.nil?

        invalid!("a zero-rated invoice needs zero_tax_rate_reason (71 to 79)")
      end

      def refuse_special!(types)
        return unless types.include?(TaxType::SPECIAL)

        raise UnsupportedError.new("Amego adapter does not support special tax (特種稅額)",
                                   provider: Client::PROVIDER)
      end

      # The core has checked that +rate+ is a MIG rate. Amego takes two of them.
      def check_rate!(rate)
        return if TAX_RATES.include?(rate)

        raise UnsupportedError.new("Amego takes a tax rate of 0 or 0.05 only, got #{number(rate)}",
                                   provider: Client::PROVIDER)
      end

      # The MIG totals from the core's breakdown (docs, section 4.3). A B2C
      # invoice keeps the tax inside SalesAmount, as F0401 does.
      def issue_totals(breakdown, b2b)
        sales = breakdown.taxable_amount
        tax = breakdown.tax_amount
        sales, tax = sales + tax, 0 unless b2b
        { "SalesAmount" => sales, "FreeTaxSalesAmount" => breakdown.tax_free_amount,
          "ZeroTaxSalesAmount" => breakdown.zero_rated_amount, "TaxAmount" => tax,
          "TotalAmount" => breakdown.total_amount }
      end

      def buyer_name(buyer, b2b)
        name = buyer&.name.to_s
        # The MIG forbids 0 to 0000 as a buyer's name [mig 表 4-2].
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
        max!(item.remark.to_s, MAX_ITEM_REMARK, "item remark", mig: true)
        max!(item.unit.to_s, MAX_UNIT, "item unit", mig: true)
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
      # item (docs, section 4.3). Both come from the core's line. The unit price
      # is the amount over the quantity, rounded to 7 decimal places, so
      # +UnitPrice × Quantity+ can miss +Amount+ by that rounding: 94 over 3 is
      # 31.3333333. The core's +net_unit_price+ is not used, because it comes
      # from the item's unit price and can miss by the rounding of the tax.
      def allowance_item(item, line)
        description = item.description.to_s
        max!(description, MAX_DESCRIPTION, "item description")
        {
          "OriginalDescription" => description,
          "Quantity" => number(item.quantity),
          "UnitPrice" => number(unit_price(line.net_amount, item.quantity)),
          "Amount" => number(line.net_amount),
          "Tax" => line.tax,
          "TaxType" => TAX_TYPE.fetch(line.tax_type)
        }
      end

      def unit_price(amount, quantity)
        quantity = quantity.to_r
        quantity.zero? ? amount.to_r : amount.to_r / quantity
      end

      # --- helpers -----------------------------------------------------------

      # Amego takes up to 7 decimals. Whole numbers go out without a point. The
      # core has already read every number as exact.
      # Rounds to 7 decimal places first, so a value that rounds to a whole
      # number is written without a point: "100", not "100.".
      def number(value)
        rational = value.to_r.round(7)
        return rational.to_i.to_s if rational.denominator == 1

        format("%.7f", rational).sub(/0+\z/, "")
      end

      # A Time → "Ymd" in Taipei time.
      def ymd(time)
        Taipei.date(time, provider: Client::PROVIDER).strftime("%Y%m%d")
      end

      # A limit that the MIG sets too (+mig: true+) is a ValidationError. A
      # shorter limit of Amego's own is UnsupportedError: another provider may
      # take the value (docs/providers/README.md, "The unified model").
      def max!(value, limit, field, mig: false)
        return if value.length <= limit

        invalid!("#{field} is longer than #{limit} characters") if mig
        unsupported!("Amego takes a #{field} of at most #{limit} characters")
      end

      # The input breaks a MIG rule, or lacks what the call needs.
      def invalid!(message)
        raise ValidationError.new(message, provider: Client::PROVIDER)
      end

      # The MIG allows the input, but Amego does not take it.
      def unsupported!(message)
        raise UnsupportedError.new(message, provider: Client::PROVIDER)
      end

      def string_keys(hash)
        (hash || {}).to_h.transform_keys(&:to_s)
      end
    end
  end
end
