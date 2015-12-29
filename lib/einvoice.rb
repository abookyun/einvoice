require "einvoice/version"
require "einvoice/configuration"
require "einvoice/connection"
require "einvoice/api"
require "einvoice/model/base"

require "einvoice/client/neweb"
require "einvoice/model/neweb/invoice"
require "einvoice/model/neweb/invoice_item"
require "einvoice/model/neweb/contact"
require "einvoice/model/neweb/customer_defined"

module Einvoice
  extend Configuration
end
