# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "digest"

module Einvoice
  module Amego
    # Speaks Amego's wire protocol: a form POST with +invoice+, +data+ (the
    # JSON payload), +time+ and +sign+, then reads the +code+ / +msg+ envelope
    # and raises the matching {Einvoice::Error} subclass.
    #
    # Amego has no encryption. +sign+ is +md5(data + time + app_key)+ over the
    # JSON string before URL encoding, so it only proves that the caller knows
    # the App Key.
    class Client
      PROVIDER = "amego"
      # One host for test and production. The credentials pick the environment.
      ENDPOINT = "https://invoice-api.amego.tw"

      attr_reader :endpoint, :timeout

      def initialize(ban:, app_key:, endpoint: ENDPOINT, timeout: 30, clock: -> { Time.now })
        if ban.to_s.empty? || app_key.to_s.empty?
          raise ValidationError.new("Amego ban and app_key are required", provider: PROVIDER)
        end

        @ban = ban.to_s
        @app_key = app_key.to_s
        @endpoint = endpoint.to_s.chomp("/")
        @timeout = timeout
        @clock = clock
      end

      # POST +payload+ to +path+ (for example +"/json/f0401"+) and return the
      # parsed response body, with +code+ 0. Any other +code+ raises.
      def request(path, payload)
        data = JSON.generate(payload)
        time = @clock.call.to_i.to_s
        form = { "invoice" => @ban, "data" => data, "time" => time, "sign" => sign(data, time) }
        read(send_request(path, form))
      end

      def sign(data, time)
        Digest::MD5.hexdigest("#{data}#{time}#{@app_key}")
      end

      # Encode every value with +%20+ for a space, not +++. Amego URL decodes
      # the POST data once, and both of PHP's decoders read +%20+ as a space.
      def self.encode_form(form)
        form.map { |key, value| "#{key}=#{URI.encode_uri_component(value)}" }.join("&")
      end

      private

      def send_request(path, form)
        uri = URI("#{@endpoint}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        post = Net::HTTP::Post.new(uri.request_uri)
        post["Content-Type"] = "application/x-www-form-urlencoded"
        post["Accept"] = "application/json"
        post.body = self.class.encode_form(form)
        parse_json(http.request(post))
      rescue Einvoice::Error
        raise
      rescue StandardError => e
        raise NetworkError.new("Amego request failed: #{e.message}", provider: PROVIDER, cause: e)
      end

      def parse_json(response)
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError => e
        raise ProviderError.new("Amego returned a non-JSON response (HTTP #{response.code})",
                                provider: PROVIDER, raw_code: response.code, cause: e)
      end

      def read(body)
        unless body.is_a?(Hash) && body.key?("code")
          raise ProviderError.new("Amego returned an unexpected response", provider: PROVIDER, raw: body)
        end
        return body if body["code"].to_s == "0"

        message = body["msg"].to_s
        code, reason = Errors.classify(body["code"])
        raise Einvoice::Error.for(
          code, message.empty? ? "Amego returned code #{body['code']}" : message,
          provider: PROVIDER, reason: reason, raw_code: body["code"].to_s, raw_message: message, raw: body
        )
      end
    end
  end
end
