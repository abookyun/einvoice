module Einvoice
  module Tradevan
    module Validator
      class SaleIdentifierValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          unless record.saleIdentifier =~ Regexp.new("\\A#{record.companyUn}_#{record.orgId}_")
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class TotalValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          unless value != record.itemList.map(&:itemTotal).map(&:to_i).inject(&:+)
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class AllowanceNumberValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          unless record.allowanceNumber =~ Regexp.new("\A#{record.orgId}")
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class InvoicePaperReturnedValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          if value.blank? && record.buyerUn.blank? && record.paperPrintMode != '0'
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class DonationUnitValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          donation_unit_list_file = [File.expand_path('../../../', __FILE__), "/donation_unit_list.json"].join
          units = JSON.parse(File.read(donation_unit_list_file))

          unless units[value]
            record.errors.add attribute, options[:message] || :invalid
          end
        end
      end

      class ItemListValidator < ActiveModel::EachValidator
        def validate_each(record, attribtue, value)
          if %w(A G H).include?(record.type) && record.itemList.map(&:itemExclude).map(&:blank?).reduce(&:|)
            record.errors[:itemList] << options[:message] || :invalid
          else
            # none
          end

          if %w(I R).include?(record.type) && record.itemList.map(&:itemTotal).map(&:blank?).reduce(&:|)
            record.errors[:itemList] << options[:message] || :invalid
          else
            # none
          end

          if record.type == 'I' && record.itemList.map(&:taxType).map(&:blank?).reduce(&:|)
            record.errors[:itemList] << options[:message] || :invalid
          else
            # none
          end

          if record.type == 'H'
            if record.itemList.map(&:invoiceNumber).map(&:blank?).reduce(&:|)
              record.errors[:itemList] << options[:message] || :invalid
            elsif record.itemList.map(&:invoiceDate).map(&:blank?).reduce(&:|)
              record.errors[:itemList] << options[:message] || :invalid
            elsif record.itemList.map(&:invoiceTime).map(&:blank?).reduce(&:|)
              record.errors[:itemList] << options[:message] || :invalid
            else
              # none
            end
          end
        end
      end
    end
  end
end
