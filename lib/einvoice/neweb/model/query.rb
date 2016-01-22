module Einvoice
  module Neweb
    module Model
      class Query < Base
        VALID_OPTIONS_KEYS = [
          :invoice_date_time_s,
          :invoice_date_time_e,
          :data_number_s,
          :data_number_e,
          :sync_status_update
        ].freeze

        attr_accessor *VALID_OPTIONS_KEYS

        validates :invoice_date_time_s, presence: true, length: { maximum: 14 }, format: { with: /\A\d{4}\d{2}\d{2}\d{2}\d{2}\Z/ }
        validates :invoice_date_time_e, presence: true, length: { maximum: 14 }, format: { with: /\A\d{4}\d{2}\d{2}\d{2}\d{2}\Z/ }
        validates :data_number_s, presence: true, length: { maximum: 20 }
        validates :data_number_e, presence: true, length: { maximum: 20 }
        validates :sync_status_update, presence: true, length: { maximum: 1 }

        def initialize
          # overwritten
        end

        def attributes=(hash)
          hash.each do |key, value|
            send("#{key}=", value)
          end
        end

        def payload
          serializable_hash(except: [:errors, :validation_context])
        end

        def wrapped_payload
          { invoice_map_root:
            { invoice_map: payload }
          }
        end
      end
    end
  end
end
