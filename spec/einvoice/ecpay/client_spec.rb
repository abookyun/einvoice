# frozen_string_literal: true

RSpec.describe Einvoice::ECPay::Client do
  subject(:client) do
    described_class.new(**Einvoice::ECPay::SANDBOX, base_url: "https://ecpay.test")
  end

  let(:key) { Einvoice::ECPay::SANDBOX[:hash_key] }
  let(:iv) { Einvoice::ECPay::SANDBOX[:hash_iv] }
  let(:url) { "https://ecpay.test/B2CInvoice/Issue" }

  def envelope(body)
    { status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(body) }
  end

  def business(fields)
    envelope("MerchantID" => "2000132", "TransCode" => 1, "TransMsg" => "Success",
             "Data" => Einvoice::ECPay::Crypto.encrypt_data(fields, key, iv))
  end

  describe "the request envelope" do
    it "encrypts Data and repeats the merchant id inside it" do
      stub_request(:post, url).to_return(business("RtnCode" => 1, "RtnMsg" => "ok"))
      client.request("/B2CInvoice/Issue", { "RelateNumber" => "ORDER_1" })

      expect(a_request(:post, url).with { |req|
        body = JSON.parse(req.body)
        data = Einvoice::ECPay::Crypto.decrypt_data(body["Data"], key, iv)

        body["MerchantID"] == "2000132" &&
          body["RqHeader"]["Revision"] == "3.0.0" &&
          body["RqHeader"]["Timestamp"].is_a?(Integer) &&
          # The merchant id is required in the encrypted payload as well.
          data == { "MerchantID" => "2000132", "RelateNumber" => "ORDER_1" }
      }).to have_been_made
    end

    it "sends JSON" do
      stub_request(:post, url).to_return(business("RtnCode" => 1))
      client.request("/B2CInvoice/Issue", {})

      expect(a_request(:post, url)
        .with(headers: { "Content-Type" => "application/json" })).to have_been_made
    end

    # ECPay's own SDKs omit optional fields rather than sending nulls, and these
    # endpoints were verified against that shape.
    it "omits nil fields instead of sending JSON nulls" do
      stub_request(:post, url).to_return(business("RtnCode" => 1))
      client.request("/B2CInvoice/Issue", { "InvoiceNo" => "LA25000001", "Reason" => nil })

      expect(a_request(:post, url).with { |req|
        data = Einvoice::ECPay::Crypto.decrypt_data(JSON.parse(req.body)["Data"], key, iv)
        !data.key?("Reason")
      }).to have_been_made
    end
  end

  describe "the transport layer" do
    it "reads a decrypt failure as an auth problem, naming the credential" do
      stub_request(:post, url).to_return(envelope(
                                           "TransCode" => 110,
                                           "TransMsg" => "The parameter [Data] decrypt fail.",
                                           "Data" => nil
                                         ))

      expect { client.request("/B2CInvoice/Issue", {}) }
        .to raise_error(Einvoice::AuthError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::CREDENTIALS_INVALID)
          expect(error.raw_code).to eq("110")
          expect(error.message).to eq("The parameter [Data] decrypt fail.")
        }
    end

    it "reads a rejected timestamp as a stale clock" do
      stub_request(:post, url).to_return(envelope(
                                           "TransCode" => 104,
                                           "TransMsg" => "Timestamp is over 10 minutes than it just produced.",
                                           "Data" => nil
                                         ))

      expect { client.request("/B2CInvoice/Issue", {}) }
        .to raise_error(Einvoice::ValidationError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::STALE_TIMESTAMP)
        }
    end

    it "does not try to decrypt Data when the envelope failed" do
      stub_request(:post, url).to_return(envelope("TransCode" => 1, "TransMsg" => "", "Data" => nil))

      expect { client.request("/B2CInvoice/Issue", {}) }.to raise_error(Einvoice::ProviderError)
    end

    it "reports a non-JSON response with its status rather than a parse error" do
      stub_request(:post, url).to_return(status: 502, body: "<html>bad gateway</html>")

      expect { client.request("/B2CInvoice/Issue", {}) }
        .to raise_error(Einvoice::ProviderError, /non-JSON response \(HTTP 502\)/)
    end

    it "wraps a connection failure as a network error" do
      stub_request(:post, url).to_timeout

      expect { client.request("/B2CInvoice/Issue", {}) }
        .to raise_error(Einvoice::NetworkError, /ECPay request failed/)
    end
  end

  describe "the business layer" do
    it "returns the decrypted payload on success" do
      stub_request(:post, url).to_return(business("RtnCode" => 1, "RtnMsg" => "開立發票成功",
                                                  "InvoiceNo" => "LA25000001"))

      expect(client.request("/B2CInvoice/Issue", {}))
        .to include("InvoiceNo" => "LA25000001")
    end

    it "raises the mapped error class for a business failure" do
      stub_request(:post, url).to_return(business("RtnCode" => 5_070_357,
                                                  "RtnMsg" => "B2C開立發票 自訂編號重覆，請重新設定"))

      expect { client.request("/B2CInvoice/Issue", {}) }
        .to raise_error(Einvoice::ConflictError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
          expect(error.raw_code).to eq("5070357")
          expect(error.raw).to include("RtnCode" => 5_070_357)
        }
    end

    # Some endpoints signal a successful outcome with a code other than 1, so the
    # caller can opt those in rather than have them raise.
    it "accepts extra success codes when asked" do
      stub_request(:post, url).to_return(business("RtnCode" => 4_000_004, "RtnMsg" => "開立發票成功"))

      expect(client.request("/B2CInvoice/Issue", {}, success_codes: [4_000_004]))
        .to include("RtnCode" => 4_000_004)
      expect { client.request("/B2CInvoice/Issue", {}) }.to raise_error(Einvoice::Error)
    end

    # A handful of endpoints answer with plain JSON in Data rather than ciphertext.
    it "reads an unencrypted Data payload when told to" do
      stub_request(:post, url).to_return(envelope(
                                           "TransCode" => 1, "TransMsg" => "",
                                           "Data" => { "RtnCode" => 1, "TotalCount" => 3 }
                                         ))

      expect(client.request("/B2CInvoice/Issue", {}, plain_data: true))
        .to include("TotalCount" => 3)
    end

    it "refuses a Data payload that is not an object at all" do
      stub_request(:post, url).to_return(envelope("TransCode" => 1, "TransMsg" => "",
                                                  "Data" => %w[unexpected array]))

      expect { client.request("/B2CInvoice/Issue", {}, plain_data: true) }
        .to raise_error(Einvoice::ProviderError, /unexpected Data payload/)
    end
  end

  describe "host selection" do
    it "defaults to the stage host" do
      expect(described_class.new(**Einvoice::ECPay::SANDBOX).base_url)
        .to eq("https://einvoice-stage.ecpay.com.tw")
    end

    it "uses the live host in production" do
      expect(described_class.new(**Einvoice::ECPay::SANDBOX,
                                 mode: Einvoice::ProviderMode::PRODUCTION).base_url)
        .to eq("https://einvoice.ecpay.com.tw")
    end

    it "keeps a path prefix on an overridden base url" do
      stub_request(:post, "https://proxy.test/ecpay/B2CInvoice/Issue")
        .to_return(business("RtnCode" => 1))
      described_class.new(**Einvoice::ECPay::SANDBOX, base_url: "https://proxy.test/ecpay")
                     .request("/B2CInvoice/Issue", {})

      expect(a_request(:post, "https://proxy.test/ecpay/B2CInvoice/Issue")).to have_been_made
    end
  end
end
