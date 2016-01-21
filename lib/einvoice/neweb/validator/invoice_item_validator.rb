module Einvoice
  module Neweb
    module Validator
      class QuantityValidator < ActiveModel::EachValidator
        include Einvoice::Neweb::Validator

        def validate_each(record, attribute, value)
          unless valid_float?(value)
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class UnitPriceValidator < ActiveModel::EachValidator
        include Einvoice::Neweb::Validator

        def validate_each(record, attribute, value)
          unless valid_float?(value)
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class AmountValidator < ActiveModel::EachValidator
        include Einvoice::Neweb::Validator

        def validate_each(record, attribute, value)
          unless valid_float?(value)
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      def valid_float?(value)
        integer, digit = value.to_s.split(".")[0..1]
        float_value = value.to_f.to_s

        return false if integer.nil? || digit.nil? || integer.delete("-").size > 12 || digit.try(:size) > 4
        return false if integer != float_value.split(".")[0] || digit != float_value.split(".")[1]
      end
    end
  end
end
