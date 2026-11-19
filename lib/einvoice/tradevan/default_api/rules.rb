# frozen_string_literal: true

module Einvoice
  module Tradevan
    module DefaultAPI
      # The +issueData+ and +voidData+ field rules, ported from the 1.x
      # validators (+IssueData+, +IssueItem+, +VoidData+ and
      # +issue_data_validator.rb+). Those rules are the only record of the
      # DEFAULTAPI schema, and they ran in production, so they are kept as they
      # were. Two changes:
      #
      # - The 1.x client also checked +donationUnit+ against a bundled list of
      #   donation codes. 2.0 has no bundled list. {Einvoice::Input} checks the
      #   format, and {Einvoice::MOF::DonationCodes} checks the registry.
      # - A key outside the schema is an error here. Tradevan rejects the whole
      #   request when it sees one (PR #38), so it is better to fail before the
      #   call.
      #
      # Each check returns a Hash of field name => messages. An empty Hash means
      # the data is valid.
      module Rules
        # A whole decimal string. String#to_r would read "100oops" as 100.
        DECIMAL = /\A-?\d+(\.\d+)?\z/

        ISSUE_TYPES = %w[I R G H A].freeze
        VOID_TYPES = %w[C I A].freeze
        YES_NO = %w[Y N].freeze
        DATE = /\A\d{8}\z/
        TIME = /\A\d{2}:\d{2}:\d{2}\z/

        ISSUE_FIELDS = %w[
          companyUn orgId orgUn type saleIdentifier allowanceIdentifier transactionNumber
          transactionDate transactionTime total transactionSource transactionTarget
          invoiceNumber allowanceNumber allowanceDate allowanceExclusiveAmount allowanceTax
          allowancePaperReturned allowanceInclusiveAmount paperPrintMode invoiceAlarmMode
          invoicePaperReturned donate donationUnit carrierType carrierId carrierIdHidden
          buyerUn buyerTitle receiverName receiverAddrZip receiverAddrRoad receiverEmail
          receiverMobile allowaDeclaration idViewId memberId checkNumber invoiceDate
          invoiceTime texclusiveAmount oeclusiveAmount zexclusiveAmount tax mainRemark
          invoiceType itemList
        ].freeze

        ITEM_FIELDS = %w[
          saleIdentifier serialNumber invoiceNumber invoiceDate invoiceTime productCode
          productName qty price tax itemExclude itemTotal taxType description
        ].freeze

        # Fields that carry the caller's input, with a DEFAULTAPI length limit of
        # Tradevan's own: stricter than the MIG's (productName 300 against 500,
        # receiverEmail 80 against 400, receiverMobile 15 against 26, carrierId
        # 64 against 400), or with no MIG field (the order and allowance ids).
        OWN_LIMITS = %w[
          transactionNumber saleIdentifier allowanceIdentifier productName description
          receiverEmail receiverMobile carrierId carrierIdHidden
        ].freeze
        TOO_LONG = /\Amust be \d+ characters or fewer\z/

        VOID_FIELDS = %w[
          type saleIdentifier invoiceNumber invoicePaperReturned allowanceNumber
          allowancePaperReturned companyUn
        ].freeze

        module_function

        # Errors for an +issueData+ Hash (string or symbol keys).
        def issue_errors(data)
          data = stringify(data)
          check = Check.new(data)
          type = data["type"].to_s

          check.unknown_keys(ISSUE_FIELDS)
          issue_common(check, data)
          issue_by_type(check, data, type)
          issue_items(check, data, type)
          check.errors
        end

        # Errors for one +itemList+ entry.
        def item_errors(item)
          item = stringify(item)
          check = Check.new(item)
          check.unknown_keys(ITEM_FIELDS)
          check.required("saleIdentifier", max: 100)
          check.required("serialNumber", is: 4, format: /\A\d+\z/)
          check.optional("invoiceNumber", is: 10)
          check.optional("invoiceDate", is: 8, format: /\A\d+\z/)
          check.optional("invoiceTime", is: 8, format: TIME)
          check.optional("productCode", max: 30)
          check.required("productName", max: 300)
          check.required("qty", max: 20)
          check.required("price", max: 20)
          %w[tax itemExclude itemTotal].each { |field| check.optional(field, max: 20) }
          check.optional("taxType", in: %w[T O Z])
          check.optional("description", max: 300)
          check.errors
        end

        # Errors for a +voidData+ Hash.
        def void_errors(data)
          data = stringify(data)
          check = Check.new(data)
          type = data["type"].to_s

          check.unknown_keys(VOID_FIELDS)
          check.required("type", in: VOID_TYPES)
          if %w[C I].include?(type)
            check.required("saleIdentifier", max: 100)
            check.required("invoiceNumber", is: 10)
            check.required("invoicePaperReturned", in: YES_NO)
          end
          if type == "A"
            check.required("companyUn", is: 8)
            check.required("allowanceNumber", is: 16)
            check.required("allowancePaperReturned", in: YES_NO)
          end
          check.errors
        end

        # Raise an error listing every problem, or return +nil+. When every
        # problem is a length over one of Tradevan's own limits, the MIG allows
        # the input, so it is an UnsupportedError (docs/providers/README.md,
        # "The unified model"). Anything else is a ValidationError.
        def validate!(errors, what)
          return if errors.empty?

          details = errors.flat_map { |field, messages| messages.map { |m| "#{field} #{m}" } }
          if errors.all? { |field, messages| own_limit?(field, messages) }
            raise UnsupportedError.new("Tradevan DEFAULTAPI does not take this #{what} — #{details.join('; ')}",
                                       provider: Client::PROVIDER, raw_message: details.join("; "))
          end
          raise ValidationError.new("Invalid Tradevan #{what} — #{details.join('; ')}",
                                    provider: Client::PROVIDER, raw_message: details.join("; "))
        end

        def own_limit?(field, messages)
          OWN_LIMITS.include?(field.sub(/\AitemList\[\d+\]\./, "")) && messages.all?(TOO_LONG)
        end

        def issue_common(check, data)
          check.required("companyUn", is: 8)
          check.required("orgId", is: 5)
          check.optional("orgUn", is: 8)
          check.required("type", in: ISSUE_TYPES)
          check.required("transactionNumber", max: 50)
          check.required("transactionDate", format: DATE)
          check.optional("transactionSource", max: 50)
          check.optional("transactionTarget", max: 50)
          check.required("paperPrintMode", in: %w[0 1 2 3 4])
          check.required("invoiceAlarmMode", in: %w[0 1 2 3 4 5 6])
          check.optional("idViewId", max: 10)
          check.optional("memberId", max: 50)

          type = data["type"].to_s
          print_mode = data["paperPrintMode"].to_s.to_i
          no_buyer = blank?(data["buyerUn"])

          if type == "A" || (no_buyer && print_mode != 0)
            check.required("invoicePaperReturned", in: YES_NO)
          end
          if print_mode.zero? && data["donate"] == "N" && type != "A"
            check.required("carrierType", is: 6)
          end
          return if %w[A H].include?(type)

          check.optional("buyerUn", is: 8)
          check.optional("buyerTitle", max: 60)
        end

        def issue_by_type(check, data, type)
          prefix = "#{data['companyUn']}_#{data['orgId']}_"
          print_mode = data["paperPrintMode"].to_s.to_i

          if %w[I R G H].include?(type)
            check.required("saleIdentifier", max: 100, prefix: prefix)
          end
          if %w[A H].include?(type)
            check.required("allowanceIdentifier", max: 100, prefix: prefix)
            check.required("allowanceExclusiveAmount", max: 20)
            check.required("allowanceTax", max: 8)
            check.required("allowancePaperReturned", in: YES_NO)
            check.required("allowanceInclusiveAmount", max: 20)
          end
          check.required("invoiceNumber", is: 10) if %w[R G H].include?(type)
          if type == "H"
            check.required("allowanceNumber", is: 16, prefix: data["orgId"].to_s)
            check.required("allowanceDate", format: DATE)
          end
          check.optional("allowaDeclaration", format: /\A\d{6}\z/) if type == "A"

          if %w[I R G].include?(type)
            check.required("transactionTime", format: TIME)
            check.required("total", max: 20)
            check.total_matches_items
            if blank?(data["buyerUn"]) && print_mode.zero?
              check.required("donate", is: 1)
            end
            check.required("donationUnit", max: 10) if data["donate"] == "Y"
            if print_mode.zero? && data["donate"] == "N"
              check.required("carrierId", max: 64)
              check.required("carrierIdHidden", max: 64)
            end
          end
          if %w[I R G A].include?(type)
            check.optional("receiverName", max: 30)
            check.optional("receiverAddrZip", max: 6)
            check.optional("receiverAddrRoad", max: 100)
            check.optional("receiverEmail", max: 80)
            check.optional("receiverMobile", max: 15)
          end
          check.optional("tax", max: 20) if %w[I G].include?(type)
          issue_type_g(check) if type == "G"
        end

        def issue_type_g(check)
          check.optional("checkNumber", is: 4)
          check.optional("invoiceDate", is: 8)
          check.optional("invoiceTime", is: 8)
          %w[texclusiveAmount oeclusiveAmount zexclusiveAmount].each do |field|
            check.optional(field, max: 20)
          end
          check.optional("mainRemark", max: 300)
          check.optional("invoiceType", in: %w[07 08])
        end

        def issue_items(check, data, type)
          items = data["itemList"]
          unless items.is_a?(Array) && !items.empty?
            check.add("itemList", "is required")
            return
          end

          items = items.map { |item| stringify(item) }
          items.each_with_index do |item, index|
            item_errors(item).each do |field, messages|
              messages.each { |message| check.add("itemList[#{index}].#{field}", message) }
            end
          end

          needed = %w[itemTotal taxType]
          needed += %w[invoiceNumber invoiceDate itemExclude] if %w[A H].include?(type)
          needed.each do |field|
            check.add("itemList", "needs #{field} on every item") if items.any? { |i| blank?(i[field]) }
          end
        end

        def stringify(hash)
          return {} unless hash.is_a?(Hash)

          hash.to_h { |key, value| [key.to_s, value] }
        end

        def blank?(value)
          value.nil? || value.to_s.strip.empty?
        end

        # Collects messages for one Hash. Lengths count characters, as the 1.x
        # validators did.
        class Check
          attr_reader :errors

          def initialize(data)
            @data = data
            @errors = {}
          end

          def add(field, message)
            (@errors[field] ||= []) << message
          end

          def unknown_keys(allowed)
            (@data.keys - allowed).each { |key| add(key, "is not a DEFAULTAPI field") }
          end

          def required(field, **rule)
            return add(field, "is required") if Rules.blank?(@data[field])

            apply(field, **rule)
          end

          def optional(field, **rule)
            apply(field, **rule) unless Rules.blank?(@data[field])
          end

          def total_matches_items
            items = Array(@data["itemList"]).map { |item| Rules.stringify(item) }
            # Only whole decimal strings: String#to_r would read "100oops" as 100.
            values = [@data["total"], *items.map { |item| item["itemTotal"] }].map(&:to_s)
            return add("total", "and every itemTotal must be decimal numbers") unless values.all?(DECIMAL)

            # Compared as decimals: "0.5" + "0.5" is "1".
            sum = items.sum { |item| item["itemTotal"].to_s.to_r }
            return if @data["total"].to_s.to_r == sum

            add("total", "must equal the sum of itemTotal (#{Number.plain(sum)})")
          end

          private

          def apply(field, is: nil, max: nil, in: nil, format: nil, prefix: nil)
            value = @data[field].to_s
            choices = binding.local_variable_get(:in)
            add(field, "must be #{is} characters") if is && value.length != is
            add(field, "must be #{max} characters or fewer") if max && value.length > max
            add(field, "must be one of #{choices.join(', ')}") if choices && !choices.include?(value)
            add(field, "has an invalid format") if format && !value.match?(format)
            add(field, "must start with #{prefix}") if prefix && !value.start_with?(prefix)
          end
        end
      end
    end
  end
end
