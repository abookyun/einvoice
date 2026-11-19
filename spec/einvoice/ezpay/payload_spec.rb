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

    it "maps a B2B invoice: prices without tax, amounts as given" do
      expect(b2b).to include("Category" => "B2B", "BuyerName" => "簡單行動支付", "BuyerUBN" => "28080623",
                             "PrintFlag" => "Y", "Amt" => 1000, "TaxAmt" => 50, "TotalAmt" => 1050,
                             "ItemCount" => "2", "ItemPrice" => "500", "ItemAmt" => "1000")
    end

    it "sends prices without tax for a business and with tax for a consumer, whatever the price mode" do
      expect(b2b(price_mode: "TAX_INCLUSIVE",
                 items: [{ description: "a", quantity: 2, unit_price: 525, amount: 1050 }]))
        .to include("ItemPrice" => "500", "ItemAmt" => "1000", "Amt" => 1000, "TaxAmt" => 50, "TotalAmt" => 1050)
      expect(issue(price_mode: "TAX_EXCLUSIVE", amount: { sales_amount: 105, tax_amount: 0, total_amount: 105 }))
        .to include("ItemPrice" => "105", "ItemAmt" => "105", "Amt" => 100, "TaxAmt" => 5, "TotalAmt" => 105)
    end

    it "refuses an amount that does not divide into a whole unit price" do
      expect { b2b(price_mode: "TAX_INCLUSIVE", items: [{ description: "a", quantity: 2, unit_price: 50, amount: 100 }],
                   amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }) }
        .to raise_error(Einvoice::UnsupportedError, /95 does not divide by 2/)
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
                    { description: "b", quantity: 1, unit_price: 500, amount: 500, tax_type: "TAX_FREE" }],
            amount: { sales_amount: 1000, tax_amount: 25, total_amount: 1025 })
      end.to raise_error(Einvoice::UnsupportedError, /mixed tax/)
    end

    it "sends a zero-rated or tax-free invoice with rate 0 and no tax" do
      data = issue(tax_type: "TAX_FREE")
      expect(data).to include("TaxType" => "3", "TaxRate" => "0", "Amt" => 100, "TaxAmt" => 0)
      expect { issue(tax_type: "ZERO_RATED") }.to raise_error(Einvoice::ValidationError, /customs_clearance/)
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

      # A donation on B2B breaks the MIG. A carrier on B2B is ezPay's own limit.
      it "refuses a donation on a B2B invoice as invalid, and a carrier as unsupported" do
        expect { b2b(donation: { npoban: "168001" }) }.to raise_error(Einvoice::ValidationError, /donated/)
        expect { b2b(carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" }) }
          .to raise_error(Einvoice::UnsupportedError, /B2C/)
      end

      it "refuses a carrier together with a donation" do
        expect { issue(carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" }, donation: { npoban: "168001" }) }
          .to raise_error(Einvoice::UnsupportedError, /together/)
      end
    end

    it "sends the rate as a percent, and takes 0 or 0.05 only" do
      expect(issue(tax_rate: 0.05)["TaxRate"]).to eq("5")
      expect { issue(tax_rate: 0.01) }.to raise_error(Einvoice::UnsupportedError, /0 or 0.05/)
    end

    it "refuses special tax" do
      expect { issue(tax_type: "SPECIAL", tax_rate: 0.15) }.to raise_error(Einvoice::UnsupportedError, /special/)
    end

    describe "local checks" do
      it "checks the order id" do
        expect { issue(order_id: "x" * 21) }.to raise_error(Einvoice::UnsupportedError, /order_id/)
        expect { issue(order_id: "ORDER-1") }.to raise_error(Einvoice::UnsupportedError, /order_id/)
      end

      it "checks the item text" do
        expect { issue(items: [{ description: "x" * 31, quantity: 1, unit_price: 100, amount: 100 }]) }
          .to raise_error(Einvoice::UnsupportedError, /description/)
        expect { issue(items: [{ description: "a|b", quantity: 1, unit_price: 100, amount: 100 }]) }
          .to raise_error(Einvoice::UnsupportedError, /\|/)
        expect { issue(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100, unit: "公斤盒" }]) }
          .to raise_error(Einvoice::UnsupportedError, /unit/)
        expect(issue(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100, unit: "pieces" }])["ItemUnit"])
          .to eq("pieces")
      end

      it "needs whole numbers that multiply out" do
        expect { issue(items: [{ description: "a", quantity: 1.5, unit_price: 100, amount: 150 }],
                       amount: { sales_amount: 150, tax_amount: 0, total_amount: 150 }) }
          .to raise_error(Einvoice::UnsupportedError, /whole number/)
        expect { issue(items: [{ description: "a", quantity: 3, unit_price: 33, amount: 100 }]) }
          .to raise_error(Einvoice::UnsupportedError, /does not divide by 3/)
        expect(issue(items: [{ description: "a", quantity: "2", unit_price: 50.0, amount: 100 }])["ItemCount"]).to eq("2")
      end

      it "checks the buyer and remark lengths" do
        # ezPay's own limits are unsupported. The remark limit is the MIG's.
        expect { issue(buyer: { name: "名" * 31 }) }.to raise_error(Einvoice::UnsupportedError, /buyer name/)
        expect { issue(buyer: { email: "#{'x' * 45}@x.com" }) }.to raise_error(Einvoice::UnsupportedError, /email/)
        expect { issue(buyer: { address: "x" * 101 }) }.to raise_error(Einvoice::UnsupportedError, /address/)
        expect { issue(remark: "x" * 201) }.to raise_error(Einvoice::ValidationError, /remark/)
      end
    end
  end

  describe ".void and .void_allowance" do
    def void(reason)
      described_class.void(Einvoice::Input.void({ invoice: "AB12345678", reason: reason }))
    end

    it "checks the reason: 6 Chinese or 20 English characters" do
      expect(void("客戶取消")).to eq("InvoiceNumber" => "AB12345678", "InvalidReason" => "客戶取消")
      expect(void("x" * 20)["InvalidReason"]).to eq("x" * 20)
      expect { void("客戶要求取消訂單") }.to raise_error(Einvoice::UnsupportedError, /reason/)
    end

    it "gives an allowance void a default reason" do
      parsed = Einvoice::Input.void_allowance({ allowance: "A1" })
      expect(described_class.void_allowance(parsed)).to eq("AllowanceNo" => "A1", "InvalidReason" => "作廢折讓")
    end
  end

  describe ".allowance" do
    def allowance(items:, amount:, business: false, price_mode: "TAX_INCLUSIVE", invoice: {}, options: nil)
      parsed = Einvoice::Input.allowance({ invoice: { number: "AB12345678", tax_type: "TAXABLE", tax_rate: "0.05",
                                                      **invoice },
                                           allowance_id: "AL_1", items: items, amount: amount,
                                           price_mode: price_mode, provider_options: options })
      described_class.allowance(parsed, { order_id: "ORDER_1", business: business })
    end

    it "sends prices with tax and no item tax for a consumer" do
      expect(allowance(items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
                       amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 })).to eq(
                         "InvoiceNo" => "AB12345678", "MerchantOrderNo" => "ORDER_1", "ItemName" => "商品一",
                         "ItemCount" => "1", "ItemUnit" => "個", "ItemPrice" => "100", "ItemAmt" => "100",
                         "ItemTaxAmt" => "0", "TotalAmt" => 100, "Status" => "1"
                       )
    end

    it "sends prices without tax and the core's line taxes for a business" do
      data = allowance(business: true, price_mode: "TAX_EXCLUSIVE",
                       items: [{ description: "a", quantity: 1, unit_price: 10, amount: 10 },
                               { description: "b", quantity: 1, unit_price: 10, amount: 10 }],
                       amount: { sales_amount: 20, tax_amount: 1, total_amount: 21 },
                       options: { tax_type_for_mixed: 1, buyer_email: "b@x.com" })
      expect(data).to include("ItemAmt" => "10|10", "ItemTaxAmt" => "0|1", "TotalAmt" => 21,
                              "TaxTypeForMixed" => "1", "BuyerEmail" => "b@x.com")
    end

    it "refuses a business line that does not divide into a whole unit price" do
      expect do
        allowance(business: true, items: [{ description: "a", quantity: 2, unit_price: 50, amount: 100 }],
                  amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 })
      end.to raise_error(Einvoice::UnsupportedError, /does not divide/)
    end

    it "takes a tax rate of 0 or 0.05 only, and no special tax" do
      item = [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }]
      expect do
        allowance(items: item, invoice: { tax_rate: "0.01" },
                  amount: { sales_amount: 99, tax_amount: 1, total_amount: 100 })
      end.to raise_error(Einvoice::UnsupportedError, /0 or 0.05/)
      expect do
        allowance(items: item, invoice: { tax_type: "SPECIAL" },
                  amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 })
      end.to raise_error(Einvoice::UnsupportedError, /special/)
    end
  end

  describe ".query" do
    def query(**reference)
      described_class.query(Einvoice::InvoiceReference.new(**reference))
    end

    it "uses the number with the random code" do
      expect(query(number: "AB1", random_code: "1234"))
        .to eq("SearchType" => "0", "InvoiceNumber" => "AB1", "RandomNum" => "1234")
    end

    it "refuses a query without the random code" do
      expect { query(number: "AB1") }.to raise_error(Einvoice::ValidationError, /random_code/)
    end
  end
end
