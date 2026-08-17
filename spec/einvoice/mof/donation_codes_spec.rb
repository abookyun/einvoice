# frozen_string_literal: true

RSpec.describe Einvoice::MOF::DonationCodes do
  subject(:codes) { described_class.new(base_url: "https://mof.test") }

  let(:url) { "https://mof.test/api/v1/DonateCodeList" }
  # WebMock's bare-URL form only matches a request with no query string, so any
  # stub that doesn't pin the parameters has to match on the path instead.
  let(:any_query) { %r{\Ahttps://mof\.test/api/v1/DonateCodeList\?} }

  def row(code, overrides = {})
    {
      "donateBan" => "92000392", "donateNm" => "社團法人台北市喜願協會",
      "donateCode" => code, "donateShortNm" => "喜願協會", "hsnNm" => "臺北市",
      "seq" => 1
    }.merge(overrides)
  end

  def json(body)
    { status: 200, headers: { "Content-Type" => "application/json" },
      body: JSON.generate(body) }
  end

  describe "#lookup" do
    it "returns the registered organisation" do
      stub_request(:get, url).with(query: { donateCode: "2718" }).to_return(json([row("2718")]))

      result = codes.lookup("2718")
      expect(result).to be_a(Einvoice::MOF::DonationCode)
      expect(result).to have_attributes(code: "2718", name: "社團法人台北市喜願協會",
                                        short_name: "喜願協會", ubn: "92000392", city: "臺北市")
      expect(result.raw).to include("seq" => 1)
    end

    it "returns nil when the code is not registered" do
      stub_request(:get, url).with(query: { donateCode: "105" }).to_return(json([]))
      expect(codes.lookup("105")).to be_nil
    end

    it "leaves a blank optional field nil rather than empty" do
      stub_request(:get, url).with(query: { donateCode: "17520" })
                             .to_return(json([row("17520", "donateShortNm" => "")]))
      expect(codes.lookup("17520").short_name).to be_nil
    end

    # Codes are identifiers, not numbers — 0096 must survive as written.
    it "keeps a leading zero" do
      stub_request(:get, url).with(query: { donateCode: "0096" }).to_return(json([row("0096")]))
      expect(codes.lookup("0096").code).to eq("0096")
    end

    it "rejects anything that is not a 3–7 digit 愛心碼, without asking 財政部" do
      ["ab", "12", "12345678", "", nil, "12a4"].each do |bad|
        expect { codes.lookup(bad) }
          .to raise_error(Einvoice::ValidationError, /愛心碼 must be 3–7 digits/)
      end
      expect(a_request(:get, any_query)).not_to have_been_made
    end
  end

  describe "#exist?" do
    it "is true for a registered code and false otherwise" do
      stub_request(:get, url).with(query: { donateCode: "2718" }).to_return(json([row("2718")]))
      stub_request(:get, url).with(query: { donateCode: "105" }).to_return(json([]))

      expect(codes.exist?("2718")).to be(true)
      expect(codes.exist?("105")).to be(false)
    end
  end

  describe "#for_ubn" do
    it "returns every code an organisation holds" do
      stub_request(:get, url).with(query: { donateBan: "92000392" })
                             .to_return(json([row("2718"), row("2719")]))

      expect(codes.for_ubn("92000392").map(&:code)).to eq(%w[2718 2719])
    end

    it "rejects a malformed 統一編號 locally" do
      expect { codes.for_ubn("123") }
        .to raise_error(Einvoice::ValidationError, /統一編號 must be 8 digits/)
    end
  end

  describe "#all" do
    it "pages until the dataset runs out" do
      full = Array.new(500) { |i| row(format("%04d", i)) }
      stub_request(:get, url).with(query: { limit: "500", offset: "0" }).to_return(json(full))
      stub_request(:get, url).with(query: { limit: "500", offset: "500" })
                             .to_return(json([row("9999")]))

      expect(codes.all.size).to eq(501)
      expect(a_request(:get, url).with(query: { limit: "500", offset: "500" })).to have_been_made
    end

    it "stops after a single request when the dataset is short" do
      stub_request(:get, url).with(query: { limit: "500", offset: "0" })
                             .to_return(json([row("2718")]))

      expect(codes.all.map(&:code)).to eq(["2718"])
      expect(a_request(:get, any_query)).to have_been_made.once
    end
  end

  describe "failures" do
    # The endpoint is open today but is published with auth schemes declared, so
    # this is the failure most likely to appear one day. Naming it beats letting
    # it surface as a parse error.
    it "says so plainly if 財政部 starts requiring credentials" do
      [401, 403].each do |status|
        stub_request(:get, any_query).to_return(status: status, body: "denied")

        expect { codes.lookup("2718") }
          .to raise_error(Einvoice::AuthError) { |error|
            expect(error.reason).to eq(Einvoice::Reason::CREDENTIALS_INVALID)
            expect(error.raw_code).to eq(status.to_s)
            expect(error.provider).to eq("mof")
          }
      end
    end

    it "reports any other HTTP status as a provider error" do
      stub_request(:get, any_query).to_return(status: 503, body: "unavailable")
      expect { codes.lookup("2718") }
        .to raise_error(Einvoice::ProviderError, /HTTP 503/)
    end

    it "reports a non-JSON response as a provider error" do
      stub_request(:get, any_query).to_return(status: 200, body: "<html>maintenance</html>")
      expect { codes.lookup("2718") }
        .to raise_error(Einvoice::ProviderError, /non-JSON/)
    end

    it "reports a JSON payload that is not a list as a provider error" do
      stub_request(:get, any_query).to_return(json("message" => "nope"))
      expect { codes.lookup("2718") }
        .to raise_error(Einvoice::ProviderError, /unexpected payload/)
    end

    it "wraps a connection failure as a network error" do
      stub_request(:get, any_query).to_timeout
      expect { codes.lookup("2718") }
        .to raise_error(Einvoice::NetworkError, /財政部 request failed/)
    end
  end

  describe "configuration" do
    it "targets 財政部's public dataset host by default" do
      expect(described_class::BASE_URL).to eq("https://dataset.einvoice.nat.gov.tw/ods/portal")
    end
  end
end
