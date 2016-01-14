module Einvoice
  module Validator
    module Neweb
      class CustomsClearanceMarkValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          if record.tax_rate.present? && record.tax_rate.to_i.zero? && value.blank?
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end
    end
  end
end
