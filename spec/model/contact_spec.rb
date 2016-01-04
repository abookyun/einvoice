require "spec_helper"

RSpec.describe Einvoice::Model::Contact, type: :model do
  context "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:address) }

    it { is_expected.to validate_length_of(:name).is_at_most(64) }
    it { is_expected.to validate_length_of(:address).is_at_most(128) }
    it { is_expected.to validate_length_of(:t_e_l).is_at_most(64) }
    it { is_expected.to validate_length_of(:email).is_at_most(512) }
  end
end
