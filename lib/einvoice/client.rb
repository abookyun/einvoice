module Einvoice
  class Client
    attr_accessor :provider

    def initialize(provider)
      @provider = provider
    end

    def issue(payload)
      provider.issue(payload)
    end
  end
end
