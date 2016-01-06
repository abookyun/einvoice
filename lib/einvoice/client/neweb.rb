require "gyoku"

module Einvoice
  module Client
    class Neweb < API
      def upload_invoice(invoice)
        if invoice.valid?
          action = invoice.data_number.present? ? "IN_PreInvoiceS.action" : "IN_SellerInvoiceS.action"
          connection.post do |request|
            request.url endpoint + action
            request.body = {
              StoreCode: client_id,
              xmldata: encode_xml(wrap(invoice))
            }
          end.body
        else
          # TODO raise errors
        end
      end

      private

      def encode_xml(data)
        ::Gyoku.xml(data, key_converter: :none)
      end

      def wrap(invoice)
        { invoice_root:
          { invoice: invoice.serializable_hash(except: [:errors, :validation_context], include: { invoice_item: {}, contact: {}, customer_defined: {}})}
        }.deep_transform_keys { |k| k.to_s.camelize }
      end
    end
  end
end
