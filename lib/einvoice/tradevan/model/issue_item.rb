module Einvoice
  module Tradevan
    module Model
      class IssueItem < Base
        VALID_OPTIONS_KEYS = [
          :saleIdentifier, # Same as invoice.saleIdentifier
          :serialNumber,
          :invoiceNumber,
          :invoiceDate,
          :invoiceTime,
          :productCode,
          :productName,
          :qty,
          :price,
          :tax,
          :itemExclude,
          :itemTotal,
          :taxType,
          :description
        ]

        attr_accessor *VALID_OPTIONS_KEYS

        validates :saleIdentifier, presence: true, length: { maximum: 100 }
        validates :serialNumber, presence: true, length: { is: 4 }, numericality: true
        validates :invoiceNumber, allow_blank: true, length: { is: 10 }
        validates :invoiceDate, allow_blank: true, length: { is: 8 }, numericality: true
        validates :invoiceTime, allow_blank: true, length: { is: 8 }, format: { with: /\Ad{2}\:\d{2}\:\d{2}\Z/ }
        validates :productCode, allow_blank: true, length: { maximum: 30 }
        validates :productName, presence: true, length: { maximum: 300 }
        validates :qty, presence: true, length: { maximum: 20 }
        validates :price, presence: true, length: { maximum: 20 }
        validates :tax, allow_blank: true, length: { maximum: 20 }
        validates :itemExclude, allow_blank: true, length: { maximum: 20 }
        validates :itemTotal, allow_blank: true, length: { maximum: 20 }
        validates :taxType, allow_blank: true, length: { is: 1 }, inclusion: { in: %w(T O Z) }
        validates :description, allow_blank: true, length: { maximum: 300 }
      end
    end
  end
end
