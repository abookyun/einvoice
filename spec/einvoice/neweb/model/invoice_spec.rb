require "spec_helper"

RSpec.describe Einvoice::Neweb::Model::Invoice, type: :model do
  context "validations" do
    subject { Einvoice::Neweb::Model::PreInvoice.new }

    it { is_expected.to validate_presence_of :seller_id }
    it { is_expected.to validate_presence_of :buyer_name }
    it { is_expected.to validate_presence_of :buyer_id }
    it { is_expected.to validate_presence_of :invoice_type }
    it { is_expected.to validate_presence_of :donate_mark }
    it { is_expected.to validate_presence_of :print_mark }
    it { is_expected.to validate_presence_of :invoice_item }
    it { is_expected.to validate_presence_of :sales_amount }
    it { is_expected.to validate_presence_of :free_tax_sales_amount }
    it { is_expected.to validate_presence_of :zero_tax_sales_amount }
    it { is_expected.to validate_presence_of :tax_type }
    it { is_expected.to validate_presence_of :tax_rate }
    it { is_expected.to validate_presence_of :tax_amount }
    it { is_expected.to validate_presence_of :total_amount }
    it { is_expected.to validate_presence_of :contact }

    it { is_expected.to validate_length_of(:seller_id).is_at_most(10) }
    it { is_expected.to validate_length_of(:buyer_name).is_at_most(60) }
    it { is_expected.to validate_length_of(:buyer_id).is_at_most(10) }
    it { is_expected.to validate_length_of(:customs_clearance_mark).is_at_most(1) }
    it { is_expected.to validate_length_of(:invoice_type).is_equal_to(2) }
    it { is_expected.to validate_length_of(:donate_mark).is_equal_to(1) }
    it { is_expected.to validate_length_of(:carrier_type).is_at_most(6) }
    it { is_expected.to validate_length_of(:carrier_id1).is_at_most(64) }
    it { is_expected.to validate_length_of(:carrier_id2).is_at_most(64) }
    it { is_expected.to validate_length_of(:print_mark).is_equal_to(1) }
    it { is_expected.to validate_length_of(:n_p_o_b_a_n).is_at_most(10) }
    it { is_expected.to validate_length_of(:random_number).is_equal_to(4) }
    it { is_expected.to validate_length_of(:sales_amount).is_at_most(12) }
    it { is_expected.to validate_length_of(:free_tax_sales_amount).is_at_most(12) }
    it { is_expected.to validate_length_of(:zero_tax_sales_amount).is_at_most(12) }
    it { is_expected.to validate_length_of(:tax_type).is_equal_to(1) }
    it { is_expected.to validate_length_of(:tax_rate).is_at_most(6) }
    it { is_expected.to validate_length_of(:tax_amount).is_at_most(12) }
    it { is_expected.to validate_length_of(:total_amount).is_at_most(12) }

    it { is_expected.to validate_inclusion_of(:customs_clearance_mark).in_array(%w(1 2)) }
    it { is_expected.to validate_inclusion_of(:invoice_type).in_array(%w(07 08)) }
    it { is_expected.to validate_inclusion_of(:donate_mark).in_array(%w(0 1)) }
    it { is_expected.to validate_inclusion_of(:print_mark).in_array(%w(Y N)) }
    it { is_expected.to validate_inclusion_of(:tax_type).in_array(%w(1 2 3 4 9)) }

    it { is_expected.to validate_numericality_of(:sales_amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:free_tax_sales_amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:zero_tax_sales_amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:tax_amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:total_amount).is_greater_than_or_equal_to(0) }

    context "validates when UBN is 0 * 10 (B2C)" do
      it "returns false if buyer_name is ascii and size > 4" do
        invoice = build(:neweb_pre_invoice, buyer_id: "0" * 10, buyer_name: "abcde")
        expect(invoice.valid?).to be_falsey
      end

      it "returns false if buyer_name isn't ascii and size > 2" do
        invoice = build(:neweb_pre_invoice, buyer_id: "0" * 10, buyer_name: "中文字")
        expect(invoice.valid?).to be_falsey
      end
    end
  end

  describe "#initialize" do
    it "raises NotImplementedError" do
      expect { described_class.new }.to raise_error NotImplementedError
    end
  end
end
