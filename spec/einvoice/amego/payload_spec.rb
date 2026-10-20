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
      expect { issue(price_mode: "TAX_EXCLUSIVE") }.to raise_error(Einvoice::ValidationError, /B2B/)
    end

    it "refuses amounts that do not match the items" do
      expect { issue(amount: { sales_amount: 90, tax_amount: 0, total_amount: 90 }) }
        .to raise_error(Einvoice::ValidationError, /add up to 100/)
      expect { b2b(amount: { sales_amount: 1001, tax_amount: 49, total_amount: 1050 }) }
        .to raise_error(Einvoice::ValidationError, /tax of 50/)
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

      data = issue(tax_type: "ZERO_RATED",
                   provider_options: { customs_clearance_mark: 1, zero_tax_rate_reason: "71" })
      expect(data).to include("TaxType" => "2", "ZeroTaxSalesAmount" => 100, "SalesAmount" => 0,
                              "CustomsClearanceMark" => "1", "ZeroTaxRateReason" => "71")
    end

    it "passes the other provider_options through" do
      data = issue(provider_options: { "track_api_code" => "T1", brand_name: "牌子", detail_amount_round: 1 })
      expect(data).to include("TrackApiCode" => "T1", "BrandName" => "牌子", "DetailAmountRound" => "1")
      expect(data).not_to have_key("TaxAdjustment")
    end

    it "refuses special tax" do
      expect { issue(tax_type: "SPECIAL") }.to raise_error(Einvoice::UnsupportedError, /special/)
    end

    it "accepts only the 5% tax rate, written as 0.05 or 5" do
      expect(issue(tax_rate: 0.05)["TaxRate"]).to eq("0.05")
      expect(issue(tax_rate: 5)["TaxRate"]).to eq("0.05")
      expect(issue(tax_rate: "0.05")["TaxRate"]).to eq("0.05")
      expect { issue(tax_rate: 0.1) }.to raise_error(Einvoice::UnsupportedError, /5%/)
      expect { issue(tax_rate: Object.new) }.to raise_error(Einvoice::ValidationError, /tax_rate/)
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
      expect { issue(buyer: { name: "000" }) }.to raise_error(Einvoice::ValidationError, /must not be/)
    end

    it "checks the documented lengths" do
      expect { issue(order_id: "x" * 41) }.to raise_error(Einvoice::ValidationError, /order_id/)
      expect { issue(remark: "x" * 201) }.to raise_error(Einvoice::ValidationError, /remark/)
      expect do
        issue(items: [{ description: "x" * 257, quantity: 1, unit_price: 100, amount: 100 }])
      end.to raise_error(Einvoice::ValidationError, /description/)
      expect do
        issue(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100, unit: "x" * 7 }])
      end.to raise_error(Einvoice::ValidationError, /unit/)
    end

    it "refuses an item number it cannot read, instead of reading it as 0" do
      expect { issue(items: [{ description: "a", quantity: "lots", unit_price: 100, amount: 100 }]) }
        .to raise_error(Einvoice::ValidationError, /item quantity must be a number, got "lots"/)
      expect { issue(items: [{ description: "a", quantity: 1, unit_price: 100, amount: Float::INFINITY }]) }
        .to raise_error(Einvoice::ValidationError, /item amount/)
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
      data = issue(items: [{ description: "a", quantity: 3, unit_price: Rational(100, 3), amount: 100 }])
      expect(data["ProductItem"].first["UnitPrice"]).to eq("33.3333333")
    end
  end

  describe ".void" do
    it "sends one entry, with the reason" do
      parsed = Einvoice::Input.void({ invoice_number: "AB12345678", reason: "取消" })
      expect(described_class.void(parsed))
        .to eq([{ "CancelInvoiceNumber" => "AB12345678", "CancelReason" => "取消" }])
    end

    it "refuses a reason longer than 20" do
      parsed = Einvoice::Input.void({ invoice_number: "AB12345678", reason: "x" * 21 })
      expect { described_class.void(parsed) }.to raise_error(Einvoice::ValidationError, /reason/)
    end
  end

  describe ".allowance" do
    let(:original) { { buyer_identifier: "0000000000", buyer_name: "消費者", invoice_date: "20261017" } }

    def allowance(items:, amount:, allowance_id: "AL_1")
      parsed = Einvoice::Input.allowance({ invoice_number: "AB12345678", allowance_id: allowance_id,
                                           items: items, amount: amount })
      described_class.allowance(parsed, original, Date.new(2026, 10, 18)).first
    end

    it "splits the tax out of the contract's B2C shape" do
      entry = allowance(items: [{ description: "商品一", quantity: 1, unit_price: 100, amount: 100 }],
                        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 })
      expect(entry).to include("AllowanceNumber" => "AL_1", "AllowanceDate" => "20261018", "AllowanceType" => "2",
                               "BuyerIdentifier" => "0000000000", "BuyerName" => "消費者",
                               "TaxAmount" => 5, "TotalAmount" => 95)
      expect(entry["ProductItem"]).to eq([{ "OriginalDescription" => "商品一", "Quantity" => "1",
                                            "UnitPrice" => "95", "Amount" => "95", "Tax" => 5, "TaxType" => "1",
                                            "OriginalInvoiceNumber" => "AB12345678",
                                            "OriginalInvoiceDate" => "20261017" }])
    end

    it "puts the rounding difference on the last taxable item" do
      entry = allowance(items: [{ description: "a", quantity: 1, unit_price: 10, amount: 10 },
                                { description: "b", quantity: 1, unit_price: 10, amount: 10 },
                                { description: "c", quantity: 1, unit_price: 10, amount: 10, tax_type: "TAX_FREE" }],
                        amount: { sales_amount: 30, tax_amount: 0, total_amount: 30 })
      taxes = entry["ProductItem"].map { |item| item["Tax"] }
      expect(taxes).to eq([0, 1, 0])
      expect(entry["TaxAmount"]).to eq(1)
      expect(entry["TotalAmount"]).to eq(29)
    end

    it "keeps amounts the caller split already" do
      entry = allowance(items: [{ description: "a", quantity: 2, unit_price: 2180, amount: 4360 }],
                        amount: { sales_amount: 4360, tax_amount: 218, total_amount: 4578 })
      expect(entry).to include("TaxAmount" => 218, "TotalAmount" => 4360)
      expect(entry["ProductItem"].first).to include("Amount" => "4360", "UnitPrice" => "2180", "Tax" => 218)
    end

    it "accepts the invoice date as a Time or a Date" do
      original[:invoice_date] = Time.new(2026, 10, 16, 20, 0, 0, "+00:00")
      entry = allowance(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 })
      expect(entry["ProductItem"].first["OriginalInvoiceDate"]).to eq("20261017")

      original[:invoice_date] = Date.new(2026, 10, 16)
      entry = allowance(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                        amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 })
      expect(entry["ProductItem"].first["OriginalInvoiceDate"]).to eq("20261016")
    end

    it "refuses an invoice date it cannot read" do
      original[:invoice_date] = "yesterday"
      expect do
        allowance(items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                  amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 })
      end.to raise_error(Einvoice::ValidationError, /invoice date/)
    end

    it "refuses an allowance number longer than 16" do
      expect do
        allowance(allowance_id: "x" * 17, items: [{ description: "a", quantity: 1, unit_price: 100, amount: 100 }],
                  amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 })
      end.to raise_error(Einvoice::ValidationError, /allowance_id/)
    end
  end

  describe ".void_allowance and .query" do
    it "builds the payloads" do
      parsed = Einvoice::Input.void_allowance({ invoice_number: "AB12345678", allowance_number: "AL_1" })
      expect(described_class.void_allowance(parsed)).to eq([{ "CancelAllowanceNumber" => "AL_1" }])

      expect(described_class.query(Einvoice::Input.query({ invoice_number: "AB12345678" })))
        .to eq("type" => "invoice", "invoice_number" => "AB12345678")
      expect(described_class.query(Einvoice::Input.query({ invoice_number: "AB12345678", order_id: "O1" })))
        .to eq("type" => "order", "order_id" => "O1")
    end
  end
end
