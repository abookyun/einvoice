require "spec_helper"
require "webmock/rspec"

RSpec.describe Einvoice::Tradevan::Provider do
  let(:key) { "0123456789abcdef" }

  let(:provider) do
    described_class.new(
      endpoint: "https://tradevan.test",
      client_id: "acnt",
      client_secret: "acntp",
      encryption_keys: { key1: key, key2: key },
      format: "json"
    )
  end

  let(:payload) do
    {
      companyUn: "12345678", orgId: "ABCDE", type: "I",
      saleIdentifier: "12345678_ABCDE_53b2a44e4b3c",
      transactionNumber: "53b2a44e4b3c", transactionDate: "20160425",
      transactionTime: "12:34:56", total: "20000", paperPrintMode: "0",
      invoiceAlarmMode: "4", donate: "N", carrierType: "3J0002",
      carrierId: "TP03000001234567", carrierIdHidden: "TP03000001234567",
      itemList: [{ saleIdentifier: "12345678_ABCDE_53b2a44e4b3c", serialNumber: "0001",
                   productName: "Coffee Latte", qty: "4000", price: "5",
                   itemTotal: "20000", taxType: "T", tax: "952" }]
    }
  end

  def encrypt(content)
    cipher = OpenSSL::Cipher::AES.new(128, :CBC)
    cipher.encrypt
    cipher.key = key
    cipher.iv = key
    cipher.padding = 0

    q, m = content.bytesize.divmod(cipher.block_size)
    if m != 0 || q == 0
      content = content.bytes.fill(0, content.bytesize..(cipher.block_size * (q + 1) - 1)).pack("C*")
    end

    Base64.strict_encode64(cipher.update(content) + cipher.final)
  end

  def stub_issue(body)
    stub_request(:post, %r{\Ahttps://tradevan\.test/DEFAULTAPI/post/issue})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: body.to_json)
  end

  describe "#issue" do
    it "sends the request through the full connection stack and decodes the response" do
      message = { "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
                  "issueStatus" => "Y", "invoiceNumber" => "GX38551078" }
      stub_issue("Success" => "Y", "Message" => encrypt(message.to_json))

      result = provider.issue(payload)

      expect(result).to be_successful
      expect(result.data).to eq message
    end

    it "returns an unsuccessful result on provider failure" do
      message = { "issueStatus" => "N", "failReason" => "duplicated" }
      stub_issue("Success" => "N", "Message" => encrypt(message.to_json))

      result = provider.issue(payload)

      expect(result).not_to be_successful
    end

    it "returns validation errors without hitting the network" do
      result = provider.issue(payload.merge(companyUn: nil))

      expect(result).not_to be_successful
      expect(result.errors).to include("Companyun")
      expect(a_request(:post, %r{tradevan\.test})).not_to have_been_made
    end
  end

  describe "#cancel" do
    it "voids an invoice through the full connection stack" do
      message = { "voidStatus" => "Y", "invoiceNumber" => "GX38551078" }
      stub_request(:post, %r{\Ahttps://tradevan\.test/DEFAULTAPI/post/cancel})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { "Success" => "Y", "Message" => encrypt(message.to_json) }.to_json)

      result = provider.cancel(type: "I", saleIdentifier: "12345678_ABCDE_53b2a44e4b3c",
                               invoiceNumber: "GX38551078", invoicePaperReturned: "Y")

      expect(result).to be_successful
      expect(result.data).to eq message
    end
  end
end
