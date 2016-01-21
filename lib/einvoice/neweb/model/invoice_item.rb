module Einvoice
  module Neweb
    module Model
      class InvoiceItem < Base
        VALID_OPTIONS_KEYS = [
          :description,
          :quantity,
          :unit,
          :unit_price,
          :amount,
          :sequence_number,
          :remark
        ].freeze

        attr_accessor *VALID_OPTIONS_KEYS

        validates :description, presence: true, length: { maximum: 256 }
        validates :quantity, presence: true, length: { maximum: 17 }, quantity: true
        validates :unit, length: { maximum: 6 }
        validates :unit_price, presence: true, length: { maximum: 17 }, unit_price: true
        validates :amount, presence: true, length: { maximum: 17 }, amount: true
        validates :sequence_number, presence: true, length: { maximum: 3 }, format: { with: /\A[1-9]|[1-9][0-9]|[1-9][0-9][0-9]\Z/ }
        validates :remark, length: { maximum: 40 }
      end
    end
  end
end
