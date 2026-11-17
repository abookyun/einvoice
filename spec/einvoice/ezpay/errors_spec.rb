# frozen_string_literal: true

RSpec.describe Einvoice::EzPay::Errors do
  describe ".classify" do
    {
      "KEY10002" => [:auth, Einvoice::Reason::CREDENTIALS_INVALID],
      "KEY10007" => [:validation, Einvoice::Reason::STALE_TIMESTAMP],
      "KEY10014" => [:network, nil],
      "INV20006" => [:not_found, nil],
      "INV90005" => [:auth, Einvoice::Reason::CONTRACT_EXPIRED],
      "INV90006" => [:number_exhausted, nil],
      "LIB10003" => [:conflict, Einvoice::Reason::DUPLICATE_ORDER],
      "LIB10005" => [:conflict, Einvoice::Reason::ALREADY_VOIDED],
      "LIB10007" => [:conflict, Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE],
      "LIB10009" => [:conflict, Einvoice::Reason::RETRY_LATER],
      "IAI10002" => [:provider, nil],
      "XYZ00000" => [:provider, nil]
    }.each do |code, expected|
      it "maps #{code} to #{expected.inspect}" do
        expect(described_class.classify(code)).to eq(expected)
      end
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
