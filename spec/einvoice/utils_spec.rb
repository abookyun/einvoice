require "spec_helper"

RSpec.describe Einvoice::Utils do
  let(:dummy_class) { Class.new { include Einvoice::Utils } }
  subject { dummy_class.new }

  describe "#serialize" do
    pending
  end

  describe "#wrap" do
    let(:invoice) { build(:neweb_pre_invoice) }

    it "wraps needed outter nodes for neweb API" do
      hash = subject.wrap(subject.serialize(invoice))
      expect(hash[:invoice_root]).to have_key(:invoice)
    end
  end

  describe "#camelize" do
    let(:invoice) { build(:neweb_pre_invoice) }

    it "camelize keys as needed" do
      hash = subject.camelize(subject.wrap(subject.serialize(invoice)))
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

      expect(subject.encode_xml(data)).to eq "<root><name>My Name</name><item><quantity>1</quantity><amount>100</amount></item><item><quantity>2</quantity><amount>200</amount></item></root>"
    end
  end
end
