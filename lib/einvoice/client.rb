module Einvoice
  class Client
    attr_accessor :provider

    def initialize(provider)
      @provider = provider
    end

    def issue(payload, options = {})
      provider.issue(payload, options)
    end
  end
end
