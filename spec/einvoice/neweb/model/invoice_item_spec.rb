require "spec_helper"

RSpec.describe Einvoice::Neweb::Model::InvoiceItem, type: :model do
  context "validations" do
    subject { build(:neweb_invoice_item) }

    it { is_expected.to validate_presence_of :description }
    it { is_expected.to validate_presence_of :quantity }
    it { is_expected.to validate_presence_of :unit_price }
    it { is_expected.to validate_presence_of :amount }
    it { is_expected.to validate_presence_of :sequence_number }

    it { is_expected.to validate_length_of(:description).is_at_most(256) }
    it { is_expected.to validate_length_of(:quantity).is_at_most(17) }
    it { is_expected.to validate_length_of(:unit).is_at_most(6) }
    it { is_expected.to validate_length_of(:unit_price).is_at_most(17) }
    it { is_expected.to validate_length_of(:amount).is_at_most(17) }
    it { is_expected.to validate_length_of(:sequence_number).is_at_most(3) }
    it { is_expected.to validate_length_of(:remark).is_at_most(40) }
  end
end
