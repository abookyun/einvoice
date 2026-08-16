# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoice::Error do
  it "exposes a stable code per subclass" do
    expect(Einvoice::AuthError.new(provider: "mock").code).to eq(:auth)
    expect(Einvoice::ConflictError.new(provider: "mock").code).to eq(:conflict)
    expect(Einvoice::NumberExhaustedError.new(provider: "mock").code).to eq(:number_exhausted)
  end

  it "lets callers rescue precisely or broadly" do
    expect { raise Einvoice::ConflictError.new("dup", provider: "mock") }
      .to raise_error(Einvoice::ConflictError)
    expect { raise Einvoice::ConflictError.new("dup", provider: "mock") }
      .to raise_error(Einvoice::Error)
    expect(Einvoice::ConflictError.ancestors).to include(StandardError)
  end

  it "preserves the provider's raw code/message/payload and a reason" do
    error = Einvoice::ConflictError.new(
      "already voided",
      provider: "ecpay",
      reason: Einvoice::Reason::ALREADY_VOIDED,
      raw_code: "5070453",
      raw_message: "該發票已被作廢過",
      raw: { "RtnCode" => 5070453 }
    )
    expect(error.provider).to eq("ecpay")
    expect(error.reason).to eq(:already_voided)
    expect(error.raw_code).to eq("5070453")
    expect(error.raw_message).to eq("該發票已被作廢過")
    expect(error.raw).to eq("RtnCode" => 5070453)
  end

  describe ".for" do
    it "builds the subclass matching a normalized code" do
      expect(Einvoice::Error.for(:not_found, "x", provider: "mock"))
        .to be_a(Einvoice::NotFoundError)
      expect(Einvoice::Error.for(:auth, provider: "mock").code).to eq(:auth)
    end

    it "falls back to UnknownError for an unrecognized code" do
      expect(Einvoice::Error.for(:nonsense, provider: "mock")).to be_a(Einvoice::UnknownError)
    end
  end

  describe "#to_h" do
    it "drops nil fields and omits raw" do
      error = Einvoice::AuthError.new("bad key", provider: "ecpay", raw_code: "0")
      expect(error.to_h).to eq(
        provider: "ecpay", code: :auth, message: "bad key", raw_code: "0"
      )
    end
  end

  describe "#cause" do
    it "keeps an explicitly passed cause" do
      original = StandardError.new("boom")
      error = Einvoice::NetworkError.new("timeout", provider: "mock", cause: original)
      expect(error.cause).to eq(original)
    end
  end

  # Same drift guard as Capability::ALL — a reason that exists but is missing
  # from the list is one no consumer can enumerate.
  describe "Reason::ALL" do
    it "lists every reason defined in the module" do
      declared = Einvoice::Reason.constants
                                 .map { |const| Einvoice::Reason.const_get(const) }
                                 .grep(Symbol)
      expect(Einvoice::Reason::ALL).to match_array(declared)
    end
  end
end
