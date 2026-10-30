# frozen_string_literal: true

module Einvoice
  # Coerces a plain Hash (symbol- or string-keyed — e.g. a JSON fixture) into the
  # immutable value types, validating as it goes and raising
  # {ValidationError} on bad input. Adapters call these before mapping to their
  # wire format, so a malformed request fails the same way everywhere and never
  # reaches the network. An already-built value object passes through untouched.
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
    DEFAULT_TAX_RATES = {
      TaxType::TAXABLE => Rational(5, 100),
      TaxType::ZERO_RATED => 0r,
      TaxType::TAX_FREE => 0r
    }.freeze

    module_function

    def issue(input, provider: nil)
      return input if input.is_a?(IssueInvoiceInput)

      h = hash!(input, "input", provider)
      items = build_items(h[:items], provider)
      amount = build_amount(h[:amount], provider)
      buyer = build_buyer(h[:buyer], provider)
      tax_type = enum!(h[:tax_type], TaxType, :tax_type, provider)
      category = h[:category] && enum!(h[:category], InvoiceCategory, :category, provider)
      check_category!(category, buyer, provider)
      IssueInvoiceInput.new(
        order_id: fetch!(h, :order_id, provider),
        buyer: buyer,
        items: items,
        amount: amount,
        tax_type: tax_type,
        price_mode: enum!(h[:price_mode], PriceMode, :price_mode, provider),
        tax_rate: tax_rate!(h[:tax_rate], tax_type, provider),
        category: category,
        carrier: build_carrier(h[:carrier], provider),
        donation: build_donation(h[:donation], provider),
        remark: h[:remark],
        currency: h[:currency],
        exchange_rate: h[:exchange_rate],
        provider_options: h[:provider_options]
      )
    end

    def void(input, provider: nil)
      return input if input.is_a?(VoidInvoiceInput)

      h = hash!(input, "input", provider)
      VoidInvoiceInput.new(
        invoice: invoice_reference!(h[:invoice], provider, need_number: true),
        reason: reason!(fetch!(h, :reason, provider), provider),
        provider_options: h[:provider_options]
      )
    end

    def allowance(input, provider: nil)
      return input if input.is_a?(AllowanceInput)

      h = hash!(input, "input", provider)
      AllowanceInput.new(
        invoice: invoice_reference!(h[:invoice], provider, need_number: true),
        allowance_id: fetch!(h, :allowance_id, provider),
        items: build_items(h[:items], provider),
        amount: build_amount(h[:amount], provider),
        provider_options: h[:provider_options]
      )
    end

    def void_allowance(input, provider: nil)
      return input if input.is_a?(VoidAllowanceInput)

      h = hash!(input, "input", provider)
      VoidAllowanceInput.new(
        allowance: allowance_reference!(h[:allowance], provider),
        reason: reason!(blank?(h[:reason]) ? DEFAULT_VOID_ALLOWANCE_REASON : h[:reason], provider),
        provider_options: h[:provider_options]
      )
    end

    def query(input, provider: nil)
      return input if input.is_a?(QueryInvoiceInput)

      h = hash!(input, "input", provider)
      invoice = invoice_reference!(h[:invoice], provider, need_number: false)
      if blank?(invoice.number) && blank?(invoice.order_id)
        fail!("query needs invoice.number or invoice.order_id", provider)
      end
      QueryInvoiceInput.new(invoice: invoice, provider_options: h[:provider_options])
    end

    # --- references ------------------------------------------------------------

    # An InvoiceReference, a Hash of its fields, or a plain invoice number.
    def invoice_reference!(value, provider, need_number:)
      fail!("invoice is required", provider) if blank?(value)

      reference = case value
                  when InvoiceReference then value
                  when String then InvoiceReference.new(number: value)
                  else build_invoice_reference(hash!(value, "invoice", provider), provider)
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
        buyer_ubn: ubn
      )
    end

    # An AllowanceReference, a Hash of its fields, or a plain allowance number.
    def allowance_reference!(value, provider)
      fail!("allowance is required", provider) if blank?(value)
      return value if value.is_a?(AllowanceReference)
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
      return value if value.is_a?(Buyer)

      h = hash!(value, "buyer", provider)
      ubn = blank?(h[:ubn]) ? nil : h[:ubn].to_s
      fail!("buyer ubn must be 8 digits, got #{ubn.inspect}", provider) if ubn && !ubn.match?(UBN_FORMAT)

      Buyer.new(name: h[:name], ubn: ubn, email: h[:email], address: h[:address],
                phone: h[:phone])
    end

    def build_carrier(value, provider)
      return nil if value.nil?
      return value if value.is_a?(Carrier)

      h = hash!(value, "carrier", provider)
      type = enum!(h[:type], CarrierType, :carrier_type, provider)
      format = CARRIER_FORMATS[type]
      if format && !h[:code].to_s.match?(format)
        fail!("carrier code for #{type} must match #{format.source}, got #{h[:code].inspect}", provider)
      end
      Carrier.new(type: type, code: h[:code])
    end

    def build_donation(value, provider)
      return nil if value.nil?
      return value if value.is_a?(Donation)

      # Kept as a String: a 愛心碼 is an identifier, not a number, and real ones
      # carry a leading zero (0096) that an integer round-trip would destroy.
      npoban = fetch!(hash!(value, "donation", provider), :npoban, provider).to_s
      unless npoban.match?(Donation::CODE_FORMAT)
        fail!("npoban must be 3–7 digits (愛心碼), got #{npoban.inspect}", provider)
      end

      Donation.new(npoban: npoban)
    end

    def build_amount(value, provider)
      return value if value.is_a?(AmountSummary)
      fail!("amount is required", provider) if value.nil?

      h = hash!(value, "amount", provider)
      sales = integer!(h[:sales_amount], :sales_amount, provider)
      tax = integer!(h[:tax_amount], :tax_amount, provider)
      total = integer!(h[:total_amount], :total_amount, provider)
      { sales_amount: sales, tax_amount: tax, total_amount: total }.each do |field, value|
        fail!("#{field} must not be negative, got #{value}", provider) if value.negative?
      end
      unless sales + tax == total
        fail!("amount total #{total} != sales #{sales} + tax #{tax}", provider)
      end
      AmountSummary.new(sales_amount: sales, tax_amount: tax, total_amount: total)
    end

    def build_items(value, provider)
      fail!("items must be a non-empty array", provider) unless value.is_a?(Array) && !value.empty?

      value.each_with_index.map do |item, index|
        next item if item.is_a?(InvoiceItem)

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
          tax_type: h[:tax_type] && enum!(h[:tax_type], TaxType, :tax_type, provider),
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

    # A decimal rate that the MIG allows. The default depends on the tax type.
    # A special-tax invoice has no default: the caller has to give its rate.
    def tax_rate!(value, tax_type, provider)
      return DEFAULT_TAX_RATES[tax_type] if value.nil?

      rate = Number.decimal!(value, field: "tax_rate", provider: provider)
      unless TAX_RATES.include?(rate)
        fail!("tax_rate must be one of the MIG rates (0, 0.01, 0.02, 0.05, 0.15, 0.25), got #{value.inspect}",
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

    def enum!(value, mod, field, provider)
      return value if mod::ALL.include?(value)

      symbol = value.is_a?(String) ? value.downcase.to_sym : nil
      return symbol if symbol && mod::ALL.include?(symbol)

      fail!("invalid #{field}: #{value.inspect}", provider)
    end

    def integer!(value, field, provider)
      return value if value.is_a?(Integer)
      # Accept an integral float/numeric but reject fractional TWD (MIG invariant).
      return value.to_i if value.is_a?(Numeric) && value == value.to_i

      fail!("#{field} must be an integer (TWD), got #{value.inspect}", provider)
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
