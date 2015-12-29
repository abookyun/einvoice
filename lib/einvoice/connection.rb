require "faraday_middleware"

module Einvoice
  module Connection
    private

    def connection
      options = {
        headers: { "Accept" => "application/#{format}; charset=utf-8" },
        url: endpoint
      }

      ::Faraday::Connection.new(options) do |connection|
        case format.to_s.downcase
        when "xml" then connection.use Faraday::Response::ParseXml
        when "json" then connection.use Faraday::Response::ParseJson
        end

        connection.adapter Faraday.default_adapter
      end
    end
  end
end
