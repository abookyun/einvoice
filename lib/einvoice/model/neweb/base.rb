require "active_model"

require "einvoice/validator/neweb/carrier_id1_validator"
require "einvoice/validator/neweb/carrier_id2_validator"
require "einvoice/validator/neweb/customs_clearance_mark_validator"
require "einvoice/validator/neweb/print_mark_validator"

module Einvoice
  module Model
    module Neweb
      class Base
        include ActiveModel::Model
        include ActiveModel::Validations
        include ActiveModel::Serialization
        include ActiveModel::Serializers::JSON

        def attributes=(hash)
          @invoice_item ||= []
          hash.each do |key, value|
            case key.to_sym
            when :invoice_item
              value.each { |v| @invoice_item << InvoiceItem.new(v) }
            when :contact
              @contact = Contact.new(value)
            when :customer_defined
              @customer_defined = CustomerDefined.new(value)
            else
              send("#{key}=", value)
            end
          end
        end

        def attributes
          instance_values
        end
      end
    end
  end
end
