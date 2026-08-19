# frozen_string_literal: true

# The executable contract for {Einvoice::Provider}. Every provider — the mock
# and each real adapter — includes it to prove it honours the unified model:
# the five operations return the right value types and statuses, and failures
# surface as Einvoice::Error subclasses, not provider-specific ones.
#
# The host group must supply `let(:provider)` (a fresh instance). Capability-
# dependent expectations are guarded by `provider.supports?`, so a partial
# adapter only gets held to what it declares.
#
# Options:
#   unknown_invoice_number: a number that is well-formed for the provider but
#     does not exist there. Real APIs check the shape before they look anything
#     up, so an adapter whose numbers have a fixed format must supply one that
#     passes that check — otherwise the lookup fails as invalid, not missing.
#   unknown_allowance_number: the same, for a 折讓單號.
RSpec.shared_examples "an invoice provider" do |options = {}|
  unknown_invoice_number = options.fetch(:unknown_invoice_number, "NOPE00000000")
  unknown_allowance_number = options.fetch(:unknown_allowance_number, "NOPE00000000")

  def issue_payload(order_id: "ORDER_1", **overrides)
    {
      order_id: order_id,
      buyer: { email: "b@x.com" },
      items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
      amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
      tax_type: "TAXABLE",
      price_mode: "TAX_INCLUSIVE",
      carrier: { type: "MEMBER" }
    }.merge(overrides)
  end

  it "declares a stable name and a capability set" do
    expect(provider.name).to be_a(String)
    expect(provider.capabilities).to all(be_a(Symbol))
  end

  describe "#issue" do
    it "returns an IssueInvoiceResult marked ISSUED, echoing the order id" do
      result = provider.issue(issue_payload(order_id: "ORDER_A"))
      expect(result).to be_a(Einvoice::IssueInvoiceResult)
      expect(result.invoice_number).to be_a(String)
      expect(result.status).to eq(Einvoice::InvoiceStatus::ISSUED)
      expect(result.order_id).to eq("ORDER_A")
      expect(result.total_amount).to eq(100)
    end

    it "raises a ValidationError (never a raw error) on invalid input" do
      expect { provider.issue(issue_payload(items: [])) }
        .to raise_error(Einvoice::ValidationError)
    end
  end

  describe "#query" do
    it "finds an issued invoice by its number" do
      issued = provider.issue(issue_payload(order_id: "ORDER_Q"))
      found = provider.query({ invoice_number: issued.invoice_number })
      expect(found).to be_a(Einvoice::QueryInvoiceResult)
      expect(found.invoice_number).to eq(issued.invoice_number)
      expect(found.amount.total_amount).to eq(100)
    end

    it "finds an issued invoice by order id when supported" do
      skip "no QUERY_BY_ORDER_ID" unless provider.supports?(Einvoice::Capability::QUERY_BY_ORDER_ID)
      provider.issue(issue_payload(order_id: "ORDER_BYID"))
      found = provider.query({ order_id: "ORDER_BYID" })
      expect(found.order_id).to eq("ORDER_BYID")
    end

    it "raises NotFoundError for an unknown invoice" do
      expect { provider.query({ invoice_number: unknown_invoice_number }) }
        .to raise_error(Einvoice::NotFoundError)
    end
  end

  describe "#void" do
    it "transitions the invoice to VOIDED" do
      issued = provider.issue(issue_payload(order_id: "ORDER_V"))
      result = provider.void({ invoice_number: issued.invoice_number, reason: "客戶取消" })
      expect(result).to be_a(Einvoice::VoidInvoiceResult)
      expect(result.status).to eq(Einvoice::InvoiceStatus::VOIDED)
    end
  end

  # A capability is a promise about behaviour, so the contract has to hold a
  # provider to it in both directions: declaring one means the feature works,
  # and not declaring it means the request is refused rather than quietly
  # mishandled. Without these, an adapter can skip its gating entirely — or
  # disagree with every other adapter about which error a state conflict is —
  # and still pass "the contract".
  describe "capability gating" do
    it "refuses a foreign-currency sale unless it declares FOREIGN_CURRENCY" do
      skip "declares FOREIGN_CURRENCY" if provider.supports?(Einvoice::Capability::FOREIGN_CURRENCY)

      expect { provider.issue(issue_payload(order_id: "ORDER_FX", currency: "USD")) }
        .to raise_error(Einvoice::UnsupportedError)
    end

    it "accepts a foreign-currency sale when it does" do
      skip "no FOREIGN_CURRENCY" unless provider.supports?(Einvoice::Capability::FOREIGN_CURRENCY)

      result = provider.issue(issue_payload(order_id: "ORDER_FX2", currency: "USD"))
      expect(result).to be_a(Einvoice::IssueInvoiceResult)
    end
  end

  # State conflicts are the errors callers branch on most, so every provider has
  # to agree on the class. The finer `reason` is deliberately not asserted: it is
  # documented as nil when an adapter cannot determine one.
  describe "operations that conflict with the invoice's state" do
    it "refuses to void the same invoice twice" do
      skip "no VOID" unless provider.supports?(Einvoice::Capability::VOID)

      issued = provider.issue(issue_payload(order_id: "ORDER_VV"))
      provider.void({ invoice_number: issued.invoice_number, reason: "客戶取消" })

      expect { provider.void({ invoice_number: issued.invoice_number, reason: "客戶取消" }) }
        .to raise_error(Einvoice::ConflictError)
    end

    it "refuses to credit a voided invoice" do
      skip "no ALLOWANCE" unless provider.supports?(Einvoice::Capability::ALLOWANCE)

      issued = provider.issue(issue_payload(order_id: "ORDER_AV"))
      provider.void({ invoice_number: issued.invoice_number, reason: "客戶取消" })

      expect do
        provider.allowance({
          invoice_number: issued.invoice_number,
          allowance_id: "AL_AV",
          items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
          amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }
        })
      end.to raise_error(Einvoice::ConflictError)
    end
  end

  describe "#allowance / #void_allowance" do
    it "credits an invoice and then cancels the allowance" do
      issued = provider.issue(issue_payload(order_id: "ORDER_AL"))
      allowance = provider.allowance({
        invoice_number: issued.invoice_number,
        allowance_id: "AL_1",
        items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }
      })
      expect(allowance).to be_a(Einvoice::AllowanceResult)
      expect(allowance.allowance_number).to be_a(String)

      cancelled = provider.void_allowance({
        invoice_number: issued.invoice_number,
        allowance_number: allowance.allowance_number
      })
      expect(cancelled).to be_a(Einvoice::VoidAllowanceResult)
      expect(cancelled.allowance_number).to eq(allowance.allowance_number)
    end

    # The same guarantee #query makes for an unknown invoice: a reference that
    # does not exist is NotFoundError, not some provider-specific error class.
    it "raises NotFoundError for an unknown allowance" do
      skip "no VOID_ALLOWANCE" unless provider.supports?(Einvoice::Capability::VOID_ALLOWANCE)

      issued = provider.issue(issue_payload(order_id: "ORDER_UA"))
      expect do
        provider.void_allowance({ invoice_number: issued.invoice_number,
                                  allowance_number: unknown_allowance_number })
      end.to raise_error(Einvoice::NotFoundError)
    end
  end
end
