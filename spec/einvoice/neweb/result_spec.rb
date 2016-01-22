require "spec_helper"

RSpec.describe Einvoice::Neweb::Result do
  describe "#initialize" do
    it "initialize instance" do
      response = double(:response)
      expect(described_class.new(response).response).to eql response
    end
  end

  describe "#errors" do
    let(:client) { Einvoice::Client.new(Einvoice::Neweb::Provider.new) }

    it "has default value" do
      expect(subject.errors).to be_nil
    end

    context "with active model errors" do
      it "returns active model validation errors" do
        invoice = build(:neweb_pre_invoice, data_number: nil)
        invoice.valid?

        expect(described_class.new(invoice.errors).errors).to include "Data number can't be blank"
      end
    end

    context "with API response errors" do
      it "joins response errors as string", vcr: { record: :once } do
        invoice = build(:neweb_pre_invoice, data_number: "53086054001")
        sn = invoice.invoice_item.first.sequence_number.to_s
        invoice_item = build(:neweb_invoice_item, sequence_number: sn)
        invoice.invoice_item << invoice_item
        expect(client.issue(invoice.payload).errors).to eq "7010: SequenceNumber不可重複"
      end
    end
  end

  describe "#success?" do
    let(:client) { Einvoice::Client.new(Einvoice::Neweb::Provider.new) }

    it "has default value" do
      expect(subject.errors).to be_falsey
    end

    it "returns true when there's no errors", vcr: { record: :once } do
      invoice = build(:neweb_pre_invoice)
      expect(client.issue(invoice.payload).success?).to be_truthy
    end

    it "returns false when there's active model errors" do
      invoice = build(:neweb_pre_invoice, data_number: nil)
      invoice.valid?

      expect(described_class.new(invoice.errors).success?).to be_falsey
    end
  end

  describe "#data" do
    pending
  end
end
