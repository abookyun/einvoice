# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoice::Capability do
  it "defines the five core operations and the optional feature flags" do
    expect(described_class::ISSUE).to eq(:issue)
    expect(described_class::VOID_ALLOWANCE).to eq(:void_allowance)
    expect(described_class::FOREIGN_CURRENCY).to eq(:foreign_currency)
    expect(described_class::ALL).to include(:issue, :query, :b2b, :mixed_tax)
    expect(described_class::ALL.uniq).to eq(described_class::ALL)
  end

  describe Einvoice::Capability::Support do
    let(:provider_class) do
      Class.new do
        include Einvoice::Capability::Support
        attr_reader :name, :capabilities

        def initialize(*caps)
          @name = "dummy"
          @capabilities = Set.new(caps)
        end
      end
    end

    it "feature-detects a declared capability" do
      provider = provider_class.new(Einvoice::Capability::ISSUE)
      expect(provider.supports?(Einvoice::Capability::ISSUE)).to be(true)
      expect(provider.supports?(Einvoice::Capability::B2B)).to be(false)
    end

    it "assert_supports! passes for a declared capability" do
      provider = provider_class.new(Einvoice::Capability::QUERY)
      expect { provider.assert_supports!(Einvoice::Capability::QUERY) }.not_to raise_error
    end

    it "assert_supports! raises UnsupportedError naming the provider for a missing one" do
      provider = provider_class.new
      expect { provider.assert_supports!(Einvoice::Capability::FOREIGN_CURRENCY) }
        .to raise_error(Einvoice::UnsupportedError, /dummy.*foreign_currency/) do |error|
          expect(error.code).to eq(:unsupported)
          expect(error.provider).to eq("dummy")
        end
    end
  end
end
