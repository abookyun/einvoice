# frozen_string_literal: true

require "openssl"
require "json"

module Einvoice
  module Tradevan
    module DefaultAPI
      # The DEFAULTAPI cipher, ported from the 1.x client (which ran in
      # production for years): AES-128-CBC with the key reused as the IV, no
      # PKCS padding, the plain text padded with NUL bytes, and strict Base64.
      #
      # A request carries one parameter, +v+. Each API parameter is encrypted
      # with +key1+, the result is wrapped with the plain +acnt+ / +acntp+ in a
      # JSON object, and that object is encrypted with +key2+. A response
      # +Message+ is decrypted with +key1+: the 1.x code did so, and Tradevan's
      # own document (which says +key2+) was wrong on this point.
      module Crypto
        BLOCK = 16

        module_function

        # Encrypt +plaintext+ with +key+ and return strict Base64.
        def encrypt(plaintext, key)
          cipher = new_cipher(key, :encrypt)
          [cipher.update(pad(plaintext.to_s.b)) + cipher.final].pack("m0")
        end

        # Reverse of {encrypt}. Trailing NUL padding is removed.
        def decrypt(base64, key)
          cipher = new_cipher(key, :decrypt)
          plain = cipher.update(base64.to_s.unpack1("m")) + cipher.final
          plain.sub(/\0+\z/, "").force_encoding(Encoding::UTF_8)
        rescue OpenSSL::Cipher::CipherError, ArgumentError => e
          raise ProviderError.new("Could not decrypt the Tradevan response",
                                  provider: Client::PROVIDER, cause: e)
        end

        # Build the +v+ query value for one call. A Hash parameter is sent as
        # JSON; anything else as its string form.
        def encode_params(params, acnt:, acntp:, key1:, key2:)
          encrypted = params.to_h { |name, value| [name.to_s, encrypt(serialize(value), key1)] }
          envelope = { "acnt" => acnt.to_s, "acntp" => acntp.to_s }.merge(encrypted)
          encrypt(JSON.generate(envelope), key2)
        end

        # Read an encrypted response +Message+ back into a Hash or an Array. Some
        # raw endpoints answer an Array. Anything else, such as +null+, is not a
        # message the adapter can read.
        def decrypt_message(message, key1)
          result = JSON.parse(decrypt(message, key1))
          return result if result.is_a?(Hash) || result.is_a?(Array)

          raise ProviderError.new("Tradevan returned a message that is not a JSON object or array",
                                  provider: Client::PROVIDER, raw: result)
        rescue JSON::ParserError => e
          raise ProviderError.new("Tradevan returned a malformed JSON message",
                                  provider: Client::PROVIDER, cause: e)
        end

        # Pad with NUL bytes to a whole block. An empty text becomes one block of
        # NULs; a text that already fills whole blocks gets nothing.
        def pad(bytes)
          remainder = bytes.bytesize % BLOCK
          return bytes if remainder.zero? && !bytes.empty?

          bytes + ("\0" * (BLOCK - remainder))
        end

        def serialize(value)
          value.is_a?(Hash) ? JSON.generate(value) : value.to_s
        end

        def new_cipher(key, direction)
          size = key.to_s.bytesize
          unless size == BLOCK
            raise ValidationError.new("Tradevan keys must be 16 bytes (AES-128-CBC), got #{size}",
                                      provider: Client::PROVIDER)
          end

          cipher = OpenSSL::Cipher.new("aes-128-cbc").public_send(direction)
          cipher.padding = 0
          cipher.key = key
          cipher.iv = key
          cipher
        end
      end
    end
  end
end
