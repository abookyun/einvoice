require 'faraday'

module FaradayMiddleware
  class DigestNeweb < Faraday::Middleware
    dependency do
      require 'digest' unless defined?(::Digest)
    end

    def initialize(app, secret)
      super(app)
      @secret = secret
    end

    def call(env)
      xmldata = env[:body][:xmldata]
      env[:body][:hash] = Digest::MD5.digest([xmldata, @secret])
      @app.call env
    end
  end
end
