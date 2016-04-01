require 'base64'
require 'openssl'

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
            request.params[:v] = encrypted_params(issueData: issue_data.payload)
          end.body

          Einvoice::Tradevan::Result.new(response)
        else
          Einvoice::Tradevan::Result.new(issue_data.errors)
        end
      end

      def get_donate_unit_list(companyUn, options = {})
        response = connection(
          ssl: {
            verify: false
          }
        ).get do |request|
          request.url endpoint_url || endpoint + "/DEFAULTAPI/get/getDonateUnitList"
          request.params[:v] = encrypted_params(companyUn: companyUn)
        end.body

        Einvoice::Tradevan::Result.new(response)
      end

      private

      def encrypted_params(params)
        encrypted_params = params.dup
        encrypted_params.each do |key, value|
          value = value.is_a?(Hash) ? value.to_json : value.to_s
          encrypted_params[key] = encrypt(encryption_keys[:key1], value)
        end

        v = { acnt: client_id, acntp: client_secret }.merge(encrypted_params).to_json
        encrypt(encryption_keys[:key2], v)
      end

      def encrypt(key, content)
        cipher = OpenSSL::Cipher::AES.new(128, :CBC)
        cipher.encrypt
        cipher.key = key
        cipher.iv = key
        cipher.padding = 0

        # padding with "\x00"
        q, m = content.size.divmod(cipher.block_size)
        content = content.ljust(cipher.block_size * (q + 1), "\x00") if m != 0

        Base64.strict_encode64(cipher.update(content) + cipher.final)
      end
    end
  end
end
