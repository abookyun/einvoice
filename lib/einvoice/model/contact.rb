module Einvoice
  module Model
    class Contact < Einvoice::Model::Base
      attr_accessor :name, :address, :t_e_l, :email

      validates :name, presence: true, length: { maximum: 64 }
      validates :address, presence: true, length: { maximum: 128 }
      validates :t_e_l, length: { maximum: 64 }
      validates :email, length: { maximum: 512 }
    end
  end
end
