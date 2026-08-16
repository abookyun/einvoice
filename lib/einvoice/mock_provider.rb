# frozen_string_literal: true

require "set"

module Einvoice
  # In-memory {Provider} for tests and local development. It runs the same input
  # validation as a real adapter (via {Input}) but never hits the network, so
  # application code can be exercised end-to-end without credentials.
  #
  # It mirrors real-adapter behaviour beyond the happy path: capability gating (a
  # non-TWD currency is rejected unless FOREIGN_CURRENCY is declared), an
  # in-memory state machine (void/allowance respect the invoice's status), and
  # {#fail_next} to inject a one-shot failure for exercising error handling.
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
      @allowances = Set.new
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
      parsed = Input.issue(input, provider: name)
      assert_currency_supported!(parsed.currency)

      invoice_number = next_invoice_number
      result = IssueInvoiceResult.new(
        invoice_number: invoice_number,
        invoice_date: parsed.date || Time.now,
        random_code: format("%04d", (@seq * 7) % 10_000),
        order_id: parsed.order_id,
        total_amount: parsed.amount.total_amount,
        status: InvoiceStatus::ISSUED,
        raw: { mock: true }
      )
      @invoices[invoice_number] = { input: parsed, result: result, status: InvoiceStatus::ISSUED }
      @by_order_id[parsed.order_id] = invoice_number
      result
    end

    def void(input)
      check_failure!
      parsed = Input.void(input, provider: name)
      stored = require_invoice(parsed.invoice_number)
      if stored[:status] == InvoiceStatus::VOIDED
        raise ConflictError.new("Invoice already voided", provider: name,
                                reason: Reason::ALREADY_VOIDED)
      end

      stored[:status] = InvoiceStatus::VOIDED
      VoidInvoiceResult.new(invoice_number: parsed.invoice_number, status: InvoiceStatus::VOIDED,
                            raw: { mock: true })
    end

    def allowance(input)
      check_failure!
      parsed = Input.allowance(input, provider: name)
      stored = require_invoice(parsed.invoice_number)
      if stored[:status] == InvoiceStatus::VOIDED
        raise ConflictError.new("Cannot credit a voided invoice", provider: name)
      end

      stored[:status] = InvoiceStatus::ALLOWANCE
      @allowance_seq += 1
      allowance_number = format("AL%08d", @allowance_seq)
      @allowances << allowance_number
      AllowanceResult.new(
        allowance_number: allowance_number,
        invoice_number: parsed.invoice_number,
        allowance_date: parsed.date || Time.now,
        total_amount: parsed.amount.total_amount,
        raw: { mock: true }
      )
    end

    def void_allowance(input)
      check_failure!
      parsed = Input.void_allowance(input, provider: name)
      unless @allowances.include?(parsed.allowance_number)
        raise NotFoundError.new("Allowance not found", provider: name)
      end

      @allowances.delete(parsed.allowance_number)
      VoidAllowanceResult.new(allowance_number: parsed.allowance_number, raw: { mock: true })
    end

    def query(input)
      check_failure!
      parsed = Input.query(input, provider: name)
      invoice_number = parsed.invoice_number || (parsed.order_id && @by_order_id[parsed.order_id])
      stored = invoice_number && @invoices[invoice_number]
      raise NotFoundError.new("Invoice not found", provider: name) unless stored

      QueryInvoiceResult.new(
        invoice_number: invoice_number,
        invoice_date: stored[:result].invoice_date,
        random_code: stored[:result].random_code,
        order_id: stored[:input].order_id,
        status: stored[:status],
        amount: stored[:input].amount,
        buyer: stored[:input].buyer,
        items: stored[:input].items,
        raw: { mock: true }
      )
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

    def require_invoice(invoice_number)
      @invoices[invoice_number] || raise(NotFoundError.new("Invoice not found", provider: name))
    end
  end
end
