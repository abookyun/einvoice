require "active_model"

require "einvoice/tradevan/validator/issue_data_validator"

module Einvoice
  module Tradevan
    module Model
      class Base
        include ActiveModel::Model
        include ActiveModel::Validations
        include ActiveModel::Serialization
        include ActiveModel::Serializers::JSON

        include Einvoice::Tradevan::Validator

        def attributes=(hash)
          @itemList ||= []
          hash.each do |key, value|
            case key.to_sym
            when :itemList
              value.each { |v| @itemList << IssueItem.new(v) }
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
