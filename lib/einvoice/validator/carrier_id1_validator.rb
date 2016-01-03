class CarrierId1Validator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    if (record.print_mark.to_s == "Y" && value.present?) || (record.print_mark.to_s == "N" && value.blank?)
      record.errors.add attribute, options[:message] || :invalid
    end
  end
end
