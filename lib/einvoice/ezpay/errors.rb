# frozen_string_literal: true

module Einvoice
  module EzPay
    # Maps ezPay's +Status+ codes onto the unified {Einvoice::Error} tree, from
    # the code list in the manual (docs/providers/ezpay/invoice.md, section 6.4).
    #
    # The list has no code for an allowance on a voided invoice, for an
    # allowance that does not exist, or for a duplicate allowance. {CONTEXT}
    # holds our guesses for those cases, by operation, so that real codes can
    # replace them in one place. Voiding an allowance twice has no code either.
    # The fake assumes LIB10005, which the main table already reads as
    # ConflictError.
    module Errors
      # code => [error class code, Reason or nil]
      CODES = {
        "KEY10002" => [:auth, Reason::CREDENTIALS_INVALID],    # cannot decrypt
        "KEY10004" => [:validation, nil],                      # data incomplete
        "KEY10006" => [:auth, Reason::NOT_ENROLLED],
        "KEY10007" => [:validation, Reason::STALE_TIMESTAMP],  # open more than 30 minutes
        "KEY10010" => [:validation, nil],
        "KEY10011" => [:validation, nil],
        "KEY10012" => [:provider, nil],                        # data transfer error
        "KEY10013" => [:validation, nil],
        "KEY10014" => [:network, nil],                         # timeout
        "KEY10015" => [:validation, nil],
        "INV10003" => [:validation, nil],
        "INV10004" => [:validation, nil],
        "INV10006" => [:validation, nil],
        "INV10012" => [:validation, nil],
        "INV10013" => [:validation, nil],
        "INV10014" => [:validation, nil],
        "INV10015" => [:validation, nil],
        "INV10016" => [:validation, nil],
        "INV10017" => [:validation, nil],
        "INV10019" => [:validation, nil],
        "INV10020" => [:auth, Reason::ACCOUNT_SUSPENDED],
        "INV10021" => [:auth, Reason::ACCOUNT_SUSPENDED],
        "INV20006" => [:not_found, nil],
        "INV70001" => [:validation, nil],
        "INV70002" => [:conflict, nil],                        # upload failed, cannot void
        "INV90005" => [:auth, Reason::CONTRACT_EXPIRED],
        "INV90006" => [:number_exhausted, nil],
        "NOR10001" => [:network, nil],
        "LIB10003" => [:conflict, Reason::DUPLICATE_ORDER],
        "LIB10005" => [:conflict, Reason::ALREADY_VOIDED],
        "LIB10007" => [:conflict, Reason::VOID_BLOCKED_BY_ALLOWANCE],
        "LIB10008" => [:conflict, Reason::PAST_DEADLINE],
        "LIB10009" => [:conflict, Reason::RETRY_LATER]         # not uploaded yet, cannot void
      }.freeze

      # Guesses for the cases the code list does not cover. On an allowance,
      # "already voided" means the invoice is voided, so nothing was credited.
      # On an allowance void, IAI10002 (query failed) is the closest to "no
      # such allowance".
      CONTEXT = {
        allowance: { "LIB10005" => [:conflict, Reason::ALLOWANCE_BLOCKED_BY_VOID] },
        void_allowance: { "IAI10002" => [:not_found, nil] }
      }.freeze

      module_function

      # @return [Array(Symbol, Symbol)] the error class code and the Reason
      #   (or nil). Unknown codes, and IAI10001 to IAI10006 outside the
      #   guesses above, are +:provider+.
      def classify(code, operation = nil)
        code = code.to_s
        CONTEXT.fetch(operation, {})[code] || CODES[code] || [:provider, nil]
      end
    end
  end
end
