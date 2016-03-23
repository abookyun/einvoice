require 'faraday'

module Faraday
  class Response::DecodeTradevan < Faraday::Middleware
    dependency do
      require 'base64' unless defined?(::Base64)
      require 'openssl' unless defined?(::OpenSSL)
    end

    def initialize(app, key1, key2)
      super(app)
      @key1 = key1
      @key2 = key2
    end

    def call(env)
      if env[:body][:Success] == 'Y'
        env[:body][:Message] = decrypt(env[:body][:Message])
      end

      @app.call env
    end

    private

    def decrypt(key, content)
      cipher = OpenSSL::Cipher::AES.new(128, :CBC)
      cipher.decrypt
      cipher.key = key

      cipher.update(Base64.decode64(content)) + cipher.final
    end
  end
end

Faraday::Response.register_middleware decode_tradevan: Faraday::Response::DecodeTradevan
