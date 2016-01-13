require "spec_helper"

RSpec.describe Einvoice::Model::Neweb::Invoice, type: :model do
  context "validations" do
    it { is_expected.to validate_presence_of :data_number }
    it { is_expected.to validate_presence_of :data_date }
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

    it { is_expected.to validate_length_of(:data_number).is_at_most(20) }
    it { is_expected.to validate_length_of(:data_date).is_at_most(10) }
    it { is_expected.to validate_length_of(:seller_id).is_at_most(10) }
    it { is_expected.to validate_length_of(:buyer_name).is_at_most(60) }
    it { is_expected.to validate_length_of(:buyer_id).is_at_most(10) }
    it { is_expected.to validate_length_of(:customs_clearance_mark).is_at_most(1) }
    it { is_expected.to validate_length_of(:invoice_type).is_at_most(2) }
    it { is_expected.to validate_length_of(:donate_mark).is_at_most(1) }
    it { is_expected.to validate_length_of(:carrier_type).is_at_most(6) }
    it { is_expected.to validate_length_of(:carrier_id1).is_at_most(64) }
    it { is_expected.to validate_length_of(:carrier_id2).is_at_most(64) }
    it { is_expected.to validate_length_of(:print_mark).is_at_most(1) }
    it { is_expected.to validate_length_of(:n_p_o_b_a_n).is_at_most(10) }
    it { is_expected.to validate_length_of(:random_number).is_at_most(4) }
    it { is_expected.to validate_length_of(:sales_amount).is_at_most(12) }
    it { is_expected.to validate_length_of(:free_tax_sales_amount).is_at_most(12) }
    it { is_expected.to validate_length_of(:zero_tax_sales_amount).is_at_most(12) }
    it { is_expected.to validate_length_of(:tax_type).is_at_most(1) }
    it { is_expected.to validate_length_of(:tax_rate).is_at_most(6) }
    it { is_expected.to validate_length_of(:tax_amount).is_at_most(12) }
    it { is_expected.to validate_length_of(:total_amount).is_at_most(12) }

    it { is_expected.to validate_numericality_of(:sales_amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:free_tax_sales_amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:zero_tax_sales_amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:tax_amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:total_amount).is_greater_than_or_equal_to(0) }
  end
end
