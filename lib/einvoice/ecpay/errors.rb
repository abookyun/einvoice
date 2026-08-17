# frozen_string_literal: true

module Einvoice
  module ECPay
    # Maps ECPay's two failure channels onto the unified {Einvoice::Error} tree.
    #
    # A B2C response has two independent result fields and both must be checked:
    # the outer +TransCode+ (transport — did the envelope decrypt and parse?) and,
    # after decrypting +Data+, the inner +RtnCode+ (business). Success is the
    # integer +1+ on each.
    #
    # Business codes are the awkward part: they span unrelated ranges (+2+,
    # +1600003+, +5070357+, +5000022+ …) and the same condition can surface under
    # different numbers per endpoint, so the Chinese +RtnMsg+ is the more reliable
    # signal. Classification therefore tries the table of codes confirmed against
    # the live stage API first, then falls back to matching the message.
    module Errors
      # Transport-level codes seen live (2026-08-15, stage).
      TRANSPORT = {
        104 => [:validation, Reason::STALE_TIMESTAMP],  # Timestamp is over 10 minutes...
        110 => [:auth, Reason::CREDENTIALS_INVALID]     # The parameter [Data] decrypt fail.
      }.freeze

      # Business codes confirmed by driving the stage API (2026-08-15). Kept small
      # and specific on purpose — a code whose meaning is endpoint-dependent (e.g.
      # a bare +2+) is left to the message matcher instead.
      BUSINESS = {
        1_600_003 => [:not_found, nil],                            # 無發票號碼資料
        2_000_039 => [:not_found, nil],                            # 查無折讓單資料
        2_000_042 => [:conflict, Reason::ALLOWANCE_BLOCKED_BY_VOID], # 作廢發票號碼不能折讓
        2_000_063 => [:conflict, Reason::ALREADY_VOIDED],          # 該折讓單已作廢過
        5_070_357 => [:conflict, Reason::DUPLICATE_ORDER],         # 自訂編號重覆
        5_070_450 => [:conflict, Reason::VOID_BLOCKED_BY_ALLOWANCE], # 該發票已被折讓過
        5_070_453 => [:conflict, Reason::ALREADY_VOIDED],          # 該發票已被作廢過
        9_000_001 => [:network, nil]                               # 呼叫財政部API失敗
      }.freeze

      # 財政部 upstream trouble is transient and retryable — never the caller's input.
      UPSTREAM_DOWN = /財政部.*(失敗|維護)|呼叫.*API失敗/
      CREDENTIALS   = /金鑰|簽章|未授權/
      NOT_ENROLLED  = /特店.*不存在|平台商.*不存在/
      EXHAUSTED     = /字軌.*(用罄|用完|不足|已滿)|號碼.*(用罄|用完)/
      # 重複 and 重覆 are both current spellings and ECPay uses both — matching only
      # one silently demotes a duplicate-order conflict to a generic validation error.
      DUPLICATE     = /重[複覆]/
      # Two different conflicts that both mention 作廢, and they call for opposite
      # responses. 已作廢 on a void means the invoice already reached the state
      # asked for — safe to treat as success. "作廢…不能…" means the operation was
      # refused *because* the invoice is voided, and nothing happened; treating
      # that as success would record a credit that does not exist.
      # ECPay writes both 已作廢 and 已被作廢; matching only the first meant the
      # fallback missed 5070453's actual wording, which went unnoticed because
      # that code is in the table above.
      ALREADY_VOID    = /已(被)?作廢/
      BLOCKED_BY_VOID = /作廢.*不能/
      ALLOWANCE_MADE = /已折讓|折讓過/
      CONFLICTING   = /已開立|已存在|同意/
      MISSING       = /查無|查不到|無.*資料|不存在/
      BUSY          = /系統(錯誤|異常|忙碌)|請稍後/

      module_function

      # Classify a transport failure → +[code, reason]+.
      def classify_transport(trans_code)
        TRANSPORT.fetch(trans_code.to_i, [:provider, nil])
      end

      # Classify a business failure → +[code, reason]+.
      def classify(rtn_code, rtn_msg = "")
        known = BUSINESS[rtn_code.to_i]
        return known if known

        [message_code(rtn_msg.to_s), message_reason(rtn_msg.to_s)]
      end

      # The fallback matcher. Anything unrecognized is treated as field/business
      # validation, which is what the long tail of ECPay's codes actually is.
      def message_code(msg)
        case msg
        when UPSTREAM_DOWN then :network
        when CREDENTIALS, NOT_ENROLLED then :auth
        when EXHAUSTED then :number_exhausted
        when DUPLICATE, ALREADY_VOID, BLOCKED_BY_VOID, ALLOWANCE_MADE, CONFLICTING then :conflict
        # AUTH already claimed 特店/平台商不存在 above, so a bare 不存在 here is a
        # missing record rather than an unknown merchant.
        when MISSING then :not_found
        when BUSY then :provider
        else :validation
        end
      end

      def message_reason(msg)
        case msg
        when CREDENTIALS then Reason::CREDENTIALS_INVALID
        when NOT_ENROLLED then Reason::NOT_ENROLLED
        # Checked before ALREADY_VOID: a message carrying both ("已作廢，不能折讓")
        # is a refusal, and the refusal is the actionable half.
        when BLOCKED_BY_VOID then Reason::ALLOWANCE_BLOCKED_BY_VOID
        when ALREADY_VOID then Reason::ALREADY_VOIDED
        # Only the void API emits 已折讓/折讓過, so it always means "void the
        # allowance first" rather than a plain conflict.
        when ALLOWANCE_MADE then Reason::VOID_BLOCKED_BY_ALLOWANCE
        when DUPLICATE then Reason::DUPLICATE_ORDER
        when BUSY then Reason::RATE_LIMITED
        end
      end
    end
  end
end
