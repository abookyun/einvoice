require 'spec_helper'

RSpec.describe Einvoice::Client::Neweb do
  describe "#upload" do
    pending
  end

  describe "#serialize" do
    let(:invoice) { build(:invoice) }

    it "includes required keys only" do
      actual_keys = subject.send(:serialize, invoice).keys.map(&:to_sym)
      expect(actual_keys - Einvoice::Model::Invoice::VALID_OPTIONS_KEYS).to be_empty
    end

    it "includes required keys only even executed #valid?" do
      invoice.valid?

      actual_keys = subject.send(:serialize, invoice).keys.map(&:to_sym)
      expect(actual_keys - Einvoice::Model::Invoice::VALID_OPTIONS_KEYS).to be_empty
    end
  end

  describe "#wrap" do
    let(:invoice) { build(:invoice) }

    it "wraps needed outter nodes for neweb API" do
      hash = subject.send(:wrap, subject.send(:serialize, invoice))
      expect(hash[:invoice_root]).to have_key(:invoice)
    end
  end

  describe "#camelize" do
    let(:invoice) { build(:invoice) }

    it "camelize keys as needed" do
      hash = subject.send(:camelize, subject.send(:wrap, subject.send(:serialize, invoice)))
      expect(hash).to have_key("InvoiceRoot")
    end
  end

  describe "#encode_xml" do
    it "encoide hash data as xml" do
      data = {
        root: {
          name: "My Name",
          item: [
            { quantity: "1", amount: "100" },
            { quantity: "2", amount: "200" },
          ]
        }
      }

      expect(subject.send(:encode_xml, data)).to eq "<root><name>My Name</name><item><quantity>1</quantity><amount>100</amount></item><item><quantity>2</quantity><amount>200</amount></item></root>"
    end
  end
end