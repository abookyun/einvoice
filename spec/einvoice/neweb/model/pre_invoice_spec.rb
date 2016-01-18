require "spec_helper"

RSpec.describe Einvoice::Neweb::Model::PreInvoice, type: :model do
  context "validations" do
    it { is_expected.to validate_presence_of :data_number }
    it { is_expected.to validate_presence_of :data_date }

    it { is_expected.to validate_length_of(:data_number).is_at_most(20) }
    it { is_expected.to validate_length_of(:data_date).is_at_most(10) }
  end
end
