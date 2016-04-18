require "spec_helper"

RSpec.describe Einvoice::Tradevan::Model::IssueItem, type: :model do
  context "validations" do
    it { is_expected.to validate_presence_of(:saleIdentifier) }
    it { is_expected.to validate_length_of(:saleIdentifier).is_at_most(100) }
    it { is_expected.to validate_presence_of(:serialNumber) }
    it { is_expected.to validate_length_of(:serialNumber).is_equal_to(4) }
    it { is_expected.to validate_length_of(:invoiceNumber).is_equal_to(10) }
    it { is_expected.to validate_length_of(:invoiceDate).is_equal_to(8) }
    it { is_expected.to validate_length_of(:invoiceTime).is_equal_to(8) }
    it { is_expected.to validate_length_of(:productCode).is_at_most(30) }
    it { is_expected.to validate_presence_of(:productName) }
    it { is_expected.to validate_length_of(:productName).is_at_most(300) }
    it { is_expected.to validate_presence_of(:qty) }
    it { is_expected.to validate_length_of(:qty).is_at_most(20) }
    it { is_expected.to validate_presence_of(:price) }
    it { is_expected.to validate_length_of(:price).is_at_most(20) }
    it { is_expected.to validate_length_of(:tax).is_at_most(20) }
    it { is_expected.to validate_length_of(:itemExclude).is_at_most(20) }
    it { is_expected.to validate_length_of(:itemTotal).is_at_most(20) }
    # it { is_expected.to validate_length_of(:taxType).is_equal_to(1) }
    it { is_expected.to validate_length_of(:description).is_at_most(300) }
  end
end
