# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoice::MockProvider do
  subject(:provider) { described_class.new }

  it_behaves_like "an invoice provider"

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

  describe "#fail_next" do
    it "makes exactly the next operation raise the injected error, then clears" do
      provider.fail_next(Einvoice::NetworkError.new("boom", provider: "mock"))
      expect { provider.query({ order_id: "whatever" }) }.to raise_error(Einvoice::NetworkError)
      # cleared: the next call behaves normally (NotFound, not Network)
      expect { provider.query({ order_id: "whatever" }) }.to raise_error(Einvoice::NotFoundError)
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

    it "reflects an allowance in a subsequent query" do
      provider.allowance({
        invoice_number: issued.invoice_number, allowance_id: "A1",
        items: [{ description: "x", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }
      })
      expect(provider.query({ invoice_number: issued.invoice_number }).status)
        .to eq(Einvoice::InvoiceStatus::ALLOWANCE)
    end

    it "refuses to credit a voided invoice" do
      provider.void({ invoice_number: issued.invoice_number, reason: "x" })
      expect do
        provider.allowance({
          invoice_number: issued.invoice_number, allowance_id: "A1",
          items: [{ description: "x", quantity: 1, unit_price: 100, amount: 100 }],
          amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }
        })
      end.to raise_error(Einvoice::ConflictError)
    end
  end
end
