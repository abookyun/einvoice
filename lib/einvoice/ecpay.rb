# frozen_string_literal: true

require "einvoice/ecpay/crypto"

module Einvoice
  # Adapter for ECPay 綠界科技's B2C 電子發票 2.0 API.
  #
  # The wire format is a JSON envelope whose +Data+ field is AES-128-CBC
  # encrypted with the merchant's HashKey/HashIV.
  module ECPay
    # ECPay's published shared **sandbox** credentials for the B2C e-invoice API.
    # They let you try the adapter against the stage host with no account of your
    # own — and are shared with every other developer doing the same, so never use
    # them for anything real.
    SANDBOX = {
      merchant_id: "2000132",
      hash_key: "ejCk326UnaZWKisg",
      hash_iv: "q9jcZX8Ib9LM8wYk"
    }.freeze
  end
end
