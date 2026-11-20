# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Einvoice
  module EzPay
    # Speaks ezPay's wire protocol: a form POST of +MerchantID_+ and the
    # encrypted +PostData_+, then the +Status+ / +Message+ / +Result+ answer.
    # +Result+ is itself a JSON string, so it is parsed a second time.
    class Client
      PROVIDER = "ezpay"
      BASE_URL = {
        ProviderMode::TEST => "https://cinv.ezpay.com.tw",
        ProviderMode::PRODUCTION => "https://inv.ezpay.com.tw"
      }.freeze
      SUCCESS = "SUCCESS"

      attr_reader :merchant_id, :mode, :base_url, :timeout

      def initialize(merchant_id:, hash_key:, hash_iv:, mode: ProviderMode::TEST, base_url: nil, timeout: 30,
                     clock: -> { Time.now })
        if [merchant_id, hash_key, hash_iv].any? { |value| value.to_s.empty? }
          raise ValidationError.new("ezPay merchant_id, hash_key and hash_iv are required", provider: PROVIDER)
        end

        @merchant_id = merchant_id.to_s
        @hash_key = hash_key.to_s
        @hash_iv = hash_iv.to_s
        @mode = mode
        @base_url = Redaction.base_url!(base_url || BASE_URL.fetch(mode) do
          raise ValidationError.new("Unknown ezPay mode: #{mode.inspect}", provider: PROVIDER)
        end, provider: PROVIDER)
        @timeout = timeout
        @clock = clock
      end

      def inspect
        "#<#{self.class.name} merchant_id=#{@merchant_id.inspect} mode=#{@mode.inspect} " \
          "base_url=#{@base_url.inspect} hash_key=#{Redaction::FILTERED} hash_iv=#{Redaction::FILTERED}>"
      end
      alias to_s inspect

      # POST +fields+ to +path+ (for example +"/Api/invoice_issue"+) under the
      # API +version+, and return the parsed +Result+ Hash. A +Status+ other
      # than +SUCCESS+ raises; +operation+ picks the guesses in {Errors::CONTEXT}.
      def request(path, version, fields, operation: nil)
        payload = { "RespondType" => "JSON", "Version" => version, "TimeStamp" => @clock.call.to_i.to_s }
                  .merge(fields.transform_keys(&:to_s))
        post_data = Crypto.encrypt(Crypto.build_query(payload), @hash_key, @hash_iv)
        read(send_request(path, { "MerchantID_" => @merchant_id, "PostData_" => post_data }), operation)
      end

      # Raise {ProviderError} unless +result+ carries the CheckCode that the
      # HashKey and HashIV give for it.
      def verify_check_code!(result)
        return if result["CheckCode"].to_s == Crypto.check_code(result, @hash_key, @hash_iv)

        raise ProviderError.new("ezPay CheckCode does not match the result", provider: PROVIDER, raw: result)
      end

      private

      def send_request(path, form)
        uri = URI("#{@base_url}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        post = Net::HTTP::Post.new(uri.request_uri)
        post.set_form_data(form)
        response = nil
        http.request(post) { |res| (response = res).read_body }
        parse(response)
      rescue *Error::NETWORK_ERRORS => e
        raise NetworkError.for_failure(e, provider: PROVIDER, name: "ezPay", response: response)
      end

      # A body that ezPay wrote (a JSON object with +Status+) decides the
      # error, whatever the HTTP status. Any other body falls back to the
      # status: HTTP 429 and 5xx are a NetworkError, so the caller can retry
      # (docs/providers/README.md, "The unified model").
      def parse(response)
        body = JSON.parse(response.body.to_s)
        return body if body.is_a?(Hash) && body.key?("Status")

        raise_for_status!(response)
        body
      rescue JSON::ParserError => e
        raise_for_status!(response)
        raise ProviderError.new("ezPay returned a non-JSON response (HTTP #{response.code})",
                                provider: PROVIDER, raw_code: response.code, cause: e)
      end

      def raise_for_status!(response)
        error = NetworkError.for_status(response, provider: PROVIDER)
        raise error if error
      end

      def read(body, operation)
        unless body.is_a?(Hash) && body.key?("Status")
          raise ProviderError.new("ezPay returned an unexpected response", provider: PROVIDER, raw: body)
        end

        status = body["Status"].to_s
        return parse_result(body) if status == SUCCESS

        message = body["Message"].to_s
        code, reason = Errors.classify(status, operation)
        raise Einvoice::Error.for(code, message.empty? ? "ezPay returned #{status}" : message,
                                  provider: PROVIDER, reason: reason, raw_code: status,
                                  raw_message: message, raw: body)
      end

      # +Result+ is a JSON string. It may also be empty, or already a Hash.
      def parse_result(body)
        result = body["Result"]
        result = JSON.parse(result) if result.is_a?(String) && !result.strip.empty?
        return result if result.is_a?(Hash)
        return {} if result.nil? || result == ""

        raise ProviderError.new("ezPay returned an unexpected Result", provider: PROVIDER, raw: body)
      rescue JSON::ParserError => e
        raise ProviderError.new("ezPay returned a Result that is not JSON", provider: PROVIDER, raw: body, cause: e)
      end
    end
  end
end
