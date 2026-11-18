# frozen_string_literal: true

RSpec.describe Einvoice::Tradevan::DefaultAPI::Client do
  subject(:client) do
    described_class.new(acnt: "acnt", acntp: password, key1: key1, key2: key2, base_url: base_url)
  end

  let(:password) { "s3cret-pass" }
  let(:key1) { "0123456789abcdef" }
  let(:key2) { "fedcba9876543210" }
  let(:base_url) { "https://tradevan.test/" }
  let(:crypto) { Einvoice::Tradevan::DefaultAPI::Crypto }

  def respond_with(body, status = 200)
    stub_request(:any, %r{\Ahttps://tradevan\.test/DEFAULTAPI/})
      .to_return(status: status, headers: { "Content-Type" => "application/json" },
                 body: body.is_a?(String) ? body : JSON.generate(body))
  end

  def encrypted(message)
    crypto.encrypt(JSON.generate(message), key1)
  end

  it "needs a base_url" do
    expect do
      described_class.new(acnt: "a", acntp: "b", key1: key1, key2: key2, base_url: "")
    end.to raise_error(Einvoice::ValidationError, /base_url/)
  end

  it "refuses a base_url without https" do
    expect do
      described_class.new(acnt: "a", acntp: "b", key1: key1, key2: key2, base_url: "http://tradevan.test")
    end.to raise_error(Einvoice::ValidationError, /https/)
  end

  it "hides the password and both keys in inspect" do
    expect(client.inspect).to include("acnt=\"acnt\"", "tradevan.test")
    [client.inspect, client.to_s].each { |text| expect(text).not_to include(password, key1, key2) }
    expect(client.to_s).to eq(client.inspect)
  end

  it "keeps the checked base_url from changing" do
    expect(client.base_url).to be_frozen
    expect { client.base_url << "@evil.test" }.to raise_error(FrozenError)
  end

  describe "#request" do
    it "sends a post/ path as POST, with v in the query string and no body" do
      respond_with("Success" => "Y", "Message" => encrypted("issueStatus" => "Y"))

      client.request("post/issue", { issueData: { "type" => "I" } })

      expect(a_request(:post, "https://tradevan.test/DEFAULTAPI/post/issue")
        .with(query: hash_including("v"), body: "",
              headers: { "Accept" => "application/json; charset=utf-8" })).to have_been_made
    end

    it "sends a get/ path as GET" do
      respond_with("Success" => "Y", "Message" => encrypted("invoiceNumber" => "GX38551078"))

      client.request("get/searchInvoiceDetail", { invoiceNumber: "GX38551078" })

      expect(a_request(:get, %r{/DEFAULTAPI/get/searchInvoiceDetail\?v=})).to have_been_made
    end

    # Ported from the 1.x decode_tradevan spec: a success Message is decrypted
    # (with key1) and parsed.
    it "decrypts and parses the Message on success" do
      message = { "invoiceNumber" => "GX38551078", "issueStatus" => "Y" }
      respond_with("Success" => "Y", "Message" => encrypted(message))

      expect(client.request("post/issue", {})).to eq(message)
    end

    it "reads the Message with key1, not key2" do
      respond_with("Success" => "Y", "Message" => crypto.encrypt(%({"a":1}), key2))

      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::ProviderError)
    end

    # Ported from the 1.x decode_tradevan spec: an error Message is plain text
    # and is not decrypted.
    it "keeps the plain Message of Success E, and raises" do
      respond_with("Success" => "E", "Message" => "some error")

      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::ProviderError) { |error|
        expect(error.raw_message).to eq("some error")
        expect(error.raw_code).to eq("E")
      }
    end

    it "maps a Success E about the account to AuthError" do
      respond_with("Success" => "E", "Message" => "帳號或密碼錯誤")

      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::AuthError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::CREDENTIALS_INVALID)
      }
    end

    it "raises a classified error for Success N, from the failReason" do
      respond_with("Success" => "N", "Message" => encrypted("issueStatus" => "N", "failReason" => "duplicated"))

      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
        expect(error.raw).to eq("issueStatus" => "N", "failReason" => "duplicated")
      }
    end

    it "raises ProviderError for Success N without a failReason" do
      respond_with("Success" => "N", "Message" => encrypted([]))

      expect { client.request("post/issue", {}) }
        .to raise_error(Einvoice::ProviderError, "Tradevan returned an error")
    end

    it "raises ProviderError for an unknown Success value" do
      respond_with("Success" => "?", "Message" => "")

      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::ProviderError, /unknown Success/)
    end

    it "raises ProviderError for an envelope that is not an object" do
      respond_with("[1]")

      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::ProviderError, /envelope/)
    end

    it "raises ProviderError for a body that is not JSON" do
      respond_with("<html>busy</html>", 200)

      expect { client.request("post/issue", {}) }
        .to raise_error(Einvoice::ProviderError, /non-JSON response \(HTTP 200\)/)
    end

    it "raises NetworkError for HTTP 5xx with a body that Tradevan did not write" do
      respond_with("<html>busy</html>", 503)
      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::NetworkError, /HTTP 503/)

      respond_with({ "error" => "bad gateway" }, 502)
      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::NetworkError, /HTTP 502/)
    end

    it "lets the HTTP status decide when Success is not Y, N or E" do
      respond_with({ "Success" => nil }, 503)
      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::NetworkError, /HTTP 503/)
    end

    it "lets HTTP 5xx decide when the Message cannot be decrypted" do
      respond_with({ "Success" => "Y", "Message" => "not a cipher" }, 503)
      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::NetworkError, /HTTP 503/)

      respond_with({ "Success" => "N", "Message" => nil }, 502)
      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::NetworkError, /HTTP 502/)
    end

    it "keeps a ProviderError for a Message that cannot be decrypted on HTTP 200" do
      respond_with({ "Success" => "Y", "Message" => "not a cipher" }, 200)
      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::ProviderError)
    end

    it "keeps a readable failReason on any HTTP status" do
      respond_with({ "Success" => "N", "Message" => encrypted("failReason" => "duplicated") }, 500)
      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::ConflictError)
    end

    it "raises NetworkError with RATE_LIMITED for HTTP 429" do
      respond_with("Too Many Requests", 429)
      expect { client.request("post/issue", {}) }
        .to raise_error(Einvoice::NetworkError) { |error| expect(error.reason).to eq(Einvoice::Reason::RATE_LIMITED) }
    end

    # The rule of the unified model: a body that the adapter can read decides.
    it "lets a body that Tradevan wrote decide, whatever the HTTP status" do
      respond_with({ "Success" => "Y", "Message" => encrypted("issueStatus" => "Y") }, 503)
      expect(client.request("post/issue", {})).to include("issueStatus" => "Y")

      respond_with({ "Success" => "E", "Message" => "帳號或密碼錯誤" }, 500)
      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::AuthError)
    end

    it "raises NetworkError when the connection fails" do
      stub_request(:any, /tradevan\.test/).to_timeout

      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::NetworkError)
    end

    it "does not report a bug as a NetworkError" do
      stub_request(:any, /tradevan\.test/).to_raise(NoMethodError.new("a bug"))

      expect { client.request("post/issue", {}) }.to raise_error(NoMethodError, /a bug/)
    end
  end

  describe "#check_status!" do
    it "passes when the field is Y" do
      expect { client.check_status!({ "issueStatus" => "Y" }, "issueStatus") }.not_to raise_error
    end

    it "raises a classified error when the field is N" do
      expect { client.check_status!({ "voidStatus" => "N", "failReason" => "查無發票資料" }, "voidStatus") }
        .to raise_error(Einvoice::NotFoundError, "查無發票資料")
    end

    it "raises when the result is not a Hash" do
      expect { client.check_status!([], "issueStatus") }.to raise_error(Einvoice::ProviderError)
    end
  end
end
