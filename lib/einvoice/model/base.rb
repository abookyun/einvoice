require "active_model"

require "einvoice/validator/carrier_id1_validator"
require "einvoice/validator/carrier_id2_validator"
require "einvoice/validator/customs_clearance_mark_validator"
require "einvoice/validator/print_mark_validator"

module Einvoice
  module Model
    class Base
      include ActiveModel::Model
      include ActiveModel::Validations
      include ActiveModel::Serialization
    end
  end
end
