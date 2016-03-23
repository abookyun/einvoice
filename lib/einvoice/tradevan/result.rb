module Einvoice
  module Tradevan
    class Result < Einvoice::Result
      def errors
        if response.is_a? ActiveModel::Errors
          response.full_messages.join('; ')
        else
          response && response["Message"]
        end
      end

      def success?
        response && (response["Success"] == 'Y' || !response.is_a?(ActiveModel::Errors))
      end

      def data
        if response.is_a? ActiveModel::Errors
          nil
        else
          response && response["Message"]
        end
      end
    end
  end
end
