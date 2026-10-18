# frozen_string_literal: true

RSpec.describe Einvoice::Amego::Provider do
  subject(:provider) { described_class.new(**FakeAmego::CREDENTIALS) }

  let!(:amego) { FakeAmego.new.install! }

  # The contract runs without provider_options: an allowance queries the
  # invoice for its buyer and date.
  it_behaves_like "an invoice provider", unknown_invoice_number: "ZZ00000000"
end

RSpec.describe Einvoice::Amego::Provider, "adapter details" do
  subject(:provider) { described_class.new(**FakeAmego::CREDENTIALS) }

  let!(:amego) { FakeAmego.new.install! }

  let(:issue_input) do
    { order_id: "ORDER_1", buyer: { name: "王小明", email: "b@x.com", phone: "0912345678" },
      items: [{ description: "商品一", quantity: 2, unit_price: 50, amount: 100, unit: "個", remark: "備註" }],
      amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
      tax_type: "TAXABLE", price_mode: "TAX_INCLUSIVE", carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" } }
  end

  def credit(issued, **extra)
    provider.allowance({ invoice_number: issued.invoice_number, allowance_id: "AL_X",
                         items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
                         amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }, **extra })
  end

  it "identifies itself and declares what it can do" do
    expect(provider.name).to eq("amego")
    expect(provider).to be_supports(Einvoice::Capability::B2B)
    expect(provider).to be_supports(Einvoice::Capability::MIXED_TAX)
    expect(provider).to be_supports(Einvoice::Capability::QUERY_BY_ORDER_ID)
    expect(provider).not_to be_supports(Einvoice::Capability::FOREIGN_CURRENCY)
    expect(provider).not_to be_supports(Einvoice::Capability::SCHEDULED_ISSUE)
  end

  it "uses the published test account by default host" do
    expect(described_class.new(**Einvoice::Amego::SANDBOX).client.endpoint).to eq("https://invoice-api.amego.tw")
  end

  describe "#issue" do
    it "reads the number, the time and the random code" do
      result = provider.issue(issue_input)

      expect(amego.path).to eq("/json/f0401")
      expect(result.invoice_number).to match(/\AAB\d{8}\z/)
      expect(result.random_code).to match(/\A\d{4}\z/)
      expect(result.invoice_date).to be_a(Time)
      expect(result.invoice_date.utc_offset).to eq(8 * 3600)
      expect(result.raw["code"]).to eq(0)
    end

    it "maps a duplicate order id to a ConflictError" do
      provider.issue(issue_input)
      expect { provider.issue(issue_input) }.to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
      }
    end
  end

  describe "#query" do
    it "maps the invoice back to the unified model" do
      issued = provider.issue(issue_input)
      found = provider.query({ order_id: "ORDER_1" })

      expect(amego.data).to eq("type" => "order", "order_id" => "ORDER_1")
      expect(found).to have_attributes(invoice_number: issued.invoice_number, random_code: issued.random_code,
                                       order_id: "ORDER_1", status: Einvoice::InvoiceStatus::ISSUED)
      expect(found.invoice_date).to be_a(Time)
      expect(found.amount).to eq(Einvoice::AmountSummary.new(sales_amount: 100, tax_amount: 0, total_amount: 100))
      expect(found.buyer).to have_attributes(name: "王小明", ubn: nil, email: "b@x.com", phone: "0912345678")
      expect(found.items.first).to have_attributes(description: "商品一", quantity: 2, unit_price: 50, amount: 100,
                                                   unit: "個", remark: "備註",
                                                   tax_type: Einvoice::TaxType::TAXABLE)
    end

    it "reports ALLOWANCE while an allowance is live, and VOIDED after a void" do
      issued = provider.issue(issue_input)
      credit(issued)
      expect(provider.query({ invoice_number: issued.invoice_number }).status).to eq(Einvoice::InvoiceStatus::ALLOWANCE)

      provider.void_allowance({ invoice_number: issued.invoice_number, allowance_number: "AL_X" })
      expect(provider.query({ invoice_number: issued.invoice_number }).status).to eq(Einvoice::InvoiceStatus::ISSUED)

      provider.void({ invoice_number: issued.invoice_number, reason: "取消" })
      expect(provider.query({ invoice_number: issued.invoice_number }).status).to eq(Einvoice::InvoiceStatus::VOIDED)
    end

    it "gives no status to a cancelled (註銷) invoice" do
      issued = provider.issue(issue_input)
      amego.invoice(issued.invoice_number)["type"] = "C0701"
      expect(provider.query({ invoice_number: issued.invoice_number }).status).to be_nil
    end

    it "keeps a decimal quantity" do
      provider.issue(issue_input.merge(items: [{ description: "a", quantity: 1.5, unit_price: 100, amount: 150 }],
                                       amount: { sales_amount: 150, tax_amount: 0, total_amount: 150 }))
      expect(provider.query({ order_id: "ORDER_1" }).items.first.quantity).to eq(1.5)
    end

    it "raises ProviderError when the answer has no data" do
      stub_request(:post, "#{FakeAmego::BASE_URL}/json/invoice_query")
        .to_return(body: JSON.generate("code" => 0, "msg" => ""))
      expect { provider.query({ invoice_number: "AB12345678" }) }.to raise_error(Einvoice::ProviderError, /no invoice/)
    end
  end

  describe "#allowance" do
    it "queries the invoice for its buyer and date" do
      issued = provider.issue(issue_input)
      result = credit(issued)

      expect(amego.path(-2)).to eq("/json/invoice_query")
      expect(amego.path).to eq("/json/g0401")
      expect(amego.data.first).to include("BuyerIdentifier" => "0000000000", "BuyerName" => "王小明")
      expect(result).to have_attributes(allowance_number: "AL_X", invoice_number: issued.invoice_number,
                                        total_amount: 100)
      expect(result.allowance_date).to be_a(Time)
    end

    it "skips the query when provider_options gives the buyer and the date" do
      issued = provider.issue(issue_input)
      date = issued.invoice_date.strftime("%Y%m%d")
      credit(issued, provider_options: { buyer_identifier: "0000000000", buyer_name: "王小明", invoice_date: date,
                                         allowance_date: "20991231" })

      expect(amego.requests.map { |r| r[:path] }).to eq(%w[/json/f0401 /json/g0401])
      expect(amego.data.first["AllowanceDate"]).to eq("20991231")
    end

    it "maps a reused allowance number to a ConflictError" do
      issued = provider.issue(issue_input.merge(amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }))
      credit(issued, amount: { sales_amount: 10, tax_amount: 0, total_amount: 10 },
                     items: [{ description: "a", quantity: 1, unit_price: 10, amount: 10 }])
      expect do
        credit(issued, amount: { sales_amount: 10, tax_amount: 0, total_amount: 10 },
                       items: [{ description: "a", quantity: 1, unit_price: 10, amount: 10 }])
      end.to raise_error(Einvoice::ConflictError) { |error| expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ALLOWANCE) }
    end
  end

  it "refuses to void an invoice with a live allowance" do
    issued = provider.issue(issue_input)
    credit(issued)
    expect { provider.void({ invoice_number: issued.invoice_number, reason: "取消" }) }
      .to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE)
      }
  end

  it "reaches other endpoints through #raw" do
    stub_request(:post, "#{FakeAmego::BASE_URL}/json/barcode").to_return(body: JSON.generate("code" => 0, "msg" => ""))
    expect(provider.raw("/json/barcode", { barCode: "/ABC1234" })).to eq("code" => 0, "msg" => "")
  end
end
