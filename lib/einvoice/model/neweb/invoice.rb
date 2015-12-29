module Einvoice
  module Model
    module Neweb
      class Invoice < Einvoice::Model::Base
        attr_accessor :data_number, :data_date, :seller_id, :buyer_name,
                      :buyer_id, :customs_clearance_mark, :invoice_type,
                      :donate_mark, :carrier_type, :carrier_id1, :carrier_id2,
                      :print_mark, :n_p_o_b_a_n, :random_number, :invoice_items,
                      :sales_amount, :free_tax_sales_amount,
                      :zero_tax_sales_amount, :tax_type, :tax_rate, :tax_amount,
                      :total_amount, :contact, :customer_defined

        def initialize(attributes={})
          invoice_items = []
          attributes.each do |attribute, value|
            case attribute.to_sym
            when :invoice_item
              invoices << InvoiceItem.new(value)
            when :contact
              contact = Contact.new(value)
            when :customer_defined
              customer_defined = CustomerDefined.new(value)
            else
              instance_variable_set("@#{attribute}", value) if respond_to?(attribute.to_sym)
            end
          end
        end
      end
    end
  end
end
