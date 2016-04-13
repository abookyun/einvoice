require 'base64'
require 'openssl'

require "einvoice/utils"

require "einvoice/tradevan/model/base"
require "einvoice/tradevan/model/issue_data"
require "einvoice/tradevan/model/issue_item"
require "einvoice/tradevan/model/void_data"

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

      def cancel(payload, options = {})
        void_data = Einvoice::Tradevan::Model::VoidData.new
        void_data.from_json(payload.to_json)

        if void_data.valid?
          response = connection(
            ssl: {
              verify: false
            }
          ).post do |request|
            request.url endpoint_url || endpoint + "/DEFAULTAPI/post/cancel"
            request.params[:v] = encrypted_params(voidData: void_data.payload)
          end.body

          Einvoice::Tradevan::Result.new(response)
        else
          Einvoice::Tradevan::Result.new(void_data.errors)
        end
      end

      def search_invoice_by_member_id(invoice_start_date, invoice_end_date, companyUn = nil, memberId = nil, carrierId = nil, sellTargetCode = nil)
        response = connection(
          ssl: {
            verify: false
          }
        ).get do |request|
          request.url endpoint_url || endpoint + "/DEFAULTAPI/get/searchInvoiceByMemberId"
          request.params[:v] = encrypted_params(
            invoiceStartDate: invoice_start_date,
            invoiceEndDate: invoice_end_date,
            companyUn: companyUn,
            memberId: memberId,
            carrierId: carrierId,
            sellTargetCode: sellTargetCode
          )
        end.body

        Einvoice::Tradevan::Result.new(response)
      end

      def search_invoice_detail(invoice_number)
        response = connection(
          ssl: {
            verify: false
          }
        ).get do |request|
          request.url endpoint_url || endpoint + "/DEFAULTAPI/get/searchInvoiceDetail"
          request.params[:v] = encrypted_params(invoiceNumber: invoice_number)
        end.body

        Einvoice::Tradevan::Result.new(response)
      end

      def send_card_info_to_cust(companyUn = nil, sellTargetCode, invoiceStartYM, invoiceEndYM, receiverEmail = nil, receiverMobile = nil)
        response = connection(
          ssl: {
            verify: false
          }
        ).get do |request|
          request.url endpoint_url || endpoint + "/DEFAULTAPI/get/sendCardInfotoCust"
          request.params[:v] = encrypted_params(
            companyUn: companyUn,
            sellTargetCode: sellTargetCode,
            invoiceStartYM: invoiceStartYM,
            invoiceEndYM: invoiceEndYM,
            receiverEmail: receiverEmail,
            receiverMobile: receiverMobile
          )
        end.body

        Einvoice::Tradevan::Result.new(response)
      end

      def get_invoice_mark_info(companyUn, orgId, uniFiedNumber, bookType, period)
        response = connection(
          ssl: {
            verify: false
          }
        ).get do |request|
          request.url endpoint_url || endpoint + "/DEFAULTAPI/get/sendCardInfotoCust"
          request.params[:v] = encrypted_params(
            companyUn: companyUn,
            orgId: orgId,
            uniFiedNumber: uniFiedNumber,
            bookType: bookType,
            period: period
          )
        end.body

        Einvoice::Tradevan::Result.new(response)
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

      def get_invoice_content(params, options = {})
        response = connection(
          ssl: {
            verify: false
          }
        ).get do |request|
          request.url endpoint_url || endpoint + "/DEFAULTAPI/get/getInvoiceContent"

          request.params[:v] = encrypted_params(params)
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

        # padding with "\u0000"
        q, m = content.bytesize.divmod(cipher.block_size)
        content_bytes_with_padding = content.bytes.fill(0, content.bytesize..(cipher.block_size * (q + 1) - 1))
        content = content_bytes_with_padding.pack('C*').force_encoding('utf-8') if m!= 0

        Base64.strict_encode64(cipher.update(content) + cipher.final)
      end
    end
  end
end
