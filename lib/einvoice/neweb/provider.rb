require "einvoice/utils"

require "einvoice/neweb/model/base"
require "einvoice/neweb/model/contact"
require "einvoice/neweb/model/customer_defined"
require "einvoice/neweb/model/invoice_item"
require "einvoice/neweb/model/invoice"
require "einvoice/neweb/model/pre_invoice"
require "einvoice/neweb/model/seller_invoice"

require "einvoice/neweb/result"

module Einvoice
  module Neweb
    class Provider < Einvoice::Provider
      include Einvoice::Utils

      def issue(payload, options)
        case options[:type]
        when :seller_invoice
          action = "IN_SellerInvoiceS.action"
          invoice = Einvoice::Neweb::Model::SellerInvoice.new
        else
          action = "IN_PreInvoiceS.action"
          invoice = Einvoice::Neweb::Model::PreInvoice.new
        end

        invoice.from_json(payload.to_json)

        if invoice.valid?
          response = connection.post do |request|
            request.url endpoint_url || endpoint + action
            request.body = {
              storecode: client_id,
              xmldata: encode_xml(camelize(invoice.wrapped_payload))
            }
          end.body

          Einvoice::Neweb::Result.new(response)
        else
          Einvoice::Neweb::Result.new(invoice.errors)
        end
      end
    end
  end
end
