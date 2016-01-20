module Einvoice
  module Neweb
    class Result < Einvoice::Result
      def errors
        if response.is_a? ActiveModel::Errors
          response.full_messages.join('; ')
        else
          data = response && (response.fetch("Result").fetch("Invoice", {}) || response.fetch("Result", {}))
          data["statcode"] == "0000" ? nil : "#{data["statcode"]}: #{data["statdesc"]}" if data
        end
      end

      def success?
        if response.is_a? ActiveModel::Errors
          false
        else
          data = response && (response.fetch("Result").fetch("Invoice", {}) || response.fetch("Result", {}))
          data["statcode"] == "0000" if data
        end
      end
    end
  end
end
