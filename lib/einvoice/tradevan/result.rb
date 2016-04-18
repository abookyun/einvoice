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

      def successful?
        response && !response.is_a?(ActiveModel::Errors) && response["Success"] == 'Y'
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
