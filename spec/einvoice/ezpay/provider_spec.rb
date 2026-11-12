# frozen_string_literal: true

RSpec.describe Einvoice::EzPay::Provider do
  subject(:provider) { described_class.new(**FakeEzPay::CREDENTIALS) }

  let!(:ezpay) { FakeEzPay.new.install! }

  # A query needs the random code, and an allowance needs the order id. The
  # reference from issue has both. The fake voids at once, unlike ezPay.
  it_behaves_like "an invoice provider",
                  unknown_reference: { number: "ZZ00000000", random_code: "0000" },
                  unknown_allowance_number: "A000000000000000"
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

  def credit(invoice, **extra)
    provider.allowance({ invoice: invoice, allowance_id: "ignored",
                         items: [{ description: "商品一", quantity: 1, unit_price: 50, amount: 50 }],
                         amount: { sales_amount: 48, tax_amount: 2, total_amount: 50 },
                         price_mode: "TAX_INCLUSIVE", **extra })
  end

  # A search result with a valid CheckCode.
  def search_reply(result)
    result = { "InvoiceTransNo" => "1", "MerchantID" => "3502275", "MerchantOrderNo" => "O1",
               "RandomNum" => "1234", "TotalAmt" => "100" }.merge(result)
    result["CheckCode"] = Einvoice::EzPay::Crypto.check_code(result, FakeEzPay::HASH_KEY, FakeEzPay::HASH_IV)
    stub_request(:post, "#{FakeEzPay::BASE_URL}/Api/invoice_search")
      .to_return(body: JSON.generate("Status" => "SUCCESS", "Result" => JSON.generate(result)))
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
    it "reads the result, checks its CheckCode, and returns a reference" do
      result = provider.issue(issue_input)

      expect(ezpay.path).to eq("/Api/invoice_issue")
      expect(ezpay.fields).to include("Version" => "1.5", "CarrierNum" => "%2FABC1234", "Amt" => "95", "TaxAmt" => "5")
      expect(result.invoice_number).to match(/\ADS\d{8}\z/)
      expect(result.random_code).to match(/\A\d{4}\z/)
      expect(result.invoice_datetime.utc_offset).to eq(8 * 3600)
      expect(result).to have_attributes(order_id: "ORDER_1", total_amount: 100,
                                        status: Einvoice::InvoiceStatus::ISSUED)
      expect(result.reference).to have_attributes(buyer_ubn: nil, tax_type: Einvoice::TaxType::TAXABLE,
                                                  tax_rate: Rational(5, 100))
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
      found = provider.query({ invoice: issued.reference })

      expect(ezpay.fields).to include("Version" => "1.3", "SearchType" => "0", "RandomNum" => issued.random_code)
      expect(found).to have_attributes(invoice_number: issued.invoice_number, random_code: issued.random_code,
                                       order_id: "ORDER_1", tax_type: Einvoice::TaxType::TAXABLE,
                                       tax_rate: Rational(5, 100))
      expect(found.amount).to eq(Einvoice::AmountSummary.new(sales_amount: 95, tax_amount: 5, total_amount: 100))
      expect(found.buyer).to have_attributes(name: "王小明", ubn: nil, email: "b@x.com", address: "台北市", phone: nil)
      expect(found.items).to eq([Einvoice::InvoiceItem.new(description: "商品一", quantity: 2, unit_price: 50,
                                                           amount: 100, unit: "個", tax_type: nil)])
    end

    it "gives no status to an invoice that is not voided, and VOIDED after a void" do
      issued = provider.issue(issue_input)
      expect(provider.query({ invoice: issued.reference }).status).to be_nil

      provider.void({ invoice: issued.reference, reason: "取消" })
      expect(provider.query({ invoice: issued.reference }).status).to eq(Einvoice::InvoiceStatus::VOIDED)
    end

    it "refuses a query by order id" do
      expect { provider.query({ invoice: { order_id: "ORDER_1", total_amount: 100 } }) }
        .to raise_error(Einvoice::UnsupportedError)
    end

    it "reads ItemDetail as an array or as nothing, and refuses one that is not JSON" do
      input = { invoice: { number: "AB1", random_code: "1234" } }

      search_reply("ItemDetail" => [{ "ItemName" => "a", "ItemCount" => 1.5, "ItemPrice" => 10, "ItemAmount" => 15 }])
      expect(provider.query(input).items.first.quantity).to eq(1.5)
      search_reply("ItemDetail" => "")
      expect(provider.query(input).items).to eq([])
      search_reply("ItemDetail" => "[oops")
      expect { provider.query(input) }.to raise_error(Einvoice::ProviderError, /ItemDetail/)
    end
  end

  describe "#allowance" do
    it "sends the order id from the reference, and reads ezPay's allowance number" do
      issued = provider.issue(issue_input)
      result = credit(issued.reference)

      expect(ezpay.path).to eq("/Api/allowance_issue")
      expect(ezpay.fields).to include("Version" => "1.3", "MerchantOrderNo" => "ORDER_1", "Status" => "1",
                                      "ItemAmt" => "50", "ItemTaxAmt" => "0")
      expect(result.allowance_number).to match(/\AA\d{15}\z/)
      expect(result).to have_attributes(invoice_number: issued.invoice_number, total_amount: 50,
                                        allowance_date: Einvoice::Taipei.today)
    end

    it "sends prices without tax for a business" do
      issued = provider.issue(issue_input.merge(buyer: { ubn: "28080623", name: "簡單行動支付" }, carrier: nil,
                                                items: [{ description: "商品一", quantity: 1, unit_price: 105,
                                                          amount: 105 }],
                                                amount: { sales_amount: 100, tax_amount: 5, total_amount: 105 }))
      credit(issued.reference, items: [{ description: "商品一", quantity: 1, unit_price: 21, amount: 21 }],
                               amount: { sales_amount: 20, tax_amount: 1, total_amount: 21 })

      expect(ezpay.fields).to include("ItemPrice" => "20", "ItemAmt" => "20", "ItemTaxAmt" => "1", "TotalAmt" => "21")
    end

    it "looks the order id up by number when the reference has none" do
      issued = provider.issue(issue_input)
      credit(issued.reference.with(order_id: nil))

      expect(ezpay.path(-2)).to eq("/Api/invoice_search")
      expect(ezpay.fields).to include("MerchantOrderNo" => "ORDER_1")
    end

    it "needs the order id, or the random code to look it up" do
      expect { credit({ number: "DS12223140", tax_type: "TAXABLE", tax_rate: "0.05" }) }
        .to raise_error(Einvoice::ValidationError, /order_id/)
    end

    it "blames ezPay, not the caller, when the lookup fails or finds no order id" do
      reference = { number: "ZZ00000000", random_code: "0000", tax_type: "TAXABLE", tax_rate: "0.05" }
      expect { credit(reference) }.to raise_error(Einvoice::ProviderError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::LOOKUP_FAILED)
      }

      search_reply("MerchantOrderNo" => "")
      expect { credit(reference) }.to raise_error(Einvoice::ProviderError, /has none/)
    end

    it "refuses to void an invoice with a live allowance" do
      issued = provider.issue(issue_input)
      credit(issued.reference)
      expect { provider.void({ invoice: issued.reference, reason: "取消" }) }
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
