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

  it "mixes in capability support" do
    expect(described_class.ancestors).to include(Einvoice::Capability::Support)
  end
end
