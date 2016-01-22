module Einvoice
  class Client
    attr_accessor :provider

    def initialize(provider)
      @provider = provider
    end

    def issue(payload, options = {})
      provider.issue(payload, options)
    end

    def query(payload, options = {})
      provider.query(payload, options = {})
    end

    def cancel(payload, options = {})
      provider.cancel(payload, options = {})
    end

    def allowance_for(payload, options = {})
      provider.allowance_for(payload, options = {})
    end

    def cancel_allowance(payload, options = {})
      provider.cancel_allowance(payload, options = {})
    end
  end
end
