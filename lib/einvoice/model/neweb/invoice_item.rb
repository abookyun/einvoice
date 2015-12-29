module Einvoice
  module Model
    module Neweb
      class InvoiceItem < Einvoice::Model::Base
        attr_accessor :description, :quantity, :unit, :unit_price, :amount,
                      :sequence_number, :remark

        def initialize(attributes={})
          attributes.each do |attribute, value|
            instance_variable_set("@#{attribute}", value) if respond_to?(attribute.to_sym)
          end
        end
      end
    end
  end
end
