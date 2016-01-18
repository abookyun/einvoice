require "spec_helper"

RSpec.describe Einvoice::Neweb::Model::Invoice, type: :model do
  describe "#initialize" do
    it "raises NotImplementedError" do
      expect { described_class.new }.to raise_error NotImplementedError
    end
  end
end
