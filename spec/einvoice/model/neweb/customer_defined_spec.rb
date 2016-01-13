require "spec_helper"

RSpec.describe Einvoice::Model::Neweb::CustomerDefined, type: :model do
  context "validations" do
    it { is_expected.to validate_length_of(:project_no).is_at_most(64) }
    it { is_expected.to validate_length_of(:purchase_no).is_at_most(64) }
    it { is_expected.to validate_length_of(:stamp_duty_flag).is_at_most(1) }
  end
end
