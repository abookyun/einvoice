require 'faraday'

module Faraday
  class Request::DigestNeweb < Faraday::Middleware
    dependency do
      require 'digest' unless defined?(::Digest)
    end

    def initialize(app, secret)
      super(app)
      @secret = secret
    end

    def call(env)
      xmldata = env[:body][:xmldata]
      env[:body][:hash] = Digest::MD5.hexdigest(xmldata + @secret)
      @app.call env
    end
  end
end

Faraday::Request.register_middleware digest_neweb: Faraday::Request::DigestNeweb
