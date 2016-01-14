require "einvoice/utils"

require "einvoice/neweb/model/base"
require "einvoice/neweb/model/contact"
require "einvoice/neweb/model/customer_defined"
require "einvoice/neweb/model/invoice_item"
require "einvoice/neweb/model/invoice"

module Einvoice
  module Neweb
    class Provider < Einvoice::Provider
      include Einvoice::Utils

      def issue(payload)
        invoice = Einvoice::Neweb::Model::Invoice.new
        invoice.from_json(payload.to_json)

        if invoice.valid?
          action = "IN_PreInvoiceS.action"
          response = connection.post do |request|
            request.url endpoint + action
            request.body = {
              storecode: client_id,
              xmldata: encode_xml(wrap(serialize(invoice)))
            }
          end.body

          Einvoice::Result.new(Einvoice::NewebResponse.new(response))
        else
          Einvoice::Result.new(Einvoice::NewebResponse.new(response))
        end
      end
    end
  end
end
