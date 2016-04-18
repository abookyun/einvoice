module Einvoice
  module Tradevan
    module Model
      class VoidData < Base
        VALID_OPTIONS_KEYS = [
          :type,
          :saleIdentifier,
          :invoiceNumber,
          :invoicePaperReturned,
          :allowanceNumber,
          :allowancePaperReturned,
        ].freeze

        attr_accessor *VALID_OPTIONS_KEYS

        validates :type, presence: true, length: { is: 1 }, inclusion: { in: %w(C I A) }

        # Type C I
        validates :saleIdentifier, presence: true, length: { maximum: 100 }, if: proc { %w(C I).include?(self.type) }
        validates :invoiceNumber, presence: true, length: { is: 10 }, if: proc { %w(C I).include?(self.type) }
        validates :invoicePaperReturned, presence: true, length: { maximum: 1 }, inclusion: { in: %w(Y N) }, if: proc { %w(C I).include?(self.type) }

        # Type A
        validates :allowanceNumber, presence: true, length: { is: 16 }, allowanceNumber: true, if: proc { self.type == 'A' }
        validates :allowancePaperReturned, presence: true, length: { is: 1 }, inclusion: { in: %w(Y N) }, if: proc { self.type == 'A' }

        def payload
          serializable_hash(except: [:errors, :validation_context, :itemList])
        end
      end
    end
  end
end
