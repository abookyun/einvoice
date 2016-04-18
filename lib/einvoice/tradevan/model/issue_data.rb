module Einvoice
  module Tradevan
    module Model
      class IssueData < Base
        VALID_OPTIONS_KEYS = [
          :companyUn,
          :orgId,
          :orgUn,
          :type,
          :saleIdentifier,
          :transactionNumber,
          :transactionDate,
          :transactionTime,
          :total,
          :transactionSource,
          :transactionTarget,
          :invoiceNumber,
          :allowanceNumber,
          :allowanceDate,
          :allowanceExclusiveAmount,
          :allowanceTax,
          :allowancePaperReturned,
          :paperPrintMode,
          :invoiceAlarmMode,
          :InvoicePaperReturned,
          :donate,
          :donationUnit,
          :carrierType,
          :carrierId,
          :carrierIdHidden,
          :buyerUn,
          :buyerTitle,
          :receiverName,
          :receiverAddrZip,
          :receiverAddrRoad,
          :receiverEmail,
          :receiverMobile,
          :idViewId,
          :memberId,
          :checkNumber,
          :invoiceDate,
          :invoiceTime,
          :texclusiveAmount,
          :oeclusiveAmount,
          :zexclusiveAmount,
          :tax,
          :mainRemark,
          :invoiceType,
          :itemList
        ].freeze

        attr_accessor *VALID_OPTIONS_KEYS

        validates :companyUn, presence: true, length: { is: 8 }
        validates :orgId, presence: true, length: { is: 5 }
        validates :orgUn, length: { is: 8 }, allow_blank: true
        validates :type, presence: true, length: { is: 1 }, inclusion: { in: %w(I R G H) }
        validates :saleIdentifier, presence: true, length: { maximum: 100 }, saleIdentifier: true
        validates :transactionNumber, presence: true, length: { maximum: 50 }
        validates :transactionDate, presence: true, length: { is: 8 }, format: { with: /\A\d{8}\Z/ }
        validates :transactionTime, presence: true, length: { is: 8 }, format: { with: /\A\d{2}\:\d{2}\:\d{2}\Z/ }
        validates :total, presence: true, length: { maximum: 20 }, total: true
        validates :transactionSource, length: { maximum: 50 } # Public Affair Firm presence: true
        validates :transactionTarget, length: { maximum: 50 } # Public Affair Firm presence: true
        validates :paperPrintMode, presence: true, length: { is: 1 }, inclusion: { in: %w(0 1 2 3 4) }
        validates :invoiceAlarmMode, presence: true, length: { is: 1 }, inclusion: { in: %w(0 1 2 3 4 5 6) }
        validates :InvoicePaperReturned, allow_blank: true, length: { maximum: 1 }, inclusion: { in: %w(Y N) }, InvoicePaperReturned: true
        validates :carrierType, presence: true, length: { is: 6 }, if: proc { self.paperPrintMode.to_i == 0 && self.donate == 'N' }
        validates :buyerUn, length: { is: 8 }, allow_blank: true
        validates :buyerTitle, length: { maximum: 60 }, allow_blank: true
        validates :idViewId, allow_blank: true, length: { maximum: 10 }
        validates :memberId, allow_blank: true, length: { maximum: 50 }
        validates :itemList, presence: true, itemList: true

        # Type R G H
        validates :invoiceNumber, presence: true, length: { is: 10 }, if: proc { %w(R G H).include?(self.type) }

        # Type H
        validates :allowanceNumber, presence: true, length: { is: 16 }, allowanceNumber: true, if: proc { self.type == 'H' }
        validates :allowanceDate, presence: true, length: { is: 8 }, format: { with: /\A\d{8}\Z/ }, if: proc { self.type == 'H' }
        validates :allowanceExclusiveAmount, presence: true, length: { maximum: 20 }, if: proc { self.type == 'H' }
        validates :allowanceTax, presence: true, length: { maximum: 8 }, if: proc { self.type == 'H' }
        validates :allowancePaperReturned, presence: true, length: { is: 1 }, inclusion: { in: %w(Y N) }, if: proc { self.type == 'H' }

        # Type I R G
        validates :donate, presence: true, length: { is: 1 }, if: proc { %w(I R G).include?(self.type) && self.buyerUn.blank? && self.paperPrintMode.to_i == 0 }
        validates :donationUnit, presence: true, length: { maximum: 10 }, if: proc { %w(I R G).include?(self.type) && self.donate == 'Y' }
        validates :carrierId, presence: true, length: { maximum: 64 }, if: proc { %w(I R G).include?(self.type) && self.paperPrintMode.to_i == 0 && self.donate == 'N' }
        validates :carrierIdHidden, presence: true, length: { maximum: 64 }, if: proc { %w(I R G).include?(self.type) && self.paperPrintMode.to_i == 0 && self.donate == 'N' }
        validates :receiverName, allow_blank: true, length: { maximum: 30 }, if: proc { %w(I R G).include?(self.type) }
        validates :receiverAddrZip, allow_blank: true, length: { maximum: 5 }, if: proc { %w(I R G).include?(self.type) }
        validates :receiverAddrRoad, allow_blank: true, length: { maximum: 100 }, if: proc { %w(I R G).include?(self.type) }
        validates :receiverEmail, allow_blank: true, length: { maximum: 80 }, if: proc { %w(I R G).include?(self.type) }
        validates :receiverMobile, allow_blank: true, length: { maximum: 15 }, if: proc { %w(I R G).include?(self.type) }

        # Type G
        validates :checkNumber, allow_blank: true, length: { is: 4 }, if: proc { self.type == 'G' }
        validates :invoiceDate, allow_blank: true, length: { is: 8 }, if: proc { self.type == 'G' }
        validates :invoiceTime, allow_blank: true, length: { is: 8 }, if: proc { self.type == 'G' }
        validates :texclusiveAmount, allow_blank: true, length: { maximum: 20 }, if: proc { self.type == 'G' }
        validates :oeclusiveAmount, allow_blank: true, length: { maximum: 20 }, if: proc { self.type == 'G' }
        validates :zexclusiveAmount, allow_blank: true, length: { maximum: 20 }, if: proc { self.type == 'G' }
        validates :tax, allow_blank: true, length: { maximum: 20 }, if: proc { self.type == 'G' }
        validates :mainRemark, allow_blank: true, length: { maximum: 300 }, if: proc { self.type == 'G' }
        validates :invoiceType, allow_blank: true, length: { is: 2 }, inclusion: { in: %w(07 08) }, if: proc { self.type == 'G' }

        def payload
          serializable_hash(except: [:errors, :validation_context], include: [:itemList])
        end
      end
    end
  end
end
