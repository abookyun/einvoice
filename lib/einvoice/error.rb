# frozen_string_literal: true

require "net/http"
require "openssl"
require "timeout"

module Einvoice
  # Normalized, action-oriented reason symbols — one level finer than the error
  # class. The classes are deliberately coarse ({ConflictError} alone covers
  # duplicate-order, void-blocked-by-allowance, already-voided and past-deadline,
  # which a caller handles completely differently), so `reason` carries the
  # distinction. `nil` when the adapter cannot determine one.
  #
  # Each value implies a concrete consumer action, e.g. +:duplicate_order+ →
  # query-and-adopt the existing invoice; +:void_blocked_by_allowance+ → issue an
  # allowance instead; +:already_voided+ → treat as idempotent success.
  #
  # That last one is why the two "wrong state" reasons are separate. Voiding an
  # already-voided invoice reached the state the caller wanted, so doing nothing
  # is correct. Crediting a voided invoice did not: no allowance exists, and
  # treating it as success would record a refund that never happened.
  module Reason
    DUPLICATE_ORDER           = :duplicate_order
    # 作廢 refused: the invoice carries a live 折讓 — void that first.
    VOID_BLOCKED_BY_ALLOWANCE = :void_blocked_by_allowance
    # 折讓 refused: the invoice is already 作廢 — there is nothing to credit, and
    # nothing was credited. Not idempotent success; the caller has to reconcile.
    ALLOWANCE_BLOCKED_BY_VOID = :allowance_blocked_by_void
    # 作廢 of an invoice already 作廢 — the requested state, so safe to ignore.
    ALREADY_VOIDED            = :already_voided
    DUPLICATE_ALLOWANCE       = :duplicate_allowance
    PAST_DEADLINE             = :past_deadline
    CARRIER_NOT_REGISTERED    = :carrier_not_registered
    RATE_LIMITED              = :rate_limited
    CREDENTIALS_INVALID       = :credentials_invalid
    NOT_ENROLLED              = :not_enrolled
    CONTRACT_EXPIRED          = :contract_expired
    IP_BLOCKED                = :ip_blocked
    ACCOUNT_SUSPENDED         = :account_suspended
    STALE_TIMESTAMP           = :stale_timestamp

    ALL = [
      DUPLICATE_ORDER, VOID_BLOCKED_BY_ALLOWANCE, ALLOWANCE_BLOCKED_BY_VOID,
      ALREADY_VOIDED, DUPLICATE_ALLOWANCE,
      PAST_DEADLINE, CARRIER_NOT_REGISTERED, RATE_LIMITED, CREDENTIALS_INVALID,
      NOT_ENROLLED, CONTRACT_EXPIRED, IP_BLOCKED, ACCOUNT_SUSPENDED, STALE_TIMESTAMP
    ].freeze
  end

  # Base class for every error the SDK raises. Adapters map provider/MOF error
  # codes onto a subclass, preserving the provider's raw code/message/payload.
  #
  # Rescue precisely (`rescue Einvoice::ConflictError`) or broadly
  # (`rescue Einvoice::Error`) — the subclass hierarchy replaces the string
  # matching the legacy client forced on callers. Each subclass exposes a stable
  # {#code} symbol so two-way parity with the TypeScript SDK's InvoiceErrorCode
  # holds.
  class Error < StandardError
    # Stable, provider-independent code for the base class. Subclasses override.
    CODE = :unknown
    # Which side failed. +:invoice+: the request breaks a rule of the MOF, or the
    # invoice is not in the state it needs. These mean the same at every
    # provider. +:provider+: the account, the connection, the provider's own
    # service, or a feature it lacks.
    GROUP = :provider
    # The low-level errors that mean the connection failed. Clients rescue only
    # these, so a bug in an adapter is not reported as a NetworkError.
    NETWORK_ERRORS = [
      IOError, SocketError, SystemCallError, Timeout::Error, EOFError,
      OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
    ].freeze

    attr_reader :provider, :reason, :raw_code, :raw_message, :raw

    def initialize(message = nil, provider:, reason: nil, raw_code: nil, raw_message: nil,
                   raw: nil, cause: nil)
      super(message)
      @provider = provider
      @reason = reason
      @raw_code = raw_code
      @raw_message = raw_message
      @raw = raw
      @explicit_cause = cause
    end

    # The stable {InvoiceErrorCode}-equivalent symbol, e.g. +:conflict+.
    def code
      self.class::CODE
    end

    # +:invoice+ or +:provider+. See {GROUP}.
    def group
      self.class::GROUP
    end

    # Preserve an explicitly-passed cause, else fall back to Ruby's ambient one.
    def cause
      @explicit_cause || super
    end

    # Structured-logging shape. Omits +raw+ (can be large / carry PII — read it
    # off the instance when needed) and drops nil fields.
    def to_h
      {
        provider: provider,
        code: code,
        group: group,
        reason: reason,
        message: message,
        raw_code: raw_code,
        raw_message: raw_message
      }.compact
    end

    # Build the subclass for a normalized code symbol. Adapters resolve a
    # provider code to one of our codes, then `raise Einvoice::Error.for(code, …)`.
    def self.for(code, message = nil, **options)
      CODE_TO_CLASS.fetch(code, UnknownError).new(message, **options)
    end
  end

  # Auth / signature / credential failure.
  class AuthError < Error
    CODE = :auth
  end

  # Request failed local or remote validation.
  class ValidationError < Error
    CODE = :validation
    GROUP = :invoice
  end

  # Referenced invoice/allowance does not exist.
  class NotFoundError < Error
    CODE = :not_found
    GROUP = :invoice
  end

  # Operation invalid for the invoice's current state (e.g. void a voided one).
  class ConflictError < Error
    CODE = :conflict
    GROUP = :invoice
  end

  # 字軌 / 配號 exhausted — no invoice number available.
  class NumberExhaustedError < Error
    CODE = :number_exhausted
    GROUP = :invoice
  end

  # Network / timeout / transport failure, and HTTP 5xx or 429. The caller can
  # retry.
  class NetworkError < Error
    CODE = :network

    # The error for an HTTP status that means "try again", or nil.
    def self.for_status(response, provider:)
      status = response.code.to_i
      return unless status == 429 || status >= 500

      reason = status == 429 ? Reason::RATE_LIMITED : nil
      new("#{provider} returned HTTP #{status}", provider: provider, reason: reason, raw_code: response.code)
    end
  end

  # Provider returned an error we could not map.
  class ProviderError < Error
    CODE = :provider
  end

  # The provider does not support the requested operation/feature.
  class UnsupportedError < Error
    CODE = :unsupported
  end

  # Anything else.
  class UnknownError < Error
    CODE = :unknown
  end

  class Error
    CODE_TO_CLASS = {
      auth: AuthError,
      validation: ValidationError,
      not_found: NotFoundError,
      conflict: ConflictError,
      number_exhausted: NumberExhaustedError,
      network: NetworkError,
      provider: ProviderError,
      unsupported: UnsupportedError,
      unknown: UnknownError
    }.freeze
  end
end
