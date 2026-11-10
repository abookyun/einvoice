# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoice::Taipei do
  around do |example|
    original = ENV.fetch("TZ", nil)
    ENV["TZ"] = "Asia/Tokyo"
    example.run
  ensure
    ENV["TZ"] = original
  end

  it "converts a Time to Taipei" do
    time = described_class.time(Time.utc(2026, 7, 31, 16, 30))
    expect(time.strftime("%F %T %:z")).to eq("2026-08-01 00:30:00 +08:00")
  end

  it "gives the Taipei date of a Time" do
    expect(described_class.date(Time.utc(2026, 7, 31, 16, 30))).to eq(Date.new(2026, 8, 1))
    expect(described_class.date(Date.new(2026, 8, 1))).to eq(Date.new(2026, 8, 1))
  end

  it "reads the clock it is given" do
    clock = double(now: Time.utc(2026, 12, 31, 16, 0))
    expect(described_class.today(clock)).to eq(Date.new(2027, 1, 1))
    expect(described_class.now(clock).utc_offset).to eq(8 * 3600)
  end

  it "accepts a DateTime" do
    value = DateTime.new(2026, 7, 31, 16, 30, 0, "+00:00")
    expect(described_class.time(value).strftime("%F %T")).to eq("2026-08-01 00:30:00")
    expect(described_class.date(value)).to eq(Date.new(2026, 8, 1))
  end

  it "reads a string only with an offset, or as a plain date" do
    expect(described_class.date("2026-08-01T16:30:00Z")).to eq(Date.new(2026, 8, 2))
    expect(described_class.date("2026-08-01")).to eq(Date.new(2026, 8, 1))
    expect { described_class.time("2026-08-01T10:00:00", field: "cancel_datetime") }
      .to raise_error(Einvoice::ValidationError, /cancel_datetime must be a date/)
  end
end
