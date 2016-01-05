module Einvoice
  module Model
    class Invoice < Einvoice::Model::Base
      attr_accessor :data_number, :data_date, :seller_id, :buyer_name,
                    :buyer_id, :customs_clearance_mark, :invoice_type,
                    :donate_mark, :carrier_type, :carrier_id1, :carrier_id2,
                    :print_mark, :n_p_o_b_a_n, :random_number, :invoice_item,
                    :sales_amount, :free_tax_sales_amount,
                    :zero_tax_sales_amount, :tax_type, :tax_rate, :tax_amount,
                    :total_amount, :contact, :customer_defined

      validates :data_number, presence: true, length: { maximum: 20 }
      validates :data_date, presence: true, length: { maximum: 10 }, format: { with: /\A\d{4}\/\d{2}\/\d{2}\z/ }
      validates :seller_id, presence: true, length: { maximum: 10 }
      validates :buyer_name, presence: true, length: { maximum: 60 }
      validates :buyer_id, presence: true, length: { maximum: 10 }
      validates :customs_clearance_mark, length: { maximum: 1 }, format: { with: /[01]/ }, customs_clearance_mark: true, allow_blank: true
      validates :invoice_type, presence: true, length: { maximum: 2 }, format: { with: /07|08/ }
      validates :donate_mark, presence: true, length: { maximum: 1 }, format: { with: /[01]/ }
      validates :carrier_type, length: { maximum: 6 }, format: { with: /[a-zA-Z]{2}\d{4}/ }, allow_blank: true
      validates :carrier_id1, length: { maximum: 64 }, carrier_id1: true, allow_blank: true
      validates :carrier_id2, length: { maximum: 64 }, carrier_id2: true, allow_blank: true
      validates :print_mark, presence: true, length: { maximum: 1 }, format: { with: /[YN]/ }, print_mark: true
      validates :n_p_o_b_a_n, length: { maximum: 10 }
      validates :random_number, length: { maximum: 4 }
      validates :invoice_item, presence: true
      validates :sales_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }
      validates :free_tax_sales_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }
      validates :zero_tax_sales_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }
      validates :tax_type, presence: true, length: { maximum: 1 }
      validates :tax_rate, presence: true, length: { maximum: 6 }
      validates :tax_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }
      validates :total_amount, presence: true, length: { maximum: 12 }, numericality: { greater_than_or_equal_to: 0 }
      validates :contact, presence: true
    end
  end
end
