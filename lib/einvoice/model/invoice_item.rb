module Einvoice
  module Model
    class InvoiceItem < Einvoice::Model::Base
      attr_accessor :description, :quantity, :unit, :unit_price, :amount,
                    :sequence_number, :remark

      validates :description, presence: true, length: { maximum: 256 }
      validates :quantity, presence: true, length: { maximum: 17 }
      validates :unit, length: { maximum: 6 }
      validates :unit_price, presence: true, length: { maximum: 17 }
      validates :amount, presence: true, length: { maximum: 17 }
      validates :sequence_number, presence: true, length: { maximum: 3 }
      validates :remark, length: { maximum: 40 }

      def initialize(attributes={})
        attributes.each do |attribute, value|
          instance_variable_set("@#{attribute}", value) if respond_to?(attribute.to_sym)
        end
      end

      def attributes
        {
          'description' => description,
          'quantity' => quantity,
          'unit' => unit,
          'unit_price' => unit_price,
          'amount' => amount,
          'sequence_number' => sequence_number,
          'remark' => remark
        }
      end
    end
  end
end
