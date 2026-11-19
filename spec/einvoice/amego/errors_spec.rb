# frozen_string_literal: true

RSpec.describe Einvoice::Amego::Errors do
  describe ".classify" do
    # The note's table is the mapping. Both ways: what the note says holds,
    # and nothing is mapped that the note leaves out.
    rows = NoteErrorTable.tables("amego/api.md").flatten
    it "maps every code as the note says" do
      expect(NoteErrorTable.mismatches(rows) { |code| described_class.classify(Integer(code)) }).to be_empty
    end

    it "maps no code that the note leaves out" do
      expect(described_class::CODES.keys.map(&:to_s) - rows.flat_map(&:codes)).to be_empty
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
