# frozen_string_literal: true

require "set"

module Einvoice
  module Tradevan
    module DefaultAPI
      # The merchant settings that every DEFAULTAPI request carries.
      #
      # +paper_print_mode+ (+0+ to +4+) and +invoice_alarm_mode+ (+0+ to +6+)
      # have no documented meaning, so the adapter does not guess a default. The
      # 1.x README used +0+ and +4+. +member_carrier_type+ is the merchant's own
      # 6-character carrier code, needed only for {CarrierType::MEMBER}.
      Settings = Data.define(:company_un, :org_id, :paper_print_mode, :invoice_alarm_mode,
                             :invoice_paper_returned, :allowance_paper_returned,
                             :member_carrier_type)

      # {Einvoice::Provider} over Tradevan 關貿's DEFAULTAPI, the API the 1.x
      # client wraps.
      #
      # **Experimental.** It is ported from the 1.x client, its validators and
      # its README examples. Nobody has run it against the live API, and Tradevan
      # does not publish its docs. Test it against your own account before you
      # rely on it. docs/providers/tradevan/defaultapi.md has the details and the
      # open questions.
      #
      # A void and an allowance need the original invoice's +saleIdentifier+,
      # and an allowance its date. The reference from issue or query has what
      # the adapter needs (docs, section 4.1).
      class Provider < ::Einvoice::Provider
        CAPABILITIES = Set[
          Capability::ISSUE,
          Capability::VOID,
          Capability::ALLOWANCE,
          Capability::VOID_ALLOWANCE,
          Capability::QUERY,
          Capability::B2B
        ].freeze

        API_VERSION = "defaultapi"

        attr_reader :capabilities, :client, :settings

        def initialize(acnt:, acntp:, key1:, key2:, base_url:, company_un:, org_id:,
                       paper_print_mode:, invoice_alarm_mode:, invoice_paper_returned:,
                       allowance_paper_returned:, member_carrier_type: nil, timeout: 30,
                       validate_payload: true, clock: Time)
          super()
          @client = Client.new(acnt: acnt, acntp: acntp, key1: key1, key2: key2,
                               base_url: base_url, timeout: timeout)
          @settings = Settings.new(
            company_un: company_un.to_s, org_id: org_id.to_s,
            paper_print_mode: paper_print_mode.to_s, invoice_alarm_mode: invoice_alarm_mode.to_s,
            invoice_paper_returned: invoice_paper_returned.to_s,
            allowance_paper_returned: allowance_paper_returned.to_s,
            member_carrier_type: member_carrier_type
          )
          @validate_payload = validate_payload
          @clock = clock
          @capabilities = CAPABILITIES
        end

        def name
          Client::PROVIDER
        end

        # Tells this adapter apart from a future one for a newer Tradevan API.
        def api_version
          API_VERSION
        end

        # Call any DEFAULTAPI path with raw parameters, for example
        #
        #   provider.raw("get/getInvoiceMarkInfo", { companyUn: "…", orgId: "…", … })
        #
        # The encryption and the error mapping are applied as usual. Brace the
        # Hash: an unbraced one is read as keyword arguments.
        def raw(path, params)
          @client.request(path, params)
        end

        # 開立發票 (type I).
        def issue(input)
          parsed = Input.issue(input, provider: name)
          assert_currency_supported!(parsed.currency)
          tax_type = TaxType.of(parsed.items, parsed.tax_type)
          assert_supports!(Capability::MIXED_TAX) if tax_type == TaxType::MIXED
          data = Payload.issue(parsed, @settings, Taipei.now(@clock))
          Rules.validate!(Rules.issue_errors(data), "issueData") if @validate_payload

          result = @client.request("post/issue", { issueData: data })
          @client.check_status!(result, "issueStatus")
          # Tradevan may have issued the invoice, so this is not a refusal. But
          # without a number the reference cannot void or credit it.
          if result["invoiceNumber"].to_s.empty?
            raise ProviderError.new("Tradevan reported the issue as done but returned no invoiceNumber",
                                    provider: name, raw: result)
          end

          IssueInvoiceResult.new(
            invoice_number: result["invoiceNumber"].to_s,
            invoice_datetime: parse_time(result["invoiceDate"], result["invoiceTime"]),
            random_code: result["checkNumber"].to_s,
            order_id: parsed.order_id,
            total_amount: parsed.amount.total_amount,
            buyer_ubn: parsed.resolved_category == InvoiceCategory::B2B ? parsed.buyer&.ubn : nil,
            tax_type: tax_type,
            tax_rate: parsed.tax_rate,
            status: InvoiceStatus::ISSUED,
            raw: result
          )
        end

        # 作廢發票 (cancel type I). DEFAULTAPI has no reason field, so the
        # unified +reason+ is not sent.
        def void(input)
          parsed = Input.void(input, provider: name)
          sale, = original_invoice(parsed, need_date: false)
          data = Payload.void(parsed, @settings, sale)
          Rules.validate!(Rules.void_errors(data), "voidData") if @validate_payload

          result = @client.request("post/cancel", { voidData: data })
          @client.check_status!(result, "voidStatus")
          VoidInvoiceResult.new(invoice_number: parsed.invoice.number, status: InvoiceStatus::VOIDED,
                                raw: result)
        end

        # 開立折讓 (issue type A). No source shows the response to type A. The
        # adapter reads +allowanceNumber+, which the type I response also has,
        # and raises {ProviderError} when it is empty. Without +allowanceDate+,
        # the date is today in Taipei, the +transactionDate+ it sent (inferred).
        def allowance(input)
          parsed = Input.allowance(input, provider: name)
          assert_supports!(Capability::MIXED_TAX) if TaxType.of(parsed.items, parsed.tax_type) == TaxType::MIXED
          sale, invoice_date = original_invoice(parsed, need_date: true)
          today = Taipei.today(@clock)
          data = Payload.allowance(parsed, @settings, sale: sale, invoice_date: invoice_date, today: today)
          Rules.validate!(Rules.issue_errors(data), "issueData") if @validate_payload

          result = @client.request("post/issue", { issueData: data })
          @client.check_status!(result, "issueStatus")
          number = result["allowanceNumber"].to_s
          if number.empty?
            raise ProviderError.new("Tradevan returned no allowanceNumber", provider: name, raw: result)
          end

          AllowanceResult.new(
            allowance_number: number,
            invoice_number: parsed.invoice.number,
            allowance_date: parse_time(result["allowanceDate"], nil)&.to_date || today,
            total_amount: parsed.amount.total_amount,
            raw: result
          )
        end

        # 作廢折讓 (cancel type A). There is no reason field here either.
        def void_allowance(input)
          parsed = Input.void_allowance(input, provider: name)
          data = Payload.void_allowance(parsed, @settings)
          Rules.validate!(Rules.void_errors(data), "voidData") if @validate_payload

          result = @client.request("post/cancel", { voidData: data })
          @client.check_status!(result, "voidStatus")
          VoidAllowanceResult.new(allowance_number: parsed.allowance.allowance_number, raw: result)
        end

        # 查詢發票 by invoice number (searchInvoiceDetail).
        #
        # The meaning of the response's +status+ codes (+I+, +V+) is unknown, so
        # the result's +status+ is +ALLOWANCE+ when +hasAllowance+ is +Y+, and
        # +nil+ otherwise. A wrong guess could report a voided invoice as issued.
        # The raw code stays in +raw["status"]+.
        def query(input)
          reference = Input.query(input, provider: name).invoice
          assert_supports!(Capability::QUERY_BY_ORDER_ID) if reference.number.nil?
          search(reference.number)
        end

        private

        def search(number)
          build_query_result(detail(number))
        end

        # The searchInvoiceDetail object. The client keeps arrays, which some
        # raw endpoints answer, but this one must be an object.
        def detail(number)
          result = @client.request("get/searchInvoiceDetail", { invoiceNumber: number })
          return result if result.is_a?(Hash)

          raise ProviderError.new("Tradevan returned an invoice detail that is not an object",
                                  provider: name, raw: result)
        end

        # The original invoice's +saleIdentifier+ and, for an allowance, its
        # date (docs, section 4.1): +provider_options[:sale_identifier]+ (for
        # invoices the 1.x client issued), else built from the reference's
        # order id. The date comes from the reference. What is missing comes
        # from a query by number. A failed query is the provider's error, not
        # the invoice's: a NotFoundError would read as "the invoice of this
        # call does not exist".
        def original_invoice(parsed, need_date:)
          reference = parsed.invoice
          sale = string_keys(parsed.provider_options)["sale_identifier"]&.to_s
          sale ||= Payload.sale_identifier(@settings, reference.order_id) if reference.order_id
          date = reference.invoice_datetime && Taipei.date(reference.invoice_datetime)
          return [sale, date] if sale && (date || !need_date)

          found = lookup(reference.number, need_date: need_date && date.nil?)
          sale ||= found[:sale]
          date ||= found[:date]
          # Only the fields this call needs have to come back.
          missing = [("saleIdentifier" unless sale), ("invoiceDate" if need_date && !date)].compact
          if missing.any?
            raise ProviderError.new("Tradevan needs the invoice's #{missing.join(' and ')}; the invoice found " \
                                    "lacks it", provider: name, reason: Reason::LOOKUP_FAILED)
          end
          [sale, date]
        end

        # Reads only what the call needs: a void does not need the date, and an
        # allowance does not need the time. So a bad field that the call does
        # not use cannot stop it.
        def lookup(number, need_date:)
          result = detail(number)
          date = need_date ? parse_time(result["invoiceDate"], nil) : nil
          { sale: presence(result["saleIdentifier"]), date: date && Taipei.date(date) }
        rescue Error => e
          raise ProviderError.new("Tradevan needs the invoice's saleIdentifier or date; looking them up " \
                                  "failed: #{e.message}", provider: name, reason: Reason::LOOKUP_FAILED, cause: e)
        end

        def build_query_result(result)
          items = Array(result["detailList"]).map { |row| build_item(row) }
          tax_type = query_tax_type(items)
          QueryInvoiceResult.new(
            invoice_number: result["invoiceNumber"].to_s,
            invoice_datetime: parse_time(result["invoiceDate"], result["invoiceTime"]),
            random_code: result["checkNumber"].to_s,
            order_id: Payload.order_id_from(@settings, result["saleIdentifier"]),
            status: result["hasAllowance"] == "Y" ? InvoiceStatus::ALLOWANCE : nil,
            amount: AmountSummary.new(sales_amount: result["exclusiveAmount"].to_i,
                                      tax_amount: result["tax"].to_i,
                                      total_amount: result["total"].to_i),
            buyer: Buyer.new(name: presence(result["receiverName"]), ubn: nil, email: nil,
                             address: presence(result["receiverAddr"]),
                             phone: presence(result["receiverPhone"])),
            items: items,
            tax_type: tax_type,
            tax_rate: query_rate(items, tax_type),
            raw: result
          )
        end

        # Two different known types make MIXED. Otherwise a line with a missing
        # or unknown type leaves the invoice's type unknown: it is not a type
        # of its own.
        def query_tax_type(items)
          known = items.map(&:tax_type).compact.uniq
          return TaxType::MIXED if known.size > 1
          return nil if known.empty? || items.any? { |item| item.tax_type.nil? }

          known.first
        end

        # DEFAULTAPI has no rate field. A taxable line is at the general rate,
        # the only one its tax letters can carry (6.1). Without a taxable line,
        # MIXED too, the rate is 0. An unknown type leaves it unknown.
        def query_rate(items, tax_type)
          return nil if tax_type.nil?

          items.any? { |item| item.tax_type == TaxType::TAXABLE } ? Payload::TAX_RATE : 0r
        end

        def build_item(row)
          InvoiceItem.new(
            description: row["productName"].to_s,
            quantity: numeric(row["qty"]),
            unit_price: numeric(row["price"]),
            amount: numeric(row["total"]),
            unit: nil,
            tax_type: Payload::TAX_TYPE.invert[row["taxType"].to_s],
            remark: nil
          )
        end

        # DEFAULTAPI sends numbers as strings. Keep whole numbers integral.
        def numeric(value)
          rational = value.to_s.to_r
          rational.denominator == 1 ? rational.to_i : rational.to_f
        end

        def string_keys(hash)
          return {} unless hash.is_a?(Hash)

          hash.to_h { |key, value| [key.to_s, value] }
        end

        def presence(value)
          string = value.to_s
          string.empty? ? nil : string
        end

        # "20160425" and "12:34:58" (UTC+8) → Time, or nil when the date is
        # missing, so that a missing date never reads as "now". A date or a
        # time that is there but not valid is the provider's error.
        def parse_time(date, time)
          return nil if date.to_s.empty?

          year, month, day = /\A(\d{4})(\d{2})(\d{2})\z/.match(date.to_s)&.captures&.map(&:to_i)
          clock = time.to_s.empty? ? "00:00:00" : time.to_s
          hour, minute, second = /\A(\d{2}):(\d{2}):(\d{2})\z/.match(clock)&.captures&.map(&:to_i)
          unless year && hour && Date.valid_date?(year, month, day) && hour < 24 && minute < 60 && second < 60
            raise ProviderError.new("Tradevan returned a date that is not valid: #{date.inspect} #{time.inspect}",
                                    provider: name)
          end

          Time.new(year, month, day, hour, minute, second, "+08:00")
        end
      end
    end
  end
end
