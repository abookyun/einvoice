module Einvoice
  module Neweb
    module Model
      class SellerInvoice < Invoice
        include Einvoice::Validator::Neweb

        TYPE_SPECIFIC_KEYS = [:invoice_number, :invoice_date]

        attr_accessor *TYPE_SPECIFIC_KEYS

        validates :invoice_number, presence: true, length: { maximum: 20 }
        validates :invoice_date, presence: true, length: { maximum: 10 }, format: { with: /\A\d{4}\/\d{2}\/\d{2}\z/ }

        def initialize
          # overwritten
        end
      end
    end
  end
end
