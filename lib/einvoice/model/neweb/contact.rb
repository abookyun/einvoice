module Einvoice
  module Model
    module Neweb
      class Contact < Einvoice::Model::Base
        attr_accessor :name, :address, :t_e_l, :email

        def initialize(attributes={})
          attributes.each do |attribute, value|
            instance_variable_set("@#{attribute}", value) if respond_to?(attribute.to_sym)
          end
        end
      end
    end
  end
end
