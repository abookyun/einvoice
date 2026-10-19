# frozen_string_literal: true

require "openssl"
require "digest"

module Einvoice
  module EzPay
    # The ezPay payload is a PHP +http_build_query+ string, padded with PKCS#7
    # to a multiple of 32 bytes, encrypted with AES-256-CBC, and hex encoded
    # (docs/providers/ezpay/invoice.md, section 2.2).
    #
    # Results carry a +CheckCode+: SHA-256 over five sorted result fields,
    # wrapped in the HashIV and the HashKey (section 2.4).
    module Crypto
      BLOCK = 32
      # PHP +urlencode+ keeps only these bytes. +rawurlencode+ also keeps +~+.
      URLENCODE_KEEP = /[^a-zA-Z0-9\-_.]/n
      RAWURLENCODE_KEEP = /[^a-zA-Z0-9\-_.~]/n
      CHECK_FIELDS = %w[InvoiceTransNo MerchantID MerchantOrderNo RandomNum TotalAmt].freeze

      module_function

      # PHP +http_build_query+ over an ordered Hash: +urlencode+ on keys and
      # values, so a space is +++.
      def build_query(fields)
        fields.map { |key, value| "#{urlencode(key)}=#{urlencode(value)}" }.join("&")
      end

      # PHP +urlencode+.
      def urlencode(value)
        value.to_s.b.gsub(URLENCODE_KEEP) { |byte| byte == " " ? "+" : format("%%%02X", byte.ord) }
      end

      # PHP +rawurlencode+ (RFC 3986): a space is +%20+.
      def rawurlencode(value)
        value.to_s.b.gsub(RAWURLENCODE_KEEP) { |byte| format("%%%02X", byte.ord) }
      end

      # PHP +urldecode+, for reading a payload back (the fake uses it).
      def urldecode(value)
        value.to_s.tr("+", " ").b.gsub(/%([0-9A-Fa-f]{2})/) { ::Regexp.last_match(1).hex.chr }
             .force_encoding(Encoding::UTF_8)
      end

      def parse_query(query)
        query.to_s.split("&").to_h do |pair|
          key, value = pair.split("=", 2)
          [urldecode(key), urldecode(value)]
        end
      end

      # Query string → PostData_. PKCS#7 always adds padding, so a string that
      # is already a multiple of 32 bytes gets a full block of 32.
      def encrypt(plaintext, key, iv)
        bytes = plaintext.to_s.b
        pad = BLOCK - (bytes.bytesize % BLOCK)
        cipher = new_cipher(key, iv, :encrypt)
        (cipher.update(bytes + (pad.chr * pad)) + cipher.final).unpack1("H*")
      end

      def decrypt(hex, key, iv)
        cipher = new_cipher(key, iv, :decrypt)
        bytes = cipher.update([hex.to_s].pack("H*")) + cipher.final
        pad = bytes.empty? ? 0 : bytes.getbyte(-1)
        raise ArgumentError, "bad padding" unless pad.between?(1, BLOCK) && bytes.bytesize >= pad

        bytes[0...-pad].force_encoding(Encoding::UTF_8)
      end

      # The CheckCode of an issue or query result.
      def check_code(result, key, iv)
        joined = CHECK_FIELDS.sort.map { |field| "#{field}=#{result[field]}" }.join("&")
        Digest::SHA256.hexdigest("HashIV=#{iv}&#{joined}&HashKey=#{key}").upcase
      end

      def new_cipher(key, iv, direction)
        cipher = OpenSSL::Cipher.new("aes-256-cbc").public_send(direction)
        cipher.key = key.to_s.b
        cipher.iv = iv.to_s.b
        cipher.padding = 0
        cipher
      end
    end
  end
end
