# frozen_string_literal: true

RSpec.describe Einvoice::EzPay::Provider do
  subject(:provider) { described_class.new(**FakeEzPay::CREDENTIALS) }

  let!(:ezpay) { FakeEzPay.new.install! }

  # A query needs the random code, and an allowance needs the order id. The
  # IssueInvoiceResult has both. The fake voids at once, unlike ezPay.
  it_behaves_like "an invoice provider",
                  unknown_invoice_number: "ZZ00000000",
                  unknown_allowance_number: "A000000000000000",
                  unknown_query_options: { random_code: "0000" },
                  follow_up: lambda { |issued|
                    { random_code: issued.random_code, order_id: issued.order_id }
                  }
end

RSpec.describe Einvoice::EzPay::Provider, "adapter details" do
  subject(:provider) { described_class.new(**FakeEzPay::CREDENTIALS) }

  let!(:ezpay) { FakeEzPay.new.install! }

  let(:issue_input) do
    { order_id: "ORDER_1", buyer: { name: "王小明", email: "b@x.com", address: "台北市" },
      items: [{ description: "商品一", quantity: 2, unit_price: 50, amount: 100, unit: "個" }],
      amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
      tax_type: "TAXABLE", price_mode: "TAX_INCLUSIVE", carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" } }
  end

  it "identifies itself and declares what it can do" do
    expect(provider.name).to eq("ezpay")
    expect(provider).to be_supports(Einvoice::Capability::B2B)
    expect(provider).to be_supports(Einvoice::Capability::MIXED_TAX)
    expect(provider).not_to be_supports(Einvoice::Capability::QUERY_BY_ORDER_ID)
    expect(provider).not_to be_supports(Einvoice::Capability::CARRIER_VALIDATION)
    expect(provider.client.base_url).to eq(FakeEzPay::BASE_URL)
  end

  describe "#issue" do
    it "reads the result and checks its CheckCode" do
      result = provider.issue(issue_input)

      expect(ezpay.path).to eq("/Api/invoice_issue")
      expect(ezpay.fields).to include("Version" => "1.5", "CarrierNum" => "%2FABC1234", "Amt" => "95", "TaxAmt" => "5")
      expect(result.invoice_number).to match(/\ADS\d{8}\z/)
      expect(result.random_code).to match(/\A\d{4}\z/)
      expect(result.invoice_date.utc_offset).to eq(8 * 3600)
      expect(result).to have_attributes(order_id: "ORDER_1", total_amount: 100,
                                        status: Einvoice::InvoiceStatus::ISSUED)
    end

    it "refuses a result whose CheckCode does not match" do
      stub_request(:post, "#{FakeEzPay::BASE_URL}/Api/invoice_issue").to_return(body: JSON.generate(
        "Status" => "SUCCESS", "Message" => "", "Result" => JSON.generate("InvoiceNumber" => "DS1", "CheckCode" => "X")
      ))
      expect { provider.issue(issue_input) }.to raise_error(Einvoice::ProviderError, /CheckCode/)
    end

    it "maps a duplicate order id to a ConflictError" do
      provider.issue(issue_input)
      expect { provider.issue(issue_input) }.to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
      }
    end
  end

  describe "#query" do
    it "maps the result back, with the items from ItemDetail" do
      issued = provider.issue(issue_input)
      found = provider.query({ order_id: "ORDER_1", provider_options: { total_amount: 100 } })

      expect(ezpay.fields).to include("Version" => "1.3", "SearchType" => "1")
      expect(found).to have_attributes(invoice_number: issued.invoice_number, random_code: issued.random_code,
                                       order_id: "ORDER_1", status: Einvoice::InvoiceStatus::ISSUED)
      expect(found.amount).to eq(Einvoice::AmountSummary.new(sales_amount: 95, tax_amount: 5, total_amount: 100))
      expect(found.buyer).to have_attributes(name: "王小明", ubn: nil, email: "b@x.com", address: "台北市", phone: nil)
      expect(found.items).to eq([Einvoice::InvoiceItem.new(description: "商品一", quantity: 2, unit_price: 50,
                                                           amount: 100, unit: "個", tax_type: nil)])
    end

    it "reports VOIDED after a void" do
      issued = provider.issue(issue_input)
      provider.void({ invoice_number: issued.invoice_number, reason: "取消" })
      found = provider.query({ invoice_number: issued.invoice_number,
                               provider_options: { random_code: issued.random_code } })
      expect(found.status).to eq(Einvoice::InvoiceStatus::VOIDED)
    end

    it "reads ItemDetail as an array or as nothing, and refuses one that is not JSON" do
      reply = lambda do |detail|
        result = { "InvoiceTransNo" => "1", "MerchantID" => "3502275", "MerchantOrderNo" => "O1",
                   "RandomNum" => "1234", "TotalAmt" => "100", "ItemDetail" => detail }
        result["CheckCode"] = Einvoice::EzPay::Crypto.check_code(result, FakeEzPay::HASH_KEY, FakeEzPay::HASH_IV)
        stub_request(:post, "#{FakeEzPay::BASE_URL}/Api/invoice_search")
          .to_return(body: JSON.generate("Status" => "SUCCESS", "Result" => JSON.generate(result)))
      end
      input = { invoice_number: "AB1", provider_options: { random_code: "1234" } }

      reply.call([{ "ItemName" => "a", "ItemCount" => 1.5, "ItemPrice" => 10, "ItemAmount" => 15 }])
      expect(provider.query(input).items.first.quantity).to eq(1.5)
      reply.call("")
      expect(provider.query(input).items).to eq([])
      reply.call("[oops")
      expect { provider.query(input) }.to raise_error(Einvoice::ProviderError, /ItemDetail/)
    end
  end

  describe "#allowance" do
    it "sends the order id and reads ezPay's allowance number" do
      issued = provider.issue(issue_input)
      result = provider.allowance({ invoice_number: issued.invoice_number, allowance_id: "ignored",
                                    items: [{ description: "商品一", quantity: 1, unit_price: 50, amount: 50 }],
                                    amount: { sales_amount: 50, tax_amount: 0, total_amount: 50 },
                                    provider_options: { order_id: "ORDER_1" } })

      expect(ezpay.fields).to include("Version" => "1.3", "MerchantOrderNo" => "ORDER_1", "Status" => "1")
      expect(result.allowance_number).to match(/\AA\d{15}\z/)
      expect(result).to have_attributes(invoice_number: issued.invoice_number, total_amount: 50, allowance_date: nil)
    end

    it "refuses to void an invoice with a live allowance" do
      issued = provider.issue(issue_input)
      provider.allowance({ invoice_number: issued.invoice_number, allowance_id: "x",
                           items: [{ description: "商品一", quantity: 1, unit_price: 50, amount: 50 }],
                           amount: { sales_amount: 50, tax_amount: 0, total_amount: 50 },
                           provider_options: { order_id: "ORDER_1" } })
      expect { provider.void({ invoice_number: issued.invoice_number, reason: "取消" }) }
        .to raise_error(Einvoice::ConflictError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE)
        }
    end
  end

  it "reaches other endpoints through #raw" do
    stub_request(:post, "#{FakeEzPay::BASE_URL}/Api/invoice_touch_issue")
      .to_return(body: JSON.generate("Status" => "SUCCESS", "Result" => JSON.generate("InvoiceNumber" => "DS1")))
    expect(provider.raw("/Api/invoice_touch_issue", "1.0", { InvoiceTransNo: "1" })).to eq("InvoiceNumber" => "DS1")
  end
end
