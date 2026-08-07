require 'base64'
require 'json'
require 'openssl'

require 'faraday'

module Faraday
  class Response::DecodeTradevan < Faraday::Middleware
    def initialize(app, key)
      super(app)
      @key = key
    end

    def call(env)
      @app.call(env).on_complete do |env|
        if env[:body] && env[:body]['Success'] != 'E'
          env[:body]['Message'] = decrypt(@key, env[:body]['Message'])
        end
      end
    end

    private

    def decrypt(key, content)
      cipher = OpenSSL::Cipher::AES.new(128, :CBC)
      cipher.decrypt
      cipher.key = key
      cipher.iv = key
      cipher.padding = 0

      decrypted = cipher.update(Base64.decode64(content)) + cipher.final
      JSON.parse(decrypted.strip)
    end
  end
end

Faraday::Response.register_middleware decode_tradevan: Faraday::Response::DecodeTradevan
