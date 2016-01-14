module Einvoice
  module Validator
    module Neweb
      class PrintMarkValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          if value == "Y" && (record.carrier_id1.present? || record.carrier_id2.present? || record.donate_mark == "Y")
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end
    end
  end
end
