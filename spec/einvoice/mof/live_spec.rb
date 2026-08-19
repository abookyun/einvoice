# frozen_string_literal: true

# Drives 財政部's real ODS dataset endpoint. Skipped unless MOF_LIVE=1, so CI and
# a normal `rspec` run stay offline; the recorded specs cover the same ground
# deterministically.
#
#   MOF_LIVE=1 bundle exec rspec spec/einvoice/mof/live_spec.rb
#
# No credentials — the dataset is public. This is what keeps the cassettes
# honest, and in particular it is the only thing that would notice 財政部 closing
# the endpoint behind the api_key/oauth2 schemes its OpenAPI already declares.
RSpec.describe "財政部 donation-code dataset (live)", :live do
  before(:all) do
    skip "set MOF_LIVE=1 to run the live 財政部 specs" unless ENV["MOF_LIVE"] == "1"
  end

  subject(:codes) { Einvoice::MOF::DonationCodes.new }

  it "is still open without credentials" do
    expect(codes.lookup("2718")).to be_a(Einvoice::MOF::DonationCode)
  end

  it "resolves a registered 愛心碼" do
    result = codes.lookup("2718")

    expect(result.code).to eq("2718")
    expect(result.name).not_to be_empty
    expect(result.ubn).to match(/\A\d{8}\z/)
  end

  it "reports an unregistered code as absent, not as an error" do
    expect(codes.lookup("105")).to be_nil
  end

  it "finds every code held by a 統一編號" do
    expect(codes.for_ubn("92000392").map(&:code)).to include("2718")
  end

  it "pages the whole dataset" do
    all = codes.all

    expect(all.size).to be > 1_500
    expect(all.map(&:code).uniq.size).to eq(all.size)
    expect(all).to all(have_attributes(code: match(/\A\d{3,7}\z/)))
  end
end
