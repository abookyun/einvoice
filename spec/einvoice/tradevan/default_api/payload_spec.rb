# frozen_string_literal: true

RSpec.describe Einvoice::Tradevan::DefaultAPI::Payload do
  let(:settings) do
    Einvoice::Tradevan::DefaultAPI::Settings.new(
      company_un: "12345678", org_id: "ABCDE", paper_print_mode: "0", invoice_alarm_mode: "4",
      invoice_paper_returned: "N", allowance_paper_returned: "Y", member_carrier_type: "1K0001"
    )
  end
  let(:rules) { Einvoice::Tradevan::DefaultAPI::Rules }

  def issue_input(**overrides)
    Einvoice::Input.issue({
      order_id: "53b2a44e4b3c",
      buyer: { name: "John Appleseed", email: "john@example.com", address: "1 Infinite Loop",
               phone: "0912123123" },
      items: [{ description: "Coffee Latte", quantity: 4000, unit_price: 5, amount: 20_000 }],
      amount: { sales_amount: 20_000, tax_amount: 0, total_amount: 20_000 },
      tax_type: "TAXABLE", price_mode: "TAX_INCLUSIVE",
      carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" }
    }.merge(overrides))
  end

  let(:now) { Time.new(2016, 4, 25, 12, 34, 56, "+08:00") }

  def build(input, with = settings)
    described_class.issue(input, with, now)
  end

  describe ".issue" do
    # A B2B invoice reports its tax: 20000 with tax is 19048 and 952.
    let(:b2b) do
      { buyer: { name: "Acme", ubn: "53538851" },
        amount: { sales_amount: 19_048, tax_amount: 952, total_amount: 20_000 } }
    end

    # The 1.x README example, built from the unified input.
    it "builds the type I issueData of the 1.x README example" do
      data = build(issue_input)

      expect(data).to include(
        "companyUn" => "12345678", "orgId" => "ABCDE", "type" => "I",
        "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c", "transactionNumber" => "53b2a44e4b3c",
        "transactionDate" => "20160425", "transactionTime" => "12:34:56", "total" => "20000",
        "paperPrintMode" => "0", "invoiceAlarmMode" => "4", "donate" => "N",
        "carrierType" => "3J0002", "carrierId" => "/ABC1234", "carrierIdHidden" => "/ABC1234",
        "receiverName" => "John Appleseed", "receiverAddrRoad" => "1 Infinite Loop",
        "receiverEmail" => "john@example.com", "receiverMobile" => "0912123123"
      )
      expect(data["itemList"]).to eq([{
                                       "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
                                       "serialNumber" => "0001", "productName" => "Coffee Latte",
                                       "qty" => "4000", "price" => "5", "itemTotal" => "20000",
                                       "taxType" => "T"
                                     }])
      expect(rules.issue_errors(data)).to eq({})
    end

    it "numbers the items and maps each tax type" do
      items = [
        { description: "A", quantity: 1, unit_price: 50, amount: 50 },
        { description: "B", quantity: 1, unit_price: 30, amount: 30, tax_type: "TAX_FREE" },
        { description: "C", quantity: 1, unit_price: 20, amount: 20, tax_type: "ZERO_RATED" }
      ]
      data = build(issue_input(items: items, amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }))

      expect(data["itemList"].map { |row| row.values_at("serialNumber", "taxType") })
        .to eq([%w[0001 T], %w[0002 O], %w[0003 Z]])
    end

    it "writes whole numbers without a decimal point and keeps real decimals" do
      items = [{ description: "A", quantity: 1.0, unit_price: 99.5, amount: 99.5 },
               { description: "B", quantity: "2", unit_price: 0.25, amount: 0.5 }]
      data = build(issue_input(items: items, amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }))

      expect(data["itemList"].map { |row| row.values_at("qty", "price", "itemTotal") })
        .to eq([%w[1 99.5 99.5], %w[2 0.25 0.5]])
    end

    it "fills buyerUn and buyerTitle for a B2B buyer" do
      data = build(issue_input(**b2b))

      expect(data).to include("buyerUn" => "53538851", "buyerTitle" => "Acme", "receiverName" => "Acme")
    end

    it "leaves donate out of a B2B invoice without a carrier" do
      data = build(issue_input(**b2b, carrier: nil))

      expect(data).not_to include("donate", "carrierType")
      expect(rules.issue_errors(data)).to eq({})
    end

    it "sends the carrier with a donation, as the schema allows both" do
      data = build(issue_input(donation: { npoban: "168001" }))

      expect(data).to include("donate" => "Y", "donationUnit" => "168001", "carrierType" => "3J0002",
                              "carrierId" => "/ABC1234")
      expect(rules.issue_errors(data)).to eq({})
    end

    it "cuts a long B2B name to 30 characters for receiverName only" do
      name = "測" * 40
      data = build(issue_input(**b2b, buyer: { name: name, ubn: "53538851" }))

      expect(data).to include("buyerTitle" => name, "receiverName" => "測" * 30)
      expect(rules.issue_errors(data)).to eq({})
    end

    it "sends a donation instead of a carrier" do
      data = build(issue_input(carrier: nil, donation: { npoban: "168001" }))

      expect(data).to include("donate" => "Y", "donationUnit" => "168001")
      expect(data).not_to include("carrierType")
      expect(rules.issue_errors(data)).to eq({})
    end

    it "maps the citizen certificate carrier" do
      data = build(issue_input(carrier: { type: "CITIZEN_CERTIFICATE", code: "TP03000001234567" }))

      expect(data).to include("carrierType" => "CQ0001", "carrierId" => "TP03000001234567")
    end

    describe "a member carrier" do
      it "uses the merchant's member_carrier_type" do
        data = build(issue_input(carrier: { type: "MEMBER", code: "M001" }))

        expect(data).to include("carrierType" => "1K0001", "carrierId" => "M001", "carrierIdHidden" => "M001")
      end

      it "falls back to the buyer's email, then phone" do
        data = build(issue_input(carrier: { type: "MEMBER" }))
        expect(data["carrierId"]).to eq("john@example.com")

        data = build(issue_input(carrier: { type: "MEMBER" }, buyer: { phone: "0912123123" }))
        expect(data["carrierId"]).to eq("0912123123")
      end

      it "refuses a member carrier with no code and no buyer contact" do
        expect { build(issue_input(carrier: { type: "MEMBER" }, buyer: nil)) }
          .to raise_error(Einvoice::ValidationError, /needs a code/)
      end

      it "refuses a member carrier when member_carrier_type is not set" do
        no_type = settings.with(member_carrier_type: nil)
        expect { build(issue_input(carrier: { type: "MEMBER", code: "M001" }), no_type) }
          .to raise_error(Einvoice::ValidationError, /member_carrier_type/)
      end
    end

    it "refuses the special tax rate, which DEFAULTAPI has no code for" do
      expect { build(issue_input(tax_type: "SPECIAL", tax_rate: 0.15)) }
        .to raise_error(Einvoice::UnsupportedError, /special tax/)
    end

    it "sends tax-excluded prices with their tax, as itemTotal includes it" do
      data = build(issue_input(**b2b, price_mode: "TAX_EXCLUSIVE",
                                      amount: { sales_amount: 20_000, tax_amount: 1000, total_amount: 21_000 }))

      expect(data["total"]).to eq("21000")
      expect(data["itemList"].first.values_at("qty", "price", "itemTotal")).to eq(%w[4000 5.25 21000])
      expect(rules.issue_errors(data)).to eq({})
    end

    # 100.5 without tax is 105.5 with tax, but the whole-TWD total is 106.
    # As Floats, 0.1 + 0.9 + 20 is not exactly 21. The check uses the values
    # that go out, and those add up.
    it "sends decimal line totals that add up to the whole total" do
      items = [{ description: "A", quantity: 1, unit_price: 0.1, amount: 0.1 },
               { description: "B", quantity: 1, unit_price: 0.9, amount: 0.9 },
               { description: "C", quantity: 1, unit_price: 20, amount: 20 }]
      data = build(issue_input(items: items, amount: { sales_amount: 21, tax_amount: 0, total_amount: 21 }))

      expect(data["itemList"].map { |row| row["itemTotal"] }).to eq(%w[0.1 0.9 20])
      expect(rules.issue_errors(data)).to eq({})
    end

    it "writes small amounts in fixed point, not as 1.0e-07" do
      expect([1.0e-07, -1.0e-07, Rational(94, 3)].map { |v| described_class.number(v) })
        .to eq(%w[0.0000001 -0.0000001 31.3333333])
    end

    it "refuses item totals with tax that cannot add up to the whole-TWD total" do
      input = issue_input(**b2b, price_mode: "TAX_EXCLUSIVE",
                                 items: [{ description: "A", quantity: 1, unit_price: 100.5, amount: 100.5 }],
                                 amount: { sales_amount: 101, tax_amount: 5, total_amount: 106 })

      expect { build(input) }.to raise_error(Einvoice::UnsupportedError, /\(105\.5\).*\(106\)/)
    end

    it "refuses a taxable rate other than 0.05, which DEFAULTAPI cannot carry" do
      expect { build(issue_input(tax_rate: 0.01)) }
        .to raise_error(Einvoice::UnsupportedError, /0\.05 only/)
    end
  end

  describe ".void" do
    it "builds the 1.x README void with the sale identifier it is given" do
      input = Einvoice::Input.void({ invoice: "GX38551078", reason: "客戶取消" })

      expect(described_class.void(input, settings, "12345678_ABCDE_53b2a44e4b3c")).to eq(
        "type" => "I", "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
        "invoiceNumber" => "GX38551078", "invoicePaperReturned" => "N"
      )
    end
  end

  describe ".allowance" do
    def allowance(amount:, items: nil)
      input = Einvoice::Input.allowance({
                                          invoice: "GX38551078", allowance_id: "AL_1",
                                          items: items || [{ description: "Coffee Latte", quantity: 1,
                                                             unit_price: 100, amount: 100 }],
                                          amount: amount, price_mode: "TAX_INCLUSIVE",
                                          tax_type: "TAXABLE", tax_rate: 0.05
                                        })
      described_class.allowance(input, settings, sale: "12345678_ABCDE_53b2a44e4b3c",
                                                 invoice_date: Date.new(2016, 4, 25), today: Date.new(2016, 5, 2))
    end

    it "sends the amounts and each line's tax split from the core" do
      data = allowance(amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 })

      expect(data).to include(
        "type" => "A", "allowanceIdentifier" => "12345678_ABCDE_AL_1", "transactionNumber" => "AL_1",
        "transactionDate" => "20160502",
        "allowanceExclusiveAmount" => "95", "allowanceTax" => "5", "allowanceInclusiveAmount" => "100",
        "allowancePaperReturned" => "Y", "invoicePaperReturned" => "N"
      )
      expect(data["itemList"].first).to include(
        "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c", "invoiceNumber" => "GX38551078",
        "invoiceDate" => "20160425", "price" => "100", "itemExclude" => "95", "tax" => "5",
        "itemTotal" => "100", "taxType" => "T"
      )
      expect(rules.issue_errors(data)).to eq({})
    end

    it "sends a tax-free line with tax 0" do
      items = [{ description: "Book", quantity: 1, unit_price: 100, amount: 100, tax_type: "TAX_FREE" }]
      data = allowance(amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }, items: items)

      expect(data.values_at("allowanceExclusiveAmount", "allowanceTax")).to eq(%w[100 0])
      expect(data["itemList"].first.values_at("itemExclude", "tax", "taxType")).to eq(%w[100 0 O])
    end

    it "numbers the lines, and their splits add up to the amounts" do
      items = [{ description: "A", quantity: 1, unit_price: 33, amount: 33 },
               { description: "B", quantity: 1, unit_price: 33, amount: 33 },
               { description: "C", quantity: 1, unit_price: 34, amount: 34 }]
      data = allowance(amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }, items: items)

      expect(data["itemList"].sum { |row| row["itemExclude"].to_i }).to eq(95)
      expect(data["itemList"].sum { |row| row["tax"].to_i }).to eq(5)
      expect(data["itemList"].map { |row| row["serialNumber"] }).to eq(%w[0001 0002 0003])
    end

    it "sends allowance line totals that are not whole: type A has no total rule" do
      input = Einvoice::Input.allowance({
                                          invoice: "GX38551078", allowance_id: "AL_1",
                                          items: [{ description: "A", quantity: 1, unit_price: 100.5, amount: 100.5 }],
                                          amount: { sales_amount: 101, tax_amount: 5, total_amount: 106 },
                                          price_mode: "TAX_EXCLUSIVE", tax_type: "TAXABLE", tax_rate: 0.05
                                        })
      data = described_class.allowance(input, settings, sale: "x", invoice_date: Date.today, today: Date.today)
      expect(data).to include("allowanceInclusiveAmount" => "106")
      expect(data["itemList"].first).to include("itemTotal" => "105.5")
    end

    it "refuses the special tax rate" do
      input = Einvoice::Input.allowance({
                                          invoice: "GX38551078", allowance_id: "AL_1",
                                          items: [{ description: "A", quantity: 1, unit_price: 100, amount: 100 }],
                                          amount: { sales_amount: 87, tax_amount: 13, total_amount: 100 },
                                          price_mode: "TAX_INCLUSIVE", tax_type: "SPECIAL", tax_rate: 0.15
                                        })
      expect do
        described_class.allowance(input, settings, sale: "x", invoice_date: Date.today, today: Date.today)
      end.to raise_error(Einvoice::UnsupportedError, /special tax/)
    end
  end

  describe ".void_allowance" do
    it "builds the 2026 README allowance void" do
      input = Einvoice::Input.void_allowance({ allowance: "ABCDE20260101001" })

      expect(described_class.void_allowance(input, settings)).to eq(
        "type" => "A", "companyUn" => "12345678", "allowanceNumber" => "ABCDE20260101001",
        "allowancePaperReturned" => "Y"
      )
    end
  end

  describe ".order_id_from" do
    it "strips the prefix this adapter adds" do
      expect(described_class.order_id_from(settings, "12345678_ABCDE_53b2a44e4b3c")).to eq("53b2a44e4b3c")
    end

    it "gives nil for a saleIdentifier with another prefix" do
      expect(described_class.order_id_from(settings, "99999999_X_1")).to be_nil
    end
  end
end
