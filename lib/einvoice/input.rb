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

      h = deep_symbolize(input)
      items = build_items(h[:items], provider)
      amount = build_amount(h[:amount], provider)
      require_present!(h, :order_id, provider)
      IssueInvoiceInput.new(
        order_id: h.fetch(:order_id),
        buyer: build_buyer(h[:buyer]),
        items: items,
        amount: amount,
        tax_type: enum!(h[:tax_type], TaxType, :tax_type, provider),
        price_mode: enum!(h[:price_mode], PriceMode, :price_mode, provider),
        tax_rate: h[:tax_rate],
        category: h[:category] && enum!(h[:category], InvoiceCategory, :category, provider),
        carrier: build_carrier(h[:carrier], provider),
        donation: h[:donation] && Donation.new(npoban: fetch!(h[:donation], :npoban, provider)),
        remark: h[:remark],
        currency: h[:currency],
        exchange_rate: h[:exchange_rate],
        date: h[:date],
        provider_options: h[:provider_options]
      )
    end

    def void(input, provider: nil)
      return input if input.is_a?(VoidInvoiceInput)

      h = deep_symbolize(input)
      require_present!(h, :invoice_number, provider)
      require_present!(h, :reason, provider)
      VoidInvoiceInput.new(
        invoice_number: h.fetch(:invoice_number),
        reason: h.fetch(:reason),
        date: h[:date],
        provider_options: h[:provider_options]
      )
    end

    def allowance(input, provider: nil)
      return input if input.is_a?(AllowanceInput)

      h = deep_symbolize(input)
      require_present!(h, :invoice_number, provider)
      require_present!(h, :allowance_id, provider)
      AllowanceInput.new(
        invoice_number: h.fetch(:invoice_number),
        allowance_id: h.fetch(:allowance_id),
        items: build_items(h[:items], provider),
        amount: build_amount(h[:amount], provider),
        date: h[:date],
        provider_options: h[:provider_options]
      )
    end

    def void_allowance(input, provider: nil)
      return input if input.is_a?(VoidAllowanceInput)

      h = deep_symbolize(input)
      require_present!(h, :invoice_number, provider)
      require_present!(h, :allowance_number, provider)
      VoidAllowanceInput.new(
        invoice_number: h.fetch(:invoice_number),
        allowance_number: h.fetch(:allowance_number),
        reason: h[:reason],
        provider_options: h[:provider_options]
      )
    end

    def query(input, provider: nil)
      return input if input.is_a?(QueryInvoiceInput)

      h = deep_symbolize(input)
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

    def build_buyer(value)
      return nil if value.nil?
      return value if value.is_a?(Buyer)

      h = deep_symbolize(value)
      Buyer.new(name: h[:name], ubn: h[:ubn], email: h[:email], address: h[:address],
                phone: h[:phone])
    end

    def build_carrier(value, provider)
      return nil if value.nil?
      return value if value.is_a?(Carrier)

      h = deep_symbolize(value)
      Carrier.new(type: enum!(h[:type], CarrierType, :carrier_type, provider), code: h[:code])
    end

    def build_amount(value, provider)
      return value if value.is_a?(AmountSummary)
      fail!("amount is required", provider) if value.nil?

      h = deep_symbolize(value)
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

      value.map do |item|
        next item if item.is_a?(InvoiceItem)

        h = deep_symbolize(item)
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

    def require_present!(hash, key, provider)
      fail!("#{key} is required", provider) if blank?(hash[key])
    end

    def fetch!(hash, key, provider)
      value = hash[key]
      fail!("#{key} is required", provider) if value.nil?
      value
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def fail!(message, provider)
      raise ValidationError.new(message, provider: provider || "einvoice")
    end

    # Shallow-then-nested symbolize without ActiveSupport. Leaves arrays of
    # hashes to the per-item builders.
    def deep_symbolize(value)
      return value unless value.is_a?(Hash)

      value.each_with_object({}) do |(k, v), out|
        out[k.to_sym] = v
      end
    end
  end
end
