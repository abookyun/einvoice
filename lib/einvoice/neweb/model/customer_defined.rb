module Einvoice
  module Neweb
    module Model
      class CustomerDefined < Base
        VALID_OPTIONS_KEYS = [
          :project_no,
          :purchase_no,
          :stamp_duty_flag
        ].freeze

        attr_accessor *VALID_OPTIONS_KEYS

        validates :project_no, length: { maximum: 64 }
        validates :purchase_no, length: { maximum: 64 }
        validates :stamp_duty_flag, length: { maximum: 1 }
      end
    end
  end
end
