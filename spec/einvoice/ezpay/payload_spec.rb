# frozen_string_literal: true

RSpec.describe Einvoice::EzPay::Payload do
  def issue(**overrides)
    described_class.issue(Einvoice::Input.issue({
      order_id: "ORDER_1",
      buyer: { email: "b@x.com" },
      items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
      amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
      tax_type: "TAXABLE", price_mode: "TAX_INCLUSIVE"
    }.merge(overrides)))
  end

  def b2b(**overrides)
    issue(buyer: { ubn: "28080623", name: "簡單行動支付" }, price_mode: "TAX_EXCLUSIVE",
          items: [{ description: "商品一", quantity: 2, unit_price: 500, amount: 1000 }],
          amount: { sales_amount: 1000, tax_amount: 50, total_amount: 1050 }, **overrides)
  end

  describe ".issue" do
    it "maps a B2C invoice, splitting the tax out of the total" do
      expect(issue).to eq(
        "MerchantOrderNo" => "ORDER_1", "Status" => "1", "Category" => "B2C", "BuyerName" => "消費者",
        "BuyerUBN" => "", "BuyerAddress" => "", "BuyerEmail" => "b@x.com", "CarrierType" => "", "CarrierNum" => "",
        "LoveCode" => "", "PrintFlag" => "Y", "TaxType" => "1", "TaxRate" => "5",
        "Amt" => 95, "TaxAmt" => 5, "TotalAmt" => 100,
        "ItemName" => "商品一", "ItemCount" => "1", "ItemUnit" => "個", "ItemPrice" => "100", "ItemAmt" => "100",
        "Comment" => ""
      )
    end

    it "keeps a B2C split the caller made" do
      expect(issue(amount: { sales_amount: 96, tax_amount: 4, total_amount: 100 }))
        .to include("Amt" => 96, "TaxAmt" => 4, "TotalAmt" => 100)
    end

    it "maps a B2B invoice: prices without tax, amounts as given" do
      expect(b2b).to include("Category" => "B2B", "BuyerName" => "簡單行動支付", "BuyerUBN" => "28080623",
                             "PrintFlag" => "Y", "Amt" => 1000, "TaxAmt" => 50, "TotalAmt" => 1050,
                             "ItemCount" => "2", "ItemPrice" => "500", "ItemAmt" => "1000")
    end

    it "uses the 統一編號 as a B2B name that is missing or longer than 60" do
      expect(b2b(buyer: { ubn: "28080623" })["BuyerName"]).to eq("28080623")
      expect(b2b(buyer: { ubn: "28080623", name: "名" * 61 })["BuyerName"]).to eq("28080623")
    end

    it "joins the item fields with |" do
      data = issue(items: [{ description: "甲", quantity: 1, unit_price: 60, amount: 60, unit: "盒" },
                           { description: "乙", quantity: 2, unit_price: 20, amount: 40 }])
      expect(data).to include("ItemName" => "甲|乙", "ItemCount" => "1|2", "ItemUnit" => "盒|個",
                              "ItemPrice" => "60|20", "ItemAmt" => "60|40")
    end

    it "derives mixed tax for B2C, with the sales split by tax type" do
      data = issue(items: [{ description: "應稅", quantity: 1, unit_price: 105, amount: 105 },
                           { description: "免稅", quantity: 1, unit_price: 50, amount: 50, tax_type: "TAX_FREE" },
                           { description: "零稅", quantity: 1, unit_price: 20, amount: 20, tax_type: "ZERO_RATED" }],
                   amount: { sales_amount: 175, tax_amount: 0, total_amount: 175 },
                   provider_options: { customs_clearance: 1 })
      expect(data).to include("TaxType" => "9", "TaxRate" => "5", "ItemTaxType" => "1|3|2",
                              "AmtSales" => 100, "AmtFree" => 50, "AmtZero" => 20,
                              "Amt" => 170, "TaxAmt" => 5, "TotalAmt" => 175, "CustomsClearance" => "1")
    end

    it "refuses mixed tax on a B2B invoice" do
      expect do
        b2b(items: [{ description: "a", quantity: 1, unit_price: 500, amount: 500 },
                    { description: "b", quantity: 1, unit_price: 500, amount: 500, tax_type: "TAX_FREE" }])
      end.to raise_error(Einvoice::ValidationError, /mixed tax/)
    end

    it "sends a zero-rated or tax-free invoice with rate 0 and no tax" do
      data = issue(tax_type: "TAX_FREE")
      expect(data).to include("TaxType" => "3", "TaxRate" => "0", "Amt" => 100, "TaxAmt" => 0)
      expect { issue(tax_type: "ZERO_RATED") }.to raise_error(Einvoice::ValidationError, /customs_clearance/)
    end

    it "refuses a price mode that does not match the category" do
      expect { issue(price_mode: "TAX_EXCLUSIVE") }.to raise_error(Einvoice::ValidationError, /tax-inclusive/)
      expect { b2b(price_mode: "TAX_INCLUSIVE") }.to raise_error(Einvoice::ValidationError, /tax-exclusive/)
    end

    it "refuses amounts that do not match the items" do
      expect { issue(amount: { sales_amount: 90, tax_amount: 0, total_amount: 90 }) }
        .to raise_error(Einvoice::ValidationError, /total_amount/)
      expect { b2b(amount: { sales_amount: 900, tax_amount: 45, total_amount: 945 }) }
        .to raise_error(Einvoice::ValidationError, /sales_amount/)
    end

    describe "carriers and donations" do
      it "rawurlencodes the carrier code before the query string encodes it again" do
        expect(issue(carrier: { type: "MOBILE_BARCODE", code: "/ABC+123" }))
          .to include("CarrierType" => "0", "CarrierNum" => "%2FABC%2B123", "PrintFlag" => "N")
      end

      it "fills a member carrier from the buyer's email" do
        expect(issue(carrier: { type: "MEMBER" })).to include("CarrierType" => "2", "CarrierNum" => "b%40x.com")
        expect { issue(buyer: nil, carrier: { type: "MEMBER" }) }.to raise_error(Einvoice::ValidationError, /code/)
      end

      it "sends a donation code without printing" do
        expect(issue(donation: { npoban: "168001" })).to include("LoveCode" => "168001", "PrintFlag" => "N")
      end

      it "refuses a carrier or a donation on a B2B invoice" do
        expect { b2b(donation: { npoban: "168001" }) }.to raise_error(Einvoice::ValidationError, /B2C/)
      end
    end

    it "accepts only the 5% tax rate, written as 0.05 or 5" do
      expect(issue(tax_rate: 0.05)["TaxRate"]).to eq("5")
      expect(issue(tax_rate: 5)["TaxRate"]).to eq("5")
      expect { issue(tax_rate: 0.1) }.to raise_error(Einvoice::UnsupportedError, /5%/)
      expect { issue(tax_rate: "five") }.to raise_error(Einvoice::ValidationError, /tax_rate/)
    end

    it "refuses special tax" do
      expect { issue(tax_type: "SPECIAL") }.to raise_error(Einvoice::UnsupportedError, /special/)
    end

    describe "local checks" do
      it "checks the order id" do
        expect { issue(order_id: "x" * 21) }.to raise_error(Einvoice::ValidationError, /order_id/)
        expect { issue(order_id: "ORDER-1") }.to raise_error(Einvoice::ValidationError, /order_id/)
      end

      it "checks the item text" do
        expect { issue(items: [{ description: "x" * 31, quantity: 1, unit_price: 100, amount: 100 }]) }
          .to raise_error(Einvoice::ValidationError, /description/)
        expect { issue(items: [{ description: "a|b", quantity: 1, unit_price: 100, amount: 100 }]) }
          .to raise_error(Einvoice::ValidationError, /\|/)
        expect { issue(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100, unit: "公斤盒" }]) }
          .to raise_error(Einvoice::ValidationError, /unit/)
        expect(issue(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100, unit: "pieces" }])["ItemUnit"])
          .to eq("pieces")
      end

      it "needs whole numbers that multiply out" do
        expect { issue(items: [{ description: "a", quantity: 1.5, unit_price: 100, amount: 150 }],
                       amount: { sales_amount: 150, tax_amount: 0, total_amount: 150 }) }
          .to raise_error(Einvoice::ValidationError, /whole number/)
        expect { issue(items: [{ description: "a", quantity: 2, unit_price: 40, amount: 100 }]) }
          .to raise_error(Einvoice::ValidationError, /quantity × unit_price/)
        expect { issue(items: [{ description: "a", quantity: "lots", unit_price: 100, amount: 100 }]) }
          .to raise_error(Einvoice::ValidationError, /whole number for item quantity, got "lots"/)
        expect(issue(items: [{ description: "a", quantity: "2", unit_price: 50.0, amount: 100 }])["ItemCount"]).to eq("2")
      end

      it "checks the buyer and remark lengths" do
        expect { issue(buyer: { name: "名" * 31 }) }.to raise_error(Einvoice::ValidationError, /buyer name/)
        expect { issue(buyer: { email: "#{'x' * 45}@x.com" }) }.to raise_error(Einvoice::ValidationError, /email/)
        expect { issue(buyer: { address: "x" * 101 }) }.to raise_error(Einvoice::ValidationError, /address/)
        expect { issue(remark: "x" * 201) }.to raise_error(Einvoice::ValidationError, /remark/)
      end
    end
  end

  describe ".void and .void_allowance" do
    it "checks the reason: 6 Chinese or 20 English characters" do
      expect(described_class.void(Einvoice::Input.void({ invoice_number: "AB12345678", reason: "客戶取消" })))
        .to eq("InvoiceNumber" => "AB12345678", "InvalidReason" => "客戶取消")
      expect(described_class.void(Einvoice::Input.void({ invoice_number: "AB1", reason: "x" * 20 }))["InvalidReason"])
        .to eq("x" * 20)
      expect { described_class.void(Einvoice::Input.void({ invoice_number: "AB1", reason: "客戶要求取消訂單" })) }
        .to raise_error(Einvoice::ValidationError, /reason/)
      expect { described_class.void(Einvoice::Input.void({ invoice_number: "AB1", reason: "" })) }
        .to raise_error(Einvoice::ValidationError)
    end

    it "gives an allowance void a default reason" do
      parsed = Einvoice::Input.void_allowance({ invoice_number: "AB1", allowance_number: "A1" })
      expect(described_class.void_allowance(parsed)).to eq("AllowanceNo" => "A1", "InvalidReason" => "作廢折讓")
    end
  end

  describe ".allowance" do
    def allowance(items:, amount:, options: { order_id: "ORDER_1" })
      described_class.allowance(Einvoice::Input.allowance({ invoice_number: "AB12345678", allowance_id: "AL_1",
                                                            items: items, amount: amount, provider_options: options }))
    end

    it "sends the contract's B2C shape with tax-inclusive prices and no item tax" do
      expect(allowance(items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
                       amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 })).to eq(
                         "InvoiceNo" => "AB12345678", "MerchantOrderNo" => "ORDER_1", "ItemName" => "商品一",
                         "ItemCount" => "1", "ItemUnit" => "個", "ItemPrice" => "100", "ItemAmt" => "100",
                         "ItemTaxAmt" => "0", "TotalAmt" => 100, "Status" => "1"
                       )
    end

    it "spreads a split tax over the items, the remainder on the last" do
      data = allowance(items: [{ description: "a", quantity: 1, unit_price: 10, amount: 10 },
                               { description: "b", quantity: 1, unit_price: 10, amount: 10 }],
                       amount: { sales_amount: 20, tax_amount: 1, total_amount: 21 },
                       options: { order_id: "ORDER_1", tax_type_for_mixed: 1, buyer_email: "b@x.com" })
      expect(data).to include("ItemTaxAmt" => "1|0", "TotalAmt" => 21, "TaxTypeForMixed" => "1",
                              "BuyerEmail" => "b@x.com")
    end

    it "needs the invoice's order id" do
      expect do
        allowance(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                  amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }, options: nil)
      end.to raise_error(Einvoice::ValidationError, /order_id/)
    end

    it "refuses amounts that do not match the items" do
      expect do
        allowance(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                  amount: { sales_amount: 90, tax_amount: 0, total_amount: 90 })
      end.to raise_error(Einvoice::ValidationError, /total_amount/)
      expect do
        allowance(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                  amount: { sales_amount: 90, tax_amount: 5, total_amount: 95 })
      end.to raise_error(Einvoice::ValidationError, /sales_amount/)
    end
  end

  describe ".query" do
    def query(input)
      described_class.query(Einvoice::Input.query(input))
    end

    it "uses the number with the random code, or the order id with the total" do
      expect(query({ invoice_number: "AB1", provider_options: { random_code: "1234" } }))
        .to eq("SearchType" => "0", "InvoiceNumber" => "AB1", "RandomNum" => "1234")
      expect(query({ order_id: "O1", provider_options: { total_amount: 100 } }))
        .to eq("SearchType" => "1", "MerchantOrderNo" => "O1", "TotalAmt" => "100")
    end

    it "refuses a query without the second key" do
      expect { query({ invoice_number: "AB1" }) }.to raise_error(Einvoice::ValidationError, /random_code/)
      expect { query({ order_id: "O1" }) }.to raise_error(Einvoice::ValidationError, /total_amount/)
    end
  end
end
