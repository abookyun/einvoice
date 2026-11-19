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

      # ECPay caps 自訂編號 at 50 characters. Input checks the 20-character
      # reason limit, which ECPay shares with the MIG.
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
        # The core asks for the clearance mark on a zero-rated invoice. ECPay
        # takes the reason from its back office when it is not sent.
        data["ClearanceMark"] = parsed.customs_clearance_mark if parsed.zero_rated?
        data["ZeroTaxRateReason"] = parsed.zero_tax_rate_reason if parsed.zero_rated? && parsed.zero_tax_rate_reason
        # 特種稅額 details the unified model has no field for.
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

      # The +Items+ of an Allowance. ECPay wants tax-included prices and amounts,
      # which the core's breakdown has.
      def allowance_items(parsed)
        lines = parsed.tax_breakdown(provider: Client::PROVIDER).lines
        items(parsed.items, parsed.tax_type).zip(lines).map do |row, line|
          row.merge("ItemPrice" => line.gross_unit_price, "ItemTaxType" => TAX_TYPE.fetch(line.tax_type),
                    "ItemAmount" => line.gross_amount)
        end
      end

      # An invoice whose items disagree on 課稅別 is a 混合稅率 (9) invoice; otherwise
      # the invoice-level tax type stands.
      def tax_type(parsed)
        type = TaxType.of(parsed.items, parsed.tax_type)
        type == TaxType::MIXED ? MIXED_TAX_CODE : TAX_TYPE.fetch(type)
      end

      # Field rules for a built payload. Each was checked against the live API; the
      # RtnCode it would otherwise come back as is noted.
      def validate_issue!(data)
        errors = []
        relate = data["RelateNumber"].to_s
        errors << "RelateNumber is required" if relate.empty?
        errors << "RelateNumber must be #{MAX_RELATE_NUMBER_LENGTH} characters or fewer" if
          relate.length > MAX_RELATE_NUMBER_LENGTH

        # 發票金額(含稅) must equal round(Σ ItemAmount) — 5000022. Only checked for
        # 含稅 (vat=1). With vat=0, ECPay does not read ItemAmount: it stores
        # ItemPrice × 1.05 and checks SalesAmount against that (stage, 2026-11-15).
        if data["vat"] != "0"
          total = data["Items"].sum { |item| item["ItemAmount"].to_f }
          unless total.round == data["SalesAmount"]
            errors << "SalesAmount (#{data['SalesAmount']}) must equal the item total (#{total.round})"
          end
        end

        errors.concat(buyer_errors(data))
        errors.concat(carrier_errors(data))

        unless errors.empty?
          raise ValidationError.new("Invalid ECPay invoice payload — #{errors.join('; ')}",
                                    provider: Client::PROVIDER, raw_message: errors.join("; "))
        end

        limits = print_limits(data)
        return if limits.empty?

        raise UnsupportedError.new("ECPay does not take this invoice — #{limits.join('; ')}",
                                   provider: Client::PROVIDER, raw_message: limits.join("; "))
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

        errors
      end

      def carrier_errors(data)
        errors = []
        carrier = data["CarrierType"].to_s
        # A B2C carrier invoice is electronic and cannot also print — 5000015.
        if data["CustomerIdentifier"].to_s.empty? && !carrier.empty? && data["Print"] == "1"
          errors << "Print must be 0 for a carrier invoice"
        end
        errors
      end

      # ECPay's own rules, beyond the MIG. The MIG allows these invoices, so
      # they are UnsupportedError (docs/providers/README.md, "The unified
      # model"): another provider may take them.
      def print_limits(data)
        limits = []
        # A printed invoice needs somewhere to print to, and a way to notify.
        if data["Print"] == "1"
          limits << "CustomerName is required for a printed invoice" if data["CustomerName"].to_s.empty?
          limits << "CustomerAddr is required for a printed invoice" if data["CustomerAddr"].to_s.empty?
          if data["CustomerEmail"].to_s.empty? && data["CustomerPhone"].to_s.empty?
            limits << "CustomerEmail or CustomerPhone is required for a printed invoice"
          end
        end
        # A 統編 invoice that is not printed has to live in a carrier — 5000028.
        if !data["CustomerIdentifier"].to_s.empty? && data["Print"] == "0" && data["CarrierType"].to_s.empty?
          limits << "A non-printed B2B invoice must use a carrier"
        end
        limits
      end

      # The sum of ItemAmount has to equal AllowanceAmount [doc 7901]: the
      # totals must agree, as the MIG asks. On each item ItemPrice × ItemCount
      # may differ from ItemAmount by 1 at most. That is ECPay's own rule, so
      # it is an UnsupportedError (docs/providers/README.md, "The unified
      # model").
      def check_allowance!(data)
        total = data["Items"].sum { |item| item["ItemAmount"].to_r }
        unless total.round == data["AllowanceAmount"]
          raise ValidationError.new("Invalid ECPay allowance payload — AllowanceAmount " \
                                    "(#{data['AllowanceAmount']}) must equal the item total (#{total.round})",
                                    provider: Client::PROVIDER)
        end

        gaps = data["Items"].each_with_index.filter_map do |item, index|
          product = item["ItemPrice"].to_r * item["ItemCount"].to_r
          next if (product - item["ItemAmount"].to_r).abs <= 1

          "Items[#{index}]: ItemPrice × ItemCount (#{Number.plain(product)}) must be within 1 of " \
            "ItemAmount (#{item['ItemAmount']})"
        end
        return if gaps.empty?

        raise UnsupportedError.new("ECPay does not take this allowance — #{gaps.join('; ')}",
                                   provider: Client::PROVIDER)
      end

      def string_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end
    end
  end
end
