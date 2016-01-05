module Einvoice
  module Client
    class Neweb < API
      def initialize
        connection.use Faraday::Request::UrlEncoded
        connection.use Faraday::Request::DigestNeweb :neweb, client_secret
      end

      def create_invoice(invoice)
        if invoice.valid?
          connection.post do |request|
            request.url "IN_PreInvoiceS.action"
            request.body = {
              StoreCode: client_id,
              xmldata: { "InvoiceRoot" =>
                { "Invoice" =>
                  invoice.serializable_hash(include: { invoice_item: {}, contact: {}, customer_defined: {}})
                }
              }
            }
          end.body
        else
          # TODO raise errors
        end
      end
    end
  end
end
