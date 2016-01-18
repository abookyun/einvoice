module Einvoice
  module Neweb
    module Validator
      class BuyerNameValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          if record.buyer_id.to_s == "0000000000" &&
             value.present? && (value.ascii_only? ? value.size > 4 : value.size > 2)
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class DonateMarkValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          if record.n_p_o_b_a_n.present? && value.to_i != 1
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
    end
  end
end
