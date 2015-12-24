require "spec_helper"

RSpec.describe Einvoice::API do
  before do
    @keys = Einvoice::Configuration::VALID_OPTIONS_KEYS
  end

  context "with module configuration" do
    before do
      Einvoice.configure do |config|
        @keys.each do |key|
          config.send("#{key}=", key)
        end
      end
    end

    after do
      Einvoice.reset
    end

    it "inherits module configuration" do
      api = Einvoice::API.new
      @keys.each do |key|
        expect(api.send(key)).to eq key
      end
    end

    context "with class configuration" do
      before do
        @configuration = {
          client_id: '9999',
          client_secret: '9999',
          endpoint: 'http://test.com/',
          format: :xml,
        }
      end

      context "during initialization" do
        it "overrides module configuration" do
          api = Einvoice::API.new(@configuration)
          @keys.each do |key|
            expect(api.send(key)).to eq @configuration[key]
          end
        end
      end

      context "after initilization" do
        let(:api) { Einvoice::API.new }

        before do
          @configuration.each do |key, value|
            api.send("#{key}=", value)
          end
        end

        it "overrides module configuration after initialization" do
          @keys.each do |key|
            expect(api.send(key)).to eq @configuration[key]
          end
        end
      end
    end
  end

  describe "#config" do
    subject { Einvoice::API.new }

    let(:config) do
      c = {}; @keys.each {|key| c[key] = key }; c
    end

    it "returns a hash representing the configuration" do
      @keys.each do |key|
        subject.send("#{key}=", key)
      end
      expect(subject.config).to eq config
    end
  end
end
