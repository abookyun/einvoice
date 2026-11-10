# frozen_string_literal: true

module Einvoice
  # The tax of an invoice or an allowance, computed by the core from its items,
  # +price_mode+, +tax_type+ and +tax_rate+. Adapters read the values their
  # provider wants from here and do not compute tax themselves.
  #
  # The totals are whole TWD and follow the MIG: +sales_amount+ excludes tax and
  # is +taxable_amount+ + +zero_rated_amount+ + +tax_free_amount+, and
  # +total_amount+ is +sales_amount+ + +tax_amount+. A B2C invoice reports its
  # AmountSummary with the tax inside the sales amount (F0401), but its
  # breakdown still splits the tax out, for providers that ask for it.
  TaxBreakdown = Data.define(:lines, :sales_amount, :taxable_amount, :zero_rated_amount, :tax_free_amount,
                             :tax_amount, :total_amount)

  # One line of a TaxBreakdown. +net_amount+ excludes tax, +gross_amount+
  # includes it, and +tax+ is whole TWD. The unit prices come from the item's
  # +unit_price+, rounded to 7 decimal places (MIG 表 15-5). They are not
  # derived from the amounts, so +unit price × quantity+ can differ from the
  # amount by the rounding of the line tax. Each provider note says how much
  # its API allows.
  TaxBreakdown::Line = Data.define(:tax_type, :net_amount, :tax, :gross_amount, :net_unit_price,
                                   :gross_unit_price)

  # Splits tax over lines by the largest remainder: each taxed line takes the
  # whole part of its share, and the units left go to the lines with the
  # largest fractions, later lines first on a tie. So the line taxes add up to
  # the total tax, and each line tax is the floor or the ceiling of its share.
  # A line tax has the sign of its amount: a discount line with a negative
  # amount can take a negative tax, and no other line does. Lines that are not
  # taxed have tax 0.
  module TaxSplit
    Line = Data.define(:amount, :tax)

    module_function

    # The TaxBreakdown of +items+. An item without a tax_type has the invoice's.
    # With a MIXED invoice tax type, every item needs its own.
    def breakdown(items, tax_type:, tax_rate:, price_mode:, provider: nil)
      types = items.each_with_index.map do |item, index|
        type = item.tax_type || tax_type
        if type.nil? || type == TaxType::MIXED
          invalid!("items[#{index}].tax_type is required when the invoice has mixed tax", provider)
        end
        type
      end
      taxed = types.map { |type| TaxType::TAXED.include?(type) }
      invalid!("tax_rate is required for a #{types.find { |t| TaxType::TAXED.include?(t) }} line", provider) if
        taxed.any? && tax_rate.nil?

      rate = taxed.any? ? Number.decimal!(tax_rate, field: "tax_rate", provider: provider) : 0r
      # A taxed line at rate 0 would file taxable sales as untaxed.
      invalid!("tax_rate must be above 0 when a line is taxable", provider) if taxed.any? && rate.zero?
      inclusive = price_mode == PriceMode::TAX_INCLUSIVE
      amounts = items.each_with_index.map do |item, index|
        Number.decimal!(item.amount, field: "items[#{index}].amount", provider: provider)
      end
      split = if inclusive
                split(amounts, taxable: taxed, rate: rate)
              else
                allocate(amounts, taxable: taxed, total_tax: (taxable_sum(amounts, taxed) * rate).round)
              end

      lines = items.each_with_index.map do |item, index|
        price = Number.decimal!(item.unit_price, field: "items[#{index}].unit_price", provider: provider)
        net_price = taxed[index] && inclusive ? price / (1 + rate) : price
        gross_price = taxed[index] && !inclusive ? price * (1 + rate) : price
        line = split[index]
        TaxBreakdown::Line.new(tax_type: types[index], net_amount: Number.plain(line.amount), tax: line.tax,
                               gross_amount: Number.plain(line.amount + line.tax),
                               net_unit_price: Number.plain(net_price.round(Number::DECIMAL_PLACES)),
                               gross_unit_price: Number.plain(gross_price.round(Number::DECIMAL_PLACES)))
      end
      totals(lines, split, inclusive)
    end

    def totals(lines, split, inclusive)
      tax = split.sum(&:tax)
      sales = inclusive ? split.sum(0r) { |line| line.amount + line.tax }.round - tax : split.sum(0r, &:amount).round
      # Sum the exact split, not the lines: net_amount may be a Float, and 0.35 +
      # 0.15 as Floats rounds to 0, not 1.
      untaxed = lambda do |type|
        lines.zip(split).select { |line, _| line.tax_type == type }.sum(0r) { |_, part| part.amount }.round
      end
      zero = untaxed.call(TaxType::ZERO_RATED)
      free = untaxed.call(TaxType::TAX_FREE)
      TaxBreakdown.new(lines: lines, sales_amount: sales, taxable_amount: sales - zero - free,
                       zero_rated_amount: zero, tax_free_amount: free, tax_amount: tax, total_amount: sales + tax)
    end

    # Splits the tax out of tax-included amounts. The total tax is
    # round(taxed total × rate / (1 + rate)). Returns tax-excluded lines.
    def split(amounts, taxable:, rate:)
      factor = rate / (1 + rate)
      total = (taxable_sum(amounts, taxable) * factor).round
      taxes = distribute(amounts, taxable, total) { |amount| amount * factor }
      amounts.zip(taxes).map { |amount, tax| Line.new(amount: amount - tax, tax: tax) }
    end

    # Spreads a total tax over tax-excluded amounts, in proportion to the taxed
    # amounts. Returns the lines with their amounts unchanged.
    def allocate(amounts, taxable:, total_tax:)
      base = taxable_sum(amounts, taxable)
      taxes = distribute(amounts, taxable, total_tax) { |amount| base.zero? ? 0 : amount * total_tax / base }
      amounts.zip(taxes).map { |amount, tax| Line.new(amount: amount, tax: tax) }
    end

    def taxable_sum(amounts, taxable)
      amounts.each_index.sum(0r) { |i| taxable[i] ? amounts[i] : 0 }
    end

    def distribute(amounts, taxable, total)
      shares = amounts.each_index.map { |i| taxable[i] ? yield(amounts[i]) : 0r }
      taxes = shares.map(&:floor)
      order = amounts.each_index.select { |i| taxable[i] }.sort_by { |i| [taxes[i] - shares[i], -i] }
      (total - taxes.sum).times { |k| taxes[order[k]] += 1 }
      taxes
    end

    def invalid!(message, provider)
      raise ValidationError.new(message, provider: provider || "einvoice")
    end
  end
end
