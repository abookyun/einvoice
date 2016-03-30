require "einvoice/utils"

require "einvoice/tradevan/model/base"
require "einvoice/tradevan/model/issue_data"
require "einvoice/tradevan/model/issue_item"

require "einvoice/tradevan/result"

module Einvoice
  module Tradevan
    class Provider < Einvoice::Provider
      def issue(payload, options = {})
        issue_data = Einvoice::Tradevan::Model::IssueData.new
        issue_data.from_json(payload.to_json)

        if issue_data.valid?
          response = connection(
            ssl: {
              verify: false
            }
          ).post do |request|
            request.url endpoint_url || endpoint + "/DEFAULTAPI/post/issue"
            request.body = {
              acnt: client_id,
              acntp: client_secret,
              issueData: issue_data.payload
            }
          end.body

          Einvoice::Tradevan::Result.new(response)
        else
          Einvoice::Tradevan::Result.new(issue_data.errors)
        end
      end
    end
  end
end
