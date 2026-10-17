# frozen_string_literal: true

RSpec.describe Einvoice::Tradevan::DefaultAPI::Client do
  subject(:client) do
    described_class.new(acnt: "acnt", acntp: "acntp", key1: key1, key2: key2, endpoint: endpoint)
  end

  let(:key1) { "0123456789abcdef" }
  let(:key2) { "fedcba9876543210" }
  let(:endpoint) { "https://tradevan.test/" }
  let(:crypto) { Einvoice::Tradevan::DefaultAPI::Crypto }

  def respond_with(body, status = 200)
    stub_request(:any, %r{\Ahttps://tradevan\.test/DEFAULTAPI/})
      .to_return(status: status, headers: { "Content-Type" => "application/json" },
                 body: body.is_a?(String) ? body : JSON.generate(body))
  end

  def encrypted(message)
    crypto.encrypt(JSON.generate(message), key1)
  end

  it "needs an endpoint" do
    expect do
      described_class.new(acnt: "a", acntp: "b", key1: key1, key2: key2, endpoint: "")
    end.to raise_error(Einvoice::ValidationError, /endpoint/)
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
      respond_with("<html>busy</html>", 503)

      expect { client.request("post/issue", {}) }
        .to raise_error(Einvoice::ProviderError, /non-JSON response \(HTTP 503\)/)
    end

    it "raises NetworkError when the connection fails" do
      stub_request(:any, /tradevan\.test/).to_timeout

      expect { client.request("post/issue", {}) }.to raise_error(Einvoice::NetworkError)
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
