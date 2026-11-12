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
#   unknown_reference: a Hash of InvoiceReference fields for an invoice that
#     does not exist at the provider. It has to carry every field the provider
#     needs to query by number, and a number that is well-formed there: real
#     APIs check both before they look anything up, so a reference that misses
#     either fails as invalid, not missing. The default has a number and
#     today's date, which is what ECPay needs. ezPay adds a random_code.
#   unknown_allowance_number: the same, for a 折讓單號.
RSpec.shared_examples "an invoice provider" do |options = {}|
  unknown_reference = options.fetch(:unknown_reference, { number: "NOPE00000000",
                                                          invoice_datetime: Einvoice::Taipei.today.iso8601 })
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
      expect(result.random_code).to match(/\A\d{4}\z/)
      expect(result.invoice_datetime).to be_a(Time)
      expect(result.reference).to have_attributes(number: result.invoice_number, tax_type: Einvoice::TaxType::TAXABLE,
                                                  tax_rate: Rational(5, 100))
    end

    it "refuses a second invoice for the same order id" do
      provider.issue(issue_payload(order_id: "ORDER_DUP"))
      expect { provider.issue(issue_payload(order_id: "ORDER_DUP")) }
        .to raise_error(Einvoice::ConflictError) { |error| expect(error.provider).to eq(provider.name) }
    end

    it "raises a ValidationError (never a raw error) on invalid input" do
      expect { provider.issue(issue_payload(items: [])) }
        .to raise_error(Einvoice::ValidationError)
    end
  end

  describe "#query" do
    it "finds an issued invoice by its number" do
      issued = provider.issue(issue_payload(order_id: "ORDER_Q"))
      found = provider.query({ invoice: issued.reference })
      expect(found).to be_a(Einvoice::QueryInvoiceResult)
      expect(found.invoice_number).to eq(issued.invoice_number)
      expect(found.amount.total_amount).to eq(100)
    end

    it "finds an issued invoice by order id when supported" do
      skip "no QUERY_BY_ORDER_ID" unless provider.supports?(Einvoice::Capability::QUERY_BY_ORDER_ID)
      provider.issue(issue_payload(order_id: "ORDER_BYID"))
      found = provider.query({ invoice: { order_id: "ORDER_BYID" } })
      expect(found.order_id).to eq("ORDER_BYID")
    end

    it "raises NotFoundError for an unknown invoice" do
      expect { provider.query({ invoice: unknown_reference }) }
        .to raise_error(Einvoice::NotFoundError)
    end
  end

  describe "#void" do
    it "transitions the invoice to VOIDED" do
      issued = provider.issue(issue_payload(order_id: "ORDER_V"))
      result = provider.void({ invoice: issued.reference, reason: "客戶取消" })
      expect(result).to be_a(Einvoice::VoidInvoiceResult)
      expect(result.status).to eq(Einvoice::InvoiceStatus::VOIDED)
      # nil is allowed: a provider may not be able to tell.
      expect(provider.query({ invoice: issued.reference }).status)
        .to eq(Einvoice::InvoiceStatus::VOIDED).or be_nil
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

    b2b = { buyer: { ubn: "53538851", name: "測試股份有限公司", email: "b@x.com" },
            amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 } }
    mixed = {
      items: [{ description: "商品一", quantity: 1, unit_price: 50, amount: 50, tax_type: "TAXABLE" },
              { description: "商品二", quantity: 1, unit_price: 50, amount: 50, tax_type: "TAX_FREE" }]
    }
    {
      Einvoice::Capability::B2B => ->(spec) { spec.provider.issue(spec.issue_payload(order_id: "ORDER_B2B", **b2b)) },
      Einvoice::Capability::MIXED_TAX => lambda { |spec|
        spec.provider.issue(spec.issue_payload(order_id: "ORDER_MIX", **mixed))
      },
      Einvoice::Capability::QUERY_BY_ORDER_ID => lambda { |spec|
        spec.provider.issue(spec.issue_payload(order_id: "ORDER_QBO"))
        spec.provider.query({ invoice: { order_id: "ORDER_QBO" } })
      },
      Einvoice::Capability::CARRIER_VALIDATION => lambda { |spec|
        spec.provider.validate_carrier({ type: "MOBILE_BARCODE", code: "/ABC1234" })
      }
    }.each do |capability, call|
      it "refuses #{capability} unless it declares it" do
        skip "declares #{capability}" if provider.supports?(capability)

        expect { call.call(self) }.to raise_error(Einvoice::UnsupportedError)
      end

      it "does #{capability} when it declares it" do
        skip "no #{capability}" unless provider.supports?(capability)

        expect { call.call(self) }.not_to raise_error
      end
    end
  end

  # State conflicts are the errors callers branch on most, so every provider has
  # to agree on the class. The finer `reason` is deliberately not asserted: it is
  # documented as nil when an adapter cannot determine one.
  describe "operations that conflict with the invoice's state" do
    def credit(issued, allowance_id)
      provider.allowance({
        invoice: issued.reference,
        allowance_id: allowance_id,
        items: [{ description: "商品一", quantity: 1, unit_price: 40, amount: 40 }],
        amount: { sales_amount: 38, tax_amount: 2, total_amount: 40 },
        price_mode: "TAX_INCLUSIVE"
      })
    end

    it "refuses to void an invoice with an allowance in force" do
      skip "no ALLOWANCE" unless provider.supports?(Einvoice::Capability::ALLOWANCE)

      issued = provider.issue(issue_payload(order_id: "ORDER_VA"))
      credit(issued, "AL_VA")

      expect { provider.void({ invoice: issued.reference, reason: "客戶取消" }) }
        .to raise_error(Einvoice::ConflictError)
    end

    it "voids the invoice once its allowance is voided, and reads it back as issued" do
      skip "no VOID_ALLOWANCE" unless provider.supports?(Einvoice::Capability::VOID_ALLOWANCE)

      issued = provider.issue(issue_payload(order_id: "ORDER_VAV"))
      provider.void_allowance({ allowance: credit(issued, "AL_VAV").reference })

      expect(provider.query({ invoice: issued.reference }).status)
        .to eq(Einvoice::InvoiceStatus::ISSUED).or be_nil
      expect(provider.void({ invoice: issued.reference, reason: "客戶取消" }).status)
        .to eq(Einvoice::InvoiceStatus::VOIDED)
    end

    it "refuses to void the same allowance twice" do
      skip "no VOID_ALLOWANCE" unless provider.supports?(Einvoice::Capability::VOID_ALLOWANCE)

      issued = provider.issue(issue_payload(order_id: "ORDER_AA"))
      allowance = credit(issued, "AL_AA")
      provider.void_allowance({ allowance: allowance.reference })

      expect { provider.void_allowance({ allowance: allowance.reference }) }
        .to raise_error(Einvoice::ConflictError)
    end

    it "refuses to void the same invoice twice" do
      skip "no VOID" unless provider.supports?(Einvoice::Capability::VOID)

      issued = provider.issue(issue_payload(order_id: "ORDER_VV"))
      provider.void({ invoice: issued.reference, reason: "客戶取消" })

      expect { provider.void({ invoice: issued.reference, reason: "客戶取消" }) }
        .to raise_error(Einvoice::ConflictError)
    end

    it "refuses to credit a voided invoice" do
      skip "no ALLOWANCE" unless provider.supports?(Einvoice::Capability::ALLOWANCE)

      issued = provider.issue(issue_payload(order_id: "ORDER_AV"))
      provider.void({ invoice: issued.reference, reason: "客戶取消" })

      expect do
        provider.allowance({
          invoice: issued.reference,
          allowance_id: "AL_AV",
          items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
          amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
          price_mode: "TAX_INCLUSIVE"
        })
      end.to raise_error(Einvoice::ConflictError)
    end
  end

  describe "#allowance / #void_allowance" do
    it "credits an invoice and then cancels the allowance" do
      issued = provider.issue(issue_payload(order_id: "ORDER_AL"))
      allowance = provider.allowance({
        invoice: issued.reference,
        allowance_id: "AL_1",
        items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
        price_mode: "TAX_INCLUSIVE"
      })
      expect(allowance).to be_a(Einvoice::AllowanceResult)
      expect(allowance.allowance_number).to be_a(String)
      expect(allowance.allowance_date).to be_a(Date)
      expect(provider.query({ invoice: issued.reference }).status)
        .to eq(Einvoice::InvoiceStatus::ALLOWANCE).or be_nil

      cancelled = provider.void_allowance({ allowance: allowance.reference })
      expect(cancelled).to be_a(Einvoice::VoidAllowanceResult)
      expect(cancelled.allowance_number).to eq(allowance.allowance_number)
    end

    # The same guarantee #query makes for an unknown invoice: a reference that
    # does not exist is NotFoundError, not some provider-specific error class.
    it "raises NotFoundError for an unknown allowance" do
      skip "no VOID_ALLOWANCE" unless provider.supports?(Einvoice::Capability::VOID_ALLOWANCE)

      issued = provider.issue(issue_payload(order_id: "ORDER_UA"))
      expect do
        provider.void_allowance({ allowance: { allowance_number: unknown_allowance_number,
                                               invoice_number: issued.invoice_number } })
      end.to raise_error(Einvoice::NotFoundError)
    end
  end
end
