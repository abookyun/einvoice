# frozen_string_literal: true

require "spec_helper"

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

    it "passes an already-built input through untouched" do
      input = described_class.issue(issue_hash)
      expect(described_class.issue(input)).to be(input)
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

  describe ".query" do
    it "requires at least one of invoice_number / order_id" do
      expect { described_class.query({}) }.to raise_error(Einvoice::ValidationError)
      expect(described_class.query({ "order_id" => "O1" }).order_id).to eq("O1")
    end
  end

  describe ".void" do
    it "requires invoice_number and reason" do
      expect { described_class.void({ "invoice_number" => "JU1" }) }
        .to raise_error(Einvoice::ValidationError, /reason/)
      expect(described_class.void({ "invoice_number" => "JU1", "reason" => "x" }).reason).to eq("x")
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
      expect { described_class.void({ "invoice_number" => "JU1", "reason" => "" }) }
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

    it "passes an already-built Donation through" do
      donation = Einvoice::Donation.new(npoban: "168001")
      expect(described_class.issue(issue_hash.merge("donation" => donation)).donation).to be(donation)
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
