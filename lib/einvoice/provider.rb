module Einvoice
  class Provider
    attr_accessor *Configuration::VALID_OPTIONS_KEYS
    attr_accessor :provider

    def initialize(options={})
      options = Einvoice.options.merge(options)
      Configuration::VALID_OPTIONS_KEYS.each do |key|
        send("#{key}=", options[key])
      end
    end

    def config
      conf = {}
      Configuration::VALID_OPTIONS_KEYS.each do |key|
        conf[key] = send key
      end
      conf
    end

    include Connection
  end
end
