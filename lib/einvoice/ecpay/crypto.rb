# frozen_string_literal: true

require "openssl"
require "json"

module Einvoice
  module ECPay
    # The ECPay B2C envelope's +Data+ field is
    # <tt>JSON → PHP urlencode → AES-128-CBC (PKCS7) → Base64</tt>, and the reverse
    # on the way back.
    #
    # The PHP url(en|de)code semantics are the part that trips implementations up:
    # a space is +++ (not +%20+) and +!*'()~+ are percent-encoded, neither of which
    # Ruby's own helpers do (+CGI.escape+ leaves +~+ alone). Encoding is done over
    # bytes so UTF-8 payloads survive.
    #
    # Verified byte-for-byte against ECPay's published cross-language AES vectors
    # (2026-08-15) — see the crypto spec.
    module Crypto
      # PHP +urlencode+ keeps only these unreserved bytes; everything else is %XX.
      UNRESERVED = /[^a-zA-Z0-9\-_.]/n

      module_function

      # PHP +urlencode+: space → +++, every other non-unreserved byte → +%XX+.
      def php_url_encode(value)
        value.to_s.b.gsub(UNRESERVED) { |byte| byte == " " ? "+" : format("%%%02X", byte.ord) }
      end

      # PHP +urldecode+: +++ → space, then percent-decode back to UTF-8.
      def php_url_decode(value)
        value.to_s.tr("+", " ")
             .gsub(/%([0-9A-Fa-f]{2})/) { ::Regexp.last_match(1).hex.chr }
             .force_encoding(Encoding::UTF_8)
      end

      # AES-128-CBC + PKCS7, Base64-encoded. +key+/+iv+ are the 16-byte HashKey/HashIV.
      def encrypt(plaintext, key, iv)
        cipher = new_cipher(key, iv, :encrypt)
        [cipher.update(plaintext.to_s) + cipher.final].pack("m0")
      end

      # Reverse of {encrypt}. Raises {Einvoice::ProviderError} on a corrupt payload.
      def decrypt(base64, key, iv)
        cipher = new_cipher(key, iv, :decrypt)
        (cipher.update(base64.to_s.unpack1("m")) + cipher.final).force_encoding(Encoding::UTF_8)
      rescue OpenSSL::Cipher::CipherError, ArgumentError => e
        raise ProviderError.new("Could not decrypt the ECPay response payload",
                                provider: "ecpay", cause: e)
      end

      # Build a request +Data+ value from a payload Hash.
      def encrypt_data(data, key, iv)
        encrypt(php_url_encode(JSON.generate(data)), key, iv)
      end

      # Read a response +Data+ value back into a Hash.
      def decrypt_data(base64, key, iv)
        JSON.parse(php_url_decode(decrypt(base64, key, iv)))
      rescue JSON::ParserError => e
        raise ProviderError.new("ECPay returned a malformed JSON payload",
                                provider: "ecpay", cause: e)
      end

      # AES-128 needs exactly 16 bytes of key and IV; a merchant pasting the wrong
      # credential is the common cause, so say which one is wrong up front.
      def new_cipher(key, iv, direction)
        assert_length!(key, "hash_key")
        assert_length!(iv, "hash_iv")
        cipher = OpenSSL::Cipher.new("aes-128-cbc").public_send(direction)
        cipher.key = key
        cipher.iv = iv
        cipher
      end

      def assert_length!(value, field)
        size = value.to_s.bytesize
        return if size == 16

        raise ValidationError.new("ECPay #{field} must be 16 bytes (AES-128-CBC), got #{size}",
                                  provider: "ecpay")
      end
    end
  end
end
