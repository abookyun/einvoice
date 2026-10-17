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

        attr_reader :endpoint, :timeout

        # @param endpoint [String] the Tradevan host. There is no default: the
        #   1.x client never shipped one, and the hosts are not public.
        def initialize(acnt:, acntp:, key1:, key2:, endpoint:, timeout: 30)
          if endpoint.to_s.empty?
            raise ValidationError.new("Tradevan endpoint is required", provider: PROVIDER)
          end

          @acnt = acnt.to_s
          @acntp = acntp.to_s
          @key1 = key1.to_s
          @key2 = key2.to_s
          @endpoint = endpoint.to_s.chomp("/")
          @timeout = timeout
        end

        # Call +path+ (for example +"post/issue"+ or +"get/searchInvoiceDetail"+)
        # with +params+, and return the decrypted +Message+. A path that starts
        # with +post/+ is sent as POST, everything else as GET.
        def request(path, params)
          v = Crypto.encode_params(params, acnt: @acnt, acntp: @acntp, key1: @key1, key2: @key2)
          read(send_request(path, v))
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
          uri = URI("#{@endpoint}#{PATH_PREFIX}#{path}")
          uri.query = URI.encode_www_form(v: v)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = @timeout
          http.read_timeout = @timeout
          parse_json(http.request(build_request(path, uri)))
        rescue Einvoice::Error
          raise
        rescue StandardError => e
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

        def parse_json(response)
          JSON.parse(response.body.to_s)
        rescue JSON::ParserError => e
          raise ProviderError.new("Tradevan returned a non-JSON response (HTTP #{response.code})",
                                  provider: PROVIDER, raw_code: response.code, cause: e)
        end

        def read(envelope)
          unless envelope.is_a?(Hash)
            raise ProviderError.new("Tradevan returned an unexpected envelope", provider: PROVIDER,
                                                                                raw: envelope)
          end

          case envelope["Success"]
          when "Y" then Crypto.decrypt_message(envelope["Message"], @key1)
          when "N" then raise_failure(envelope)
          when "E" then raise_transport(envelope)
          else
            raise ProviderError.new("Tradevan returned an unknown Success value: " \
                                    "#{envelope['Success'].inspect}", provider: PROVIDER, raw: envelope)
          end
        end

        # +Success: "N"+ carries an encrypted Message, like a success does.
        def raise_failure(envelope)
          result = Crypto.decrypt_message(envelope["Message"], @key1)
          reason = result.is_a?(Hash) ? result["failReason"].to_s : ""
          raise_business(reason, result)
        end

        # +Success: "E"+ carries a plain text Message.
        def raise_transport(envelope)
          message = envelope["Message"].to_s
          code, reason = Errors.classify_transport(message)
          raise Einvoice::Error.for(
            code, message.empty? ? "Tradevan transport error" : message,
            provider: PROVIDER, reason: reason, raw_code: "E", raw_message: message, raw: envelope
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
