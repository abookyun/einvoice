require "spec_helper"

RSpec.describe Einvoice::Configuration do
  subject { Class.new { extend Einvoice::Configuration } }

  describe "#configure" do
    it "provides a syntax sugar to configure" do
      expect { |b|
        subject.configure &b
      }.to yield_with_args(subject)
    end
  end

  describe "#options" do
    it "returns all options as a hash" do
      expect(subject.options).to be_a Hash
    end

    Einvoice::Configuration::VALID_OPTIONS_KEYS.each do |k|
      it "includes #{k} option key" do
        expect(subject.options).to have_key k
      end
    end
  end

  describe "#reset" do
    Einvoice::Configuration::VALID_OPTIONS_KEYS.each do |k|
      it "resets #{k} option to default value" do
        subject.send "#{k}=", "foo"

        expect {
          subject.reset
        }.to change(subject, k)
      end
    end
  end
end
