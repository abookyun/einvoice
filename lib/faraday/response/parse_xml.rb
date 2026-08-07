require 'faraday'
require 'multi_xml'

module Faraday
  class Response::ParseXml < Faraday::Middleware
    def on_complete(env)
      return unless env[:body].is_a?(String) && !env[:body].strip.empty?

      env[:body] = ::MultiXml.parse(env[:body])
    end
  end
end

Faraday::Response.register_middleware xml: Faraday::Response::ParseXml
