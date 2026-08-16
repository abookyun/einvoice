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
    module_function

    def issue(input, provider: nil)
      return input if input.is_a?(IssueInvoiceInput)

      h = hash!(input, "input", provider)
      items = build_items(h[:items], provider)
      amount = build_amount(h[:amount], provider)
      IssueInvoiceInput.new(
        order_id: fetch!(h, :order_id, provider),
        buyer: build_buyer(h[:buyer], provider),
        items: items,
        amount: amount,
        tax_type: enum!(h[:tax_type], TaxType, :tax_type, provider),
        price_mode: enum!(h[:price_mode], PriceMode, :price_mode, provider),
        tax_rate: h[:tax_rate],
        category: h[:category] && enum!(h[:category], InvoiceCategory, :category, provider),
        carrier: build_carrier(h[:carrier], provider),
        donation: build_donation(h[:donation], provider),
        remark: h[:remark],
        currency: h[:currency],
        exchange_rate: h[:exchange_rate],
        date: h[:date],
        provider_options: h[:provider_options]
      )
    end

    def void(input, provider: nil)
      return input if input.is_a?(VoidInvoiceInput)

      h = hash!(input, "input", provider)
      VoidInvoiceInput.new(
        invoice_number: fetch!(h, :invoice_number, provider),
        reason: fetch!(h, :reason, provider),
        date: h[:date],
        provider_options: h[:provider_options]
      )
    end

    def allowance(input, provider: nil)
      return input if input.is_a?(AllowanceInput)

      h = hash!(input, "input", provider)
      AllowanceInput.new(
        invoice_number: fetch!(h, :invoice_number, provider),
        allowance_id: fetch!(h, :allowance_id, provider),
        items: build_items(h[:items], provider),
        amount: build_amount(h[:amount], provider),
        date: h[:date],
        provider_options: h[:provider_options]
      )
    end

    def void_allowance(input, provider: nil)
      return input if input.is_a?(VoidAllowanceInput)

      h = hash!(input, "input", provider)
      VoidAllowanceInput.new(
        invoice_number: fetch!(h, :invoice_number, provider),
        allowance_number: fetch!(h, :allowance_number, provider),
        reason: h[:reason],
        provider_options: h[:provider_options]
      )
    end

    def query(input, provider: nil)
      return input if input.is_a?(QueryInvoiceInput)

      h = hash!(input, "input", provider)
      if blank?(h[:invoice_number]) && blank?(h[:order_id])
        fail!("query requires invoice_number or order_id", provider)
      end
      QueryInvoiceInput.new(
        invoice_number: h[:invoice_number],
        order_id: h[:order_id],
        provider_options: h[:provider_options]
      )
    end

    # --- builders --------------------------------------------------------------

    def build_buyer(value, provider)
      return nil if value.nil?
      return value if value.is_a?(Buyer)

      h = hash!(value, "buyer", provider)
      Buyer.new(name: h[:name], ubn: h[:ubn], email: h[:email], address: h[:address],
                phone: h[:phone])
    end

    def build_carrier(value, provider)
      return nil if value.nil?
      return value if value.is_a?(Carrier)

      h = hash!(value, "carrier", provider)
      Carrier.new(type: enum!(h[:type], CarrierType, :carrier_type, provider), code: h[:code])
    end

    def build_donation(value, provider)
      return nil if value.nil?
      return value if value.is_a?(Donation)

      Donation.new(npoban: fetch!(hash!(value, "donation", provider), :npoban, provider))
    end

    def build_amount(value, provider)
      return value if value.is_a?(AmountSummary)
      fail!("amount is required", provider) if value.nil?

      h = hash!(value, "amount", provider)
      sales = integer!(h[:sales_amount], :sales_amount, provider)
      tax = integer!(h[:tax_amount], :tax_amount, provider)
      total = integer!(h[:total_amount], :total_amount, provider)
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
