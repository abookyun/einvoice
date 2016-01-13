module Einvoice
  class Result
    attr_reader :response

    def initialize(response = nil)
      @response = response
    end

    def errors
      if response.is_a? ActiveModel::Errors
        response.full_messages.join('; ')
      else
        response && response.fetch("Result", {}) do |data|
          "#{data["statcode"]}: #{data["statdesc"]}"
        end
      end
    end

    def success?
      if response.is_a? ActiveModel::Errors
        false
      elsif response && response.fetch("Result", {})["statdesc"] == "0000"
        true
      else
        false
      end
    end
  end
end
