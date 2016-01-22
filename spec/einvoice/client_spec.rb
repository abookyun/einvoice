require "spec_helper"

RSpec.describe Einvoice::Client do
  describe "#initialize" do
    it "initialize instance" do
      provider = double(:provider)
      expect(described_class.new(provider).provider).to eql provider
    end
  end

  describe "#issue" do
    let(:provider) { double(:provider) }
    subject { described_class.new(provider) }

    it "calls provider to issue" do
      expect(provider).to receive(:issue).with({}, {})
      subject.issue({})
    end
  end

  describe "#query" do
    let(:provider) { double(:provider) }
    subject { described_class.new(provider) }

    it "calls provider to query" do
      expect(provider).to receive(:query).with({}, {})
      subject.query({})
    end
  end

  describe "#cancel" do
    let(:provider) { double(:provider) }
    subject { described_class.new(provider) }

    it "calls provider to cancel" do
      expect(provider).to receive(:cancel).with({}, {})
      subject.cancel({})
    end
  end

  describe "#allowance_for" do
    let(:provider) { double(:provider) }
    subject { described_class.new(provider) }

    it "calls provider to allowance_for" do
      expect(provider).to receive(:allowance_for).with({}, {})
      subject.allowance_for({})
    end
  end

  describe "#cancel_allowance" do
    let(:provider) { double(:provider) }
    subject { described_class.new(provider) }

    it "calls provider to cancel_allowance" do
      expect(provider).to receive(:cancel_allowance).with({}, {})
      subject.cancel_allowance({})
    end
  end
end
