# frozen_string_literal: true

# The adapter against real ECPay responses, replayed from cassettes recorded on
# the stage host with ECPay's published sandbox credentials.
#
# This is the layer the hand-written fake cannot give us: the payloads here are
# ECPay's own, so the field names, value types (ItemCount comes back as a float,
# IIS_Identifier as a zero placeholder) and error codes are the real ones rather
# than our reading of the documentation. It runs offline, so CI gets that
# guarantee on every push.
#
# See spec/support/vcr.rb for how to re-record.
RSpec.describe "Einvoice::ECPay::Provider against recorded ECPay responses" do
  # Bump when re-recording — 自訂編號 must be unique per merchant, so re-recording
  # under the old ids would be rejected as duplicates.
  let(:recording_epoch) { "20260815" }

  # Recording only ever uses the published sandbox credentials, never the
  # environment, so a cassette cannot capture a real merchant's traffic.
  subject(:provider) { Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX) }

  def order_id(name)
    "RBVCR#{recording_epoch}#{name}"
  end

  def issue_input(order, overrides = {})
    {
      order_id: order,
      buyer: { email: "test@example.com" },
      items: [{ description: "整合測試商品", quantity: 2, unit_price: 50, amount: 100 }],
      amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
      tax_type: "TAXABLE",
      price_mode: "TAX_INCLUSIVE",
      carrier: { type: "MEMBER" }
    }.merge(overrides)
  end

  describe "#issue", vcr: { cassette_name: "ecpay/issue" } do
    it "reads ECPay's own issue response into an IssueInvoiceResult" do
      result = provider.issue(issue_input(order_id("issue")))

      expect(result).to be_a(Einvoice::IssueInvoiceResult)
      expect(result.invoice_number).to match(/\A[A-Z]{2}\d{8}\z/)
      expect(result.random_code).to match(/\A\d{4}\z/)
      expect(result.invoice_date).to be_a(Time)
      expect(result.status).to eq(Einvoice::InvoiceStatus::ISSUED)
      expect(result.total_amount).to eq(100)
      # The untouched provider payload stays available for anything unmapped.
      expect(result.raw).to include("RtnCode" => 1, "RtnMsg" => "開立發票成功")
    end
  end

  describe "#query" do
    it "reads a GetIssue response into a QueryInvoiceResult",
       vcr: { cassette_name: "ecpay/query_by_order_id" } do
      order = order_id("qorder")
      issued = provider.issue(issue_input(order))
      found = provider.query(order_id: order)

      expect(found).to be_a(Einvoice::QueryInvoiceResult)
      expect(found.invoice_number).to eq(issued.invoice_number)
      expect(found.order_id).to eq(order)
      expect(found.status).to eq(Einvoice::InvoiceStatus::ISSUED)
      expect(found.random_code).to eq(issued.random_code)
      expect(found.invoice_date).to be_a(Time)
    end

    it "maps the amounts and the buyer ECPay returns",
       vcr: { cassette_name: "ecpay/query_amounts" } do
      order = order_id("qamt")
      provider.issue(issue_input(order))
      found = provider.query(order_id: order)

      expect(found.amount).to be_a(Einvoice::AmountSummary)
      expect(found.amount.total_amount).to eq(100)
      expect(found.amount.sales_amount + found.amount.tax_amount)
        .to eq(found.amount.total_amount)
      expect(found.buyer.email).to eq("test@example.com")
      # ECPay writes a zero placeholder rather than leaving a B2C 統編 blank.
      expect(found.buyer.ubn).to be_nil
    end

    it "maps the items ECPay returns, whose numbers come back as floats",
       vcr: { cassette_name: "ecpay/query_items" } do
      order = order_id("qitems")
      provider.issue(issue_input(order))
      item = provider.query(order_id: order).items.first

      expect(item).to be_a(Einvoice::InvoiceItem)
      expect(item.description).to eq("整合測試商品")
      expect(item.quantity).to eq(2)
      expect(item.unit_price).to eq(50)
      expect(item.amount).to eq(100)
      expect(item.tax_type).to eq(Einvoice::TaxType::TAXABLE)
    end

    it "pairs an invoice number with its issue date",
       vcr: { cassette_name: "ecpay/query_by_invoice_number" } do
      issued = provider.issue(issue_input(order_id("qnum")))
      found = provider.query(invoice_number: issued.invoice_number)

      expect(found.invoice_number).to eq(issued.invoice_number)
    end
  end

  describe "#void", vcr: { cassette_name: "ecpay/void" } do
    it "voids an invoice and reports it as voided afterwards" do
      order = order_id("void")
      issued = provider.issue(issue_input(order))

      result = provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢")
      expect(result).to be_a(Einvoice::VoidInvoiceResult)
      expect(result.status).to eq(Einvoice::InvoiceStatus::VOIDED)

      expect(provider.query(order_id: order).status).to eq(Einvoice::InvoiceStatus::VOIDED)
    end
  end

  describe "#allowance", vcr: { cassette_name: "ecpay/allowance" } do
    it "credits an invoice, blocks the void, then reverses the allowance" do
      order = order_id("allow")
      issued = provider.issue(issue_input(order))

      allowance = provider.allowance(
        invoice_number: issued.invoice_number,
        allowance_id: "AL_#{order}",
        items: [{ description: "整合測試商品", quantity: 1, unit_price: 50, amount: 50 }],
        amount: { sales_amount: 50, tax_amount: 0, total_amount: 50 }
      )
      expect(allowance).to be_a(Einvoice::AllowanceResult)
      expect(allowance.allowance_number).not_to be_empty
      expect(allowance.invoice_number).to eq(issued.invoice_number)
      expect(allowance.allowance_date).to be_a(Time)

      # A partly credited invoice reads as ALLOWANCE, not ISSUED.
      expect(provider.query(order_id: order).status).to eq(Einvoice::InvoiceStatus::ALLOWANCE)

      # And it cannot be voided until the 折讓單 is reversed — the whole reason
      # :void_blocked_by_allowance exists.
      expect { provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢") }
        .to raise_error(Einvoice::ConflictError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE)
          expect(error.raw_code).to eq("5070450")
        }

      reversed = provider.void_allowance(invoice_number: issued.invoice_number,
                                         allowance_number: allowance.allowance_number)
      expect(reversed).to be_a(Einvoice::VoidAllowanceResult)
      expect(reversed.allowance_number).to eq(allowance.allowance_number)
    end
  end

  describe "crediting a voided invoice", vcr: { cassette_name: "ecpay/allowance_on_voided" } do
    # The contract requires a ConflictError here, and ECPay reports it with a
    # code and wording that read nothing like its other conflicts — which is
    # exactly why this is pinned against real traffic rather than a guess.
    it "is refused as a conflict, not a field error" do
      order = order_id("voidalw")
      issued = provider.issue(issue_input(order))
      provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢")

      expect do
        provider.allowance(
          invoice_number: issued.invoice_number, allowance_id: "AL_#{order}",
          items: [{ description: "整合測試商品", quantity: 1, unit_price: 50, amount: 50 }],
          amount: { sales_amount: 50, tax_amount: 0, total_amount: 50 }
        )
      end.to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::ALREADY_VOIDED)
        expect(error.raw_code).to eq("2000042")
        expect(error.raw_message).to include("作廢發票號碼不能折讓")
      }
    end
  end

  describe "B2B", vcr: { cassette_name: "ecpay/b2b" } do
    it "issues against a 統一編號 and reads it back" do
      order = order_id("b2b")
      provider.issue(issue_input(order, buyer: { ubn: "53538851", name: "測試股份有限公司",
                                                 email: "test@example.com" }))

      expect(provider.query(order_id: order).buyer.ubn).to eq("53538851")
    end
  end

  # Each of these is a real ECPay failure, so the mapping is checked against the
  # codes and wording the API actually produces rather than ones we invented.
  describe "error mapping" do
    it "maps a duplicate 自訂編號 to a duplicate-order conflict",
       vcr: { cassette_name: "ecpay/duplicate_order" } do
      order = order_id("dup")
      provider.issue(issue_input(order))

      expect { provider.issue(issue_input(order)) }
        .to raise_error(Einvoice::ConflictError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
          expect(error.raw_code).to eq("5070357")
          expect(error.raw_message).to include("重覆")
          expect(error.provider).to eq("ecpay")
        }
    end

    it "maps a second void to an already-voided conflict",
       vcr: { cassette_name: "ecpay/already_voided" } do
      issued = provider.issue(issue_input(order_id("revoid")))
      provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢")

      expect { provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢") }
        .to raise_error(Einvoice::ConflictError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::ALREADY_VOIDED)
          expect(error.raw_code).to eq("5070453")
        }
    end

    it "maps an unknown invoice to not found",
       vcr: { cassette_name: "ecpay/unknown_invoice" } do
      expect { provider.query(invoice_number: "ZZ00000000") }
        .to raise_error(Einvoice::NotFoundError) { |error|
          expect(error.raw_code).to eq("2")
          expect(error.raw_message).to include("查無發票資料")
        }
    end

    it "maps an unknown 折讓單 to not found",
       vcr: { cassette_name: "ecpay/unknown_allowance" } do
      expect do
        provider.void_allowance(invoice_number: "ZZ00000000",
                                allowance_number: "9999999999999999")
      end.to raise_error(Einvoice::NotFoundError) { |error|
        expect(error.raw_code).to eq("2000039")
      }
    end

    # The wrong HashKey fails at the transport layer, before any business logic —
    # ECPay cannot decrypt Data, so it never sees the request at all.
    it "maps a bad hash key to an auth error",
       vcr: { cassette_name: "ecpay/bad_credentials" } do
      wrong = Einvoice::ECPay::Provider.new(
        merchant_id: Einvoice::ECPay::SANDBOX[:merchant_id],
        hash_key: "0000000000000000", hash_iv: "1111111111111111"
      )

      expect { wrong.issue(issue_input(order_id("badkey"))) }
        .to raise_error(Einvoice::AuthError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::CREDENTIALS_INVALID)
          expect(error.raw_code).to eq("110")
          expect(error.message).to match(/decrypt fail/i)
        }
    end

    it "surfaces an amount ECPay rejects as a validation error",
       vcr: { cassette_name: "ecpay/amount_mismatch" } do
      # Local validation off, so this is ECPay rejecting it rather than us.
      lax = Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX, validate_payload: false)

      expect do
        lax.issue(issue_input(order_id("amt"),
                              amount: { sales_amount: 999, tax_amount: 0, total_amount: 999 }))
      end.to raise_error(Einvoice::ValidationError) { |error|
        expect(error.raw_code).to eq("5000022")
        expect(error.raw_message).to include("金額")
      }
    end
  end

  describe "carrier validation" do
    it "confirms a registered 手機條碼", vcr: { cassette_name: "ecpay/check_barcode" } do
      expect(provider.validate_mobile_barcode("/ABC1234")).to be(true)
    end

    it "resolves the organisation behind a 愛心碼",
       vcr: { cassette_name: "ecpay/check_love_code" } do
      expect(provider.love_code_organ_name("168001")).to be_a(String)
      expect(provider.validate_love_code("168001")).to be(true)
    end
  end
end
