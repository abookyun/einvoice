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
      # A void and an allowance need the original invoice's order id, which the
      # unified inputs do not carry. Pass it as
      # <tt>provider_options: { order_id: "ORDER_1" }</tt>. An allowance also
      # needs the original invoice date: <tt>provider_options: { invoice_date: }</tt>.
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

        def initialize(acnt:, acntp:, key1:, key2:, endpoint:, company_un:, org_id:,
                       paper_print_mode:, invoice_alarm_mode:, invoice_paper_returned:,
                       allowance_paper_returned:, member_carrier_type: nil, timeout: 30,
                       validate_payload: true)
          super()
          @client = Client.new(acnt: acnt, acntp: acntp, key1: key1, key2: key2,
                               endpoint: endpoint, timeout: timeout)
          @settings = Settings.new(
            company_un: company_un.to_s, org_id: org_id.to_s,
            paper_print_mode: paper_print_mode.to_s, invoice_alarm_mode: invoice_alarm_mode.to_s,
            invoice_paper_returned: invoice_paper_returned.to_s,
            allowance_paper_returned: allowance_paper_returned.to_s,
            member_carrier_type: member_carrier_type
          )
          @validate_payload = validate_payload
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
          data = Payload.issue(parsed, @settings)
          Rules.validate!(Rules.issue_errors(data), "issueData") if @validate_payload

          result = @client.request("post/issue", { issueData: data })
          @client.check_status!(result, "issueStatus")

          IssueInvoiceResult.new(
            invoice_number: result["invoiceNumber"].to_s,
            invoice_date: parse_time(result["invoiceDate"], result["invoiceTime"]),
            random_code: result["checkNumber"].to_s,
            order_id: parsed.order_id,
            total_amount: parsed.amount.total_amount,
            status: InvoiceStatus::ISSUED,
            raw: result
          )
        end

        # 作廢發票 (cancel type I). DEFAULTAPI has no reason field, so the
        # unified +reason+ is not sent.
        def void(input)
          parsed = Input.void(input, provider: name)
          data = Payload.void(parsed, @settings)
          Rules.validate!(Rules.void_errors(data), "voidData") if @validate_payload

          result = @client.request("post/cancel", { voidData: data })
          @client.check_status!(result, "voidStatus")
          VoidInvoiceResult.new(invoice_number: parsed.invoice_number, status: InvoiceStatus::VOIDED,
                                raw: result)
        end

        # 開立折讓 (issue type A). No source shows the response to type A. The
        # adapter reads +allowanceNumber+, which the type I response also has,
        # and raises {ProviderError} when it is empty.
        def allowance(input)
          parsed = Input.allowance(input, provider: name)
          data = Payload.allowance(parsed, @settings)
          Rules.validate!(Rules.issue_errors(data), "issueData") if @validate_payload

          result = @client.request("post/issue", { issueData: data })
          @client.check_status!(result, "issueStatus")
          number = result["allowanceNumber"].to_s
          if number.empty?
            raise ProviderError.new("Tradevan returned no allowanceNumber", provider: name, raw: result)
          end

          AllowanceResult.new(
            allowance_number: number,
            invoice_number: parsed.invoice_number,
            allowance_date: parse_time(result["allowanceDate"], nil),
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
          VoidAllowanceResult.new(allowance_number: parsed.allowance_number, raw: result)
        end

        # 查詢發票 by invoice number (searchInvoiceDetail).
        #
        # The meaning of the response's +status+ codes (+I+, +V+) is unknown, so
        # the result's +status+ is +ALLOWANCE+ when +hasAllowance+ is +Y+, and
        # +nil+ otherwise. A wrong guess could report a voided invoice as issued.
        # The raw code stays in +raw["status"]+.
        def query(input)
          parsed = Input.query(input, provider: name)
          assert_supports!(Capability::QUERY_BY_ORDER_ID) if parsed.invoice_number.to_s.empty?

          result = @client.request("get/searchInvoiceDetail", { invoiceNumber: parsed.invoice_number })
          build_query_result(result)
        end

        private

        def build_query_result(result)
          QueryInvoiceResult.new(
            invoice_number: result["invoiceNumber"].to_s,
            invoice_date: parse_time(result["invoiceDate"], result["invoiceTime"]),
            random_code: result["checkNumber"].to_s,
            order_id: Payload.order_id_from(@settings, result["saleIdentifier"]),
            status: result["hasAllowance"] == "Y" ? InvoiceStatus::ALLOWANCE : nil,
            amount: AmountSummary.new(sales_amount: result["exclusiveAmount"].to_i,
                                      tax_amount: result["tax"].to_i,
                                      total_amount: result["total"].to_i),
            buyer: Buyer.new(name: presence(result["receiverName"]), ubn: nil, email: nil,
                             address: presence(result["receiverAddr"]),
                             phone: presence(result["receiverPhone"])),
            items: Array(result["detailList"]).map { |row| build_item(row) },
            raw: result
          )
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

        def presence(value)
          string = value.to_s
          string.empty? ? nil : string
        end

        # "20160425" and "12:34:58" (UTC+8) → Time, or nil when the date is
        # missing, so that a missing date never reads as "now".
        def parse_time(date, time)
          match = /\A(\d{4})(\d{2})(\d{2})\z/.match(date.to_s)
          return nil unless match

          hour, minute, second = time.to_s.split(":").map(&:to_i)
          Time.new(*match.captures.map(&:to_i), hour.to_i, minute.to_i, second.to_i, "+08:00")
        end
      end
    end
  end
end
