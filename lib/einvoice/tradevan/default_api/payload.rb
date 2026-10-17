# frozen_string_literal: true

module Einvoice
  module Tradevan
    module DefaultAPI
      # Builds +issueData+ and +voidData+ from the unified inputs.
      #
      # Nobody has run these against the live API in 2026, so each choice that
      # the sources do not settle is named in a comment, and
      # docs/providers/tradevan/defaultapi.md lists the open questions.
      module Payload
        TAX_TYPE = {
          TaxType::TAXABLE => "T",
          TaxType::ZERO_RATED => "Z",
          TaxType::TAX_FREE => "O"
        }.freeze

        CARRIER_TYPE = {
          CarrierType::MOBILE_BARCODE => "3J0002",
          CarrierType::CITIZEN_CERTIFICATE => "CQ0001"
        }.freeze

        # The rate the adapter uses to split the tax out of a tax-included amount.
        TAX_RATE = 0.05

        module_function

        # +issueData+ for type +I+ (a new invoice).
        def issue(parsed, settings)
          assert_issue_supported!(parsed)
          date, time = taipei(parsed.date)
          sale = sale_identifier(settings, parsed.order_id)

          data = header(settings).merge(
            "type" => "I",
            "saleIdentifier" => sale,
            "transactionNumber" => parsed.order_id.to_s,
            "transactionDate" => date,
            "transactionTime" => time,
            "total" => number(parsed.amount.total_amount),
            "invoicePaperReturned" => settings.invoice_paper_returned,
            "itemList" => items(parsed.items, sale, parsed.tax_type)
          )
          data.merge!(buyer(parsed))
          data.merge!(donation_and_carrier(parsed, settings))
          data.compact
        end

        # +voidData+ for type +I+ (void an invoice).
        def void(parsed, settings)
          {
            "type" => "I",
            "saleIdentifier" => original_sale_identifier(parsed, settings),
            "invoiceNumber" => parsed.invoice_number.to_s,
            "invoicePaperReturned" => settings.invoice_paper_returned
          }
        end

        # +issueData+ for type +A+ (a new allowance).
        def allowance(parsed, settings)
          options = string_keys(parsed.provider_options)
          invoice_date = options["invoice_date"] || parsed.date
          if invoice_date.nil?
            raise ValidationError.new(
              "Tradevan needs the original invoice date for an allowance. " \
              "Pass provider_options: { invoice_date: }", provider: Client::PROVIDER
            )
          end

          exclusive, tax, inclusive = allowance_amounts(parsed)
          original = original_sale_identifier(parsed, settings)
          header(settings).merge(
            "type" => "A",
            "allowanceIdentifier" => sale_identifier(settings, parsed.allowance_id),
            "transactionNumber" => parsed.allowance_id.to_s,
            "transactionDate" => taipei(nil).first,
            "allowanceExclusiveAmount" => number(exclusive),
            "allowanceTax" => number(tax),
            "allowanceInclusiveAmount" => number(inclusive),
            "allowancePaperReturned" => settings.allowance_paper_returned,
            "invoicePaperReturned" => settings.invoice_paper_returned,
            "itemList" => allowance_items(parsed, original, taipei(invoice_date).first, exclusive)
          )
        end

        # +voidData+ for type +A+ (void an allowance).
        def void_allowance(parsed, settings)
          {
            "type" => "A",
            "companyUn" => settings.company_un,
            "allowanceNumber" => parsed.allowance_number.to_s,
            "allowancePaperReturned" => settings.allowance_paper_returned
          }
        end

        # +"#{companyUn}_#{orgId}_#{id}"+. The prefix is a DEFAULTAPI rule. Using
        # the order id for the rest is our choice, so that a void can rebuild it.
        def sale_identifier(settings, id)
          "#{settings.company_un}_#{settings.org_id}_#{id}"
        end

        # The order id back from a +saleIdentifier+ built by {sale_identifier}.
        def order_id_from(settings, sale_identifier)
          prefix = sale_identifier(settings, "")
          value = sale_identifier.to_s
          value.start_with?(prefix) ? value.delete_prefix(prefix) : value
        end

        def header(settings)
          {
            "companyUn" => settings.company_un,
            "orgId" => settings.org_id,
            "paperPrintMode" => settings.paper_print_mode,
            "invoiceAlarmMode" => settings.invoice_alarm_mode
          }
        end

        # DEFAULTAPI has no code for a special tax rate, and +itemTotal+ is
        # always tax included.
        def assert_issue_supported!(parsed)
          kinds = [parsed.tax_type, *parsed.items.map(&:tax_type)].compact
          if kinds.include?(TaxType::SPECIAL)
            raise UnsupportedError.new("Tradevan DEFAULTAPI has no special tax rate (特種稅率)",
                                       provider: Client::PROVIDER)
          end
          return unless parsed.price_mode == PriceMode::TAX_EXCLUSIVE

          raise ValidationError.new("Tradevan DEFAULTAPI takes tax-included item totals. " \
                                    "Use price_mode TAX_INCLUSIVE", provider: Client::PROVIDER)
        end

        def buyer(parsed)
          buyer = parsed.buyer
          return {} unless buyer

          fields = {
            "receiverName" => buyer.name,
            "receiverAddrRoad" => buyer.address,
            "receiverEmail" => buyer.email,
            "receiverMobile" => buyer.phone
          }
          if parsed.resolved_category == InvoiceCategory::B2B
            fields["buyerUn"] = buyer.ubn
            fields["buyerTitle"] = buyer.name
          end
          fields.reject { |_, value| value.to_s.empty? }
        end

        def donation_and_carrier(parsed, settings)
          return { "donate" => "Y", "donationUnit" => parsed.donation.npoban } if parsed.donation

          carrier = parsed.carrier
          # With donate "N", the 1.x rules ask for a carrier. A B2B invoice
          # without a carrier therefore leaves donate out.
          return {} if carrier.nil? && parsed.resolved_category == InvoiceCategory::B2B

          fields = { "donate" => "N" }
          return fields unless carrier

          code = carrier_code(parsed)
          fields.merge("carrierType" => carrier_type(carrier, settings),
                       "carrierId" => code, "carrierIdHidden" => code)
        end

        def carrier_type(carrier, settings)
          return CARRIER_TYPE.fetch(carrier.type) unless carrier.type == CarrierType::MEMBER
          return settings.member_carrier_type unless settings.member_carrier_type.to_s.empty?

          raise ValidationError.new("A member carrier needs member_carrier_type, the merchant's " \
                                    "own 6-character code from Tradevan", provider: Client::PROVIDER)
        end

        # A member carrier without a code uses the buyer's email, then phone.
        # This is our choice: the sources do not say what Tradevan expects.
        def carrier_code(parsed)
          code = parsed.carrier.code.to_s
          return code unless code.empty?

          fallback = [parsed.buyer&.email, parsed.buyer&.phone].map(&:to_s).find { |v| !v.empty? }
          return fallback if fallback && parsed.carrier.type == CarrierType::MEMBER

          raise ValidationError.new("The carrier needs a code", provider: Client::PROVIDER)
        end

        def items(list, sale, invoice_tax_type)
          list.each_with_index.map do |item, index|
            {
              "saleIdentifier" => sale,
              "serialNumber" => format("%04d", index + 1),
              "productName" => item.description.to_s,
              "qty" => number(item.quantity),
              "price" => number(item.unit_price),
              "itemTotal" => number(item.amount),
              "taxType" => TAX_TYPE.fetch(item.tax_type || invoice_tax_type || TaxType::TAXABLE)
            }
          end
        end

        # Allowance amounts: without tax, tax, with tax. A taxable allowance sent
        # with tax 0 (the shared contract's B2C shape) has the tax inside the
        # total, so it is split out here.
        def allowance_amounts(parsed)
          amount = parsed.amount
          taxable = parsed.items.all? { |item| [nil, TaxType::TAXABLE].include?(item.tax_type) }
          return [amount.sales_amount, amount.tax_amount, amount.total_amount] unless
            taxable && amount.tax_amount.zero?

          total = amount.total_amount
          exclusive = (total / (1 + TAX_RATE)).round
          [exclusive, total - exclusive, total]
        end

        # Share the allowance's exclusive total over the items by amount. The
        # last item takes the rounding difference, so the items add up.
        def allowance_items(parsed, sale, invoice_date, exclusive)
          total = parsed.items.sum { |item| item.amount.to_r }
          given = 0
          parsed.items.each_with_index.map do |item, index|
            last = index == parsed.items.size - 1
            share = last || total.zero? ? exclusive - given : (exclusive * item.amount.to_r / total).round
            given += share
            {
              "saleIdentifier" => sale,
              "serialNumber" => format("%04d", index + 1),
              "invoiceNumber" => parsed.invoice_number.to_s,
              "invoiceDate" => invoice_date,
              "productName" => item.description.to_s,
              "qty" => number(item.quantity),
              "price" => number(item.unit_price),
              "itemExclude" => number(share),
              "itemTotal" => number(item.amount),
              "taxType" => TAX_TYPE.fetch(item.tax_type || TaxType::TAXABLE)
            }
          end
        end

        # A void or an allowance needs the original invoice's saleIdentifier,
        # which the unified input does not carry.
        def original_sale_identifier(parsed, settings)
          options = string_keys(parsed.provider_options)
          return options["sale_identifier"].to_s if options["sale_identifier"]
          return sale_identifier(settings, options["order_id"]) if options["order_id"]

          raise ValidationError.new(
            "Tradevan needs the original invoice's order id. " \
            "Pass provider_options: { order_id: } (or { sale_identifier: })",
            provider: Client::PROVIDER
          )
        end

        # [yyyyMMdd, HH:MM:SS] in UTC+8. A String date is read as yyyyMMdd or
        # yyyy-MM-dd.
        def taipei(value)
          return [value.delete("-/"), "00:00:00"] if value.is_a?(String)

          time = value.respond_to?(:to_time) ? value.to_time : value
          time = (time || Time.now).getlocal("+08:00")
          [time.strftime("%Y%m%d"), time.strftime("%H:%M:%S")]
        end

        # DEFAULTAPI sends every value as a string. Whole numbers lose their ".0".
        def number(value)
          return value if value.is_a?(String)

          rational = value.to_r
          rational.denominator == 1 ? rational.to_i.to_s : value.to_f.to_s
        end

        def string_keys(hash)
          return {} unless hash.is_a?(Hash)

          hash.to_h { |key, value| [key.to_s, value] }
        end
      end
    end
  end
end
