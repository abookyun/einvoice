# frozen_string_literal: true

module Einvoice
  module Tradevan
    module DefaultAPI
      # Maps DEFAULTAPI failures onto the unified {Einvoice::Error} tree.
      #
      # DEFAULTAPI has no error code list. A failure is +Success: "E"+ with a
      # plain text +Message+, or +Success: "N"+ (or an inner +issueStatus+ /
      # +voidStatus+ of +"N"+) with a free text +failReason+. The only failure
      # text on record is +duplicated+, and it comes from a 1.x spec stub, not
      # from a real response. So every pattern below is a guess, kept in one
      # place so that real texts can replace it.
      #
      # Unknown failures fall back to +:provider+, not +:validation+: with so few
      # samples, an unknown failure is more likely a provider problem than bad
      # input.
      module Errors
        CREDENTIALS = /帳號|密碼|金鑰|acnt|key|password|account/i
        DUPLICATE = /duplicat|重[複覆]/i
        # Checked before ALREADY_VOID: "已作廢，不能折讓" is a refusal, and the
        # refusal is the part the caller can act on.
        BLOCKED_BY_VOID = /作廢.*不能|不能.*作廢.*折讓/
        ALREADY_VOID = /已(被)?作廢/
        ALLOWANCE_MADE = /已折讓|折讓過/
        MISSING = /查無|不存在|not\s*found/i

        module_function

        # +Success: "E"+: the request did not reach the business logic.
        def classify_transport(message)
          return [:auth, Reason::CREDENTIALS_INVALID] if message.to_s.match?(CREDENTIALS)

          [:provider, nil]
        end

        # +Success: "N"+, or an inner status of +"N"+.
        def classify(message)
          case message.to_s
          when DUPLICATE then [:conflict, Reason::DUPLICATE_ORDER]
          when BLOCKED_BY_VOID then [:conflict, Reason::ALLOWANCE_BLOCKED_BY_VOID]
          when ALREADY_VOID then [:conflict, Reason::ALREADY_VOIDED]
          when ALLOWANCE_MADE then [:conflict, Reason::VOID_BLOCKED_BY_ALLOWANCE]
          when MISSING then [:not_found, nil]
          else [:provider, nil]
          end
        end
      end
    end
  end
end
