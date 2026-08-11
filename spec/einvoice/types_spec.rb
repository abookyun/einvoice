# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Einvoice unified types" do
  describe Einvoice::Buyer do
    it "defaults every field to nil" do
      expect(described_class.new.to_h).to eq(
        name: nil, ubn: nil, email: nil, address: nil, phone: nil
      )
    end

    it "is a business buyer only when a ubn is present" do
      expect(described_class.new(ubn: "53538851").business?).to be(true)
      expect(described_class.new(ubn: "").business?).to be(false)
      expect(described_class.new(email: "b@x.com").business?).to be(false)
    end
  end

  describe Einvoice::InvoiceItem do
    it "requires the core fields and defaults the optional ones" do
      item = described_class.new(description: "商品一", quantity: 1, unit_price: 100, amount: 100)
      expect(item.tax_type).to be_nil
      expect(item.remark).to be_nil
      expect { described_class.new(description: "x", quantity: 1, unit_price: 1) }
        .to raise_error(ArgumentError)
    end
  end

  describe Einvoice::IssueInvoiceInput do
    let(:base) do
      {
        order_id: "ORDER_1",
        buyer: Einvoice::Buyer.new(email: "b@x.com"),
        items: [Einvoice::InvoiceItem.new(description: "商品一", quantity: 1, unit_price: 100, amount: 100)],
        amount: Einvoice::AmountSummary.new(sales_amount: 100, tax_amount: 0, total_amount: 100),
        tax_type: Einvoice::TaxType::TAXABLE,
        price_mode: Einvoice::PriceMode::TAX_INCLUSIVE
      }
    end

    it "derives category from the buyer's ubn when not set explicitly" do
      expect(described_class.new(**base).resolved_category).to eq(:b2c)
      b2b = described_class.new(**base, buyer: Einvoice::Buyer.new(ubn: "53538851"))
      expect(b2b.resolved_category).to eq(:b2b)
    end

    it "honours an explicit category over the derived one" do
      input = described_class.new(**base, category: Einvoice::InvoiceCategory::B2B)
      expect(input.resolved_category).to eq(:b2b)
    end

    it "is immutable and supports #with and pattern matching" do
      input = described_class.new(**base)
      expect { input.instance_variable_set(:@order_id, "x") }.to raise_error(FrozenError)
      expect(input.with(order_id: "ORDER_2").order_id).to eq("ORDER_2")
      input => { order_id:, tax_type: }
      expect([order_id, tax_type]).to eq(["ORDER_1", :taxable])
    end
  end

  describe "enums" do
    it "expose their members as frozen symbol lists" do
      expect(Einvoice::TaxType::ALL).to eq(%i[taxable zero_rated tax_free special])
      expect(Einvoice::CarrierType::MEMBER).to eq(:member)
      expect(Einvoice::InvoiceStatus::ALL).to be_frozen
    end
  end
end
