# frozen_string_literal: true

require "einvoice"
require "einvoice/ezpay/crypto"
require "einvoice/ezpay/errors"
require "einvoice/ezpay/client"
require "einvoice/ezpay/payload"
require "einvoice/ezpay/provider"

module Einvoice
  # Adapter for ezPay 簡單行動支付's e-invoice API. Experimental: see
  # {Provider}.
  #
  # The wire format is a form POST whose +PostData_+ is a PHP query string,
  # encrypted with AES-256-CBC and hex encoded. None of that reaches
  # application code: {Provider} exposes only the unified model.
  module EzPay
  end
end
