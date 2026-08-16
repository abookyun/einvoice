# frozen_string_literal: true

RSpec.describe Einvoice::ECPay::Provider do
  subject(:provider) do
    described_class.new(**Einvoice::ECPay::SANDBOX, base_url: FakeECPay::BASE_URL)
  end

  let!(:ecpay) { FakeECPay.new.install! }

  # The whole point of the adapter: it honours the same contract the mock does,
  # here over the real wire format — AES envelope, PHP url-encoding and ECPay's
  # own RtnCodes included.
  it_behaves_like "an invoice provider",
                  unknown_invoice_number: "ZZ00000000",
                  unknown_allowance_number: "9999999999999999"

  it "identifies itself and declares what it can do" do
    expect(provider.name).to eq("ecpay")
    expect(provider).to be_supports(Einvoice::Capability::B2B)
    expect(provider).to be_supports(Einvoice::Capability::QUERY_BY_ORDER_ID)
    expect(provider).to be_supports(Einvoice::Capability::CARRIER_VALIDATION)
  end

  # ECPay's B2C API has no foreign-currency field at all, so the capability is
  # deliberately absent and a non-TWD sale must fail loudly rather than be filed
  # as if it were TWD.
  it "does not claim foreign-currency support" do
    expect(provider).not_to be_supports(Einvoice::Capability::FOREIGN_CURRENCY)
  end

  def issue_input(overrides = {})
    {
      order_id: "ORDER_1",
      buyer: { email: "buyer@example.com" },
      items: [{ description: "咖啡拿鐵", quantity: 1, unit_price: 100, amount: 100 }],
      amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
      tax_type: "TAXABLE",
      price_mode: "TAX_INCLUSIVE",
      carrier: { type: "MEMBER" }
    }.merge(overrides)
  end

  describe "#issue" do
    it "sends the unified input as an ECPay Issue payload" do
      provider.issue(issue_input)

      expect(ecpay.path).to eq("/B2CInvoice/Issue")
      expect(ecpay.payload).to include(
        "MerchantID" => "2000132",
        "RelateNumber" => "ORDER_1",
        "CustomerEmail" => "buyer@example.com",
        "CarrierType" => "1",     # 綠界會員載具
        "TaxType" => "1",         # 應稅
        "InvType" => "07",        # 一般稅額
        "vat" => "1",             # 單價含稅
        "Print" => "0",           # carried invoices are electronic
        "Donation" => "0",
        "SalesAmount" => 100
      )
      expect(ecpay.payload["Items"]).to eq(
        [{ "ItemSeq" => 1, "ItemName" => "咖啡拿鐵", "ItemCount" => 1,
           "ItemWord" => "式", "ItemPrice" => 100, "ItemTaxType" => "1", "ItemAmount" => 100 }]
      )
    end

    it "returns the issued invoice number and random code" do
      result = provider.issue(issue_input)

      expect(result.invoice_number).to match(/\A[A-Z]{2}\d{8}\z/)
      expect(result.random_code).to match(/\A\d{4}\z/)
      expect(result.invoice_date).to be_a(Time)
      expect(result.status).to eq(Einvoice::InvoiceStatus::ISSUED)
    end

    it "maps a duplicate 自訂編號 to a conflict the caller can act on" do
      provider.issue(issue_input)

      expect { provider.issue(issue_input) }.to raise_error(Einvoice::ConflictError) do |error|
        expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
        expect(error.raw_code).to eq("5070357")
        expect(error.provider).to eq("ecpay")
      end
    end

    it "carries a 統一編號 as a B2B invoice" do
      provider.issue(issue_input(buyer: { ubn: "53538851", name: "測試公司", email: "b@x.com" }))

      expect(ecpay.payload).to include("CustomerIdentifier" => "53538851",
                                       "CustomerName" => "測試公司")
    end

    it "refuses a foreign-currency sale instead of filing it as TWD" do
      expect { provider.issue(issue_input(currency: "USD")) }
        .to raise_error(Einvoice::UnsupportedError, /foreign_currency/)
    end

    it "never reaches the network when the input is invalid" do
      expect { provider.issue(issue_input(items: [])) }.to raise_error(Einvoice::ValidationError)
      expect(ecpay.requests).to be_empty
    end
  end

  describe "#query" do
    it "looks up by 自訂編號 when given an order id" do
      provider.issue(issue_input(order_id: "ORDER_Q"))
      result = provider.query(order_id: "ORDER_Q")

      expect(ecpay.payload).to include("RelateNumber" => "ORDER_Q")
      expect(result.order_id).to eq("ORDER_Q")
      expect(result.amount.total_amount).to eq(100)
      expect(result.items.first.description).to eq("咖啡拿鐵")
    end

    it "pairs an invoice number with its issue date, as GetIssue requires" do
      issued = provider.issue(issue_input)
      provider.query(invoice_number: issued.invoice_number)

      expect(ecpay.payload).to include(
        "InvoiceNo" => issued.invoice_number,
        "InvoiceDate" => Time.now.getlocal("+08:00").strftime("%Y-%m-%d")
      )
    end

    it "accepts an explicit issue date for an older invoice" do
      issued = provider.issue(issue_input)
      expect do
        provider.query(invoice_number: issued.invoice_number,
                       provider_options: { invoice_date: "2020-01-01" })
      end.to raise_error(Einvoice::NotFoundError)

      expect(ecpay.payload).to include("InvoiceDate" => "2020-01-01")
    end

    it "reports a voided invoice as voided" do
      issued = provider.issue(issue_input)
      provider.void(invoice_number: issued.invoice_number, reason: "客戶取消")

      expect(provider.query(order_id: "ORDER_1").status).to eq(Einvoice::InvoiceStatus::VOIDED)
    end

    it "reports a credited invoice as having an allowance" do
      issued = provider.issue(issue_input)
      provider.allowance(invoice_number: issued.invoice_number, allowance_id: "AL_1",
                         items: [{ description: "咖啡拿鐵", quantity: 1, unit_price: 40,
                                   amount: 40 }],
                         amount: { sales_amount: 40, tax_amount: 0, total_amount: 40 })

      expect(provider.query(order_id: "ORDER_1").status)
        .to eq(Einvoice::InvoiceStatus::ALLOWANCE)
    end

    it "drops ECPay's zero placeholder for a B2C buyer's 統一編號" do
      provider.issue(issue_input)
      expect(provider.query(order_id: "ORDER_1").buyer.ubn).to be_nil
    end
  end

  describe "#void" do
    it "defaults the invoice date to today in Taipei" do
      issued = provider.issue(issue_input)
      provider.void(invoice_number: issued.invoice_number, reason: "客戶取消")

      expect(ecpay.payload).to include(
        "InvoiceNo" => issued.invoice_number,
        "InvoiceDate" => Time.now.getlocal("+08:00").strftime("%Y-%m-%d"),
        "Reason" => "客戶取消"
      )
    end

    it "flags a second void as already voided" do
      issued = provider.issue(issue_input)
      provider.void(invoice_number: issued.invoice_number, reason: "客戶取消")

      expect { provider.void(invoice_number: issued.invoice_number, reason: "客戶取消") }
        .to raise_error(Einvoice::ConflictError) { |e|
          expect(e.reason).to eq(Einvoice::Reason::ALREADY_VOIDED)
        }
    end

    it "tells the caller to void the allowance first" do
      issued = provider.issue(issue_input)
      provider.allowance(invoice_number: issued.invoice_number, allowance_id: "AL_1",
                         items: [{ description: "咖啡拿鐵", quantity: 1, unit_price: 40,
                                   amount: 40 }],
                         amount: { sales_amount: 40, tax_amount: 0, total_amount: 40 })

      expect { provider.void(invoice_number: issued.invoice_number, reason: "客戶取消") }
        .to raise_error(Einvoice::ConflictError) { |e|
          expect(e.reason).to eq(Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE)
        }
    end

    it "rejects a reason longer than ECPay's 20-character limit locally" do
      expect { provider.void(invoice_number: "LA25000001", reason: "超" * 21) }
        .to raise_error(Einvoice::ValidationError, /20 characters or fewer/)
      expect(ecpay.requests).to be_empty
    end

    it "raises NotFoundError for an unknown invoice" do
      expect { provider.void(invoice_number: "ZZ00000000", reason: "客戶取消") }
        .to raise_error(Einvoice::NotFoundError)
    end
  end

  describe "#allowance and #void_allowance" do
    let(:allowance_input) do
      {
        invoice_number: issued.invoice_number,
        allowance_id: "AL_1",
        items: [{ description: "咖啡拿鐵", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }
      }
    end
    let(:issued) { provider.issue(issue_input) }

    it "defaults to notifying nobody" do
      provider.allowance(allowance_input)
      expect(ecpay.payload).to include("AllowanceNotify" => "N", "AllowanceAmount" => 100)
    end

    it "passes notification settings through provider options" do
      provider.allowance(allowance_input.merge(
                           provider_options: { allowance_notify: "E",
                                               notify_mail: "buyer@example.com" }
                         ))

      expect(ecpay.payload).to include("AllowanceNotify" => "E",
                                       "NotifyMail" => "buyer@example.com")
    end

    it "returns the 折讓單號 and restores the credit when voided" do
      allowance = provider.allowance(allowance_input)
      expect(allowance.allowance_number).not_to be_empty
      expect(allowance.invoice_number).to eq(issued.invoice_number)

      provider.void_allowance(invoice_number: issued.invoice_number,
                              allowance_number: allowance.allowance_number)

      # With the allowance reversed the invoice is back to a plain issued state.
      expect(provider.query(order_id: "ORDER_1").status).to eq(Einvoice::InvoiceStatus::ISSUED)
    end

    it "flags voiding the same 折讓單 twice" do
      allowance = provider.allowance(allowance_input)
      void_input = { invoice_number: issued.invoice_number,
                     allowance_number: allowance.allowance_number }
      provider.void_allowance(void_input)

      expect { provider.void_allowance(void_input) }
        .to raise_error(Einvoice::ConflictError) { |e|
          expect(e.reason).to eq(Einvoice::Reason::ALREADY_VOIDED)
        }
    end

    it "raises NotFoundError for an unknown 折讓單" do
      expect do
        provider.void_allowance(invoice_number: issued.invoice_number,
                                allowance_number: "9999999999999999")
      end.to raise_error(Einvoice::NotFoundError)
    end
  end

  describe "carrier validation" do
    it "confirms a registered 手機條碼" do
      expect(provider.validate_mobile_barcode("/ABC1234")).to be(true)
      expect(ecpay.payload).to eq("MerchantID" => "2000132", "BarCode" => "/ABC1234")
    end

    it "reports an unregistered 手機條碼" do
      expect(provider.validate_mobile_barcode("/ZZZ9999")).to be(false)
    end

    it "rejects a malformed 手機條碼 without asking ECPay" do
      expect { provider.validate_mobile_barcode("ABC1234") }
        .to raise_error(Einvoice::ValidationError, /Invalid mobile barcode/)
      expect(ecpay.requests).to be_empty
    end

    it "resolves the organisation behind a 愛心碼" do
      expect(provider.love_code_organ_name("168001")).to eq("財團法人ＯＭＧ關懷社會愛心基金會")
      expect(provider.validate_love_code("168001")).to be(true)
    end

    it "reports an unregistered 愛心碼" do
      expect(provider.validate_love_code("999")).to be(false)
      expect(provider.love_code_organ_name("999")).to be_nil
    end

    it "rejects a malformed 愛心碼 without asking ECPay" do
      expect { provider.validate_love_code("12") }
        .to raise_error(Einvoice::ValidationError, /Invalid love code/)
    end
  end

  describe "#raw" do
    it "reaches an endpoint the adapter does not model, with the envelope applied" do
      expect { provider.raw("/B2CInvoice/InvoicePrint", { "InvoiceNo" => "LA25000001" }) }
        .to raise_error(Einvoice::Error)

      expect(ecpay.path).to eq("/B2CInvoice/InvoicePrint")
      expect(ecpay.payload).to include("InvoiceNo" => "LA25000001")
    end
  end

  describe "configuration" do
    it "targets the stage host by default" do
      client = described_class.new(**Einvoice::ECPay::SANDBOX).client
      expect(client.base_url).to eq("https://einvoice-stage.ecpay.com.tw")
    end

    it "targets the live host in production mode" do
      client = described_class.new(**Einvoice::ECPay::SANDBOX,
                                   mode: Einvoice::ProviderMode::PRODUCTION).client
      expect(client.base_url).to eq("https://einvoice.ecpay.com.tw")
    end

    it "rejects an unknown mode" do
      expect { described_class.new(**Einvoice::ECPay::SANDBOX, mode: :staging) }
        .to raise_error(Einvoice::ValidationError, /Unknown ECPay mode/)
    end

    it "can skip local payload validation for a field ECPay accepts but we reject" do
      lax = described_class.new(**Einvoice::ECPay::SANDBOX, base_url: FakeECPay::BASE_URL,
                                validate_payload: false)
      lax.issue(issue_input(amount: { sales_amount: 1, tax_amount: 0, total_amount: 1 },
                            items: [{ description: "x", quantity: 1, unit_price: 100,
                                      amount: 100 }]))

      expect(ecpay.payload).to include("SalesAmount" => 1)
    end
  end
end
