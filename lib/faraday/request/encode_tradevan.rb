require 'faraday'

module Faraday
  class Request::EncodeTradevan < Faraday::Middleware
    dependency do
      require 'digest' unless defined?(::Digest)
      require 'base64' unless defined?(::Base64)
      require 'openssl' unless defined?(::OpenSSL)
    end

    def initialize(app, key1, key2)
      super(app)
      @key1 = key1
      @key2 = key2
    end

    def call(env)
      acnt = env[:body].delete(:acnt)
      acntp_digest = Digest::MD5.hexdigest("FinvC" + env[:body].delete(:acntp))
      args = env.delete(:body)
      encrypted_args = args.each { |_, value| encrypt(@key1, value.to_json) }
      v_hash = encrypted_args.merge(acnt: acnt, acntp: acntp_digest)

      env[:body][:v] = encrypt(@key2, v_hash.to_json)
      @app.call env
    end

    private

    def encrypt(key, content)
      cipher = OpenSSL::Cipher::AES.new(128, :CBC)
      cipher.encrypt
      cipher.key = key

      Base64.encode64(cipher.update(content) + cipher.final)
    end
  end
end

Faraday::Request.register_middleware encode_tradevan: Faraday::Request::EncodeTradevan
