require "spec_helper"

RSpec.describe Einvoice::Result do
  describe "#initialize" do
    it "initialize instance" do
      response = double(:response)
      expect(described_class.new(response).response).to eql response
    end
  end

  describe "#errors" do
    it "raises NotImplementedError" do
      expect { subject.errors }.to raise_error NotImplementedError
    end
  end

  describe "#successful?" do
    it "raises NotImplementedError" do
      expect { subject.successful? }.to raise_error NotImplementedError
    end
  end

  describe "#data" do
    it "raises NotImplementedError" do
      expect { subject.data }.to raise_error NotImplementedError
    end
  end
end
