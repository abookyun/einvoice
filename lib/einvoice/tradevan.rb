# frozen_string_literal: true

require "einvoice/tradevan/default_api/crypto"
require "einvoice/tradevan/default_api/errors"
require "einvoice/tradevan/default_api/client"
require "einvoice/tradevan/default_api/rules"
require "einvoice/tradevan/default_api/payload"
require "einvoice/tradevan/default_api/provider"

module Einvoice
  # Adapters for Tradevan 關貿網路. Each Tradevan API version has its own
  # namespace, so a newer one can sit next to the old one:
  #
  #   provider = Einvoice::Tradevan::DefaultAPI::Provider.new(...)
  #
  # There is deliberately no shorter alias. An alias that later points to a newer
  # API would move users to it without them noticing.
  module Tradevan
    # Tradevan's DEFAULTAPI (paths under +/DEFAULTAPI/+), the API the 1.x client
    # wraps. Experimental: see {Provider}.
    module DefaultAPI
    end
  end
end
