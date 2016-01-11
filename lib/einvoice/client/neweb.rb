require "gyoku"

module Einvoice
  module Client
    class Neweb < API
      def upload(invoice)
        action = "IN_PreInvoiceS.action"
        connection.post do |request|
          request.url endpoint + action
          request.body = {
            storecode: client_id,
            xmldata: encode_xml(wrap(serialize(invoice)))
          }
        end.body
      end

      private

      def serialize(invoice)
        invoice.serializable_hash(except: [:errors, :validation_context], include: [:invoice_item, :contact, :customer_defined])
      end

      def wrap(hash)
        { invoice_root:
          { invoice: hash }
        }
      end

      def camelize(hash)
        hash.deep_transform_keys { |k| k.to_s.camelize }
      end

      def encode_xml(hash)
        ::Gyoku.xml(hash, key_converter: :none)
      end
    end
  end
end
