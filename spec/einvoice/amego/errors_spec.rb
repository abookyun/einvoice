# frozen_string_literal: true

RSpec.describe Einvoice::Amego::Errors do
  describe ".classify" do
    {
      15 => [:validation, Einvoice::Reason::STALE_TIMESTAMP],
      16 => [:auth, Einvoice::Reason::CREDENTIALS_INVALID],
      21 => [:provider, Einvoice::Reason::RATE_LIMITED],
      71 => [:not_found, nil],
      3_040_111 => [:number_exhausted, nil],
      3_040_171 => [:conflict, Einvoice::Reason::DUPLICATE_ORDER],
      3_050_121 => [:conflict, Einvoice::Reason::RETRY_LATER],
      3_050_122 => [:conflict, Einvoice::Reason::ALREADY_VOIDED],
      3_050_131 => [:conflict, Einvoice::Reason::RETRY_LATER],
      3_050_141 => [:conflict, Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE],
      4_040_153 => [:conflict, Einvoice::Reason::ALLOWANCE_BLOCKED_BY_VOID],
      4_040_161 => [:conflict, Einvoice::Reason::DUPLICATE_ALLOWANCE],
      4_050_134 => [:not_found, nil],
      4_050_141 => [:conflict, Einvoice::Reason::RETRY_LATER]
    }.each do |code, expected|
      it "maps #{code} to #{expected.inspect}" do
        expect(described_class.classify(code)).to eq(expected)
      end
    end

    it "reads a code sent as a string" do
      expect(described_class.classify("71")).to eq([:not_found, nil])
    end

    it "treats the other f0401 30401xx codes as field format errors" do
      expect(described_class.classify(3_040_150)).to eq([:validation, nil])
    end

    it "falls back to :provider for a code outside the table" do
      expect(described_class.classify(5_555_555)).to eq([:provider, nil])
      expect(described_class.classify("x")).to eq([:provider, nil])
    end

    it "maps only to Reason values the core defines" do
      reasons = described_class::CODES.values.map(&:last).compact
      expect(reasons - Einvoice::Reason::ALL).to be_empty
    end
  end
end
