require "spec_helper"

RSpec.describe Einvoice::Client do
  describe "#initialize" do
    it "initialize instance" do
      provider = double(:provider)
      expect(described_class.new(provider).provider).to eql provider
    end
  end
end
