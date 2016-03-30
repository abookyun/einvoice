module Einvoice
  class Client
    attr_accessor :provider

    def initialize(provider)
      @provider = provider
    end

    def method_missing(m, *args, &block)
      provider.send(m, *args, &block)
    end
  end
end
