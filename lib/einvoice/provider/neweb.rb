require "einvoice/utils"

require "einvoice/model/neweb/base"
require "einvoice/model/neweb/contact"
require "einvoice/model/neweb/customer_defined"
require "einvoice/model/neweb/invoice_item"
require "einvoice/model/neweb/invoice"

module Einvoice
  module Provider
    class Neweb < Base
      include Einvoice::Utils

      def issue(payload)
        invoice = Einvoice::Model::Neweb::Invoice.new
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
