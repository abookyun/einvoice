require "faraday_middleware"
require "faraday/request/digest_neweb"
require "faraday/response/decode_tradevan"

module Einvoice
  module Connection
    private

    def connection(options = {})
      connection_options = {
        headers: { "Accept" => "application/#{format}; charset=utf-8" },
        url: endpoint
      }.merge(options)

      ::Faraday::Connection.new(connection_options) do |connection|
        case self.class.to_s
        when "Einvoice::Neweb::Provider"
          connection.request :digest_neweb, client_secret
        when "Einvoice::Tradevan::Provider"
          connection.response :decode_tradevan, encryption_keys[:key1]
        else
          # none
        end
        connection.request :url_encoded

        case format.to_s.downcase
        when "xml" then connection.response :xml
        when "json" then connection.response :json
        end

        connection.adapter Faraday.default_adapter
      end
    end
  end
end
