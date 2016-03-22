module Einvoice
  module Tradevan
    class Result < Einvoice::Result
      def errors
        if response.is_a? ActiveModel::Errors
          response.full_messages.join('; ')
        else
          response&.dig(:Message)
        end
      end

      def success?
        !response&.is_a? ActiveModel::Errors || response&.dig(:Success) == 'Y'
      end

      def data
        if response&.is_a? ActiveModel::Errors
          nil
        else
          response&.dig(:Message)
        end
      end
    end
  end
end
