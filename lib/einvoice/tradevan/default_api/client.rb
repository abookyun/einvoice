# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Einvoice
  module Tradevan
    module DefaultAPI
      # Speaks the DEFAULTAPI wire protocol: encrypt the parameters into +v+,
      # send it in the query string (also for the POST endpoints, as the 1.x
      # client did), then read the +Success+ / +Message+ envelope and raise the
      # matching {Einvoice::Error} subclass.
      #
      # Callers get the decrypted +Message+ back and never see the envelope.
      class Client
        PROVIDER = "tradevan"
        PATH_PREFIX = "/DEFAULTAPI/"
        # The envelope's +Success+ values. A body with another value was not
        # written by DEFAULTAPI, so the HTTP status decides.
        SUCCESS_VALUES = %w[Y N E].freeze

        attr_reader :base_url, :timeout

        # @param base_url [String] the Tradevan host. There is no default: the
        #   1.x client never shipped one, and the hosts are not public.
        def initialize(acnt:, acntp:, key1:, key2:, base_url:, timeout: 30)
          if base_url.to_s.empty?
            raise ValidationError.new("Tradevan base_url is required", provider: PROVIDER)
          end

          @acnt = acnt.to_s
          @acntp = acntp.to_s
          @key1 = key1.to_s
          @key2 = key2.to_s
          # Frozen: the checks above must hold for every request after this.
          @base_url = Redaction.base_url!(base_url, provider: PROVIDER)
          @timeout = timeout
        end

        def inspect
          "#<#{self.class.name} base_url=#{@base_url.inspect} acnt=#{@acnt.inspect} " \
            "acntp=#{Redaction::FILTERED} key1=#{Redaction::FILTERED} key2=#{Redaction::FILTERED}>"
        end
        alias to_s inspect

        # Call +path+ (for example +"post/issue"+ or +"get/searchInvoiceDetail"+)
        # with +params+, and return the decrypted +Message+. A path that starts
        # with +post/+ is sent as POST, everything else as GET.
        def request(path, params)
          v = Crypto.encode_params(params, acnt: @acnt, acntp: @acntp, key1: @key1, key2: @key2)
          read(*send_request(path, v))
        end

        # Raise unless the inner status field (+issueStatus+, +voidStatus+) is
        # +"Y"+. +Success: "Y"+ alone only means the envelope was read.
        def check_status!(result, field)
          return if result.is_a?(Hash) && result[field] == "Y"

          reason = result.is_a?(Hash) ? result["failReason"].to_s : ""
          raise_business(reason, result)
        end

        private

        def send_request(path, v)
          uri = URI("#{@base_url}#{PATH_PREFIX}#{path}")
          uri.query = URI.encode_www_form(v: v)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = @timeout
          http.read_timeout = @timeout
          response = http.request(build_request(path, uri))
          [parse(response), response]
        rescue *Error::NETWORK_ERRORS => e
          raise NetworkError.new("Tradevan request failed: #{e.message}", provider: PROVIDER, cause: e)
        end

        def build_request(path, uri)
          request = if path.start_with?("post/")
                      Net::HTTP::Post.new(uri.request_uri).tap do |post|
                        post["Content-Type"] = "application/x-www-form-urlencoded"
                        post.body = ""
                      end
                    else
                      Net::HTTP::Get.new(uri.request_uri)
                    end
          request["Accept"] = "application/json; charset=utf-8"
          request
        end

        # A body that Tradevan wrote (a JSON object with +Success+) decides the
        # error, whatever the HTTP status. Any other body falls back to the
        # status: HTTP 429 and 5xx are a NetworkError, so the caller can retry
        # (docs/providers/README.md, "The unified model").
        def parse(response)
          body = JSON.parse(response.body.to_s)
          return body if body.is_a?(Hash) && SUCCESS_VALUES.include?(body["Success"])

          raise_for_status!(response)
          body
        rescue JSON::ParserError => e
          raise_for_status!(response)
          raise ProviderError.new("Tradevan returned a non-JSON response (HTTP #{response.code})",
                                  provider: PROVIDER, raw_code: response.code, cause: e)
        end

        def raise_for_status!(response)
          error = NetworkError.for_status(response, provider: PROVIDER)
          raise error if error
        end

        def read(envelope, response)
          unless envelope.is_a?(Hash)
            raise ProviderError.new("Tradevan returned an unexpected envelope", provider: PROVIDER,
                                                                                raw: envelope)
          end

          case envelope["Success"]
          when "Y" then message(envelope, response)
          when "N" then raise_failure(envelope, response)
          when "E" then raise_transport(envelope, response)
          else
            raise ProviderError.new("Tradevan returned an unknown Success value: " \
                                    "#{envelope['Success'].inspect}", provider: PROVIDER, raw: envelope)
          end
        end

        # +Success: "N"+ carries an encrypted Message, like a success does.
        # The decrypted +Message+. When it cannot be read, the envelope tells
        # nothing, so HTTP 429 and 5xx decide, as for any other body.
        def message(envelope, response)
          Crypto.decrypt_message(envelope["Message"], @key1)
        rescue ProviderError
          raise_for_status!(response)
          raise
        end

        def raise_failure(envelope, response)
          result = message(envelope, response)
          reason = result.is_a?(Hash) ? result["failReason"].to_s : ""
          raise_business(reason, result)
        end

        # +Success: "E"+ carries a plain text Message. Without readable text,
        # the envelope tells nothing, so HTTP 429 and 5xx decide. Otherwise it
        # is a plain ProviderError: an object such as {"password" => nil} must
        # not reach the patterns, which would read it as a credential error.
        def raise_transport(envelope, response)
          message = envelope["Message"]
          unless message.is_a?(String) && !message.strip.empty?
            raise_for_status!(response)
            raise ProviderError.new("Tradevan returned an error without a readable message",
                                    provider: PROVIDER, raw_code: "E", raw: envelope)
          end

          code, reason = Errors.classify_transport(message)
          raise Einvoice::Error.for(
            code, message, provider: PROVIDER, reason: reason, raw_code: "E", raw_message: message, raw: envelope
          )
        end

        def raise_business(message, raw)
          code, reason = Errors.classify(message)
          raise Einvoice::Error.for(
            code, message.empty? ? "Tradevan returned an error" : message,
            provider: PROVIDER, reason: reason, raw_code: "N", raw_message: message, raw: raw
          )
        end
      end
    end
  end
end
