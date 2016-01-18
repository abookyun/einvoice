module Einvoice
  module Neweb
    class Result < Einvoice::Result
      def errors
        if response.is_a? ActiveModel::Errors
          response.full_messages.join('; ')
        else
          response && response.fetch("Result", {}) do |data|
            data["statcode"] == "0000" ? nil : "#{data["statcode"]}: #{data["statdesc"]}"
          end
        end
      end

      def success?
        if response.is_a? ActiveModel::Errors
          false
        else
          response && response.fetch("Result", {}) do |data|
            data["statcode"] == "0000" ? true : false
          end
        end
      end
    end
  end
end
