# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoice::MockProvider do
  subject(:provider) { described_class.new }

  it_behaves_like "an invoice provider"

  # The same contract with only the five operations, so the "refuses unless it
  # declares it" side of each capability runs too.
  context "with only the five operations" do
    subject(:provider) do
      described_class.new(capabilities: [Einvoice::Capability::ISSUE, Einvoice::Capability::VOID,
                                         Einvoice::Capability::ALLOWANCE, Einvoice::Capability::VOID_ALLOWANCE,
                                         Einvoice::Capability::QUERY])
    end

    it_behaves_like "an invoice provider"
  end

  it "declares every capability by default" do
    expect(provider.capabilities).to eq(Set.new(Einvoice::Capability::ALL))
  end

  describe "capability gating" do
    it "rejects a non-TWD currency when FOREIGN_CURRENCY is not declared" do
      domestic = described_class.new(capabilities: Einvoice::Capability::ALL - [Einvoice::Capability::FOREIGN_CURRENCY])
      payload = {
        order_id: "O1", buyer: { email: "b@x.com" },
        items: [{ description: "x", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
        tax_type: "TAXABLE", price_mode: "TAX_INCLUSIVE", currency: "USD", exchange_rate: 31
      }
      expect { domestic.issue(payload) }.to raise_error(Einvoice::UnsupportedError)
    end
  end

  describe "#validate_carrier" do
    it "accepts a well-formed carrier" do
      expect(provider.validate_carrier({ type: "MOBILE_BARCODE", code: "/ABC1234" })).to be(true)
    end

    it "needs a carrier" do
      expect { provider.validate_carrier(nil) }.to raise_error(Einvoice::ValidationError, /carrier is required/)
    end
  end

  describe "#fail_next" do
    it "makes exactly the next operation raise the injected error, then clears" do
      provider.fail_next(Einvoice::NetworkError.new("boom", provider: "mock"))
      expect { provider.query({ invoice: { order_id: "whatever" } }) }.to raise_error(Einvoice::NetworkError)
      # cleared: the next call behaves normally (NotFound, not Network)
      expect { provider.query({ invoice: { order_id: "whatever" } }) }.to raise_error(Einvoice::NotFoundError)
    end
  end

  describe "state machine" do
    let(:issued) do
      provider.issue({
        order_id: "O1", buyer: { email: "b@x.com" },
        items: [{ description: "x", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
        tax_type: "TAXABLE", price_mode: "TAX_INCLUSIVE"
      })
    end

    it "returns references that carry the original document" do
      expect(issued.reference).to eq(Einvoice::InvoiceReference.new(
                                       number: issued.invoice_number, invoice_datetime: issued.invoice_datetime,
                                       random_code: issued.random_code, order_id: "O1", total_amount: 100,
                                       tax_type: Einvoice::TaxType::TAXABLE, tax_rate: Rational(5, 100)
                                     ))
      found = provider.query({ invoice: issued.invoice_number })
      expect(found.reference).to eq(issued.reference)
    end

    it "names and types its dates as the MIG does" do
      expect(issued.invoice_datetime.utc_offset).to eq(8 * 3600)
      allowance = provider.allowance({
        invoice: issued.reference, allowance_id: "A1",
        items: [{ description: "x", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }, price_mode: "TAX_INCLUSIVE"
      })
      expect(allowance.allowance_date).to be_a(Date)
      cancelled = provider.void_allowance({ allowance: allowance.reference })
      expect(cancelled.cancel_datetime.utc_offset).to eq(8 * 3600)
      voided = provider.void({ invoice: issued.reference, reason: "x" })
      expect(voided.cancel_datetime.utc_offset).to eq(8 * 3600)
    end

    it "reflects an allowance in a subsequent query" do
      provider.allowance({
        invoice: issued.reference, allowance_id: "A1",
        items: [{ description: "x", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }, price_mode: "TAX_INCLUSIVE"
      })
      expect(provider.query({ invoice: issued.reference }).status)
        .to eq(Einvoice::InvoiceStatus::ALLOWANCE)
    end

    it "refuses to credit a voided invoice" do
      provider.void({ invoice: issued.reference, reason: "x" })
      expect do
        provider.allowance({
          invoice: issued.reference, allowance_id: "A1",
          items: [{ description: "x", quantity: 1, unit_price: 100, amount: 100 }],
          amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }, price_mode: "TAX_INCLUSIVE"
        })
      end.to raise_error(Einvoice::ConflictError)
    end
  end

  # Every failure the mock raises should be as informative as a real adapter's,
  # since it is what callers write their error handling against.
  describe "the reasons it reports" do
    def issue!(order_id: "ORDER_1")
      provider.issue(
        order_id: order_id,
        buyer: { email: "b@x.com" },
        items: [{ description: "商品", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
        tax_type: "TAXABLE", price_mode: "TAX_INCLUSIVE"
      )
    end

    it "reports a second void as already voided" do
      issued = issue!
      provider.void({ invoice: issued.reference, reason: "x" })

      expect { provider.void({ invoice: issued.reference, reason: "x" }) }
        .to raise_error(Einvoice::ConflictError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::ALREADY_VOIDED)
        }
    end

    it "reports crediting a voided invoice as blocked, not as idempotent success" do
      issued = issue!
      provider.void({ invoice: issued.reference, reason: "x" })

      expect do
        provider.allowance(invoice: issued.reference, allowance_id: "AL_1",
                           items: [{ description: "商品", quantity: 1, unit_price: 50,
                                     amount: 50 }],
                           amount: { sales_amount: 48, tax_amount: 2, total_amount: 50 }, price_mode: "TAX_INCLUSIVE")
      end.to raise_error(Einvoice::ConflictError) { |error|
        # Not ALREADY_VOIDED: no credit was recorded, so "treat as success" —
        # what that reason instructs — would invent a refund.
        expect(error.reason).to eq(Einvoice::Reason::ALLOWANCE_BLOCKED_BY_VOID)
      }
    end

    it "tags every failure with the provider name" do
      expect { provider.query({ invoice: "NOPE00000000" }) }
        .to raise_error(Einvoice::NotFoundError) { |error|
          expect(error.provider).to eq("mock")
        }
    end
  end
end
