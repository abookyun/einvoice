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
end
