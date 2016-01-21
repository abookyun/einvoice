require "spec_helper"

RSpec.describe Einvoice::Utils do
  let(:dummy_class) { Class.new { include Einvoice::Utils } }
  subject { dummy_class.new }

  describe "#camelize" do
    let(:invoice) { build(:neweb_pre_invoice) }

    it "camelize keys as needed" do
      hash = subject.camelize(invoice.wrapped_payload)
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
