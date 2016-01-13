module Einvoice
  module Model
    module Neweb
      class Contact < Einvoice::Model::Neweb::Base
        VALID_OPTIONS_KEYS = [
          :name,
          :address,
          :t_e_l,
          :email
        ].freeze

        attr_accessor *VALID_OPTIONS_KEYS

        validates :name, presence: true, length: { maximum: 64 }
        validates :address, presence: true, length: { maximum: 128 }
        validates :t_e_l, length: { maximum: 64 }
        validates :email, length: { maximum: 512 }
      end
    end
  end
end
