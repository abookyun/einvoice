require "spec_helper"

RSpec.describe Einvoice::Neweb::Model::CustomerDefined, type: :model do
  context "validations" do
    it { is_expected.to validate_length_of(:project_no).is_at_most(64) }
    it { is_expected.to validate_length_of(:purchase_no).is_at_most(64) }
    it { is_expected.to validate_length_of(:stamp_duty_flag).is_equal_to(1) }
  end
end
