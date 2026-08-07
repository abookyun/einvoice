require "spec_helper"

RSpec.describe Einvoice::Client do
  describe "#initialize" do
    it "initialize instance" do
      provider = double(:provider)
      expect(described_class.new(provider).provider).to eql provider
    end
  end

  describe "delegation" do
    subject(:client) { described_class.new(Einvoice::Tradevan::Provider.new) }

    it "delegates calls to the provider" do
      provider = double(:provider, issue: :result)
      expect(described_class.new(provider).issue({})).to eq :result
    end

    it "responds to the provider's public methods" do
      expect(client).to respond_to(:issue)
    end

    it "does not respond to unknown methods" do
      expect(client).not_to respond_to(:nonexistent)
    end

    it "does not expose the provider's private methods" do
      expect { client.encrypt("key", "content") }.to raise_error(NoMethodError)
    end
  end
end
