require "active_model"

require "einvoice/neweb/validator/carrier_id1_validator"
require "einvoice/neweb/validator/carrier_id2_validator"
require "einvoice/neweb/validator/customs_clearance_mark_validator"
require "einvoice/neweb/validator/print_mark_validator"

module Einvoice
  module Neweb
    module Model
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
