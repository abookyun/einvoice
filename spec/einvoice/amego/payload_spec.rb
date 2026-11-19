# frozen_string_literal: true

RSpec.describe Einvoice::Amego::Payload do
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
    issue(buyer: { ubn: "28080623", name: "光貿科技" },
          items: [{ description: "商品一", quantity: 1, unit_price: 1050, amount: 1050 }],
          amount: { sales_amount: 1000, tax_amount: 50, total_amount: 1050 }, **overrides)
  end

  describe ".issue" do
    it "maps a B2C invoice: tax stays inside the total" do
      data = issue
      expect(data).to include("OrderId" => "ORDER_1", "BuyerIdentifier" => "0000000000", "BuyerName" => "消費者",
                              "BuyerEmailAddress" => "b@x.com", "SalesAmount" => 100, "FreeTaxSalesAmount" => 0,
                              "ZeroTaxSalesAmount" => 0, "TaxType" => "1", "TaxRate" => "0.05",
                              "TaxAmount" => 0, "TotalAmount" => 100, "DetailVat" => "1",
                              "CarrierType" => "", "NPOBAN" => "")
      expect(data["ProductItem"]).to eq([{ "Description" => "商品一", "Quantity" => "1", "Unit" => "",
                                           "UnitPrice" => "100", "Amount" => "100", "Remark" => "",
                                           "TaxType" => "1" }])
    end

    it "splits the tax out of a B2B invoice with Amego's formula" do
      data = b2b
      expect(data).to include("BuyerIdentifier" => "28080623", "BuyerName" => "光貿科技",
                              "SalesAmount" => 1000, "TaxAmount" => 50, "TotalAmount" => 1050)
    end

    it "uses the 統一編號 as the name of a B2B buyer without one" do
      expect(b2b(buyer: { ubn: "28080623" })["BuyerName"]).to eq("28080623")
    end

    it "adds the tax on top of B2B tax-exclusive prices" do
      data = b2b(price_mode: "TAX_EXCLUSIVE",
                 items: [{ description: "商品一", quantity: 1, unit_price: 1000, amount: 1000 }])
      expect(data).to include("DetailVat" => "0", "SalesAmount" => 1000, "TaxAmount" => 50, "TotalAmount" => 1050)
    end

    it "refuses tax-exclusive prices on a B2C invoice" do
      expect { issue(price_mode: "TAX_EXCLUSIVE", amount: { sales_amount: 105, tax_amount: 0, total_amount: 105 }) }
        .to raise_error(Einvoice::UnsupportedError, /B2B/)
    end

    it "derives the mixed tax type 9 from items with different tax types" do
      data = issue(items: [{ description: "應稅", quantity: 1, unit_price: 100, amount: 100 },
                           { description: "免稅", quantity: 1, unit_price: 50, amount: 50, tax_type: "TAX_FREE" }],
                   amount: { sales_amount: 150, tax_amount: 0, total_amount: 150 })
      expect(data).to include("TaxType" => "9", "SalesAmount" => 100, "FreeTaxSalesAmount" => 50)
      expect(data["ProductItem"].map { |item| item["TaxType"] }).to eq(%w[1 3])
    end

    it "needs the clearance mark and reason for a zero-rated sale" do
      expect { issue(tax_type: "ZERO_RATED") }.to raise_error(Einvoice::ValidationError, /customs_clearance_mark/)
      expect { issue(tax_type: "ZERO_RATED", customs_clearance_mark: 1) }
        .to raise_error(Einvoice::ValidationError, /zero_tax_rate_reason/)

      data = issue(tax_type: "ZERO_RATED", customs_clearance_mark: 1, zero_tax_rate_reason: "71")
      expect(data).to include("TaxType" => "2", "TaxRate" => "0", "ZeroTaxSalesAmount" => 100, "SalesAmount" => 0,
                              "CustomsClearanceMark" => "1", "ZeroTaxRateReason" => "71")
    end

    it "passes the other provider_options through" do
      data = issue(provider_options: { "track_api_code" => "T1", brand_name: "牌子", detail_amount_round: 1 })
      expect(data).to include("TrackApiCode" => "T1", "BrandName" => "牌子", "DetailAmountRound" => "1")
      expect(data).not_to have_key("TaxAdjustment")
    end

    it "refuses special tax" do
      expect { issue(tax_type: "SPECIAL", tax_rate: 0.15) }.to raise_error(Einvoice::UnsupportedError, /special/)
    end

    it "sends the rate as a decimal, and takes 0 or 0.05 only" do
      expect(issue(tax_rate: 0.05)["TaxRate"]).to eq("0.05")
      expect(issue(tax_rate: "0.05")["TaxRate"]).to eq("0.05")
      expect { issue(tax_rate: 0.01) }.to raise_error(Einvoice::UnsupportedError, /0 or 0.05/)
    end

    describe "carriers" do
      it "sends the same code as the visible and the hidden id" do
        data = issue(carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" })
        expect(data).to include("CarrierType" => "3J0002", "CarrierId1" => "/ABC1234", "CarrierId2" => "/ABC1234")
        expect(issue(carrier: { type: "CITIZEN_CERTIFICATE", code: "TP12345678901234" })["CarrierType"])
          .to eq("CQ0001")
      end

      it "fills a member carrier from the buyer's email, else from a mobile number" do
        expect(issue(carrier: { type: "MEMBER" })).to include("CarrierType" => "amego", "CarrierId1" => "b@x.com")
        data = issue(buyer: { phone: "0912-345-678" }, carrier: { type: "MEMBER" })
        expect(data["CarrierId1"]).to eq("a0912345678")
      end

      it "refuses a member carrier with nothing to fill it" do
        expect { issue(buyer: { phone: "02-1234-5678" }, carrier: { type: "MEMBER" }) }
          .to raise_error(Einvoice::ValidationError, /needs a code/)
      end
    end

    it "sends a donation code" do
      expect(issue(donation: { npoban: "168001" })["NPOBAN"]).to eq("168001")
    end

    it "refuses a buyer name of only zeros" do
      expect { issue(buyer: { name: "000" }) }.to raise_error(Einvoice::UnsupportedError, /"000"/)
    end

    # Amego's own limits are unsupported. The MIG's limits are invalid input.
    it "checks the documented lengths" do
      expect { issue(order_id: "x" * 41) }.to raise_error(Einvoice::UnsupportedError, /order_id/)
      expect { issue(remark: "x" * 201) }.to raise_error(Einvoice::ValidationError, /remark/)
      expect do
        issue(items: [{ description: "x" * 257, quantity: 1, unit_price: 100, amount: 100 }])
      end.to raise_error(Einvoice::UnsupportedError, /description/)
      expect do
        issue(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100, unit: "x" * 7 }])
      end.to raise_error(Einvoice::ValidationError, /unit/)
    end

    it "refuses an item number it cannot read, instead of reading it as 0" do
      expect { issue(items: [{ description: "a", quantity: "lots", unit_price: 100, amount: 100 }]) }
        .to raise_error(Einvoice::ValidationError, /quantity must be a number, got "lots"/)
      expect { issue(items: [{ description: "a", quantity: 1, unit_price: 100, amount: Float::INFINITY }]) }
        .to raise_error(Einvoice::ValidationError, /amount/)
    end

    it "reads numbers given as a String, a Float or a BigDecimal exactly" do
      require "bigdecimal"
      data = issue(items: [{ description: "a", quantity: "1.5", unit_price: BigDecimal("66.7"), amount: 100.05 },
                           { description: "b", quantity: 1, unit_price: 0.1, amount: -0.05 }])
      expect(data["ProductItem"].map { |item| item.values_at("Quantity", "UnitPrice", "Amount") })
        .to eq([%w[1.5 66.7 100.05], %w[1 0.1 -0.05]])
      expect(data["TotalAmount"]).to eq(100)
    end

    it "writes decimals with up to 7 places" do
      data = issue(items: [{ description: "a", quantity: 3, unit_price: "33.3333333", amount: 100 },
                           { description: "b", quantity: 1, unit_price: "12.50", amount: "12.50" }],
                   amount: { sales_amount: 113, tax_amount: 0, total_amount: 113 })
      expect(data["ProductItem"].map { |item| item["UnitPrice"] }).to eq(%w[33.3333333 12.5])
    end
  end

  describe ".void" do
    it "sends one entry, with the reason" do
      parsed = Einvoice::Input.void({ invoice: "AB12345678", reason: "取消" })
      expect(described_class.void(parsed))
        .to eq([{ "CancelInvoiceNumber" => "AB12345678", "CancelReason" => "取消" }])
    end
  end

  describe ".allowance" do
    let(:original) do
      { buyer_identifier: "0000000000", buyer_name: "消費者",
        invoice_datetime: Time.new(2026, 10, 17, 9, 0, 0, "+08:00") }
    end

    def allowance(items:, amount:, allowance_id: "AL_1", price_mode: "TAX_INCLUSIVE", tax_rate: "0.05")
      parsed = Einvoice::Input.allowance({ invoice: { number: "AB12345678", tax_type: "TAXABLE", tax_rate: tax_rate },
                                           allowance_id: allowance_id, items: items, amount: amount,
                                           price_mode: price_mode })
      described_class.allowance(parsed, original, Date.new(2026, 10, 18)).first
    end

    it "sends the amounts without tax, and the line taxes from the core" do
      entry = allowance(items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
                        amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 })
      expect(entry).to include("AllowanceNumber" => "AL_1", "AllowanceDate" => "20261018", "AllowanceType" => "2",
                               "BuyerIdentifier" => "0000000000", "BuyerName" => "消費者",
                               "TaxAmount" => 5, "TotalAmount" => 95)
      expect(entry["ProductItem"]).to eq([{ "OriginalDescription" => "商品一", "Quantity" => "1",
                                            "UnitPrice" => "95", "Amount" => "95", "Tax" => 5, "TaxType" => "1",
                                            "OriginalInvoiceNumber" => "AB12345678",
                                            "OriginalInvoiceDate" => "20261017" }])
    end

    it "splits the tax over the taxed lines as the core does" do
      entry = allowance(items: [{ description: "a", quantity: 1, unit_price: 10, amount: 10 },
                                { description: "b", quantity: 1, unit_price: 10, amount: 10 },
                                { description: "c", quantity: 1, unit_price: 10, amount: 10, tax_type: "TAX_FREE" }],
                        amount: { sales_amount: 29, tax_amount: 1, total_amount: 30 })
      expect(entry["ProductItem"].map { |item| item["Tax"] }).to eq([0, 1, 0])
      expect(entry).to include("TaxAmount" => 1, "TotalAmount" => 29)
    end

    it "derives the unit price from the amount without tax, rounded to 7 decimal places" do
      entry = allowance(items: [{ description: "a", quantity: 3, unit_price: 33, amount: 99 }],
                        amount: { sales_amount: 94, tax_amount: 5, total_amount: 99 })
      expect(entry["ProductItem"].first).to include("Quantity" => "3", "UnitPrice" => "31.3333333", "Amount" => "94")
    end

    it "keeps tax-exclusive amounts as they are" do
      entry = allowance(price_mode: "TAX_EXCLUSIVE",
                        items: [{ description: "a", quantity: 2, unit_price: 2180, amount: 4360 }],
                        amount: { sales_amount: 4360, tax_amount: 218, total_amount: 4578 })
      expect(entry).to include("TaxAmount" => 218, "TotalAmount" => 4360)
      expect(entry["ProductItem"].first).to include("Amount" => "4360", "UnitPrice" => "2180", "Tax" => 218)
    end

    it "writes the invoice date in Taipei time" do
      original[:invoice_datetime] = Time.new(2026, 10, 16, 20, 0, 0, "+00:00")
      entry = allowance(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                        amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 })
      expect(entry["ProductItem"].first["OriginalInvoiceDate"]).to eq("20261017")
    end

    it "takes a tax rate of 0 or 0.05 only" do
      expect do
        allowance(tax_rate: "0.01", items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                  amount: { sales_amount: 99, tax_amount: 1, total_amount: 100 })
      end.to raise_error(Einvoice::UnsupportedError, /0 or 0.05/)
    end

    it "refuses special tax" do
      parsed = Einvoice::Input.allowance({ invoice: { number: "AB12345678", tax_type: "SPECIAL", tax_rate: "0.15" },
                                           allowance_id: "AL_1", price_mode: "TAX_EXCLUSIVE",
                                           items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                                           amount: { sales_amount: 100, tax_amount: 15, total_amount: 115 } })
      expect { described_class.allowance(parsed, original, Date.new(2026, 10, 18)) }
        .to raise_error(Einvoice::UnsupportedError, /special/)
    end

    it "refuses an allowance number longer than 16" do
      expect do
        allowance(allowance_id: "x" * 17, items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                  amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 })
      end.to raise_error(Einvoice::ValidationError, /allowance_id/)
    end
  end

  describe ".void_allowance and .query" do
    it "builds the payloads" do
      parsed = Einvoice::Input.void_allowance({ allowance: "AL_1" })
      expect(described_class.void_allowance(parsed)).to eq([{ "CancelAllowanceNumber" => "AL_1" }])

      expect(described_class.query(Einvoice::InvoiceReference.new(number: "AB12345678")))
        .to eq("type" => "invoice", "invoice_number" => "AB12345678")
      expect(described_class.query(Einvoice::InvoiceReference.new(number: "AB12345678", order_id: "O1")))
        .to eq("type" => "order", "order_id" => "O1")
    end
  end

  describe ".number" do
    it "writes whole numbers without a point, and up to 7 decimal places" do
      expect(described_class.number(100)).to eq("100")
      expect(described_class.number(Rational(94, 3))).to eq("31.3333333")
      expect(described_class.number(0.25)).to eq("0.25")
    end

    it "rounds first, so a value close to a whole number has no trailing point" do
      expect(described_class.number(Rational(100_000_000_001, 1_000_000_000))).to eq("100")
    end
  end
end
