module Einvoice
  module Model
    module Neweb
      class CustomerDefined < Einvoice::Model::Base
        attr_accessor :project_no, :purchase_no, :stamp_duty_flag

        def initialize(attributes={})
          attributes.each do |attribute, value|
            instance_variable_set("@#{attribute}", value) if respond_to?(attribute.to_sym)
          end
        end
      end
    end
  end
end
