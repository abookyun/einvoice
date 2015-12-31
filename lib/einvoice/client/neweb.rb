module Einvoice
  module Client
    class Neweb < API
      def initialize
        connection.use Faraday::Request::UrlEncoded
        connection.use Faraday::Request::DigestNeweb :neweb, client_secret
      end

      def create_invoice(invoice)
        connection.post do |request|
          request.url "IN_PreInvoiceS.action"
          request.body = {
            StoreCode: client_id,
            xmldata: invoice.to_json
          }
        end.body
      end
    end
  end
end
