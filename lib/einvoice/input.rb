# frozen_string_literal: true

module Einvoice
  # Coerces a plain Hash (symbol- or string-keyed — e.g. a JSON fixture) into the
  # immutable value types, validating as it goes and raising
  # {ValidationError} on bad input. Adapters call these before mapping to their
  # wire format, so a malformed request fails the same way everywhere and never
  # reaches the network.
  #
  # A value object built with +.new+ goes through the same checks as a Hash:
  # Input turns it back into a Hash first. So whatever an adapter gets from
  # Input has passed every check, however the caller built it.
  #
  # Enum fields accept either the canonical symbol (+:taxable+) or a wire-style
  # string (+"TAXABLE"+, any case) — the bridge that lets the Ruby SDK consume
  # the same language-neutral fixtures as the TypeScript one.
  #
  # Deliberately dependency-free: a small hand-written validator, not a schema
  # library, keeping the core's runtime dependencies at zero.
  module Input
    # 統一編號 [mig 表 4-7].
    UBN_FORMAT = /\A\d{8}\z/
    # 手機條碼: "/" and 7 of 0-9 A-Z . + -. 自然人憑證: 2 letters and 14 digits.
    CARRIER_FORMATS = {
      CarrierType::MOBILE_BARCODE => %r{\A/[0-9A-Z.+-]{7}\z},
      CarrierType::CITIZEN_CERTIFICATE => /\A[A-Z]{2}\d{14}\z/
    }.freeze
    # MIG F0501 and G0501 allow a reason of 1 to 20 characters.
    MAX_REASON_LENGTH = 20
    DEFAULT_VOID_ALLOWANCE_REASON = "作廢折讓"
    # The rates the MIG allows [mig 表 4-18].
    TAX_RATES = [0, Rational(1, 100), Rational(2, 100), Rational(5, 100), Rational(15, 100),
                 Rational(25, 100)].freeze
    STANDARD_TAX_RATE = Rational(5, 100)
    # A reference or an allowance can describe a mixed-tax invoice.
    REFERENCE_TAX_TYPES = (TaxType::ALL + [TaxType::MIXED]).freeze

    module_function

    def issue(input, provider: nil)
      h = hash!(unbuild(input), "input", provider)
      items = build_items(h[:items], provider)
      amount = build_amount(h[:amount], provider)
      buyer = build_buyer(h[:buyer], provider)
      tax_type = enum!(h[:tax_type], TaxType::ALL, :tax_type, provider)
      category = h[:category] && enum!(h[:category], InvoiceCategory::ALL, :category, provider)
      check_category!(category, buyer, provider)
      parsed = IssueInvoiceInput.new(
        order_id: fetch!(h, :order_id, provider),
        buyer: buyer,
        items: items,
        amount: amount,
        tax_type: tax_type,
        price_mode: enum!(h[:price_mode], PriceMode::ALL, :price_mode, provider),
        tax_rate: tax_rate!(h[:tax_rate], items, tax_type, provider),
        category: category,
        carrier: build_carrier(h[:carrier], provider),
        donation: build_donation(h[:donation], provider),
        remark: h[:remark],
        currency: h[:currency],
        exchange_rate: h[:exchange_rate],
        provider_options: h[:provider_options]
      )
      check_issue_amount!(parsed, provider)
      parsed
    end

    def void(input, provider: nil)
      h = hash!(unbuild(input), "input", provider)
      VoidInvoiceInput.new(
        invoice: invoice_reference!(h[:invoice], provider, need_number: true),
        reason: reason!(fetch!(h, :reason, provider), provider),
        provider_options: h[:provider_options]
      )
    end

    # The tax type and rate come from the input, else from the invoice
    # reference. There is no default: an allowance taxed at the wrong rate is a
    # wrong filing. An allowance with no taxed line has rate 0.
    def allowance(input, provider: nil)
      h = hash!(unbuild(input), "input", provider)
      invoice = invoice_reference!(h[:invoice], provider, need_number: true)
      tax_type = h[:tax_type] ? enum!(h[:tax_type], REFERENCE_TAX_TYPES, :tax_type, provider) : invoice.tax_type
      fail!("tax_type is required, or invoice.tax_type in the reference", provider) if tax_type.nil?

      items = build_items(h[:items], provider)
      tax_rate = h[:tax_rate].nil? ? invoice.tax_rate : mig_rate!(h[:tax_rate], "tax_rate", provider)
      tax_rate ||= 0r if items.none? { |item| TaxType::TAXED.include?(item.tax_type || tax_type) }
      fail!("tax_rate is required, or invoice.tax_rate in the reference", provider) if tax_rate.nil?

      parsed = AllowanceInput.new(
        invoice: invoice,
        allowance_id: fetch!(h, :allowance_id, provider),
        items: items,
        amount: build_amount(h[:amount], provider),
        price_mode: enum!(h[:price_mode], PriceMode::ALL, :price_mode, provider),
        tax_type: tax_type,
        tax_rate: tax_rate,
        provider_options: h[:provider_options]
      )
      check_allowance_amount!(parsed, provider)
      parsed
    end

    def void_allowance(input, provider: nil)
      h = hash!(unbuild(input), "input", provider)
      VoidAllowanceInput.new(
        allowance: allowance_reference!(h[:allowance], provider),
        reason: reason!(blank?(h[:reason]) ? DEFAULT_VOID_ALLOWANCE_REASON : h[:reason], provider),
        provider_options: h[:provider_options]
      )
    end

    def query(input, provider: nil)
      h = hash!(unbuild(input), "input", provider)
      invoice = invoice_reference!(h[:invoice], provider, need_number: false)
      if blank?(invoice.number) && blank?(invoice.order_id)
        fail!("query needs invoice.number or invoice.order_id", provider)
      end
      QueryInvoiceInput.new(invoice: invoice, provider_options: h[:provider_options])
    end

    # A carrier on its own, for Provider#validate_carrier.
    def carrier(input, provider: nil)
      fail!("carrier is required", provider) if input.nil?

      build_carrier(unbuild(input), provider)
    end

    # A value object back to the Hash it came from, all the way down, so it
    # takes the same path through the checks as a Hash. A reference becomes
    # its stored form (#to_h).
    def unbuild(value)
      case value
      when InvoiceReference, AllowanceReference then value.to_h
      when Data then value.to_h.transform_values { |field| unbuild(field) }
      when Hash then value.transform_values { |field| unbuild(field) }
      when Array then value.map { |item| unbuild(item) }
      else value
      end
    end

    # --- amounts ---------------------------------------------------------------

    # The items decide the totals. An invoice follows F0401: for a consumer the
    # tax is inside sales_amount and tax_amount is 0, for a business it is apart.
    # Either way the tax is round(taxable sales × tax_rate), so the same input
    # gets the same tax at every provider.
    def check_issue_amount!(input, provider)
      breakdown = input.tax_breakdown(provider: provider)
      amount = input.amount
      check_total!(amount, breakdown, provider)
      if input.resolved_category == InvoiceCategory::B2B
        check_tax!(amount, breakdown, input.tax_rate, provider)
      elsif !amount.tax_amount.zero?
        fail!("a B2C invoice has tax_amount 0 and the tax inside sales_amount (F0401), got tax_amount " \
              "#{amount.tax_amount}", provider)
      end
    end

    # An allowance follows G0401: sales_amount excludes tax.
    def check_allowance_amount!(input, provider)
      breakdown = input.tax_breakdown(provider: provider)
      check_total!(input.amount, breakdown, provider)
      check_tax!(input.amount, breakdown, input.tax_rate, provider)
    end

    def check_total!(amount, breakdown, provider)
      return if amount.total_amount == breakdown.total_amount

      fail!("total_amount is #{amount.total_amount}, but the items add up to #{breakdown.total_amount} " \
            "with tax", provider)
    end

    def check_tax!(amount, breakdown, rate, provider)
      return if amount.tax_amount == breakdown.tax_amount

      fail!("tax_amount is #{amount.tax_amount}, but the tax of the items is #{breakdown.tax_amount} " \
            "(taxable #{breakdown.taxable_amount} at #{Number.plain(rate.to_r)})", provider)
    end

    # --- references ------------------------------------------------------------

    # An InvoiceReference, a Hash of its fields, or a plain invoice number.
    def invoice_reference!(value, provider, need_number:)
      fail!("invoice is required", provider) if blank?(value)

      reference = if value.is_a?(String)
                    InvoiceReference.new(number: value)
                  else
                    build_invoice_reference(hash!(value, "invoice", provider), provider)
                  end
      fail!("invoice.number is required", provider) if need_number && blank?(reference.number)
      reference
    end

    def build_invoice_reference(h, provider)
      ubn = blank?(h[:buyer_ubn]) ? nil : h[:buyer_ubn].to_s
      fail!("invoice.buyer_ubn must be 8 digits, got #{ubn.inspect}", provider) if ubn && !ubn.match?(UBN_FORMAT)

      InvoiceReference.new(
        number: presence(h[:number]),
        invoice_datetime: h[:invoice_datetime] &&
          Taipei.time(h[:invoice_datetime], field: "invoice.invoice_datetime", provider: provider),
        random_code: presence(h[:random_code]),
        order_id: presence(h[:order_id]),
        total_amount: h[:total_amount] && Number.integer!(h[:total_amount], field: "invoice.total_amount",
                                                                             provider: provider),
        buyer_ubn: ubn,
        tax_type: h[:tax_type] && enum!(h[:tax_type], REFERENCE_TAX_TYPES, :"invoice.tax_type", provider),
        tax_rate: h[:tax_rate].nil? ? nil : mig_rate!(h[:tax_rate], "invoice.tax_rate", provider)
      )
    end

    # An AllowanceReference, a Hash of its fields, or a plain allowance number.
    def allowance_reference!(value, provider)
      fail!("allowance is required", provider) if blank?(value)
      return AllowanceReference.new(allowance_number: value) if value.is_a?(String)

      h = hash!(value, "allowance", provider)
      AllowanceReference.new(
        allowance_number: fetch!(h, :allowance_number, provider),
        allowance_date: h[:allowance_date] &&
          Taipei.date(h[:allowance_date], field: "allowance.allowance_date", provider: provider),
        invoice_number: presence(h[:invoice_number])
      )
    end

    def presence(value)
      blank?(value) ? nil : value
    end

    # --- builders --------------------------------------------------------------

    def build_buyer(value, provider)
      return nil if value.nil?

      h = hash!(value, "buyer", provider)
      ubn = blank?(h[:ubn]) ? nil : h[:ubn].to_s
      fail!("buyer ubn must be 8 digits, got #{ubn.inspect}", provider) if ubn && !ubn.match?(UBN_FORMAT)

      Buyer.new(name: h[:name], ubn: ubn, email: h[:email], address: h[:address],
                phone: h[:phone])
    end

    def build_carrier(value, provider)
      return nil if value.nil?

      h = hash!(value, "carrier", provider)
      type = enum!(h[:type], CarrierType::ALL, :carrier_type, provider)
      format = CARRIER_FORMATS[type]
      if format && !h[:code].to_s.match?(format)
        fail!("carrier code for #{type} must match #{format.source}, got #{h[:code].inspect}", provider)
      end
      Carrier.new(type: type, code: h[:code])
    end

    def build_donation(value, provider)
      return nil if value.nil?

      # Kept as a String: a 愛心碼 is an identifier, not a number, and real ones
      # carry a leading zero (0096) that an integer round-trip would destroy.
      npoban = fetch!(hash!(value, "donation", provider), :npoban, provider).to_s
      unless npoban.match?(Donation::CODE_FORMAT)
        fail!("npoban must be 3–7 digits (愛心碼), got #{npoban.inspect}", provider)
      end

      Donation.new(npoban: npoban)
    end

    def build_amount(value, provider)
      fail!("amount is required", provider) if value.nil?

      h = hash!(value, "amount", provider)
      sales, tax, total = %i[sales_amount tax_amount total_amount].map do |field|
        value = Number.integer!(h[field], field: "amount.#{field}", provider: provider)
        fail!("amount.#{field} must not be negative, got #{value}", provider) if value.negative?
        value
      end
      unless sales + tax == total
        fail!("amount total #{total} != sales #{sales} + tax #{tax}", provider)
      end
      AmountSummary.new(sales_amount: sales, tax_amount: tax, total_amount: total)
    end

    def build_items(value, provider)
      fail!("items must be a non-empty array", provider) unless value.is_a?(Array) && !value.empty?

      value.each_with_index.map do |item, index|
        h = hash!(item, "items[#{index}]", provider)
        %i[quantity unit_price amount].each do |field|
          Number.decimal!(fetch!(h, field, provider), field: "items[#{index}].#{field}", provider: provider)
        end
        InvoiceItem.new(
          description: fetch!(h, :description, provider),
          quantity: fetch!(h, :quantity, provider),
          unit_price: fetch!(h, :unit_price, provider),
          amount: fetch!(h, :amount, provider),
          unit: h[:unit],
          tax_type: h[:tax_type] && enum!(h[:tax_type], TaxType::ALL, :tax_type, provider),
          remark: h[:remark]
        )
      end
    end

    # --- checks ----------------------------------------------------------------

    # A B2B invoice needs a 統一編號. An explicit category has to agree with it.
    def check_category!(category, buyer, provider)
      business = buyer&.business? || false
      if category == InvoiceCategory::B2B && !business
        fail!("a B2B invoice needs buyer.ubn", provider)
      elsif category == InvoiceCategory::B2C && business
        fail!("a B2C invoice cannot carry buyer.ubn #{buyer.ubn}", provider)
      end
    end

    # A decimal rate that the MIG allows. When none is given, the lines decide,
    # not the header: a taxable line is taxed at 5% under a tax-free header
    # too. A special-tax line has no default: the caller has to give its rate.
    def tax_rate!(value, items, tax_type, provider)
      return mig_rate!(value, "tax_rate", provider) unless value.nil?

      types = items.map { |item| item.tax_type || tax_type }
      return nil if types.include?(TaxType::SPECIAL)

      types.include?(TaxType::TAXABLE) ? STANDARD_TAX_RATE : 0r
    end

    def mig_rate!(value, field, provider)
      rate = Number.decimal!(value, field: field, provider: provider)
      unless TAX_RATES.include?(rate)
        fail!("#{field} must be one of the MIG rates (0, 0.01, 0.02, 0.05, 0.15, 0.25), got #{value.inspect}",
              provider)
      end
      rate
    end

    def reason!(reason, provider)
      length = reason.to_s.length
      fail!("reason must be #{MAX_REASON_LENGTH} characters or fewer, got #{length}", provider) if length > MAX_REASON_LENGTH
      reason
    end

    # --- helpers ---------------------------------------------------------------

    def enum!(value, allowed, field, provider)
      return value if allowed.include?(value)

      symbol = value.is_a?(String) ? value.downcase.to_sym : nil
      return symbol if symbol && allowed.include?(symbol)

      fail!("invalid #{field}: #{value.inspect}", provider)
    end

    # Read a required field, or fail naming it. "Required" means present, not
    # merely non-nil: an empty string is a missing value everywhere in this
    # model, and letting one through only defers the failure to the provider.
    def fetch!(hash, key, provider)
      value = hash[key]
      fail!("#{key} is required", provider) if blank?(value)
      value
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def fail!(message, provider)
      raise ValidationError.new(message, provider: provider || "einvoice")
    end

    # Coerce a value that has to be an object, naming the field it came from.
    # Every nested shape goes through here, so a caller who passes a String, an
    # Array or nothing at all gets the same {ValidationError} as any other bad
    # input instead of a NoMethodError raised three frames deeper.
    def hash!(value, field, provider)
      fail!("#{field} must be an object, got #{type_of(value)}", provider) unless value.is_a?(Hash)

      symbolize_keys(value)
    end

    # One level deep, which is all the nesting there is: arrays of hashes are
    # handled by the per-item builders, which call back through {hash!}.
    def symbolize_keys(hash)
      hash.each_with_object({}) { |(key, value), out| out[key.to_sym] = value }
    end

    def type_of(value)
      value.nil? ? "nil" : value.class.name
    end
  end
end
