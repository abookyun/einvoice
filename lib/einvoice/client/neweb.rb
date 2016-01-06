module Einvoice
  module Client
    class Neweb < API
      def initialize
        connection.use Faraday::Request::UrlEncoded
        connection.use Faraday::Request::DigestNeweb :neweb, client_secret
      end

      def upload_invoice(invoice)
        if invoice.valid?
          action = invoice.data_number.present? ? "IN_PreInvoiceS.action" : "IN_SellerInvoiceS.action"
          connection.post do |request|
            request.url action
            request.body = {
              StoreCode: client_id,
              xmldata: wrap(invoice).deep_transform_keys { |k| k.to_s.camelize }
            }
          end.body
        else
          # TODO raise errors
        end
      end

      private

      def wrap(invoice)
        { invoice_root:
          { invoice: invoice.serializable_hash(except: [:errors, :validation_context], include: { invoice_item: {}, contact: {}, customer_defined: {}})}
        }
      end
    end
  end
end
