# frozen_string_literal: true

require "set"

module Einvoice
  # In-memory {Provider} for tests and local development. It runs the same input
  # validation as a real adapter (via {Input}) but never hits the network, so
  # application code can be exercised end-to-end without credentials.
  #
  # It mirrors real-adapter behaviour beyond the happy path: capability gating
  # (each operation, and a non-TWD currency, is refused unless its capability
  # is declared), an in-memory state machine (an invoice with an allowance in
  # force cannot be voided, a voided invoice cannot be credited, and voiding
  # its last allowance returns it to issued), and {#fail_next} to inject a
  # one-shot failure for exercising error handling.
  class MockProvider < Provider
    attr_reader :capabilities

    # @param track [String] the 字軌 prefix (2 letters) for generated numbers
    # @param seq [Integer] deterministic start for generated invoice numbers
    # @param capabilities [Enumerable] restrict declared capabilities to simulate
    #   a specific provider profile; defaults to all
    def initialize(track: "MK", seq: 10_000_000, capabilities: Capability::ALL)
      super()
      @track = track
      @seq = seq
      @allowance_seq = 0
      @capabilities = Set.new(capabilities)
      @invoices = {}
      @by_order_id = {}
      # 折讓單號 => { invoice_number:, voided: }
      @allowances = {}
      @queued_failure = nil
    end

    def name
      "mock"
    end

    # Make the next operation raise +error+, then clear it — for exercising a
    # caller's handling of transport/provider failures the happy path never
    # produces (NETWORK, AUTH, NUMBER_EXHAUSTED, …).
    def fail_next(error)
      @queued_failure = error
    end

    def issue(input)
      check_failure!
      assert_supports!(Capability::ISSUE)
      parsed = Input.issue(input, provider: name)
      assert_currency_supported!(parsed.currency)
      assert_supports!(Capability::B2B) if parsed.resolved_category == InvoiceCategory::B2B
      tax_type = TaxType.of(parsed.items, parsed.tax_type)
      assert_supports!(Capability::MIXED_TAX) if tax_type == TaxType::MIXED
      fail!(ConflictError, "Order id already issued", Reason::DUPLICATE_ORDER) if @by_order_id.key?(parsed.order_id)

      invoice_number = next_invoice_number
      result = IssueInvoiceResult.new(
        invoice_number: invoice_number,
        invoice_datetime: Taipei.now,
        random_code: format("%04d", (@seq * 7) % 10_000),
        order_id: parsed.order_id,
        total_amount: parsed.amount.total_amount,
        buyer_ubn: parsed.buyer&.ubn,
        tax_type: tax_type,
        tax_rate: parsed.tax_rate,
        status: InvoiceStatus::ISSUED,
        raw: { mock: true }
      )
      @invoices[invoice_number] = { input: parsed, result: result, status: InvoiceStatus::ISSUED }
      @by_order_id[parsed.order_id] = invoice_number
      result
    end

    def void(input)
      check_failure!
      assert_supports!(Capability::VOID)
      parsed = Input.void(input, provider: name)
      stored = require_invoice(parsed.invoice.number)
      fail!(ConflictError, "Invoice already voided", Reason::ALREADY_VOIDED) if
        stored[:status] == InvoiceStatus::VOIDED
      fail!(ConflictError, "Void the invoice's allowances first", Reason::VOID_BLOCKED_BY_ALLOWANCE) if
        allowance_in_force?(parsed.invoice.number)

      stored[:status] = InvoiceStatus::VOIDED
      VoidInvoiceResult.new(invoice_number: parsed.invoice.number, status: InvoiceStatus::VOIDED,
                            cancel_datetime: Taipei.now, raw: { mock: true })
    end

    def allowance(input)
      check_failure!
      assert_supports!(Capability::ALLOWANCE)
      parsed = Input.allowance(input, provider: name)
      stored = require_invoice(parsed.invoice.number)
      # A voided invoice has nothing left to credit. Deliberately not
      # ALREADY_VOIDED: that one means "already in the state you asked for, treat
      # as success", which here would record a refund that never happened.
      fail!(ConflictError, "Cannot credit a voided invoice", Reason::ALLOWANCE_BLOCKED_BY_VOID) if
        stored[:status] == InvoiceStatus::VOIDED

      stored[:status] = InvoiceStatus::ALLOWANCE
      @allowance_seq += 1
      allowance_number = format("AL%08d", @allowance_seq)
      @allowances[allowance_number] = { invoice_number: parsed.invoice.number, voided: false }
      AllowanceResult.new(
        allowance_number: allowance_number,
        invoice_number: parsed.invoice.number,
        allowance_date: Taipei.today,
        total_amount: parsed.amount.total_amount,
        raw: { mock: true }
      )
    end

    def void_allowance(input)
      check_failure!
      assert_supports!(Capability::VOID_ALLOWANCE)
      parsed = Input.void_allowance(input, provider: name)
      allowance_number = parsed.allowance.allowance_number
      allowance = @allowances[allowance_number] || fail!(NotFoundError, "Allowance not found")
      fail!(ConflictError, "Allowance already voided", Reason::ALREADY_VOIDED) if allowance[:voided]

      allowance[:voided] = true
      invoice_number = allowance[:invoice_number]
      @invoices[invoice_number][:status] = InvoiceStatus::ISSUED unless allowance_in_force?(invoice_number)
      VoidAllowanceResult.new(allowance_number: allowance_number, cancel_datetime: Taipei.now,
                              raw: { mock: true })
    end

    def query(input)
      check_failure!
      assert_supports!(Capability::QUERY)
      parsed = Input.query(input, provider: name)
      reference = parsed.invoice
      assert_supports!(Capability::QUERY_BY_ORDER_ID) if reference.number.nil?
      invoice_number = reference.number || @by_order_id[reference.order_id]
      stored = invoice_number && @invoices[invoice_number]
      fail!(NotFoundError, "Invoice not found") unless stored

      QueryInvoiceResult.new(
        invoice_number: invoice_number,
        invoice_datetime: stored[:result].invoice_datetime,
        random_code: stored[:result].random_code,
        order_id: stored[:input].order_id,
        status: stored[:status],
        amount: stored[:input].amount,
        buyer: stored[:input].buyer,
        items: stored[:input].items,
        tax_type: stored[:result].tax_type,
        tax_rate: stored[:result].tax_rate,
        raw: { mock: true }
      )
    end

    # Every well-formed carrier counts as registered.
    def validate_carrier(carrier)
      check_failure!
      assert_supports!(Capability::CARRIER_VALIDATION)
      Input.carrier(carrier, provider: name)
      true
    end

    private

    def check_failure!
      return unless @queued_failure

      error = @queued_failure
      @queued_failure = nil
      raise error
    end

    def next_invoice_number
      n = @seq
      @seq += 1
      format("%s%08d", @track, n)
    end

    def allowance_in_force?(invoice_number)
      @allowances.each_value.any? { |a| a[:invoice_number] == invoice_number && !a[:voided] }
    end

    def require_invoice(invoice_number)
      @invoices[invoice_number] || fail!(NotFoundError, "Invoice not found")
    end

    # One raise site shape, so a missing reason is visible rather than incidental.
    def fail!(error_class, message, reason = nil)
      raise error_class.new(message, provider: name, reason: reason)
    end
  end
end
