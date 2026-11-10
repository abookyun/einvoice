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
                  unknown_reference: { number: "ZZ00000000", invoice_datetime: Einvoice::Taipei.today.iso8601 },
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
      expect(result.invoice_datetime).to be_a(Time)
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
      provider.issue(issue_input(buyer: { ubn: "53538851", name: "測試公司", email: "b@x.com" },
                                 amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }))

      expect(ecpay.payload).to include("CustomerIdentifier" => "53538851",
                                       "CustomerName" => "測試公司")
    end

    it "refuses a foreign-currency sale instead of filing it as TWD" do
      expect { provider.issue(issue_input(currency: "USD")) }
        .to raise_error(Einvoice::UnsupportedError, /foreign_currency/)
    end

    it "refuses a taxable rate other than 5%" do
      expect { provider.issue(issue_input(tax_rate: 0.01)) }
        .to raise_error(Einvoice::UnsupportedError, /0.05 only/)
      expect(ecpay.requests).to be_empty
    end

    it "never reaches the network when the input is invalid" do
      expect { provider.issue(issue_input(items: [])) }.to raise_error(Einvoice::ValidationError)
      expect(ecpay.requests).to be_empty
    end
  end

  describe "#query" do
    it "looks up by 自訂編號 when the reference has an order id" do
      provider.issue(issue_input(order_id: "ORDER_Q"))
      result = provider.query(invoice: { order_id: "ORDER_Q" })

      expect(ecpay.payload).to include("RelateNumber" => "ORDER_Q")
      expect(result.order_id).to eq("ORDER_Q")
      expect(result.amount.total_amount).to eq(100)
      expect(result.items.first.description).to eq("咖啡拿鐵")
    end

    it "pairs an invoice number with its issue date, as GetIssue requires" do
      issued = provider.issue(issue_input)
      provider.query(invoice: { number: issued.invoice_number, invoice_datetime: issued.invoice_datetime })

      expect(ecpay.payload).to include(
        "InvoiceNo" => issued.invoice_number,
        "InvoiceDate" => issued.invoice_datetime.strftime("%Y-%m-%d")
      )
    end

    it "needs the issue date to query by number" do
      expect { provider.query(invoice: "LA25000001") }
        .to raise_error(Einvoice::ValidationError, /invoice.invoice_datetime/)
      expect(ecpay.requests).to be_empty
    end

    it "does not find an invoice under another date" do
      issued = provider.issue(issue_input)
      expect do
        provider.query(invoice: { number: issued.invoice_number, invoice_datetime: Date.new(2020, 1, 1) })
      end.to raise_error(Einvoice::NotFoundError)

      expect(ecpay.payload).to include("InvoiceDate" => "2020-01-01")
    end

    it "reports a voided invoice as voided" do
      issued = provider.issue(issue_input)
      provider.void(invoice: issued.reference, reason: "客戶取消")

      expect(provider.query(invoice: issued.reference).status).to eq(Einvoice::InvoiceStatus::VOIDED)
    end

    it "reports a credited invoice as having an allowance" do
      issued = provider.issue(issue_input)
      provider.allowance(invoice: issued.reference, allowance_id: "AL_1",
                         items: [{ description: "咖啡拿鐵", quantity: 1, unit_price: 40,
                                   amount: 40 }],
                         amount: { sales_amount: 38, tax_amount: 2, total_amount: 40 }, price_mode: "TAX_INCLUSIVE")

      expect(provider.query(invoice: issued.reference).status)
        .to eq(Einvoice::InvoiceStatus::ALLOWANCE)
    end

    it "reads a cancelled (註銷) invoice as status nil" do
      issued = provider.issue(issue_input)
      ecpay.cancel!(issued.invoice_number)

      expect(provider.query(invoice: issued.reference).status).to be_nil
    end

    it "drops ECPay's zero placeholder for a B2C buyer's 統一編號" do
      issued = provider.issue(issue_input)
      found = provider.query(invoice: issued.reference)
      expect(found.buyer.ubn).to be_nil
      expect(found.reference).to eq(issued.reference)
    end
  end

  describe "#void" do
    it "sends the issue date of the reference" do
      issued = provider.issue(issue_input)
      provider.void(invoice: issued.reference, reason: "客戶取消")

      expect(ecpay.payload).to include(
        "InvoiceNo" => issued.invoice_number,
        "InvoiceDate" => issued.invoice_datetime.strftime("%Y-%m-%d"),
        "Reason" => "客戶取消"
      )
    end

    it "keeps the calendar day of a Date on a host east of UTC+8" do
      original = ENV.fetch("TZ", nil)
      ENV["TZ"] = "Asia/Tokyo"
      issued = provider.issue(issue_input)
      day = Einvoice::Taipei.date(issued.invoice_datetime)
      provider.void(invoice: { number: issued.invoice_number, invoice_datetime: day }, reason: "客戶取消")

      expect(ecpay.payload).to include("InvoiceDate" => day.strftime("%Y-%m-%d"))
    ensure
      ENV["TZ"] = original
    end

    it "looks the issue date up by order id when the reference has none" do
      issued = provider.issue(issue_input)
      provider.void(invoice: { number: issued.invoice_number, order_id: "ORDER_1" }, reason: "客戶取消")

      expect(ecpay.path(-2)).to eq("/B2CInvoice/GetIssue")
      expect(ecpay.payload(-2)).to include("RelateNumber" => "ORDER_1")
      expect(ecpay.payload).to include("InvoiceDate" => issued.invoice_datetime.strftime("%Y-%m-%d"))
    end

    it "reports a failed lookup as the provider's error, not a missing invoice" do
      expect { provider.void(invoice: { number: "LA25000001", order_id: "NO_SUCH" }, reason: "客戶取消") }
        .to raise_error(Einvoice::ProviderError) { |e|
          expect(e.reason).to eq(Einvoice::Reason::LOOKUP_FAILED)
          expect(e.cause).to be_a(Einvoice::NotFoundError)
          expect(e.message).to match(/void needs invoice.invoice_datetime/)
        }
    end

    it "does not guess the issue date of a plain number" do
      expect { provider.void(invoice: "LA25000001", reason: "客戶取消") }
        .to raise_error(Einvoice::ValidationError, /void needs invoice.invoice_datetime/)
      expect(ecpay.requests).to be_empty
    end

    it "flags a second void as already voided" do
      issued = provider.issue(issue_input)
      provider.void(invoice: issued.reference, reason: "客戶取消")

      expect { provider.void(invoice: issued.reference, reason: "客戶取消") }
        .to raise_error(Einvoice::ConflictError) { |e|
          expect(e.reason).to eq(Einvoice::Reason::ALREADY_VOIDED)
        }
    end

    it "tells the caller to void the allowance first" do
      issued = provider.issue(issue_input)
      provider.allowance(invoice: issued.reference, allowance_id: "AL_1",
                         items: [{ description: "咖啡拿鐵", quantity: 1, unit_price: 40,
                                   amount: 40 }],
                         amount: { sales_amount: 38, tax_amount: 2, total_amount: 40 }, price_mode: "TAX_INCLUSIVE")

      expect { provider.void(invoice: issued.reference, reason: "客戶取消") }
        .to raise_error(Einvoice::ConflictError) { |e|
          expect(e.reason).to eq(Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE)
        }
    end

    it "rejects a reason longer than 20 characters locally" do
      expect { provider.void(invoice: "LA25000001", reason: "超" * 21) }
        .to raise_error(Einvoice::ValidationError, /20 characters or fewer/)
      expect(ecpay.requests).to be_empty
    end

    it "raises NotFoundError for an unknown invoice" do
      expect { provider.void(invoice: { number: "ZZ00000000", invoice_datetime: Time.now }, reason: "客戶取消") }
        .to raise_error(Einvoice::NotFoundError)
    end
  end

  describe "#allowance and #void_allowance" do
    let(:allowance_input) do
      {
        invoice: issued.reference,
        allowance_id: "AL_1",
        items: [{ description: "咖啡拿鐵", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }, price_mode: "TAX_INCLUSIVE"
      }
    end
    let(:issued) { provider.issue(issue_input) }

    it "defaults to notifying nobody" do
      provider.allowance(allowance_input)
      expect(ecpay.payload).to include("AllowanceNotify" => "N", "AllowanceAmount" => 100,
                                       "InvoiceDate" => issued.invoice_datetime.strftime("%Y-%m-%d"))
    end

    it "passes notification settings through provider options" do
      provider.allowance(allowance_input.merge(
                           provider_options: { allowance_notify: "E",
                                               notify_mail: "buyer@example.com" }
                         ))

      expect(ecpay.payload).to include("AllowanceNotify" => "E",
                                       "NotifyMail" => "buyer@example.com")
    end

    it "sends tax-included item prices and amounts, as ECPay wants" do
      provider.allowance(allowance_input)
      expect(ecpay.payload["Items"].first).to include("ItemAmount" => 100, "ItemPrice" => 100)
    end

    # ECPay allows ItemPrice × ItemCount to differ from ItemAmount by 1. Here
    # 2 × 26.25 = 52.5 against 53, because the line tax is rounded.
    it "adds the tax to tax-excluded prices and amounts" do
      provider.allowance(allowance_input.merge(
                           price_mode: "TAX_EXCLUSIVE",
                           items: [{ description: "咖啡拿鐵", quantity: 2, unit_price: 25, amount: 50 }],
                           amount: { sales_amount: 50, tax_amount: 3, total_amount: 53 }
                         ))
      expect(ecpay.payload["Items"].first).to include("ItemCount" => 2, "ItemPrice" => 26.25, "ItemAmount" => 53)
    end

    it "refuses an allowance taxed at a rate ECPay does not have" do
      at_one_percent = allowance_input.merge(tax_rate: 0.01,
                                             amount: { sales_amount: 99, tax_amount: 1, total_amount: 100 })
      expect { provider.allowance(at_one_percent) }
        .to raise_error(Einvoice::UnsupportedError, /0.05 only/)
    end

    it "returns the 折讓單號 and restores the credit when voided" do
      allowance = provider.allowance(allowance_input)
      expect(allowance.allowance_number).not_to be_empty
      expect(allowance.invoice_number).to eq(issued.invoice_number)
      expect(allowance.reference.invoice_number).to eq(issued.invoice_number)

      provider.void_allowance(allowance: allowance.reference)

      # With the allowance reversed the invoice is back to a plain issued state.
      expect(provider.query(invoice: issued.reference).status).to eq(Einvoice::InvoiceStatus::ISSUED)
    end

    it "needs the invoice number to void an allowance" do
      expect { provider.void_allowance(allowance: "2026081500000001") }
        .to raise_error(Einvoice::ValidationError, /allowance.invoice_number/)
      expect(ecpay.requests).to be_empty
    end

    it "flags voiding the same 折讓單 twice" do
      allowance = provider.allowance(allowance_input)
      provider.void_allowance(allowance: allowance.reference)

      expect { provider.void_allowance(allowance: allowance.reference) }
        .to raise_error(Einvoice::ConflictError) { |e|
          expect(e.reason).to eq(Einvoice::Reason::ALREADY_VOIDED)
        }
    end

    it "raises NotFoundError for an unknown 折讓單" do
      expect do
        provider.void_allowance(allowance: { allowance_number: "9999999999999999",
                                             invoice_number: issued.invoice_number })
      end.to raise_error(Einvoice::NotFoundError)
    end
  end

  describe "carrier validation" do
    it "confirms a registered 手機條碼" do
      expect(provider.validate_carrier({ type: "MOBILE_BARCODE", code: "/ABC1234" })).to be(true)
      expect(ecpay.payload).to eq("MerchantID" => "2000132", "BarCode" => "/ABC1234")
    end

    it "reports an unregistered 手機條碼" do
      expect(provider.validate_carrier(Einvoice::Carrier.new(type: :mobile_barcode, code: "/ZZZ9999")))
        .to be(false)
    end

    it "rejects a malformed 手機條碼 without asking ECPay" do
      expect { provider.validate_carrier({ type: "MOBILE_BARCODE", code: "ABC1234" }) }
        .to raise_error(Einvoice::ValidationError, /carrier code for mobile_barcode/)
      expect(ecpay.requests).to be_empty
    end

    it "cannot check a citizen certificate" do
      expect { provider.validate_carrier({ type: "CITIZEN_CERTIFICATE", code: "AB12345678901234" }) }
        .to raise_error(Einvoice::UnsupportedError, /mobile barcode only/)
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

    # The flag covers ECPay's own rules only. The core's checks always run.
    it "can skip ECPay's own payload rules, for one ECPay has since relaxed" do
      lax = described_class.new(**Einvoice::ECPay::SANDBOX, base_url: FakeECPay::BASE_URL,
                                validate_payload: false)
      lax.issue(issue_input(order_id: "X" * 51))

      expect(ecpay.payload).to include("RelateNumber" => "X" * 51)
    end
  end
end
