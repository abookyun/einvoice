module Einvoice
  module Model
    class CustomerDefined < Einvoice::Model::Base
      attr_accessor :project_no, :purchase_no, :stamp_duty_flag

      validates :project_no, length: { maximum: 64 }
      validates :purchase_no, length: { maximum: 64 }
      validates :stamp_duty_flag, length: { maximum: 1 }
    end
  end
end
