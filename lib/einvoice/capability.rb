# frozen_string_literal: true

module Einvoice
  # Feature flags a provider may or may not support. Every adapter declares its
  # own set so callers feature-detect at runtime ({Capability::Support#supports?})
  # instead of discovering a gap only when a request fails.
  #
  # The five core operations are listed so a degraded/partial adapter can be
  # honest about what it omits; the rest cover optional behaviour that genuinely
  # differs between value-added centers.
  module Capability
    # 開立發票.
    ISSUE = :issue
    # 作廢發票.
    VOID = :void
    # 開立折讓.
    ALLOWANCE = :allowance
    # 作廢折讓.
    VOID_ALLOWANCE = :void_allowance
    # 查詢發票.
    QUERY = :query
    # Issue to a business buyer with a 統一編號 (B2B).
    B2B = :b2b
    # Mixed tax-rate invoice (應稅 + 零稅率 + 免稅 in one document).
    MIXED_TAX = :mixed_tax
    # Look up an invoice by the merchant order id, not just the invoice number.
    QUERY_BY_ORDER_ID = :query_by_order_id
    # Schedule an invoice to be issued automatically at a future date.
    SCHEDULED_ISSUE = :scheduled_issue
    # Validate a carrier (手機條碼 / 愛心碼) against the tax authority.
    CARRIER_VALIDATION = :carrier_validation
    # Annotate a foreign-currency sale via currency + exchange_rate. Statutory
    # amounts are still filed in integer TWD; providers that don't support it
    # reject a non-TWD currency instead of silently dropping it.
    FOREIGN_CURRENCY = :foreign_currency

    ALL = [
      ISSUE, VOID, ALLOWANCE, VOID_ALLOWANCE, QUERY, B2B, MIXED_TAX,
      QUERY_BY_ORDER_ID, SCHEDULED_ISSUE, CARRIER_VALIDATION, FOREIGN_CURRENCY
    ].freeze

    # Mixed into anything that exposes a +#capabilities+ set and a +#name+.
    module Support
      # Whether this provider declares support for +capability+.
      def supports?(capability)
        capabilities.include?(capability)
      end

      # Raise {UnsupportedError} unless this provider supports +capability+.
      def assert_supports!(capability)
        return if supports?(capability)

        raise Einvoice::UnsupportedError.new(
          %(Provider "#{name}" does not support capability "#{capability}"),
          provider: name
        )
      end
    end
  end
end
