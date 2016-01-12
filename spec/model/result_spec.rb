require "spec_helper"

RSpec.describe Einvoice::Model::Result do
  describe "#initialize" do
    it "initialize instance" do
      response = double(:response)
      expect(described_class.new(response).response).to eql response
    end
  end

  describe "#errors" do
    it "has default value" do
      expect(subject.errors).to be_nil
    end

    it "returns active model validation errors" do
      invoice = build(:invoice, data_number: nil)
      invoice.valid?

      expect(described_class.new(invoice.errors).errors).to include "Data number can't be blank"
    end
  end

  describe "#success?" do
    it "has default value" do
      expect(subject.errors).to be_falsey
    end

    it "returns false when there's active model errors" do
      invoice = build(:invoice, data_number: nil)
      invoice.valid?

      expect(described_class.new(invoice.errors).success?).to be_falsey
    end
  end
end
