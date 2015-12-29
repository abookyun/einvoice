module Einvoice
  module Client
    class Neweb < API
      def create_invoice(invoice)
        connection.post do |request|
          request.url "IN_PreInvoiceS.action"
          request.body = {
            StoreCode: client_id,
            hash: client_secret,
            xmldata: invoice.to_xml
          }
        end.body
      end
    end
  end
end
