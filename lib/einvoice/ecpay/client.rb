# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Einvoice
  module ECPay
    # Speaks the ECPay B2C wire protocol: wrap a payload Hash as
    # <tt>{ MerchantID, RqHeader: { Timestamp, Revision }, Data: <encrypted> }</tt>,
    # POST it as JSON, then unwrap and check both result layers, raising the
    # matching {Einvoice::Error} subclass.
    #
    # Callers get the decrypted business payload back and never see the envelope.
    class Client
      PROVIDER = "ecpay"

      # B2C 電子發票 hosts.
      BASE_URL = {
        test: "https://einvoice-stage.ecpay.com.tw",
        production: "https://einvoice.ecpay.com.tw"
      }.freeze

      # Fixed by the B2C spec. The stage API accepts a request without it
      # (verified 2026-08-15), but it is documented as required and the response
      # echoes it back, so it is always sent.
      REVISION = "3.0.0"

      attr_reader :merchant_id, :mode, :base_url, :timeout

      def initialize(merchant_id:, hash_key:, hash_iv:, mode: ProviderMode::TEST,
                     base_url: nil, timeout: 30)
        @merchant_id = merchant_id.to_s
        @hash_key = hash_key.to_s
        @hash_iv = hash_iv.to_s
        @mode = mode
        @base_url = base_url || BASE_URL.fetch(mode) do
          raise ValidationError.new("Unknown ECPay mode: #{mode.inspect}", provider: PROVIDER)
        end
        @timeout = timeout
      end

      # POST +data+ to +path+ and return the decrypted business payload.
      #
      # @param success_codes [Array<Integer>] extra +RtnCode+s to accept besides +1+
      # @param plain_data [Boolean] the endpoint answers with unencrypted +Data+
      def request(path, data, success_codes: [], plain_data: false)
        envelope = post(path, build_body(data))
        check_transport!(envelope)

        result = plain_data ? envelope["Data"] : decrypt_data(envelope["Data"])
        check_business!(result, success_codes)
        result
      end

      private

      def build_body(data)
        {
          "MerchantID" => @merchant_id,
          "RqHeader" => { "Timestamp" => Time.now.to_i, "Revision" => REVISION },
          # MerchantID is required in the encrypted payload as well as the envelope.
          "Data" => Crypto.encrypt_data(
            { "MerchantID" => @merchant_id }.merge(stringify(data)), @hash_key, @hash_iv
          )
        }
      end

      # Omit nils rather than sending JSON nulls: an absent optional field is the
      # shape ECPay's own SDKs produce, and the shape these endpoints were verified
      # against. Top-level only — nested payloads are built without nils.
      def stringify(data)
        data.each_with_object({}) do |(key, value), out|
          out[key.to_s] = value unless value.nil?
        end
      end

      def post(path, body)
        uri = URI("#{@base_url.chomp('/')}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        response = http.request(post_request(uri, body))
        parse_json(response)
      rescue Einvoice::Error
        raise
      rescue StandardError => e
        raise NetworkError.new("ECPay request failed: #{e.message}", provider: PROVIDER, cause: e)
      end

      def post_request(uri, body)
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
        request
      end

      def parse_json(response)
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError => e
        raise ProviderError.new(
          "ECPay returned a non-JSON response (HTTP #{response.code})",
          provider: PROVIDER, raw_code: response.code, cause: e
        )
      end

      # Layer 1 — the envelope. A failure here means the request never reached the
      # business logic (bad credentials, skewed clock, malformed encryption).
      def check_transport!(envelope)
        trans_code = envelope["TransCode"]
        return if trans_code.to_i == 1 && !blank?(envelope["Data"])

        code, reason = Errors.classify_transport(trans_code)
        message = envelope["TransMsg"].to_s
        raise Einvoice::Error.for(
          code, message.empty? ? "ECPay transport error" : message,
          provider: PROVIDER, reason: reason, raw_code: trans_code.to_s,
          raw_message: message, raw: envelope
        )
      end

      # Layer 2 — the business result, only reachable once the envelope was good.
      def check_business!(result, success_codes)
        unless result.is_a?(Hash)
          raise ProviderError.new("ECPay returned an unexpected Data payload", provider: PROVIDER,
                                                                              raw: result)
        end

        rtn_code = result["RtnCode"].to_i
        return if rtn_code == 1 || success_codes.include?(rtn_code)

        message = result["RtnMsg"].to_s
        code, reason = Errors.classify(rtn_code, message)
        raise Einvoice::Error.for(
          code, message.empty? ? "ECPay returned an error" : message,
          provider: PROVIDER, reason: reason, raw_code: rtn_code.to_s,
          raw_message: message, raw: result
        )
      end

      def decrypt_data(data)
        Crypto.decrypt_data(data, @hash_key, @hash_iv)
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
