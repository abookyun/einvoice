# frozen_string_literal: true

RSpec.describe Einvoice::EzPay::Client do
  subject(:client) do
    described_class.new(merchant_id: "3502275", hash_key: key, hash_iv: iv, base_url: "https://ezpay.test/",
                        clock: -> { Time.at(1_729_000_000) })
  end

  let(:key) { "abcdefghijklmnopqrstuvwxyz012345" }
  let(:iv) { "0123456789abcdef" }
  let(:crypto) { Einvoice::EzPay::Crypto }

  it_behaves_like "a provider client" do
    let(:stub_host) { /ezpay\.test/ }
    let(:secrets) { [key, iv] }
    let(:error_body) { JSON.generate("Status" => "INV90000", "Message" => "error") }

    def send_request = client.request("/Api/x", "1.0", {})
    def build_client(base_url:) = described_class.new(merchant_id: "1", hash_key: key, hash_iv: iv, base_url: base_url)
  end

  def respond_with(body, status = 200)
    stub_request(:post, %r{\Ahttps://ezpay\.test/})
      .to_return(status: status, body: body.is_a?(String) ? body : JSON.generate(body))
  end

  it "needs all three credentials" do
    expect { described_class.new(merchant_id: "", hash_key: key, hash_iv: iv) }
      .to raise_error(Einvoice::ValidationError)
  end

  it "picks the host by mode" do
    test = described_class.new(merchant_id: "1", hash_key: key, hash_iv: iv)
    production = described_class.new(merchant_id: "1", hash_key: key, hash_iv: iv,
                                      mode: Einvoice::ProviderMode::PRODUCTION)
    expect([test.base_url, production.base_url]).to eq(%w[https://cinv.ezpay.com.tw https://inv.ezpay.com.tw])
    expect { described_class.new(merchant_id: "1", hash_key: key, hash_iv: iv, mode: :staging) }
      .to raise_error(Einvoice::ValidationError, /mode/)
  end

  it "refuses a base_url without https, or with a user and password" do
    expect { described_class.new(merchant_id: "1", hash_key: key, hash_iv: iv, base_url: "http://ezpay.test") }
      .to raise_error(Einvoice::ValidationError, /https/)
    expect { described_class.new(merchant_id: "1", hash_key: key, hash_iv: iv, base_url: "https://u:p@ezpay.test") }
      .to raise_error(Einvoice::ValidationError, /user or password/)
    expect(described_class.new(merchant_id: "1", hash_key: key, hash_iv: iv, base_url: "http://localhost:3000").base_url)
      .to eq("http://localhost:3000")
  end

  it "hides the HashKey and the HashIV in inspect" do
    expect(client.inspect).to include("merchant_id=\"3502275\"", "ezpay.test")
    expect(client.inspect).not_to include(key, iv)
    expect(client.to_s).to eq(client.inspect)
  end

  describe "#request" do
    it "posts MerchantID_ and the encrypted PostData_, with RespondType, Version and TimeStamp first" do
      respond_with("Status" => "SUCCESS", "Message" => "", "Result" => "{}")

      client.request("/Api/invoice_invalid", "1.0", { InvoiceNumber: "AB12345678" })

      form = nil
      expect(a_request(:post, "https://ezpay.test/Api/invoice_invalid")
        .with { |request| form = URI.decode_www_form(request.body).to_h }).to have_been_made
      expect(form["MerchantID_"]).to eq("3502275")
      expect(crypto.decrypt(form["PostData_"], key, iv))
        .to eq("RespondType=JSON&Version=1.0&TimeStamp=1729000000&InvoiceNumber=AB12345678")
    end

    it "parses Result a second time" do
      respond_with("Status" => "SUCCESS", "Message" => "", "Result" => JSON.generate("InvoiceNumber" => "AB1"))
      expect(client.request("/Api/x", "1.0", {})).to eq("InvoiceNumber" => "AB1")
    end

    it "accepts a Result that is already an object, or empty" do
      respond_with("Status" => "SUCCESS", "Message" => "", "Result" => { "A" => "1" })
      expect(client.request("/Api/x", "1.0", {})).to eq("A" => "1")
      respond_with("Status" => "SUCCESS", "Message" => "")
      expect(client.request("/Api/x", "1.0", {})).to eq({})
    end

    it "raises ProviderError on a Result it cannot read" do
      respond_with("Status" => "SUCCESS", "Result" => "not json")
      expect { client.request("/Api/x", "1.0", {}) }.to raise_error(Einvoice::ProviderError, /not JSON/)
      respond_with("Status" => "SUCCESS", "Result" => [1])
      expect { client.request("/Api/x", "1.0", {}) }.to raise_error(Einvoice::ProviderError, /unexpected Result/)
    end

    it "raises the mapped error, keeping the raw status and message" do
      respond_with("Status" => "LIB10003", "Message" => "商店訂單編號重複", "Result" => "")

      expect { client.request("/Api/invoice_issue", "1.5", {}) }.to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
        expect(error.raw_code).to eq("LIB10003")
        expect(error.message).to eq("商店訂單編號重複")
      }
    end

    it "uses the operation's guesses" do
      respond_with("Status" => "IAI10002", "Message" => "")
      expect { client.request("/Api/allowanceInvalid", "1.0", {}, operation: :void_allowance) }
        .to raise_error(Einvoice::NotFoundError, /IAI10002/)
    end

    it "raises ProviderError on a body that is not JSON, or has no Status" do
      respond_with("<html>", 200)
      expect { client.request("/Api/x", "1.0", {}) }.to raise_error(Einvoice::ProviderError, /HTTP 200/)
      respond_with("ok" => true)
      expect { client.request("/Api/x", "1.0", {}) }.to raise_error(Einvoice::ProviderError, /unexpected response/)
    end

    it "raises NetworkError for HTTP 5xx with a body that ezPay did not write" do
      respond_with("<html>", 502)
      expect { client.request("/Api/x", "1.0", {}) }.to raise_error(Einvoice::NetworkError, /HTTP 502/)
      respond_with({ "error" => "bad gateway" }, 503)
      expect { client.request("/Api/x", "1.0", {}) }.to raise_error(Einvoice::NetworkError, /HTTP 503/)
    end

    it "raises NetworkError with RATE_LIMITED for HTTP 429" do
      respond_with("Too Many Requests", 429)
      expect { client.request("/Api/x", "1.0", {}) }
        .to raise_error(Einvoice::NetworkError) { |error| expect(error.reason).to eq(Einvoice::Reason::RATE_LIMITED) }
    end

    # The rule of the unified model: a body that the adapter can read decides.
    it "lets a body that ezPay wrote decide, whatever the HTTP status" do
      respond_with({ "Status" => "SUCCESS", "Message" => "", "Result" => "{}" }, 503)
      expect(client.request("/Api/x", "1.0", {})).to eq({})
      respond_with({ "Status" => "LIB10003", "Message" => "商店訂單編號重複", "Result" => "" }, 500)
      expect { client.request("/Api/x", "1.0", {}) }.to raise_error(Einvoice::ConflictError)
    end

    it "raises NetworkError when the connection fails" do
      stub_request(:post, %r{ezpay\.test}).to_raise(Errno::ECONNREFUSED)
      expect { client.request("/Api/x", "1.0", {}) }.to raise_error(Einvoice::NetworkError)
    end

    it "does not report a bug as a NetworkError" do
      stub_request(:post, %r{ezpay\.test}).to_raise(NoMethodError.new("a bug"))
      expect { client.request("/Api/x", "1.0", {}) }.to raise_error(NoMethodError, /a bug/)
    end
  end

  describe "#verify_check_code!" do
    let(:result) do
      fields = { "InvoiceTransNo" => "1", "MerchantID" => "3502275", "MerchantOrderNo" => "O1", "RandomNum" => "1234",
                 "TotalAmt" => 100 }
      fields.merge("CheckCode" => crypto.check_code(fields, key, iv))
    end

    it "accepts a matching CheckCode" do
      expect { client.verify_check_code!(result) }.not_to raise_error
    end

    it "refuses a result that does not match" do
      expect { client.verify_check_code!(result.merge("TotalAmt" => 101)) }
        .to raise_error(Einvoice::ProviderError, /CheckCode/)
    end
  end
end
