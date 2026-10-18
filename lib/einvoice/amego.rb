# frozen_string_literal: true

require "einvoice/amego/errors"
require "einvoice/amego/client"

module Einvoice
  # Adapter for Amego 光貿科技's JSON e-invoice API.
  #
  # The wire format is a form POST with a JSON +data+ field and an MD5 +sign+.
  # There is no encryption.
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
