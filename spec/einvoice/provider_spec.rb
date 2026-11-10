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

  it "checks a carrier only when the provider declares CARRIER_VALIDATION" do
    adapter = lambda do |capabilities|
      Class.new(described_class) do
        define_method(:name) { "test" }
        define_method(:capabilities) { capabilities }
      end.new
    end
    carrier = { type: :mobile_barcode, code: "/ABC1234" }

    expect { adapter.call([Einvoice::Capability::ISSUE]).validate_carrier(carrier) }
      .to raise_error(Einvoice::UnsupportedError)
    expect { adapter.call([Einvoice::Capability::CARRIER_VALIDATION]).validate_carrier(carrier) }
      .to raise_error(NotImplementedError, /must implement #validate_carrier/)
  end

  it "mixes in capability support" do
    expect(described_class.ancestors).to include(Einvoice::Capability::Support)
  end
end
