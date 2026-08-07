module Einvoice
  class Client
    attr_accessor :provider

    def initialize(provider)
      @provider = provider
    end

    def method_missing(m, *args, &block)
      if provider.respond_to?(m)
        provider.public_send(m, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(m, include_private = false)
      provider.respond_to?(m) || super
    end
  end
end
