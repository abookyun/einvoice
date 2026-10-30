# frozen_string_literal: true

require "date"

module Einvoice
  # Taipei time (UTC+8). Taiwan has no daylight saving time, so a fixed offset
  # is correct. The MIG reads every date and time in UTC+8.
  #
  # Adapters use this module and do not call Date#to_time. Date#to_time uses the
  # host time zone, so on a host east of UTC+8 it gives the day before.
  module Taipei
    OFFSET = "+08:00"

    module_function

    # The current Taipei time. +clock+ is anything that answers #now.
    def now(clock = Time)
      clock.now.getlocal(OFFSET)
    end

    def today(clock = Time)
      now(clock).to_date
    end

    # A Time in Taipei. A Date becomes midnight in Taipei.
    def time(value, field: "time", provider: nil)
      case value
      when DateTime then value.to_time.getlocal(OFFSET)
      when Date then Time.new(value.year, value.month, value.day, 0, 0, 0, OFFSET)
      when Time then value.getlocal(OFFSET)
      else invalid!("#{field} must be a Time or a Date, got #{value.class}", provider)
      end
    end

    # The Taipei calendar date of a Time, or the Date itself.
    def date(value, field: "date", provider: nil)
      case value
      when DateTime then value.to_time.getlocal(OFFSET).to_date
      when Date then value
      when Time then value.getlocal(OFFSET).to_date
      else invalid!("#{field} must be a Date or a Time, got #{value.class}", provider)
      end
    end

    def invalid!(message, provider)
      raise ValidationError.new(message, provider: provider || "einvoice")
    end
  end
end
