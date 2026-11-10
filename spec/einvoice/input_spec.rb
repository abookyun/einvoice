# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"

RSpec.describe Einvoice::Input do
  # A wire-style, string-keyed hash like a JSON fixture would supply.
  let(:issue_hash) do
    {
      "order_id" => "ORDER_1",
      "buyer" => { "email" => "b@x.com" },
      "items" => [{ "description" => "商品一", "quantity" => 1, "unit_price" => 100, "amount" => 100 }],
      "amount" => { "sales_amount" => 100, "tax_amount" => 0, "total_amount" => 100 },
      "tax_type" => "TAXABLE",
      "price_mode" => "TAX_INCLUSIVE",
      "carrier" => { "type" => "MEMBER" }
    }
  end

  describe ".issue" do
    it "coerces a string-keyed hash into value objects with canonical enum symbols" do
      input = described_class.issue(issue_hash)
      expect(input).to be_a(Einvoice::IssueInvoiceInput)
      expect(input.order_id).to eq("ORDER_1")
      expect(input.tax_type).to eq(:taxable)
      expect(input.price_mode).to eq(:tax_inclusive)
      expect(input.carrier.type).to eq(:member)
      expect(input.buyer).to be_a(Einvoice::Buyer)
      expect(input.items.first).to be_a(Einvoice::InvoiceItem)
      expect(input.amount.total_amount).to eq(100)
    end

    # A value object built with .new takes the same checks as a Hash, so an
    # adapter can trust whatever Input returns.
    it "checks a value object as it checks a Hash" do
      input = described_class.issue(issue_hash)
      expect(described_class.issue(input)).to eq(input)

      expect { described_class.issue(input.with(buyer: Einvoice::Buyer.new(ubn: "123"))) }
        .to raise_error(Einvoice::ValidationError, /buyer ubn must be 8 digits/)
      wrong_total = Einvoice::AmountSummary.new(sales_amount: 1, tax_amount: 0, total_amount: 1)
      expect { described_class.issue(input.with(amount: wrong_total)) }
        .to raise_error(Einvoice::ValidationError, /total_amount is 1, but the items add up to 100/)
      item = Einvoice::InvoiceItem.new(description: "x", quantity: "lots", unit_price: 100, amount: 100)
      expect { described_class.issue(issue_hash.merge("items" => [item])) }
        .to raise_error(Einvoice::ValidationError, /items\[0\].quantity must be a number/)
    end

    it "raises ValidationError tagged with the provider on a missing order_id" do
      expect { described_class.issue(issue_hash.reject { |k| k == "order_id" }, provider: "ecpay") }
        .to raise_error(Einvoice::ValidationError) { |e| expect(e.provider).to eq("ecpay") }
    end

    it "rejects an inconsistent amount summary" do
      bad = issue_hash.merge("amount" => { "sales_amount" => 100, "tax_amount" => 5, "total_amount" => 999 })
      expect { described_class.issue(bad) }.to raise_error(Einvoice::ValidationError, /total 999/)
    end

    it "rejects a fractional TWD amount (MIG integer invariant)" do
      bad = issue_hash.merge("amount" => { "sales_amount" => 99.5, "tax_amount" => 0.5, "total_amount" => 100 })
      expect { described_class.issue(bad) }.to raise_error(Einvoice::ValidationError, /integer/)
    end

    it "rejects an unknown tax_type" do
      expect { described_class.issue(issue_hash.merge("tax_type" => "WHATEVER")) }
        .to raise_error(Einvoice::ValidationError, /tax_type/)
    end

    it "rejects an empty items list" do
      expect { described_class.issue(issue_hash.merge("items" => [])) }
        .to raise_error(Einvoice::ValidationError, /items/)
    end
  end

  describe "MIG checks on an issue" do
    def issue(**changes)
      described_class.issue(issue_hash.merge(changes.transform_keys(&:to_s)))
    end

    def error_for(&block)
      block.call
      nil
    rescue Einvoice::ValidationError => e
      e.message
    end

    # F0401 for a business buyer: the tax is apart from the sales amount.
    let(:b2b_amount) { { "sales_amount" => 95, "tax_amount" => 5, "total_amount" => 100 } }

    it "requires an 8-digit buyer ubn" do
      expect(error_for { issue(buyer: { "ubn" => "abc" }) }).to match(/buyer ubn must be 8 digits/)
      expect(issue(buyer: { "ubn" => 53_538_851 }, amount: b2b_amount).buyer.ubn).to eq("53538851")
    end

    it "makes the category agree with the buyer ubn" do
      expect(error_for { issue(category: "B2B") }).to match(/B2B invoice needs buyer.ubn/)
      expect(error_for { issue(category: "B2C", buyer: { "ubn" => "53538851" }) })
        .to match(/B2C invoice cannot carry buyer.ubn/)
      expect(issue(category: "B2B", buyer: { "ubn" => "53538851" }, amount: b2b_amount).category).to eq(:b2b)
    end

    it "checks the total against the items" do
      expect(error_for { issue(amount: { "sales_amount" => 90, "tax_amount" => 0, "total_amount" => 90 }) })
        .to match(/total_amount is 90, but the items add up to 100 with tax/)
      expect(issue(price_mode: "TAX_EXCLUSIVE", amount: { "sales_amount" => 105, "tax_amount" => 0,
                                                          "total_amount" => 105 }).amount.total_amount).to eq(105)
    end

    # The same tax at every provider: round(taxable sales × tax_rate) for a
    # business, and 0 for a consumer, whose tax is inside sales_amount.
    it "checks the tax against the items" do
      business = { buyer: { "ubn" => "53538851" } }
      amount = ->(sales, tax) { { "sales_amount" => sales, "tax_amount" => tax, "total_amount" => sales + tax } }
      expect(error_for { issue(**business, amount: amount.call(100, 0)) })
        .to match(/tax_amount is 0, but the tax of the items is 5 \(taxable 95 at 0.05\)/)
      expect(error_for { issue(**business, amount: amount.call(96, 4)) })
        .to match(/tax_amount is 4, but the tax of the items is 5/)
      expect(error_for { issue(amount: b2b_amount) }).to match(/a B2C invoice has tax_amount 0/)

      mixed = [{ "description" => "a", "quantity" => 1, "unit_price" => 100, "amount" => 100 },
               { "description" => "b", "quantity" => 1, "unit_price" => 50, "amount" => 50, "tax_type" => "TAX_FREE" }]
      input = issue(**business, items: mixed, amount: amount.call(145, 5))
      expect(input.tax_breakdown).to have_attributes(taxable_amount: 95, tax_free_amount: 50, tax_amount: 5)
    end

    it "rejects negative totals" do
      expect(error_for { issue(amount: { "sales_amount" => -100, "tax_amount" => 0, "total_amount" => -100 }) })
        .to match(/sales_amount must not be negative/)
    end

    it "requires item numbers with at most 7 decimal places" do
      item = { "description" => "x", "quantity" => "lots", "unit_price" => 100, "amount" => 100 }
      expect(error_for { issue(items: [item]) }).to match(/items\[0\].quantity must be a number/)
      expect(error_for { issue(items: [item.merge("quantity" => "0.00000001")]) })
        .to match(/items\[0\].quantity may have at most 7 decimal places/)
      item = item.merge("quantity" => "0.5", "unit_price" => 200)
      expect(issue(items: [item]).items.first.quantity).to eq("0.5")
      expect(error_for { issue(items: [item.merge("quantity" => BigDecimal("0.00000001"))]) })
        .to match(/items\[0\].quantity may have at most 7 decimal places/)
      expect(issue(items: [item.merge("quantity" => BigDecimal("0.5"))]).items.first.quantity)
        .to eq(BigDecimal("0.5"))
    end

    it "checks the carrier code shape" do
      expect(error_for { issue(carrier: { "type" => "MOBILE_BARCODE", "code" => "ABC" }) })
        .to match(/carrier code for mobile_barcode/)
      expect(error_for { issue(carrier: { "type" => "CITIZEN_CERTIFICATE", "code" => "A1" }) })
        .to match(/carrier code for citizen_certificate/)
      expect(issue(carrier: { "type" => "MOBILE_BARCODE", "code" => "/ABC+123" }).carrier.code).to eq("/ABC+123")
    end

    it "allows a donation and a carrier together" do
      input = issue(donation: { "npoban" => "168001" })
      expect([input.carrier, input.donation]).to all(be_truthy)
    end

    it "defaults tax_rate by tax type" do
      expect(issue.tax_rate).to eq(Rational(5, 100))
      expect(issue(tax_type: "ZERO_RATED").tax_rate).to eq(0)
      expect(error_for { issue(tax_type: "SPECIAL") }).to match(/tax_rate is required for a special line/)
    end

    it "accepts only the MIG tax rates, as decimals" do
      expect(issue(tax_type: "SPECIAL", tax_rate: 0.15).tax_rate).to eq(Rational(15, 100))
      expect(error_for { issue(tax_rate: 5) }).to match(/tax_rate must be one of the MIG rates/)
      expect(error_for { issue(tax_rate: 0.3) }).to match(/tax_rate must be one of the MIG rates/)
    end
  end

  describe ".query" do
    it "needs a number or an order id in the reference" do
      expect { described_class.query({}) }.to raise_error(Einvoice::ValidationError, /invoice is required/)
      expect { described_class.query({ "invoice" => { "random_code" => "1234" } }) }
        .to raise_error(Einvoice::ValidationError, /invoice.number or invoice.order_id/)
      expect(described_class.query({ "invoice" => { "order_id" => "O1" } }).invoice.order_id).to eq("O1")
    end
  end

  describe ".void" do
    it "requires invoice and reason" do
      expect { described_class.void({ "invoice" => "JU1" }) }
        .to raise_error(Einvoice::ValidationError, /reason/)
      expect { described_class.void({ "reason" => "x" }) }
        .to raise_error(Einvoice::ValidationError, /invoice is required/)
      expect(described_class.void({ "invoice" => "JU1", "reason" => "x" }).reason).to eq("x")
    end

    it "limits the reason to 20 characters" do
      expect { described_class.void({ "invoice" => "JU1", "reason" => "x" * 21 }) }
        .to raise_error(Einvoice::ValidationError, /reason must be 20 characters or fewer/)
    end
  end

  describe ".allowance" do
    let(:taxable) { Einvoice::InvoiceReference.new(number: "JU1", tax_type: :taxable, tax_rate: Rational(5, 100)) }

    def allowance(items, amount, invoice: taxable, price_mode: "TAX_INCLUSIVE", **rest)
      described_class.allowance({ invoice: invoice, allowance_id: "A1", items: items, amount: amount,
                                  price_mode: price_mode, **rest })
    end

    def item(amount, **rest)
      { description: "x", quantity: 1, unit_price: amount, amount: amount }.merge(rest)
    end

    def taxes(input)
      input.tax_breakdown.lines.map { |line| [line.net_amount, line.tax] }
    end

    it "splits the tax out of tax-included items, and leaves the items as given" do
      input = allowance([item(100)], { sales_amount: 95, tax_amount: 5, total_amount: 100 })
      line = input.tax_breakdown.lines.first
      expect(line).to have_attributes(net_amount: 95, tax: 5, gross_amount: 100, net_unit_price: 95.2380952,
                                      gross_unit_price: 100)
      expect(input.items.first).to have_attributes(amount: 100, unit_price: 100)
    end

    it "puts the rounding remainder on the last taxable line" do
      input = allowance([item(10), item(10), item(10)], { sales_amount: 29, tax_amount: 1, total_amount: 30 })
      expect(taxes(input)).to eq([[10, 0], [10, 0], [9, 1]])
    end

    it "adds the tax to tax-excluded items" do
      input = allowance([item(95), item(48)], { sales_amount: 143, tax_amount: 7, total_amount: 150 },
                        price_mode: "TAX_EXCLUSIVE")
      expect(taxes(input)).to eq([[95, 5], [48, 2]])
      expect(input.tax_breakdown.lines.first.gross_unit_price).to eq(99.75)
    end

    it "keeps a fractional amount as a Float" do
      input = allowance([item(10.5)], { sales_amount: 10, tax_amount: 1, total_amount: 11 })
      expect(taxes(input)).to eq([[9.5, 1]])
    end

    # A zero-rated invoice, such as an export, has no tax to split out. The core
    # used to read tax_amount 0 as "split the 5% out" and filed 952 + 48.
    it "takes no tax from a zero-rated or tax-free invoice" do
      export = Einvoice::InvoiceReference.new(number: "JU1", tax_type: :zero_rated, tax_rate: 0)
      input = allowance([item(1000)], { sales_amount: 1000, tax_amount: 0, total_amount: 1000 }, invoice: export)
      expect(taxes(input)).to eq([[1000, 0]])
      expect { allowance([item(1000)], { sales_amount: 952, tax_amount: 48, total_amount: 1000 }, invoice: export) }
        .to raise_error(Einvoice::ValidationError, /tax_amount is 48, but the tax of the items is 0/)

      free = allowance([item(100)], { sales_amount: 100, tax_amount: 0, total_amount: 100 },
                       invoice: "JU1", tax_type: "TAX_FREE")
      expect(free.tax_rate).to eq(0)
    end

    it "needs every item's tax type when the invoice has mixed tax" do
      mixed = Einvoice::InvoiceReference.new(number: "JU1", tax_type: :mixed, tax_rate: Rational(5, 100))
      amount = { sales_amount: 148, tax_amount: 2, total_amount: 150 }
      expect { allowance([item(100), item(50)], amount, invoice: mixed) }
        .to raise_error(Einvoice::ValidationError, /items\[0\].tax_type is required when the invoice has mixed tax/)

      input = allowance([item(100, tax_type: "TAX_FREE"), item(50, tax_type: "TAXABLE")],
                        { sales_amount: 148, tax_amount: 2, total_amount: 150 }, invoice: mixed)
      expect(taxes(input)).to eq([[100, 0], [48, 2]])
      expect(input.tax_breakdown).to have_attributes(taxable_amount: 48, tax_free_amount: 100)
    end

    it "takes the tax type and rate from the input before the reference, and has no default" do
      input = allowance([item(100)], { sales_amount: 99, tax_amount: 1, total_amount: 100 }, tax_rate: 0.01)
      expect(input.tax_rate).to eq(Rational(1, 100))

      expect { allowance([item(100)], { sales_amount: 95, tax_amount: 5, total_amount: 100 }, invoice: "JU1") }
        .to raise_error(Einvoice::ValidationError, /tax_type is required, or invoice.tax_type in the reference/)
      expect do
        allowance([item(100)], { sales_amount: 95, tax_amount: 5, total_amount: 100 }, invoice: "JU1",
                                                                                       tax_type: "TAXABLE")
      end.to raise_error(Einvoice::ValidationError, /tax_rate is required, or invoice.tax_rate/)
    end

    it "checks the amount against the items, as G0401 has it" do
      expect { allowance([item(90)], { sales_amount: 95, tax_amount: 5, total_amount: 100 }) }
        .to raise_error(Einvoice::ValidationError, /total_amount is 100, but the items add up to 90/)
      # Tax 0 with tax-included items was the old way to ask for a split.
      expect { allowance([item(100)], { sales_amount: 100, tax_amount: 0, total_amount: 100 }) }
        .to raise_error(Einvoice::ValidationError, /tax_amount is 0, but the tax of the items is 5/)
      # Untaxed items cannot carry tax: this used to give sales 100, tax 0, total 105.
      expect do
        allowance([item(100, tax_type: "TAX_FREE")], { sales_amount: 100, tax_amount: 5, total_amount: 105 },
                  price_mode: "TAX_EXCLUSIVE")
      end.to raise_error(Einvoice::ValidationError, /total_amount is 105, but the items add up to 100/)
    end
  end

  describe ".void_allowance" do
    it "fills the reason the MIG suggests" do
      input = described_class.void_allowance({ "allowance" => "A1" })
      expect(input.reason).to eq("作廢折讓")
    end
  end

  describe "references" do
    it "takes a plain number, a hash or a reference" do
      expect(described_class.void({ invoice: "JU1", reason: "x" }).invoice)
        .to eq(Einvoice::InvoiceReference.new(number: "JU1"))
      reference = Einvoice::InvoiceReference.new(number: "JU2", order_id: "O2")
      expect(described_class.void({ invoice: reference, reason: "x" }).invoice).to eq(reference)
    end

    it "reads the fields of a hash" do
      invoice = described_class.void({
        invoice: { "number" => "JU1", "invoice_datetime" => Date.new(2026, 8, 1), "random_code" => "1234",
                   "order_id" => "O1", "total_amount" => "100", "buyer_ubn" => "53538851" },
        reason: "x"
      }).invoice
      expect(invoice.invoice_datetime.strftime("%F %T %:z")).to eq("2026-08-01 00:00:00 +08:00")
      expect(invoice.total_amount).to eq(100)
      expect(invoice.buyer_ubn).to eq("53538851")
    end

    it "checks the fields of a hash" do
      expect { described_class.void({ invoice: { number: "JU1", buyer_ubn: "1" }, reason: "x" }) }
        .to raise_error(Einvoice::ValidationError, /invoice.buyer_ubn must be 8 digits/)
      expect { described_class.void({ invoice: { number: "JU1", total_amount: "12.5" }, reason: "x" }) }
        .to raise_error(Einvoice::ValidationError, /invoice.total_amount must be a whole number/)
      expect { described_class.void({ invoice: { number: "JU1", invoice_datetime: 20_260_801 }, reason: "x" }) }
        .to raise_error(Einvoice::ValidationError, /invoice.invoice_datetime must be a Time/)
      expect { described_class.void({ invoice: { order_id: "O1" }, reason: "x" }) }
        .to raise_error(Einvoice::ValidationError, /invoice.number is required/)
    end

    # A reference is stored for days, often as JSON, so its stored form has to
    # come back as the same reference.
    it "reads a stored reference back unchanged" do
      invoice = Einvoice::InvoiceReference.new(
        number: "JU1", invoice_datetime: Time.utc(2026, 7, 31, 16, 30, Rational(1, 4)), random_code: "0123",
        order_id: "O1", total_amount: 100, buyer_ubn: "53538851", tax_type: :mixed, tax_rate: Rational(5, 100)
      )
      allowance = Einvoice::AllowanceReference.new(allowance_number: "A1", allowance_date: Date.new(2026, 8, 1),
                                                   invoice_number: "JU1")
      stored = JSON.parse(JSON.generate(invoice: invoice.to_h, allowance: allowance.to_h))

      expect(stored["invoice"]["invoice_datetime"]).to eq("2026-08-01T00:30:00.250000000+08:00")
      expect(described_class.void({ invoice: stored["invoice"], reason: "x" }).invoice).to eq(invoice)
      expect(described_class.void_allowance({ allowance: stored["allowance"] }).allowance).to eq(allowance)
    end

    it "reads a stored time only with its offset" do
      read = ->(value) { described_class.void({ invoice: { number: "JU1", invoice_datetime: value }, reason: "x" }) }
      times = ["2026-08-01T10:00:00+08:00", "2026-08-01T02:00:00Z", "2026-08-01 10:00:00 +0800"]
      expect(times.map { |time| read.call(time).invoice.invoice_datetime }.uniq)
        .to eq([Time.new(2026, 8, 1, 10, 0, 0, "+08:00")])
      expect(read.call("2026-08-01").invoice.invoice_datetime.strftime("%F %T %:z")).to eq("2026-08-01 00:00:00 +08:00")
      expect { read.call("2026-08-01 10:00:00") }
        .to raise_error(Einvoice::ValidationError, /invoice.invoice_datetime must be a date .* or a time with an offset/)
      expect { read.call("2026-02-30") }.to raise_error(Einvoice::ValidationError, /not a valid date/)
    end

    it "takes an allowance as a plain number, a hash or a reference" do
      expect(described_class.void_allowance({ allowance: "A1" }).allowance.allowance_number).to eq("A1")
      allowance = described_class.void_allowance({
        allowance: { allowance_number: "A1", allowance_date: Time.utc(2026, 7, 31, 16), invoice_number: "JU1" }
      }).allowance
      expect(allowance).to eq(Einvoice::AllowanceReference.new(allowance_number: "A1",
                                                               allowance_date: Date.new(2026, 8, 1),
                                                               invoice_number: "JU1"))
      expect { described_class.void_allowance({}) }.to raise_error(Einvoice::ValidationError, /allowance is required/)
    end
  end

  # "Required" has to mean the same thing for every field. Two helpers used to
  # disagree — one treated an empty string as missing, the other only checked
  # for nil — so an empty description or npoban sailed through to the provider.
  describe "required fields" do
    it "rejects an empty string the same way as a missing key" do
      {
        "order_id" => /order_id is required/,
        "items" => /description is required/
      }.each do |field, message|
        hash = field == "items" ? issue_hash.merge("items" => [issue_hash["items"].first.merge("description" => "")]) : issue_hash.merge(field => "")
        expect { described_class.issue(hash) }.to raise_error(Einvoice::ValidationError, message)
      end
    end

    it "rejects an empty npoban" do
      expect { described_class.issue(issue_hash.merge("donation" => { "npoban" => "" })) }
        .to raise_error(Einvoice::ValidationError, /npoban is required/)
    end

    it "rejects an empty reason on a void" do
      expect { described_class.void({ "invoice" => "JU1", "reason" => "" }) }
        .to raise_error(Einvoice::ValidationError, /reason is required/)
    end

    # A zero is a value, not an absence — blank? must not swallow it.
    it "still accepts zero quantities and amounts" do
      input = described_class.issue(issue_hash.merge(
                                      "items" => [{ "description" => "贈品", "quantity" => 0,
                                                    "unit_price" => 0, "amount" => 0 }],
                                      "amount" => { "sales_amount" => 0, "tax_amount" => 0,
                                                    "total_amount" => 0 }
                                    ))
      expect(input.items.first.quantity).to eq(0)
      expect(input.amount.total_amount).to eq(0)
    end
  end

  # The promise of this layer is that bad input fails the same way everywhere.
  # A value of the wrong shape used to escape as a raw NoMethodError/TypeError
  # from wherever it was first indexed, which is neither catchable as
  # Einvoice::Error nor any help in locating the offending field.
  describe "input that is not the right shape" do
    it "rejects a top-level value that is not an object, on every operation" do
      %i[issue void allowance void_allowance query].each do |operation|
        [nil, "string", [], 42].each do |value|
          expect { described_class.public_send(operation, value) }
            .to raise_error(Einvoice::ValidationError, /input must be an object/),
                "#{operation}(#{value.inspect}) did not raise a ValidationError"
        end
      end
    end

    it "names the nested field that was the wrong shape" do
      {
        "buyer" => /buyer must be an object, got String/,
        "carrier" => /carrier must be an object, got String/,
        "amount" => /amount must be an object, got String/,
        "donation" => /donation must be an object, got String/
      }.each do |field, message|
        expect { described_class.issue(issue_hash.merge(field => "nope")) }
          .to raise_error(Einvoice::ValidationError, message)
      end
    end

    it "names the item index that was the wrong shape" do
      expect { described_class.issue(issue_hash.merge("items" => [nil])) }
        .to raise_error(Einvoice::ValidationError, /items\[0\] must be an object, got nil/)

      expect { described_class.issue(issue_hash.merge("items" => [issue_hash["items"].first, 42])) }
        .to raise_error(Einvoice::ValidationError, /items\[1\] must be an object, got Integer/)
    end

    it "still accepts an absent optional object" do
      input = described_class.issue(issue_hash.merge("buyer" => nil, "carrier" => nil))
      expect(input.buyer).to be_nil
      expect(input.carrier).to be_nil
    end
  end

  # donation was the one nested shape that never had its keys normalized, so a
  # string-keyed one — the whole point of this layer — was rejected as missing.
  describe "donation" do
    it "accepts string keys like every other nested object" do
      input = described_class.issue(issue_hash.merge("donation" => { "npoban" => "168001" }))
      expect(input.donation).to eq(Einvoice::Donation.new(npoban: "168001"))
    end

    it "accepts symbol keys" do
      input = described_class.issue(issue_hash.merge("donation" => { npoban: "168001" }))
      expect(input.donation.npoban).to eq("168001")
    end

    it "checks a Donation value object as it checks a Hash" do
      donation = Einvoice::Donation.new(npoban: "168001")
      expect(described_class.issue(issue_hash.merge("donation" => donation)).donation).to eq(donation)
      expect { described_class.issue(issue_hash.merge("donation" => Einvoice::Donation.new(npoban: "abc"))) }
        .to raise_error(Einvoice::ValidationError, /npoban must be 3–7 digits/)
    end

    it "requires the npoban" do
      expect { described_class.issue(issue_hash.merge("donation" => {})) }
        .to raise_error(Einvoice::ValidationError, /npoban is required/)
    end

    # Present but nonsense used to sail through to the provider, which is the
    # one thing this layer exists to prevent.
    it "rejects an npoban that is not a 3–7 digit 愛心碼" do
      ["abc", "1", "12", "12345678", "168-001", "16 8001", "１６８００１"].each do |bad|
        expect { described_class.issue(issue_hash.merge("donation" => { "npoban" => bad })) }
          .to raise_error(Einvoice::ValidationError, /npoban must be 3–7 digits/)
      end
    end

    it "accepts the full 3–7 digit range" do
      %w[105 0096 168001 1234567].each do |good|
        input = described_class.issue(issue_hash.merge("donation" => { "npoban" => good }))
        expect(input.donation.npoban).to eq(good)
      end
    end

    # A JSON payload can carry the code as a number. Normalizing to a String
    # keeps it comparable with 財政部's data, which returns strings.
    it "normalizes a numeric npoban to a String" do
      input = described_class.issue(issue_hash.merge("donation" => { "npoban" => 168_001 }))
      expect(input.donation.npoban).to eq("168001")
    end

    # 0096 is a real 愛心碼. As an Integer it is 96, which is not a valid code,
    # so this has to fail rather than be padded back into something plausible.
    it "refuses a numeric code whose leading zero was already lost" do
      expect { described_class.issue(issue_hash.merge("donation" => { "npoban" => 96 })) }
        .to raise_error(Einvoice::ValidationError, /npoban must be 3–7 digits/)
    end

    # The rule is applied in three places — here, the ECPay payload and the
    # 財政部 client. Core used to accept "abc" while the other two rejected it,
    # so sharing one object is what stops them drifting apart again. Identity,
    # not equality: an inlined copy of the same pattern would pass ==.
    it "is the same object the 財政部 client matches against" do
      expect(Einvoice::MOF::DonationCodes::CODE_FORMAT).to be(Einvoice::Donation::CODE_FORMAT)
    end
  end
end
