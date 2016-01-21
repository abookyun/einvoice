module Einvoice
  module Neweb
    module Model
      class Invoice < Base
        VALID_OPTIONS_KEYS = [
          :seller_id,
          :buyer_name,
          :buyer_id,
          :customs_clearance_mark,
          :invoice_type,
          :donate_mark,
          :carrier_type,
          :carrier_id1,
          :carrier_id2,
          :print_mark,
          :n_p_o_b_a_n,
          :random_number,
          :invoice_item,
          :sales_amount,
          :free_tax_sales_amount,
          :zero_tax_sales_amount,
          :tax_type,
          :tax_rate,
          :tax_amount,
          :total_amount,
          :contact,
          :customer_defined
        ].freeze

        attr_accessor *VALID_OPTIONS_KEYS

        validates :seller_id, presence: true, length: { maximum: 10 }
        validates :buyer_name, presence: true, length: { maximum: 60 }, buyer_name: true
        validates :buyer_id, presence: true, length: { maximum: 10 }
        validates :customs_clearance_mark, length: { maximum: 1 }, inclusion: { in: %w(1 2) }, allow_blank: true
        validates :invoice_type, presence: true, length: { is: 2 }, inclusion: { in: %w(07 08) }
        validates :donate_mark, presence: true, length: { is: 1 }, inclusion: { in: %w(0 1) }, donate_mark: true
        validates :carrier_type, length: { maximum: 6 }, format: { with: /[a-zA-Z]{2}\d{4}/ }, allow_blank: true
        validates :carrier_id1, length: { maximum: 64 }, carrier_id1: true, allow_blank: true
        validates :carrier_id2, length: { maximum: 64 }, carrier_id2: true, allow_blank: true
        validates :print_mark, presence: true, length: { is: 1 }, inclusion: { in: %w(Y N) }, print_mark: true
        validates :n_p_o_b_a_n, length: { maximum: 10 }
        validates :random_number, length: { is: 4 }, allow_blank: true
        validates :invoice_item, presence: true
        validates :sales_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }
        validates :free_tax_sales_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }
        validates :zero_tax_sales_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }
        validates :tax_type, presence: true, length: { is: 1 }, inclusion: { in: %w(1 2 3 4 9) }
        validates :tax_rate, presence: true, length: { maximum: 6 }
        validates :tax_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }
        validates :total_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }, total_amount: true
        validates :contact, presence: true

        def initialize
          raise NotImplementedError, "You should initialize with subclasses"
        end
      end
    end
  end
end
