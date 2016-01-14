require "active_support"

require "einvoice/version"
require "einvoice/configuration"
require "einvoice/connection"
require "einvoice/result"
require "einvoice/response"
require "einvoice/client"

require "einvoice/provider/base"
require "einvoice/provider/neweb"

module Einvoice
  extend Configuration
end
