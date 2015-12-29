require 'active_model'

module Einvoice
  module Model
    class Base
      include ActiveModel::Model
      include ActiveModel::Validations
      include ActiveModel::Serialization
    end
  end
end
