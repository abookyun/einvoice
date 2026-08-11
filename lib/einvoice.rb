# frozen_string_literal: true

require "einvoice/version"
require "einvoice/error"
require "einvoice/capability"
require "einvoice/types"
require "einvoice/input"

# Provider-agnostic Taiwan e-invoice SDK (財政部 MIG 4.0).
#
# The core models the five operations once — issue (開立), void (作廢),
# allowance (折讓), void-allowance (折讓作廢), query (查詢) — as a unified value
# model plus a {Einvoice::Provider} contract. Each value-added center ships as a
# thin adapter mapping the unified model to/from its wire format, so switching
# providers is a one-line constructor change and never touches business code.
module Einvoice
end
