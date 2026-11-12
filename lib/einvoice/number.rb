# frozen_string_literal: true

module Einvoice
  # Number checks for MIG fields. Amounts on an item may have up to 7 decimal
  # places (MIG 表 15-5). Totals are whole TWD.
  module Number
    DECIMAL_PLACES = 7
    DECIMAL = /\A-?\d+(\.\d+)?\z/

    module_function

    # A Rational for a number with at most 7 decimal places. Accepts Integer,
    # Rational, BigDecimal, Float and numeric strings. Float goes through its
    # string form, so 0.1 stays 1/10 and does not become a binary fraction.
    def decimal!(value, field:, provider: nil)
      rational = to_rational(value)
      invalid!("#{field} must be a number, got #{value.inspect}", provider) if rational.nil?
      if (rational * (10**DECIMAL_PLACES)).denominator != 1
        invalid!("#{field} may have at most #{DECIMAL_PLACES} decimal places, got #{value.inspect}", provider)
      end
      rational
    end

    def integer!(value, field:, provider: nil)
      rational = to_rational(value)
      if rational.nil? || rational.denominator != 1
        invalid!("#{field} must be a whole number, got #{value.inspect}", provider)
      end
      rational.to_i
    end

    def to_rational(value)
      case value
      when Integer, Rational then value.to_r
      when Float then value.finite? ? Rational(value.to_s) : nil
      when Numeric then value.to_r
      when String then value.strip.match?(DECIMAL) ? Rational(value.strip) : nil
      end
    end

    # An Integer when the value is whole, else a Float, so an amount serializes
    # as 95 or 47.5 and not as a Rational.
    def plain(value)
      value.denominator == 1 ? value.to_i : value.to_f
    end

    def invalid!(message, provider)
      raise ValidationError.new(message, provider: provider || "einvoice")
    end
  end
end
