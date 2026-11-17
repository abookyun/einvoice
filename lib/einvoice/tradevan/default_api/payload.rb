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

        # The only taxable rate: DEFAULTAPI has no rate field.
        TAX_RATE = Rational(5, 100)

        module_function

        # +issueData+ for type +I+ (a new invoice). +now+ is the time of this
        # issue: Tradevan requires +transactionDate+ and +transactionTime+.
        def issue(parsed, settings, now)
          types = parsed.items.map { |item| item.tax_type || parsed.tax_type }
          check_tax!(types, parsed.tax_rate)
          breakdown = parsed.tax_breakdown(provider: Client::PROVIDER)
          sale = sale_identifier(settings, parsed.order_id)

          data = header(settings).merge(
            "type" => "I",
            "saleIdentifier" => sale,
            "transactionNumber" => parsed.order_id.to_s,
            "transactionDate" => now.strftime("%Y%m%d"),
            "transactionTime" => now.strftime("%H:%M:%S"),
            "total" => number(breakdown.total_amount),
            "invoicePaperReturned" => settings.invoice_paper_returned,
            "itemList" => items(parsed.items, breakdown.lines, sale)
          )
          data.merge!(buyer(parsed))
          data.merge!(donation_and_carrier(parsed, settings))
          data.compact
        end

        # +voidData+ for type +I+ (void an invoice). +sale+ is the original
        # invoice's +saleIdentifier+ (docs, section 4.1).
        def void(parsed, settings, sale)
          {
            "type" => "I",
            "saleIdentifier" => sale,
            "invoiceNumber" => parsed.invoice.number.to_s,
            "invoicePaperReturned" => settings.invoice_paper_returned
          }
        end

        # +issueData+ for type +A+ (a new allowance). +sale+ and +invoice_date+
        # are the original invoice's (docs, section 4.1). +today+ is a Date.
        def allowance(parsed, settings, sale:, invoice_date:, today:)
          breakdown = parsed.tax_breakdown(provider: Client::PROVIDER)
          check_tax!(breakdown.lines.map(&:tax_type), parsed.tax_rate)
          amount = parsed.amount
          header(settings).merge(
            "type" => "A",
            "allowanceIdentifier" => sale_identifier(settings, parsed.allowance_id),
            "transactionNumber" => parsed.allowance_id.to_s,
            "transactionDate" => today.strftime("%Y%m%d"),
            "allowanceExclusiveAmount" => number(amount.sales_amount),
            "allowanceTax" => number(amount.tax_amount),
            "allowanceInclusiveAmount" => number(amount.total_amount),
            "allowancePaperReturned" => settings.allowance_paper_returned,
            "invoicePaperReturned" => settings.invoice_paper_returned,
            "itemList" => allowance_items(parsed, breakdown.lines, sale, invoice_date.strftime("%Y%m%d"))
          )
        end

        # +voidData+ for type +A+ (void an allowance).
        def void_allowance(parsed, settings)
          {
            "type" => "A",
            "companyUn" => settings.company_un,
            "allowanceNumber" => parsed.allowance.allowance_number.to_s,
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

        # DEFAULTAPI has no code for a special tax rate (6.1) and no rate
        # field, so a taxable line has to be at the general rate.
        def check_tax!(types, rate)
          if types.include?(TaxType::SPECIAL)
            raise UnsupportedError.new("Tradevan DEFAULTAPI has no special tax rate (特種稅率)",
                                       provider: Client::PROVIDER)
          end
          return unless types.include?(TaxType::TAXABLE) && rate.to_r != TAX_RATE

          raise UnsupportedError.new("Tradevan DEFAULTAPI takes a taxable rate of 0.05 only, got #{rate.to_f}",
                                     provider: Client::PROVIDER)
        end

        def buyer(parsed)
          buyer = parsed.buyer
          return {} unless buyer

          # receiverName takes 30 characters, buyerTitle 60. A longer B2B name
          # is cut for receiverName only.
          fields = {
            "receiverName" => buyer.name && buyer.name[0, 30],
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

        # A carrier goes with a donation too: the schema allows both (5.1).
        def donation_and_carrier(parsed, settings)
          carrier = parsed.carrier
          if parsed.donation
            fields = { "donate" => "Y", "donationUnit" => parsed.donation.npoban }
          else
            # With donate "N", the 1.x rules ask for a carrier. A B2B invoice
            # without a carrier therefore leaves donate out.
            return {} if carrier.nil? && parsed.resolved_category == InvoiceCategory::B2B

            fields = { "donate" => "N" }
          end
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

        # +itemTotal+ is tax included (4.3), so every price mode is sent as the
        # core's gross line amount and unit price.
        def items(list, lines, sale)
          list.zip(lines).each_with_index.map do |(item, line), index|
            {
              "saleIdentifier" => sale,
              "serialNumber" => format("%04d", index + 1),
              "productName" => item.description.to_s,
              "qty" => number(item.quantity),
              "price" => number(line.gross_unit_price),
              "itemTotal" => number(line.gross_amount),
              "taxType" => TAX_TYPE.fetch(line.tax_type)
            }
          end
        end

        # Each allowance line carries its tax split (G0401): +itemExclude+
        # without tax, +tax+, and +itemTotal+ with tax, all from the core.
        def allowance_items(parsed, lines, sale, invoice_date)
          parsed.items.zip(lines).each_with_index.map do |(item, line), index|
            {
              "saleIdentifier" => sale,
              "serialNumber" => format("%04d", index + 1),
              "invoiceNumber" => parsed.invoice.number.to_s,
              "invoiceDate" => invoice_date,
              "productName" => item.description.to_s,
              "qty" => number(item.quantity),
              "price" => number(line.gross_unit_price),
              "itemExclude" => number(line.net_amount),
              "tax" => number(line.tax),
              "itemTotal" => number(line.gross_amount),
              "taxType" => TAX_TYPE.fetch(line.tax_type)
            }
          end
        end

        # DEFAULTAPI sends every value as a string. Whole numbers lose their ".0".
        def number(value)
          return value if value.is_a?(String)

          rational = value.to_r
          rational.denominator == 1 ? rational.to_i.to_s : value.to_f.to_s
        end
      end
    end
  end
end
