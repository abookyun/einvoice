# frozen_string_literal: true

RSpec.describe Einvoice::EzPay::Errors do
  describe ".classify" do
    # The note's table is the mapping. Both ways: what the note says holds,
    # and nothing is mapped that the note leaves out.
    rows = NoteErrorTable.tables("ezpay/invoice.md").flatten
    it "maps every code as the note says" do
      expect(NoteErrorTable.mismatches(rows) { |code| described_class.classify(code) }).to be_empty
    end

    it "maps no code that the note leaves out" do
      expect(described_class::CODES.keys - rows.flat_map(&:codes)).to be_empty
    end

    it "falls back to :provider for a code outside the table" do
      expect(described_class.classify("XYZ00000")).to eq([:provider, nil])
    end

    # The code list has no code for these cases, so the operation decides.
    it "reads an already-voided invoice on an allowance as a refusal, not success" do
      expect(described_class.classify("LIB10005", :allowance))
        .to eq([:conflict, Einvoice::Reason::ALLOWANCE_BLOCKED_BY_VOID])
    end

    it "reads a failed query on an allowance void as an unknown allowance" do
      expect(described_class.classify("IAI10002", :void_allowance)).to eq([:not_found, nil])
    end

    it "maps only to Reason values the core defines" do
      reasons = (described_class::CODES.values + described_class::CONTEXT.values.flat_map(&:values))
                .map(&:last).compact
      expect(reasons - Einvoice::Reason::ALL).to be_empty
    end
  end
end
