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
      carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" },
      date: Time.new(2016, 4, 25, 12, 34, 56, "+08:00")
    }.merge(overrides))
  end

  describe ".issue" do
    # The 1.x README example, built from the unified input.
    it "builds the type I issueData of the 1.x README example" do
      data = described_class.issue(issue_input, settings)

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

    it "uses the current time in UTC+8 without a date" do
      data = described_class.issue(issue_input(date: nil), settings)

      expect(data["transactionDate"]).to eq(Time.now.getlocal("+08:00").strftime("%Y%m%d"))
      expect(data["transactionTime"]).to match(/\A\d{2}:\d{2}:\d{2}\z/)
    end

    it "numbers the items and maps each tax type" do
      items = [
        { description: "A", quantity: 1, unit_price: 50, amount: 50 },
        { description: "B", quantity: 1, unit_price: 30, amount: 30, tax_type: "TAX_FREE" },
        { description: "C", quantity: 1, unit_price: 20, amount: 20, tax_type: "ZERO_RATED" }
      ]
      data = described_class.issue(issue_input(items: items, amount: { sales_amount: 100, tax_amount: 0,
                                                                       total_amount: 100 }), settings)

      expect(data["itemList"].map { |row| row.values_at("serialNumber", "taxType") })
        .to eq([%w[0001 T], %w[0002 O], %w[0003 Z]])
    end

    it "writes whole numbers without a decimal point and keeps real decimals" do
      items = [{ description: "A", quantity: 1.0, unit_price: 99.5, amount: 99.5 },
               { description: "B", quantity: "2", unit_price: 0.25, amount: 0.5 }]
      data = described_class.issue(issue_input(items: items, amount: { sales_amount: 100, tax_amount: 0,
                                                                       total_amount: 100 }), settings)

      expect(data["itemList"].map { |row| row.values_at("qty", "price", "itemTotal") })
        .to eq([%w[1 99.5 99.5], %w[2 0.25 0.5]])
    end

    it "fills buyerUn and buyerTitle for a B2B buyer" do
      data = described_class.issue(issue_input(buyer: { name: "Acme", ubn: "53538851" }), settings)

      expect(data).to include("buyerUn" => "53538851", "buyerTitle" => "Acme", "receiverName" => "Acme")
    end

    it "leaves donate out of a B2B invoice without a carrier" do
      data = described_class.issue(issue_input(buyer: { name: "Acme", ubn: "53538851" }, carrier: nil),
                                   settings)

      expect(data).not_to include("donate", "carrierType")
      expect(rules.issue_errors(data)).to eq({})
    end

    it "sends a donation instead of a carrier" do
      data = described_class.issue(issue_input(carrier: nil, donation: { npoban: "168001" }), settings)

      expect(data).to include("donate" => "Y", "donationUnit" => "168001")
      expect(data).not_to include("carrierType")
      expect(rules.issue_errors(data)).to eq({})
    end

    it "maps the citizen certificate carrier" do
      data = described_class.issue(issue_input(carrier: { type: "CITIZEN_CERTIFICATE",
                                                          code: "TP03000001234567" }), settings)

      expect(data).to include("carrierType" => "CQ0001", "carrierId" => "TP03000001234567")
    end

    describe "a member carrier" do
      it "uses the merchant's member_carrier_type" do
        data = described_class.issue(issue_input(carrier: { type: "MEMBER", code: "M001" }), settings)

        expect(data).to include("carrierType" => "1K0001", "carrierId" => "M001", "carrierIdHidden" => "M001")
      end

      it "falls back to the buyer's email, then phone" do
        data = described_class.issue(issue_input(carrier: { type: "MEMBER" }), settings)
        expect(data["carrierId"]).to eq("john@example.com")

        data = described_class.issue(issue_input(carrier: { type: "MEMBER" },
                                                 buyer: { phone: "0912123123" }), settings)
        expect(data["carrierId"]).to eq("0912123123")
      end

      it "refuses a member carrier with no code and no buyer contact" do
        expect { described_class.issue(issue_input(carrier: { type: "MEMBER" }, buyer: nil), settings) }
          .to raise_error(Einvoice::ValidationError, /needs a code/)
      end

      it "refuses a member carrier when member_carrier_type is not set" do
        expect do
          described_class.issue(issue_input(carrier: { type: "MEMBER", code: "M001" }),
                                settings.with(member_carrier_type: nil))
        end.to raise_error(Einvoice::ValidationError, /member_carrier_type/)
      end
    end

    it "refuses a mobile barcode carrier without a code" do
      expect { described_class.issue(issue_input(carrier: { type: "MOBILE_BARCODE" }), settings) }
        .to raise_error(Einvoice::ValidationError, /needs a code/)
    end

    it "refuses the special tax rate, which DEFAULTAPI has no code for" do
      expect { described_class.issue(issue_input(tax_type: "SPECIAL"), settings) }
        .to raise_error(Einvoice::UnsupportedError, /special tax/)
    end

    it "refuses tax-excluded prices" do
      expect { described_class.issue(issue_input(price_mode: "TAX_EXCLUSIVE"), settings) }
        .to raise_error(Einvoice::ValidationError, /tax-included/)
    end
  end

  describe ".void" do
    def void_input(options)
      Einvoice::Input.void({ invoice_number: "GX38551078", reason: "客戶取消", provider_options: options })
    end

    it "builds the 1.x README void from the order id" do
      expect(described_class.void(void_input(order_id: "53b2a44e4b3c"), settings)).to eq(
        "type" => "I", "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
        "invoiceNumber" => "GX38551078", "invoicePaperReturned" => "N"
      )
    end

    it "takes a full sale_identifier instead" do
      data = described_class.void(void_input("sale_identifier" => "12345678_ABCDE_other"), settings)

      expect(data["saleIdentifier"]).to eq("12345678_ABCDE_other")
    end

    it "needs the order id" do
      expect { described_class.void(void_input(nil), settings) }
        .to raise_error(Einvoice::ValidationError, /order id/)
    end

    it "does not send the reason, which DEFAULTAPI has no field for" do
      expect(described_class.void(void_input(order_id: "x"), settings)).not_to include("reason")
    end
  end

  describe ".allowance" do
    def allowance_input(amount:, items: nil, options: { order_id: "53b2a44e4b3c", invoice_date: "2016-04-25" })
      Einvoice::Input.allowance({
                                  invoice_number: "GX38551078", allowance_id: "AL_1",
                                  items: items || [{ description: "Coffee Latte", quantity: 1,
                                                     unit_price: 100, amount: 100 }],
                                  amount: amount, provider_options: options
                                })
    end

    it "splits the tax out of a taxable allowance sent with tax 0" do
      data = described_class.allowance(
        allowance_input(amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }), settings
      )

      expect(data).to include(
        "type" => "A", "allowanceIdentifier" => "12345678_ABCDE_AL_1", "transactionNumber" => "AL_1",
        "allowanceExclusiveAmount" => "95", "allowanceTax" => "5", "allowanceInclusiveAmount" => "100",
        "allowancePaperReturned" => "Y", "invoicePaperReturned" => "N"
      )
      expect(data["itemList"].first).to include(
        "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c", "invoiceNumber" => "GX38551078",
        "invoiceDate" => "20160425", "itemExclude" => "95", "itemTotal" => "100", "taxType" => "T"
      )
      expect(rules.issue_errors(data)).to eq({})
    end

    it "keeps an amount that already has the tax split out" do
      data = described_class.allowance(
        allowance_input(amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }), settings
      )

      expect(data.values_at("allowanceExclusiveAmount", "allowanceTax", "allowanceInclusiveAmount"))
        .to eq(%w[95 5 100])
    end

    it "does not split a tax-free allowance" do
      items = [{ description: "Book", quantity: 1, unit_price: 100, amount: 100, tax_type: "TAX_FREE" }]
      data = described_class.allowance(
        allowance_input(amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }, items: items), settings
      )

      expect(data.values_at("allowanceExclusiveAmount", "allowanceTax")).to eq(%w[100 0])
      expect(data["itemList"].first["taxType"]).to eq("O")
    end

    it "shares the tax-excluded total over the items, so they add up" do
      items = [{ description: "A", quantity: 1, unit_price: 33, amount: 33 },
               { description: "B", quantity: 1, unit_price: 33, amount: 33 },
               { description: "C", quantity: 1, unit_price: 34, amount: 34 }]
      data = described_class.allowance(
        allowance_input(amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }, items: items), settings
      )

      excludes = data["itemList"].map { |row| row["itemExclude"].to_i }
      expect(excludes.sum).to eq(95)
      expect(data["itemList"].map { |row| row["serialNumber"] }).to eq(%w[0001 0002 0003])
    end

    it "reads the invoice date from a Time, a String, or the input's date" do
      at = Time.new(2016, 4, 25, 23, 0, 0, "+08:00")
      [{ order_id: "x", invoice_date: at }, { order_id: "x", invoice_date: "20160425" }].each do |options|
        data = described_class.allowance(
          allowance_input(amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }, options: options),
          settings
        )
        expect(data["itemList"].first["invoiceDate"]).to eq("20160425")
      end

      input = Einvoice::Input.allowance({
                                          invoice_number: "GX38551078", allowance_id: "AL_1", date: at,
                                          items: [{ description: "A", quantity: 1, unit_price: 100,
                                                    amount: 100 }],
                                          amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
                                          provider_options: { order_id: "x" }
                                        })
      expect(described_class.allowance(input, settings)["itemList"].first["invoiceDate"]).to eq("20160425")
    end

    it "needs the original invoice date" do
      expect do
        described_class.allowance(
          allowance_input(amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
                          options: { order_id: "x" }), settings
        )
      end.to raise_error(Einvoice::ValidationError, /invoice date/)
    end

    it "needs the original order id" do
      expect do
        described_class.allowance(
          allowance_input(amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
                          options: { invoice_date: "20160425" }), settings
        )
      end.to raise_error(Einvoice::ValidationError, /order id/)
    end
  end

  describe ".void_allowance" do
    it "builds the 2026 README allowance void" do
      input = Einvoice::Input.void_allowance({ invoice_number: "GX38551078",
                                               allowance_number: "ABCDE20260101001" })

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

    it "returns a saleIdentifier with another prefix as it is" do
      expect(described_class.order_id_from(settings, "99999999_X_1")).to eq("99999999_X_1")
    end
  end
end
