require "spec_helper"

RSpec.describe Einvoice::Neweb::Model::Query, type: :model do
  context "validations" do
    subject { build(:neweb_query) }

    it { is_expected.to validate_presence_of :invoice_date_time_s }
    it { is_expected.to validate_presence_of :invoice_date_time_e }
    it { is_expected.to validate_presence_of :data_number_s }
    it { is_expected.to validate_presence_of :data_number_e }
    it { is_expected.to validate_presence_of :sync_status_update }

    it { is_expected.to validate_length_of(:invoice_date_time_s).is_at_most(14) }
    it { is_expected.to validate_length_of(:invoice_date_time_e).is_at_most(14) }
    it { is_expected.to validate_length_of(:data_number_s).is_at_most(20) }
    it { is_expected.to validate_length_of(:data_number_e).is_at_most(20) }
    it { is_expected.to validate_length_of(:sync_status_update).is_at_most(1) }
  end

  describe "#payload" do
    pending
  end

  describe "#wrapped_payload" do
    let(:query) { build(:neweb_query) }

    it "wraps needed outter nodes for neweb API" do
      expect(query.wrapped_payload[:invoice_map_root]).to have_key(:invoice_map)
    end
  end
end
