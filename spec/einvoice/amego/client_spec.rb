# frozen_string_literal: true

RSpec.describe Einvoice::Amego::Client do
  subject(:client) { described_class.new(ban: "12345678", app_key: "key", endpoint: endpoint, clock: clock) }

  let(:endpoint) { "https://amego.test/" }
  let(:clock) { -> { Time.at(1_729_000_000) } }

  def respond_with(body, status = 200)
    stub_request(:post, %r{\Ahttps://amego\.test/json/})
      .to_return(status: status, headers: { "Content-Type" => "application/json" },
                 body: body.is_a?(String) ? body : JSON.generate(body))
  end

  def sent_form
    form = nil
    expect(a_request(:post, %r{amego\.test}).with { |request| form = URI.decode_www_form(request.body).to_h })
      .to have_been_made
    form
  end

  it "needs a ban and an app key" do
    expect { described_class.new(ban: "", app_key: "k") }.to raise_error(Einvoice::ValidationError)
    expect { described_class.new(ban: "1", app_key: nil) }.to raise_error(Einvoice::ValidationError)
  end

  it "defaults to Amego's one host" do
    expect(described_class.new(ban: "1", app_key: "k").endpoint).to eq("https://invoice-api.amego.tw")
  end

  describe "#request" do
    it "posts the form envelope, signed over the JSON before URL encoding" do
      respond_with("code" => 0, "msg" => "")

      client.request("/json/f0501", [{ "CancelInvoiceNumber" => "AB12345678", "CancelReason" => "取消 訂單" }])

      form = sent_form
      data = '[{"CancelInvoiceNumber":"AB12345678","CancelReason":"取消 訂單"}]'
      expect(form).to eq("invoice" => "12345678", "data" => data, "time" => "1729000000",
                         "sign" => Digest::MD5.hexdigest("#{data}1729000000key"))
      expect(a_request(:post, "https://amego.test/json/f0501")
        .with(headers: { "Content-Type" => "application/x-www-form-urlencoded" })).to have_been_made
    end

    it "returns the body on code 0" do
      respond_with("code" => 0, "msg" => "", "invoice_number" => "AB12345678")
      expect(client.request("/json/f0401", {})["invoice_number"]).to eq("AB12345678")
    end

    it "raises the mapped error, keeping the raw code and message" do
      respond_with("code" => 71, "msg" => "查無資料")

      expect { client.request("/json/invoice_query", {}) }.to raise_error(Einvoice::NotFoundError) { |error|
        expect(error.message).to eq("查無資料")
        expect(error.raw_code).to eq("71")
        expect(error.provider).to eq("amego")
      }
    end

    it "names the code when the message is empty" do
      respond_with("code" => 99, "msg" => "")
      expect { client.request("/json/f0401", {}) }.to raise_error(Einvoice::ProviderError, /code 99/)
    end

    it "raises ProviderError on a body that is not JSON" do
      respond_with("<html>", 502)
      expect { client.request("/json/f0401", {}) }.to raise_error(Einvoice::ProviderError, /HTTP 502/)
    end

    it "raises ProviderError on JSON without a code" do
      respond_with("ok" => true)
      expect { client.request("/json/f0401", {}) }.to raise_error(Einvoice::ProviderError, /unexpected/)
    end

    it "raises NetworkError when the connection fails" do
      stub_request(:post, %r{amego\.test}).to_raise(Errno::ECONNREFUSED)
      expect { client.request("/json/f0401", {}) }.to raise_error(Einvoice::NetworkError)
    end
  end

  # The Python sample on https://invoice.amego.tw/api_doc/example says: "此範例
  # md5 結果為 f53a336934b2af0589b845638d1495cc". Its data is the JSON from
  # Python's json.dumps(indent=0), and its time is in a comment (1628136135).
  # Amego signs the string as sent, so the JSON layout is part of the input.
  describe "#sign, against Amego's published sample" do
    it "gives the md5 that the sample prints" do
      items = [{ "Description" => "測試商品1", "Quantity" => "1", "UnitPrice" => "170", "Amount" => "170",
                 "Remark" => "", "TaxType" => "1" },
               { "Description" => "會員折抵", "Quantity" => "1", "UnitPrice" => "-2", "Amount" => "-2",
                 "Remark" => "", "TaxType" => "1" }]
      invoice = { "OrderId" => "A20200817105934", "BuyerIdentifier" => "28080623", "BuyerName" => "光貿科技有限公司",
                  "NPOBAN" => "", "ProductItem" => items, "SalesAmount" => "160", "FreeTaxSalesAmount" => "0",
                  "ZeroTaxSalesAmount" => "0", "TaxType" => "1", "TaxRate" => "0.05", "TaxAmount" => "8",
                  "TotalAmount" => "168" }
      # Python's json.dumps(indent=0): a newline after each { , [ and item, and
      # \uXXXX for every non-ASCII character.
      data = JSON.pretty_generate(invoice, indent: "", ascii_only: true)
      sample = described_class.new(ban: "12345678", app_key: Einvoice::Amego::SANDBOX[:app_key])

      expect(sample.sign(data, "1628136135")).to eq("f53a336934b2af0589b845638d1495cc")
    end
  end

  describe ".encode_form" do
    it "writes a space as %20, which both of PHP's decoders read as a space" do
      expect(described_class.encode_form("data" => "a b+c")).to eq("data=a%20b%2Bc")
    end
  end
end
