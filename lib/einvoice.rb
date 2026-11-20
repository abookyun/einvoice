# frozen_string_literal: true

require "einvoice/version"
require "einvoice/error"
require "einvoice/redaction"
require "einvoice/taipei"
require "einvoice/number"
require "einvoice/tax_split"
require "einvoice/capability"
require "einvoice/types"
require "einvoice/input"
require "einvoice/provider"
require "einvoice/mock_provider"

# Provider-agnostic Taiwan e-invoice SDK (財政部 MIG 4.1).
#
# The core models the five operations once: issue (開立), void (作廢),
# allowance (折讓), void-allowance (折讓作廢) and query (查詢). It has a unified
# value model and an {Einvoice::Provider} contract. Each value-added center is a
# thin adapter that maps the unified model to its wire format and back.
#
# This file loads the core only. The adapters and the MOF clients load on
# demand, so an app loads only what it uses: require "einvoice/ecpay",
# "einvoice/amego", "einvoice/ezpay", "einvoice/tradevan" or "einvoice/mof".
module Einvoice
end
