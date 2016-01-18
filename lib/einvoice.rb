require "active_support"

require "einvoice/client"
require "einvoice/configuration"
require "einvoice/connection"
require "einvoice/provider"
require "einvoice/result"
require "einvoice/utils"
require "einvoice/version"

require "einvoice/neweb/provider"

module Einvoice
  extend Configuration
end
