module Einvoice
  module Neweb
    module Validator
      class BuyerNameValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          if record.buyer_id.to_s == "0000000000" &&
             record.buyer_name.present? && (record.buyer_name.ascii_only? ? record.buyer_name.size > 4 : record.buyer_name.size > 2)
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class CarrierId1Validator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          if (record.print_mark.to_s == "Y" && value.present?) || (record.print_mark.to_s == "N" && value.blank?)
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class CarrierId2Validator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          if (record.print_mark.to_s == "Y" && value.present?) || (record.print_mark.to_s == "N" && value.blank?)
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class PrintMarkValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          if value == "Y" && (record.carrier_id1.present? || record.carrier_id2.present? || record.donate_mark == "Y")
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

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
