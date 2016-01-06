require "faraday_middleware"
require "faraday/request/digest_neweb"

module Einvoice
  module Connection
    private

    def connection
      options = {
        headers: { "Accept" => "application/#{format}; charset=utf-8" },
        url: endpoint
      }

      ::Faraday::Connection.new(options) do |connection|
        connection.request :digest, client_secret
        connection.request :url_encoded

        # Parser
        case format.to_s.downcase
        when "xml" then connection.response :xml
        when "json" then connection.response :json
        end

        connection.adapter Faraday.default_adapter
      end
    end
  end
end
