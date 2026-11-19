# frozen_string_literal: true

module Einvoice
  module Amego
    # Maps Amego's +code+ values onto the unified {Einvoice::Error} tree.
    #
    # The codes come from Amego's error code page
    # (https://invoice.amego.tw/info_detail?mid=71). docs/providers/amego/api.md
    # section 6.4 lists them. Codes +15+ and +71+ were seen on the live test
    # account.
    module Errors
      # code => [error class code, Reason or nil]
      CODES = {
        # Common codes.
        10 => [:provider, nil],                           # system maintenance
        11 => [:auth, Reason::CREDENTIALS_INVALID],       # invoice (統一編號) empty
        12 => [:auth, Reason::CREDENTIALS_INVALID],       # invoice (統一編號) wrong
        13 => [:auth, Reason::NOT_ENROLLED],              # status not active
        14 => [:auth, Reason::IP_BLOCKED],
        15 => [:auth, Reason::STALE_TIMESTAMP],     # time out of range
        16 => [:auth, Reason::CREDENTIALS_INVALID],       # sign wrong
        17 => [:validation, nil],                         # data empty
        18 => [:provider, nil],                           # database connection failed
        19 => [:auth, Reason::ACCOUNT_SUSPENDED],
        20 => [:validation, nil],                         # data is not JSON
        21 => [:provider, Reason::RATE_LIMITED],
        22 => [:auth, Reason::NOT_ENROLLED],              # API access not applied for
        23 => [:validation, nil],                         # this API takes an array
        51 => [:provider, nil],                           # past the 180-day query limit
        71 => [:not_found, nil],
        99 => [:provider, nil],
        # f0401
        3_040_111 => [:number_exhausted, nil],
        3_040_132 => [:validation, Reason::CARRIER_NOT_REGISTERED],
        3_040_171 => [:conflict, Reason::DUPLICATE_ORDER],
        3_040_191 => [:number_exhausted, nil],
        # f0501
        3_050_111 => [:validation, nil],
        3_050_113 => [:validation, nil],
        3_050_121 => [:conflict, Reason::RETRY_LATER],                # still being issued
        3_050_122 => [:conflict, Reason::ALREADY_VOIDED],
        3_050_123 => [:conflict, nil],                    # already cancelled (註銷)
        3_050_125 => [:not_found, nil],
        3_050_126 => [:conflict, Reason::PAST_DEADLINE],
        3_050_131 => [:conflict, Reason::RETRY_LATER],                # a queued change is waiting
        3_050_141 => [:conflict, Reason::VOID_BLOCKED_BY_ALLOWANCE],
        # g0401
        4_040_145 => [:validation, nil],
        4_040_151 => [:validation, nil],
        4_040_153 => [:conflict, Reason::ALLOWANCE_BLOCKED_BY_VOID],
        4_040_154 => [:conflict, nil],                    # original invoice cancelled
        4_040_156 => [:not_found, nil],
        4_040_157 => [:validation, nil],
        4_040_161 => [:conflict, Reason::DUPLICATE_ALLOWANCE],
        4_040_171 => [:validation, nil],
        4_040_173 => [:validation, nil],
        # g0501
        4_050_132 => [:conflict, Reason::ALREADY_VOIDED],
        4_050_134 => [:not_found, nil],
        4_050_135 => [:conflict, Reason::PAST_DEADLINE],
        4_050_141 => [:conflict, Reason::RETRY_LATER],                # a queued change is waiting

        9_000_111 => [:validation, nil],                  # barcode empty
        9_000_112 => [:validation, nil]                   # barcode format wrong
      }.freeze

      # The other f0401 codes from 3040101 to 3040199 are field format errors.
      ISSUE_FIELD_ERRORS = (3_040_101..3_040_199)

      module_function

      # @return [Array(Symbol, Symbol)] the error class code and the Reason
      #   (or nil). Codes outside the table are +:provider+: Amego knows why it
      #   refused, and we do not.
      def classify(code)
        code = Integer(code, exception: false)
        return CODES[code] if CODES.key?(code)
        return [:validation, nil] if code && ISSUE_FIELD_ERRORS.cover?(code)

        [:provider, nil]
      end
    end
  end
end
