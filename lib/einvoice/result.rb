module Einvoice
  class Result
    attr_reader :response

    def initialize(response = nil)
      @response = response
    end

    def errors
      response.errors unless success?
    end

    def success?
      response.success?
    end
  end
end
