# frozen_string_literal: true

require "einvoice"
require "einvoice/amego/errors"
require "einvoice/amego/client"
require "einvoice/amego/payload"
require "einvoice/amego/provider"

module Einvoice
  # Adapter for Amego 光貿科技's JSON e-invoice API.
  #
  # The wire format is a form POST with a JSON +data+ field and an MD5 +sign+.
  # There is no encryption. None of that reaches application code: {Provider}
  # exposes only the unified model.
  #
  #   provider = Einvoice::Amego::Provider.new(**Einvoice::Amego::SANDBOX)
  #   provider.issue(order_id: "ORDER_1", ...)   # => Einvoice::IssueInvoiceResult
  module Amego
    # Amego's published shared **test** account. Every developer uses it, so
    # never use it for anything real. Amego has one host for test and
    # production: these credentials are what make a call a test.
    SANDBOX = {
      ban: "12345678",
      app_key: "sHeq7t8G1wiQvhAuIM27"
    }.freeze
  end
end
