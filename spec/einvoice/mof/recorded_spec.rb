# frozen_string_literal: true

# The client against real 財政部 responses, replayed from cassettes recorded on
# the public ODS dataset endpoint.
#
# The stubbed specs can only prove the client agrees with our reading of the API.
# These payloads are 財政部's own, so the field names and shapes under test are
# the real ones — including the parts nothing else would catch, like a 愛心碼
# whose leading zero must survive as a string.
#
# See spec/support/vcr.rb for how to re-record. The dataset is public and needs
# no credentials, so a cassette here holds nothing sensitive.
RSpec.describe "Einvoice::MOF::DonationCodes against recorded 財政部 responses" do
  subject(:codes) { Einvoice::MOF::DonationCodes.new }

  describe "#lookup", vcr: { cassette_name: "mof/lookup" } do
    it "resolves a registered 愛心碼 to its organisation" do
      result = codes.lookup("2718")

      expect(result).to be_a(Einvoice::MOF::DonationCode)
      expect(result.code).to eq("2718")
      expect(result.name).to eq("社團法人台北市喜願協會")
      expect(result.ubn).to match(/\A\d{8}\z/)
      expect(result.city).not_to be_empty
    end
  end

  describe "an unregistered code", vcr: { cassette_name: "mof/lookup_missing" } do
    # 105 is well-formed and absent from the dataset — the case that separates
    # "not registered" from "malformed", which the client answers locally.
    it "is nil rather than an error" do
      expect(codes.lookup("105")).to be_nil
      expect(codes.exist?("105")).to be(false)
    end
  end

  describe "#for_ubn", vcr: { cassette_name: "mof/for_ubn" } do
    it "finds the codes registered to a 統一編號" do
      results = codes.for_ubn("92000392")

      expect(results).to all(be_a(Einvoice::MOF::DonationCode))
      expect(results.map(&:code)).to include("2718")
    end
  end

  describe "#all", vcr: { cassette_name: "mof/all" } do
    it "pages the whole dataset" do
      all = codes.all

      expect(all.size).to be > 1_500
      expect(all.map(&:code).uniq.size).to eq(all.size)
      expect(all).to all(have_attributes(code: match(/\A\d{3,7}\z/)))
    end

    # Real codes include 0096; parsing them as numbers would silently corrupt it.
    it "keeps codes as strings, leading zeros intact" do
      expect(codes.all.map(&:code)).to include(a_string_starting_with("0"))
    end
  end
end
