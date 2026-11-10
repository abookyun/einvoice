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
    # A date and time with an offset: ISO 8601 (2026-08-01T10:00:00+08:00, or Z)
    # or Time#to_s (2026-08-01 10:00:00 +0800). A string without an offset is
    # refused, so a stored time is never read in the wrong zone.
    ZONED_TIME = /\A(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(\.\d+)? ?(Z|[+-]\d{2}:?\d{2})\z/
    # A calendar date, read as that day in Taipei.
    DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/

    module_function

    # The current Taipei time. +clock+ is anything that answers #now.
    def now(clock = Time)
      clock.now.getlocal(OFFSET)
    end

    def today(clock = Time)
      now(clock).to_date
    end

    # A Time in Taipei. A Date becomes midnight in Taipei. A String has to match
    # ZONED_TIME or DATE.
    def time(value, field: "time", provider: nil)
      value = parse(value, field, provider) if value.is_a?(String)
      case value
      when DateTime then value.to_time.getlocal(OFFSET)
      when Date then Time.new(value.year, value.month, value.day, 0, 0, 0, OFFSET)
      when Time then value.getlocal(OFFSET)
      else invalid!("#{field} must be a Time or a Date, got #{value.class}", provider)
      end
    end

    # The Taipei calendar date of a Time, or the Date itself. A String has to
    # match ZONED_TIME or DATE.
    def date(value, field: "date", provider: nil)
      value = parse(value, field, provider) if value.is_a?(String)
      case value
      when DateTime then value.to_time.getlocal(OFFSET).to_date
      when Date then value
      when Time then value.getlocal(OFFSET).to_date
      else invalid!("#{field} must be a Date or a Time, got #{value.class}", provider)
      end
    end

    # The stored form of a time: ISO 8601 in Taipei, with fractional seconds
    # only when it has them. +time+ reads it back unchanged.
    def iso8601(value)
      value = time(value)
      format = value.subsec.zero? ? "%Y-%m-%dT%H:%M:%S%:z" : "%Y-%m-%dT%H:%M:%S.%N%:z"
      value.strftime(format)
    end

    def parse(string, field, provider)
      if (match = ZONED_TIME.match(string))
        year, month, day, hour, minute, second, fraction, zone = match.captures
        seconds = second.to_i + (fraction ? Rational(fraction[1..].to_i, 10**(fraction.length - 1)) : 0)
        zone = zone == "Z" ? "UTC" : zone.sub(/(\d{2})(\d{2})\z/, '\1:\2')
        Time.new(year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i, seconds, zone)
      elsif (match = DATE.match(string))
        Date.new(*match.captures.map(&:to_i))
      else
        invalid!("#{field} must be a date (2026-08-01) or a time with an offset (2026-08-01T10:00:00+08:00), " \
                 "got #{string.inspect}", provider)
      end
    rescue ArgumentError # Date::Error is one too
      invalid!("#{field} is not a valid date or time, got #{string.inspect}", provider)
    end

    def invalid!(message, provider)
      raise ValidationError.new(message, provider: provider || "einvoice")
    end
  end
end
