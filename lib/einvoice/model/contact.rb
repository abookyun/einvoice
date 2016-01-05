module Einvoice
  module Model
    class Contact < Einvoice::Model::Base
      attr_accessor :name, :address, :t_e_l, :email

      validates :name, presence: true, length: { maximum: 64 }
      validates :address, presence: true, length: { maximum: 128 }
      validates :t_e_l, length: { maximum: 64 }
      validates :email, length: { maximum: 512 }

      def initialize(attributes={})
        attributes.each do |attribute, value|
          instance_variable_set("@#{attribute}", value) if respond_to?(attribute.to_sym)
        end
      end

      def attributes
        {
          'name' => name,
          'address' => address,
          't_e_l' => t_e_l,
          'email' => email
        }
      end
    end
  end
end
