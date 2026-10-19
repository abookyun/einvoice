# frozen_string_literal: true

require "einvoice/ezpay/crypto"
require "einvoice/ezpay/errors"
require "einvoice/ezpay/client"

module Einvoice
  # Adapter for ezPay 簡單行動支付's e-invoice API.
  #
  # The wire format is a form POST whose +PostData_+ is a PHP query string,
  # encrypted with AES-256-CBC and hex encoded.
  module EzPay
  end
end
