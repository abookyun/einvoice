# frozen_string_literal: true

require "spec_helper"
require "pp"

RSpec.describe Einvoice::Redaction do
  describe "results" do
    let(:result) do
      Einvoice::QueryInvoiceResult.new(
        invoice_number: "AB12345678", invoice_datetime: nil, random_code: "1234", order_id: "O1",
        status: :issued, amount: nil, buyer: nil, items: [], raw: { "IIS_Customer_Name" => "王小明" }
      )
    end

    it "hides raw in inspect, to_s and pp" do
      [result.inspect, result.to_s, PP.pp(result, +"")].each do |text|
        expect(text).to include("raw=[FILTERED]", 'invoice_number="AB12345678"')
        expect(text).not_to include("王小明")
      end
    end

    it "keeps raw readable" do
      expect(result.raw).to eq("IIS_Customer_Name" => "王小明")
    end
  end

  describe "an ECPay client" do
    it "hides the HashKey and HashIV" do
      client = Einvoice::ECPay::Client.new(**Einvoice::ECPay::SANDBOX)
      text = Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX).inspect + client.to_s

      expect(text).to include("hash_key=[FILTERED]", 'merchant_id="2000132"')
      expect(text).not_to include(Einvoice::ECPay::SANDBOX[:hash_key], Einvoice::ECPay::SANDBOX[:hash_iv])
    end
  end

  describe ".base_url!" do
    def check(url)
      described_class.base_url!(url, provider: "x")
    end

    it "accepts https, and http for localhost" do
      expect(check("https://einvoice.example")).to eq("https://einvoice.example")
      expect(check("http://localhost:3000")).to eq("http://localhost:3000")
      expect(check("http://127.0.0.1")).to eq("http://127.0.0.1")
    end

    it "refuses plain http to another host" do
      expect { check("http://einvoice.example") }
        .to raise_error(Einvoice::ValidationError, /base_url must use https/)
    end

    it "refuses a value that is not a URL" do
      expect { check("https://") }.to raise_error(Einvoice::ValidationError, /must use https/)
      expect { check("http://exa mple") }.to raise_error(Einvoice::ValidationError, /not a valid URL/)
    end

    it "is checked when an adapter is built" do
      expect { Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX, base_url: "http://ecpay.example") }
        .to raise_error(Einvoice::ValidationError)
      expect { Einvoice::MOF::DonationCodes.new(base_url: "http://mof.example") }
        .to raise_error(Einvoice::ValidationError)
    end
  end
end
