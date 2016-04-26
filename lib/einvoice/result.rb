module Einvoice
  class Result
    attr_reader :response

    def initialize(response = nil)
      @response = response
    end

    def errors
      raise NotImplementedError, 'You must initialize one of Einvoice::Response subclasses then use it.'
    end

    def successful?
      raise NotImplementedError, 'You must initialize one of Einvoice::Response subclasses then use it.'
    end

    def data
      raise NotImplementedError, 'You must initialize one of Einvoice::Response subclasses then use it.'
    end
  end
end
