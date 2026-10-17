# frozen_string_literal: true

RSpec.describe Einvoice::Tradevan::DefaultAPI::Provider do
  subject(:provider) { described_class.new(**FakeTradevan::CREDENTIALS) }

  let!(:tradevan) { FakeTradevan.new.install! }

  # The contract over the DEFAULTAPI wire format: the v parameter, both keys,
  # the Success/Message envelope. A void and an allowance need the original
  # invoice's order id and date, which the unified inputs do not carry.
  it_behaves_like "an invoice provider",
                  unknown_invoice_number: "ZZ00000000",
                  unknown_allowance_number: "ABCDE20260101999",
                  follow_up: lambda { |issued|
                    { order_id: issued.order_id, invoice_date: issued.invoice_date }
                  }

  let(:issue_input) do
    {
      order_id: "53b2a44e4b3c",
      buyer: { name: "John Appleseed", email: "john@example.com" },
      items: [{ description: "Coffee Latte", quantity: 4000, unit_price: 5, amount: 20_000 }],
      amount: { sales_amount: 20_000, tax_amount: 0, total_amount: 20_000 },
      tax_type: "TAXABLE", price_mode: "TAX_INCLUSIVE",
      carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" }
    }
  end

  def issue_data(index = -1)
    JSON.parse(tradevan.params(index)["issueData"])
  end

  it "identifies itself and declares what it can do" do
    expect(provider.name).to eq("tradevan")
    expect(provider.api_version).to eq("defaultapi")
    expect(provider).to be_supports(Einvoice::Capability::B2B)
    expect(provider).not_to be_supports(Einvoice::Capability::QUERY_BY_ORDER_ID)
    expect(provider).not_to be_supports(Einvoice::Capability::MIXED_TAX)
    expect(provider).not_to be_supports(Einvoice::Capability::FOREIGN_CURRENCY)
  end

  describe "#issue" do
    # Ported from the 1.x provider spec: the request goes through the whole
    # stack, and the response is decoded.
    it "sends the request through the full wire format and reads the response" do
      result = provider.issue(issue_input)

      expect(tradevan.path).to eq("post/issue")
      expect(tradevan.http_method).to eq(:post)
      expect(issue_data).to include("type" => "I", "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
                                    "total" => "20000", "carrierType" => "3J0002")
      expect(result.invoice_number).to match(/\AGX\d{8}\z/)
      expect(result.random_code).to match(/\A\d{4}\z/)
      expect(result.invoice_date).to be_a(Time)
      expect(result.order_id).to eq("53b2a44e4b3c")
      expect(result.total_amount).to eq(20_000)
      expect(result.status).to eq(Einvoice::InvoiceStatus::ISSUED)
      expect(result.raw["issueStatus"]).to eq("Y")
    end

    # 1.x returned an unsuccessful result here. 2.0 raises, and the failReason
    # decides the class.
    it "raises ConflictError when Tradevan reports the order as duplicated" do
      provider.issue(issue_input)

      expect { provider.issue(issue_input) }.to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
        expect(error.raw_message).to eq("duplicated")
      }
    end

    # Ported from the 1.x provider spec: invalid data never reaches the network.
    it "raises ValidationError without a request when the data breaks the field rules" do
      expect { provider.issue(issue_input.merge(order_id: "x" * 51)) }
        .to raise_error(Einvoice::ValidationError, /transactionNumber/)
      expect(tradevan.requests).to be_empty
    end

    it "lets validate_payload: false send the data as it is" do
      lax = described_class.new(**FakeTradevan::CREDENTIALS, validate_payload: false)

      expect { lax.issue(issue_input.merge(order_id: "x" * 51)) }.not_to raise_error
      expect(tradevan.requests.size).to eq(1)
    end

    it "sends only DEFAULTAPI fields, so Tradevan does not reject the request (PR #38)" do
      provider.issue(issue_input)

      expect(issue_data.keys - Einvoice::Tradevan::DefaultAPI::Rules::ISSUE_FIELDS).to be_empty
      expect(issue_data["itemList"].flat_map(&:keys) - Einvoice::Tradevan::DefaultAPI::Rules::ITEM_FIELDS)
        .to be_empty
    end

    it "issues a B2B invoice" do
      provider.issue(issue_input.merge(buyer: { name: "Acme", ubn: "53538851" }, carrier: nil))

      expect(issue_data).to include("buyerUn" => "53538851", "buyerTitle" => "Acme")
    end
  end

  describe "#void" do
    # Ported from the 1.x provider spec.
    it "voids an invoice through the full wire format" do
      issued = provider.issue(issue_input)
      result = provider.void(invoice_number: issued.invoice_number, reason: "客戶取消",
                             provider_options: { order_id: "53b2a44e4b3c" })

      expect(tradevan.path).to eq("post/cancel")
      expect(JSON.parse(tradevan.params["voidData"])).to eq(
        "type" => "I", "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
        "invoiceNumber" => issued.invoice_number, "invoicePaperReturned" => "N"
      )
      expect(result.status).to eq(Einvoice::InvoiceStatus::VOIDED)
    end

    it "needs the order id, and says so before any request" do
      expect { provider.void(invoice_number: "GX38551078", reason: "客戶取消") }
        .to raise_error(Einvoice::ValidationError, /order id/)
      expect(tradevan.requests).to be_empty
    end

    it "refuses to void an invoice that has an allowance" do
      issued = provider.issue(issue_input)
      provider.allowance(invoice_number: issued.invoice_number, allowance_id: "AL_V",
                         items: [{ description: "Coffee Latte", quantity: 1, unit_price: 100, amount: 100 }],
                         amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
                         provider_options: { order_id: issued.order_id, invoice_date: issued.invoice_date })

      expect do
        provider.void(invoice_number: issued.invoice_number, reason: "客戶取消",
                      provider_options: { order_id: issued.order_id })
      end.to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE)
      }
    end
  end

  describe "#allowance" do
    let(:issued) { provider.issue(issue_input) }

    def allowance(**overrides)
      provider.allowance({
        invoice_number: issued.invoice_number, allowance_id: "AL_1",
        items: [{ description: "Coffee Latte", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
        provider_options: { order_id: issued.order_id, invoice_date: issued.invoice_date }
      }.merge(overrides))
    end

    it "sends type A with the tax split out, and reads the allowance number" do
      result = allowance

      expect(issue_data).to include("type" => "A", "allowanceExclusiveAmount" => "95", "allowanceTax" => "5",
                                    "allowanceInclusiveAmount" => "100")
      expect(result.allowance_number).to match(/\AABCDE\d{11}\z/)
      expect(result.allowance_date).to be_a(Time)
      expect(result.invoice_number).to eq(issued.invoice_number)
      expect(result.total_amount).to eq(100)
    end

    it "raises ProviderError when the response has no allowanceNumber" do
      issued
      message = Einvoice::Tradevan::DefaultAPI::Crypto.encrypt(%({"issueStatus":"Y"}), FakeTradevan::KEY1)
      stub_request(:post, %r{tradevan\.test/DEFAULTAPI/post/issue})
        .to_return(headers: { "Content-Type" => "application/json" },
                   body: JSON.generate("Success" => "Y", "Message" => message))

      expect { allowance }.to raise_error(Einvoice::ProviderError, /no allowanceNumber/)
    end

    it "needs the original invoice date" do
      expect { allowance(provider_options: { order_id: issued.order_id }) }
        .to raise_error(Einvoice::ValidationError, /invoice date/)
    end
  end

  describe "#void_allowance" do
    it "refuses an allowance number that is not 16 characters, before any request" do
      expect { provider.void_allowance(invoice_number: "GX38551078", allowance_number: "NOPE00000000") }
        .to raise_error(Einvoice::ValidationError, /allowanceNumber/)
      expect(tradevan.requests).to be_empty
    end
  end

  describe "#query" do
    it "reads searchInvoiceDetail into the unified result" do
      issued = provider.issue(issue_input)
      found = provider.query(invoice_number: issued.invoice_number)

      expect(tradevan.path).to eq("get/searchInvoiceDetail")
      expect(tradevan.http_method).to eq(:get)
      expect(found.invoice_number).to eq(issued.invoice_number)
      expect(found.order_id).to eq("53b2a44e4b3c")
      expect(found.random_code).to eq(issued.random_code)
      expect(found.invoice_date).to be_a(Time)
      expect(found.amount).to eq(Einvoice::AmountSummary.new(sales_amount: 19_048, tax_amount: 952,
                                                             total_amount: 20_000))
      expect(found.buyer.name).to eq("John Appleseed")
      expect(found.items.first).to have_attributes(description: "Coffee Latte", quantity: 4000, unit_price: 5,
                                                   amount: 20_000, tax_type: Einvoice::TaxType::TAXABLE)
    end

    # The meaning of status I and V is unknown, so the adapter does not guess.
    it "leaves status nil, unless the invoice has an allowance" do
      issued = provider.issue(issue_input)
      expect(provider.query(invoice_number: issued.invoice_number).status).to be_nil

      provider.allowance(invoice_number: issued.invoice_number, allowance_id: "AL_Q",
                         items: [{ description: "Coffee Latte", quantity: 1, unit_price: 100, amount: 100 }],
                         amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
                         provider_options: { order_id: issued.order_id, invoice_date: issued.invoice_date })
      found = provider.query(invoice_number: issued.invoice_number)
      expect(found.status).to eq(Einvoice::InvoiceStatus::ALLOWANCE)
      expect(found.raw["status"]).to eq("I")
    end

    it "refuses a query by order id, which this adapter does not declare" do
      expect { provider.query(order_id: "53b2a44e4b3c") }.to raise_error(Einvoice::UnsupportedError)
    end
  end

  describe "#raw" do
    it "calls any path with the encryption and error mapping applied" do
      issued = provider.issue(issue_input)

      expect(provider.raw("get/searchInvoiceDetail", { invoiceNumber: issued.invoice_number })["invoiceNumber"])
        .to eq(issued.invoice_number)
    end
  end

  it "raises AuthError when the account is wrong" do
    wrong = described_class.new(**FakeTradevan::CREDENTIALS, acntp: "wrong")

    expect { wrong.issue(issue_input) }.to raise_error(Einvoice::AuthError)
  end

  it "needs 16-byte keys" do
    bad = described_class.new(**FakeTradevan::CREDENTIALS, key1: "short")

    expect { bad.issue(issue_input) }.to raise_error(Einvoice::ValidationError, /16 bytes/)
  end
end
