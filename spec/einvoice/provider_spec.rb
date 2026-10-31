# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoice::Provider do
  it "raises NotImplementedError for every unimplemented method" do
    provider = described_class.new
    %i[name capabilities].each do |m|
      expect { provider.public_send(m) }.to raise_error(NotImplementedError)
    end
    %i[issue void allowance void_allowance query].each do |m|
      expect { provider.public_send(m, {}) }.to raise_error(NotImplementedError)
    end
  end

  describe "#validate_carrier" do
    def provider_with(capabilities)
      Class.new(described_class) do
        define_method(:name) { "bare" }
        define_method(:capabilities) { capabilities }
      end.new
    end

    it "refuses without CARRIER_VALIDATION" do
      expect { provider_with(Set[]).validate_carrier({}) }.to raise_error(Einvoice::UnsupportedError)
    end
  end

  it "mixes in capability support" do
    expect(described_class.ancestors).to include(Einvoice::Capability::Support)
  end
end
