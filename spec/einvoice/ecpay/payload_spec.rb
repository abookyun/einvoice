# frozen_string_literal: true

RSpec.describe Einvoice::ECPay::Payload do
  def parse(overrides = {})
    Einvoice::Input.issue({
      order_id: "ORDER_1",
      buyer: { email: "buyer@example.com" },
      items: [{ description: "商品", quantity: 1, unit_price: 100, amount: 100 }],
      amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
      tax_type: "TAXABLE",
      price_mode: "TAX_INCLUSIVE",
      carrier: { type: "MEMBER" }
    }.merge(overrides), provider: "ecpay")
  end

  def build(validate: true, **overrides)
    described_class.issue(parse(overrides), validate: validate)
  end

  describe "printing" do
    # ECPay decides paper vs electronic from Print, and the two are mutually
    # exclusive with a carrier — a carried invoice that also prints is rejected.
    it "keeps a carried invoice electronic" do
      expect(build).to include("Print" => "0")
    end

    it "keeps a donated invoice electronic" do
      payload = build(carrier: nil, donation: { npoban: "168001" })
      expect(payload).to include("Print" => "0", "Donation" => "1", "LoveCode" => "168001")
    end

    it "prints an invoice with neither carrier nor donation" do
      payload = build(carrier: nil,
                      buyer: { name: "王小明", address: "台北市信義路一段1號",
                               email: "buyer@example.com" })
      expect(payload).to include("Print" => "1")
    end

    it "refuses to print without somewhere to send the paper" do
      expect { build(carrier: nil) }
        .to raise_error(Einvoice::ValidationError, /CustomerName is required.*CustomerAddr is required/m)
    end

    it "refuses to print without a way to reach the buyer" do
      expect { build(carrier: nil, buyer: { name: "王小明", address: "台北市信義路一段1號" }) }
        .to raise_error(Einvoice::ValidationError, /CustomerEmail or CustomerPhone is required/)
    end

    it "accepts a phone in place of an email on a printed invoice" do
      payload = build(carrier: nil,
                      buyer: { name: "王小明", address: "台北市信義路一段1號", phone: "0912345678" })
      expect(payload).to include("Print" => "1", "CustomerPhone" => "0912345678")
    end
  end

  describe "tax types" do
    it "maps 應稅 to 07 一般稅額" do
      expect(build).to include("TaxType" => "1", "InvType" => "07")
    end

    it "maps 特種稅額 to InvType 08" do
      expect(build(tax_type: "SPECIAL")).to include("TaxType" => "4", "InvType" => "08")
    end

    # 混合稅率 is not something the caller asks for — it is implied by items that
    # disagree, and ECPay expresses it as TaxType 9 plus a per-item tax type.
    it "derives 混合稅率 from items that disagree" do
      payload = build(
        tax_type: "TAXABLE",
        items: [
          { description: "應稅商品", quantity: 1, unit_price: 100, amount: 100 },
          { description: "免稅商品", quantity: 1, unit_price: 50, amount: 50, tax_type: "TAX_FREE" }
        ],
        amount: { sales_amount: 150, tax_amount: 0, total_amount: 150 }
      )

      expect(payload).to include("TaxType" => "9")
      expect(payload["Items"].map { |item| item["ItemTaxType"] }).to eq(%w[1 3])
    end

    it "does not call an invoice mixed when every item agrees" do
      payload = build(items: [
                        { description: "a", quantity: 1, unit_price: 50, amount: 50,
                          tax_type: "TAXABLE" },
                        { description: "b", quantity: 1, unit_price: 50, amount: 50,
                          tax_type: "TAXABLE" }
                      ])
      expect(payload).to include("TaxType" => "1")
    end

    it "requires a clearance mark for a zero-rated invoice" do
      expect { build(tax_type: "ZERO_RATED") }
        .to raise_error(Einvoice::ValidationError, /ClearanceMark is required/)
    end

    it "accepts a zero-rated invoice once the clearance mark is supplied" do
      payload = build(tax_type: "ZERO_RATED", provider_options: { clearance_mark: "2" })
      expect(payload).to include("TaxType" => "2", "ClearanceMark" => "2")
    end

    it "requires a clearance mark when a zero-rated item is mixed in" do
      expect do
        build(items: [
                { description: "a", quantity: 1, unit_price: 50, amount: 50, tax_type: "TAXABLE" },
                { description: "b", quantity: 1, unit_price: 50, amount: 50, tax_type: "ZERO_RATED" }
              ])
      end.to raise_error(Einvoice::ValidationError, /ClearanceMark is required/)
    end
  end

  describe "amounts" do
    it "sends the tax-inclusive total and marks prices as inclusive" do
      expect(build).to include("SalesAmount" => 100, "vat" => "1")
    end

    it "marks tax-exclusive pricing" do
      expect(build(price_mode: "TAX_EXCLUSIVE")).to include("vat" => "0")
    end

    # ECPay rejects this as 5000022; catching it locally saves a round trip and
    # gives a message naming both numbers.
    it "rejects a total that disagrees with the items" do
      expect { build(amount: { sales_amount: 1, tax_amount: 0, total_amount: 1 }) }
        .to raise_error(Einvoice::ValidationError, /SalesAmount \(1\) must equal the item total \(100\)/)
    end

    # With vat=0 ECPay recomputes the total from the untaxed lines, so a local
    # equality check would reject requests the API accepts.
    it "leaves the total alone for tax-exclusive pricing" do
      payload = build(price_mode: "TAX_EXCLUSIVE",
                      amount: { sales_amount: 100, tax_amount: 5, total_amount: 105 })
      expect(payload).to include("SalesAmount" => 105)
    end
  end

  describe "buyers and carriers" do
    it "sends a 統一編號 as the B2B identifier" do
      expect(build(buyer: { ubn: "53538851", name: "測試公司" }))
        .to include("CustomerIdentifier" => "53538851")
    end

    it "leaves the identifier empty for a consumer" do
      expect(build).to include("CustomerIdentifier" => "")
    end

    it "rejects a malformed 統一編號" do
      expect { build(buyer: { ubn: "123", name: "測試公司" }) }
        .to raise_error(Einvoice::ValidationError, /CustomerIdentifier must be 8 digits/)
    end

    # A 統編 invoice has to be either printed or stored in a carrier; ECPay
    # answers 5000028 otherwise.
    it "requires a carrier for an unprinted B2B invoice" do
      expect { build(carrier: nil, buyer: { ubn: "53538851", name: "測試公司" }, donation: { npoban: "168001" }) }
        .to raise_error(Einvoice::ValidationError, /non-printed B2B invoice must use a carrier/)
    end

    it "maps each carrier type to its ECPay code" do
      expect(build(carrier: { type: "MEMBER" })).to include("CarrierType" => "1")
      expect(build(carrier: { type: "CITIZEN_CERTIFICATE", code: "AB12345678901234" }))
        .to include("CarrierType" => "2", "CarrierNum" => "AB12345678901234")
      expect(build(carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" }))
        .to include("CarrierType" => "3", "CarrierNum" => "/ABC1234")
    end

    # Input rejects a malformed 愛心碼 first, so reaching this rule takes a
    # Donation value object, which Input passes through untouched. Worth keeping
    # both: the adapter is what talks to ECPay, and 5000007 is its answer.
    it "requires a love code when donating, even if the code bypassed Input" do
      expect { build(carrier: nil, donation: Einvoice::Donation.new(npoban: "abc")) }
        .to raise_error(Einvoice::ValidationError, /LoveCode .* is required when donating/)
    end
  end

  describe "items" do
    it "numbers items and defaults the unit ECPay requires" do
      expect(build["Items"].first).to include("ItemSeq" => 1, "ItemWord" => "式")
    end

    it "keeps an explicit unit and remark" do
      payload = build(items: [{ description: "商品", quantity: 2, unit_price: 50, amount: 100,
                                unit: "件", remark: "備註" }])
      expect(payload["Items"].first).to include("ItemWord" => "件", "ItemRemark" => "備註")
    end

    it "omits the remark key entirely when there is none" do
      expect(build["Items"].first).not_to have_key("ItemRemark")
    end
  end

  describe "provider options" do
    it "passes 零稅率 and 特種稅額 details through" do
      payload = build(tax_type: "ZERO_RATED",
                      provider_options: { clearance_mark: "1", zero_tax_rate_reason: "71" })
      expect(payload).to include("ClearanceMark" => "1", "ZeroTaxRateReason" => "71")
    end

    it "lets a raw data override reach fields the mapper does not model" do
      payload = build(provider_options: { data: { "ChannelPartner" => "1" } })
      expect(payload).to include("ChannelPartner" => "1")
    end
  end

  describe "the 自訂編號" do
    it "is required" do
      expect { described_class.issue(parse.with(order_id: "")) }
        .to raise_error(Einvoice::ValidationError, /RelateNumber is required/)
    end

    it "is capped at 50 characters" do
      expect { described_class.issue(parse.with(order_id: "X" * 51)) }
        .to raise_error(Einvoice::ValidationError, /50 characters or fewer/)
    end
  end

  it "can be built without validation for a rule ECPay has since relaxed" do
    expect(build(validate: false, amount: { sales_amount: 1, tax_amount: 0, total_amount: 1 }))
      .to include("SalesAmount" => 1)
  end
end
