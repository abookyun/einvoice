# frozen_string_literal: true

module Einvoice
  module ECPay
    # Maps the unified value model onto ECPay's +Issue+ payload, and checks the
    # field rules locally so a bad request fails before the network.
    #
    # The rules encoded here were confirmed against the live stage API rather than
    # taken from the documentation, which both over-states some requirements the
    # API does not enforce and forbids combinations it accepts (a 統編 invoice may
    # carry a carrier, for instance).
    module Payload
      # 課稅別 → ECPay TaxType. 9 (混合) is derived from the items, not requested.
      TAX_TYPE = {
        TaxType::TAXABLE => "1",
        TaxType::ZERO_RATED => "2",
        TaxType::TAX_FREE => "3",
        TaxType::SPECIAL => "4"
      }.freeze
      MIXED_TAX_CODE = "9"

      # 載具類別 → ECPay CarrierType.
      CARRIER_TYPE = {
        CarrierType::MEMBER => "1",              # 綠界會員載具
        CarrierType::CITIZEN_CERTIFICATE => "2", # 自然人憑證條碼
        CarrierType::MOBILE_BARCODE => "3"       # 手機條碼
      }.freeze

      # ECPay caps 作廢/折讓 reasons at 20 characters, and 自訂編號 at 50.
      MAX_REASON_LENGTH = 20
      MAX_RELATE_NUMBER_LENGTH = 50
      # Default unit (單位) when an item does not name one; ItemWord is required.
      DEFAULT_UNIT = "式"

      module_function

      # Build the +Issue+ Data payload from a parsed {Einvoice::IssueInvoiceInput}.
      def issue(parsed, validate: true)
        options = string_keys(parsed.provider_options)
        carrier = parsed.carrier
        donating = !parsed.donation.nil?
        # A carrier or donated invoice is electronic; anything else prints on paper.
        print = carrier || donating ? "0" : "1"
        b2b = parsed.resolved_category == InvoiceCategory::B2B

        data = {
          "RelateNumber" => parsed.order_id,
          "CustomerID" => options["customer_id"].to_s,
          "CustomerIdentifier" => b2b ? parsed.buyer&.ubn.to_s : "",
          "CustomerName" => parsed.buyer&.name.to_s,
          "CustomerAddr" => parsed.buyer&.address.to_s,
          "CustomerPhone" => parsed.buyer&.phone.to_s,
          "CustomerEmail" => parsed.buyer&.email.to_s,
          "Print" => print,
          "Donation" => donating ? "1" : "0",
          "LoveCode" => parsed.donation&.npoban.to_s,
          "CarrierType" => carrier ? CARRIER_TYPE.fetch(carrier.type) : "",
          "CarrierNum" => carrier&.code.to_s,
          "TaxType" => tax_type(parsed),
          "SalesAmount" => parsed.amount.total_amount,
          "InvoiceRemark" => parsed.remark.to_s,
          "Items" => items(parsed.items, parsed.tax_type),
          "InvType" => parsed.tax_type == TaxType::SPECIAL ? "08" : "07",
          "vat" => parsed.price_mode == PriceMode::TAX_EXCLUSIVE ? "0" : "1"
        }
        # 零稅率/特種稅額 details the unified model has no field for.
        data["ClearanceMark"] = options["clearance_mark"] if options.key?("clearance_mark")
        data["ZeroTaxRateReason"] = options["zero_tax_rate_reason"] if options.key?("zero_tax_rate_reason")
        data["SpecialTaxType"] = options["special_tax_type"] if options.key?("special_tax_type")
        # Last-resort escape hatch for fields this mapper does not model.
        data.merge!(string_keys(options["data"])) if options["data"]

        validate_issue!(data) if validate
        data
      end

      # Build the +Items+ array shared by Issue and Allowance.
      def items(list, invoice_tax_type = nil)
        list.each_with_index.map do |item, index|
          row = {
            "ItemSeq" => index + 1,
            "ItemName" => item.description,
            "ItemCount" => item.quantity,
            "ItemWord" => item.unit || DEFAULT_UNIT,
            "ItemPrice" => item.unit_price,
            "ItemTaxType" => TAX_TYPE.fetch(item.tax_type || invoice_tax_type || TaxType::TAXABLE),
            "ItemAmount" => item.amount
          }
          row["ItemRemark"] = item.remark if item.remark
          row
        end
      end

      # An invoice whose items disagree on 課稅別 is a 混合稅率 (9) invoice; otherwise
      # the invoice-level tax type stands.
      def tax_type(parsed)
        kinds = parsed.items.map { |item| item.tax_type || parsed.tax_type }.uniq
        return MIXED_TAX_CODE if kinds.size > 1

        TAX_TYPE.fetch(kinds.first || parsed.tax_type)
      end

      # Field rules for a built payload. Each was checked against the live API; the
      # RtnCode it would otherwise come back as is noted.
      def validate_issue!(data)
        errors = []
        relate = data["RelateNumber"].to_s
        errors << "RelateNumber is required" if relate.empty?
        errors << "RelateNumber must be #{MAX_RELATE_NUMBER_LENGTH} characters or fewer" if
          relate.length > MAX_RELATE_NUMBER_LENGTH

        # 發票金額(含稅) must equal round(Σ ItemAmount) — 5000022. Only enforced for
        # 含稅 (vat=1); with vat=0 ECPay recomputes the total itself.
        if data["vat"] != "0"
          total = data["Items"].sum { |item| item["ItemAmount"].to_f }
          unless total.round == data["SalesAmount"]
            errors << "SalesAmount (#{data['SalesAmount']}) must equal the item total (#{total.round})"
          end
        end

        errors.concat(buyer_errors(data))
        errors.concat(carrier_errors(data))
        errors << "ClearanceMark is required for a zero-rated invoice" if clearance_missing?(data)

        return if errors.empty?

        raise ValidationError.new("Invalid ECPay invoice payload — #{errors.join('; ')}",
                                  provider: Client::PROVIDER, raw_message: errors.join("; "))
      end

      def buyer_errors(data)
        errors = []
        ubn = data["CustomerIdentifier"].to_s
        errors << "CustomerIdentifier must be 8 digits" unless ubn.empty? || ubn.match?(/\A\d{8}\z/)

        # Input enforces the same rule, so this only fires for a Donation value
        # object built directly, which Input passes through untouched.
        love_code = data["LoveCode"].to_s
        if data["Donation"] == "1" && !love_code.match?(Donation::CODE_FORMAT)
          errors << "LoveCode (3–7 digits) is required when donating"
        end

        # A printed invoice needs somewhere to print to, and a way to notify.
        if data["Print"] == "1"
          errors << "CustomerName is required for a printed invoice" if data["CustomerName"].to_s.empty?
          errors << "CustomerAddr is required for a printed invoice" if data["CustomerAddr"].to_s.empty?
          if data["CustomerEmail"].to_s.empty? && data["CustomerPhone"].to_s.empty?
            errors << "CustomerEmail or CustomerPhone is required for a printed invoice"
          end
        end
        errors
      end

      def carrier_errors(data)
        errors = []
        carrier = data["CarrierType"].to_s
        if data["CustomerIdentifier"].to_s.empty?
          # A B2C carrier invoice is electronic and cannot also print — 5000015.
          errors << "Print must be 0 for a carrier invoice" if !carrier.empty? && data["Print"] == "1"
        elsif data["Print"] == "0" && carrier.empty?
          # A 統編 invoice that is not printed has to live in a carrier — 5000028.
          errors << "A non-printed B2B invoice must use a carrier"
        end
        errors
      end

      # 零稅率 (TaxType 2, or 9 when a zero-rated item is mixed in) needs the
      # customs-clearance mark — 5000007.
      def clearance_missing?(data)
        return false unless data["ClearanceMark"].to_s.empty?
        return true if data["TaxType"] == "2"

        data["TaxType"] == MIXED_TAX_CODE &&
          data["Items"].any? { |item| item["ItemTaxType"] == "2" }
      end

      # ECPay rejects a 作廢/折讓 reason longer than 20 characters.
      def check_reason!(reason, field)
        return if reason.to_s.length <= MAX_REASON_LENGTH

        raise ValidationError.new(
          "#{field} must be #{MAX_REASON_LENGTH} characters or fewer, got #{reason.to_s.length}",
          provider: Client::PROVIDER
        )
      end

      def string_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end
    end
  end
end
