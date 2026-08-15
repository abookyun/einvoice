# frozen_string_literal: true

# Drives ECPay's real B2C stage API. Skipped unless ECPAY_LIVE=1, so CI and a
# normal `rspec` run stay offline; the fake in the provider spec covers the same
# ground deterministically.
#
#   ECPAY_LIVE=1 bundle exec rspec spec/einvoice/ecpay/live_spec.rb
#
# It defaults to ECPay's published sandbox credentials, so ECPAY_LIVE=1 is enough;
# override with ECPAY_MERCHANT_ID / ECPAY_HASH_KEY / ECPAY_HASH_IV to run it
# against your own stage account.
#
# What it is for: the fake can only prove the adapter agrees with our reading of
# the API. This proves the reading itself — the encryption, the envelope, the
# field names, and every RtnCode the error mapping keys on.
RSpec.describe "ECPay live stage API", :live do
  before(:all) do
    skip "set ECPAY_LIVE=1 to run the live ECPay stage specs" unless ENV["ECPAY_LIVE"] == "1"
  end

  let(:provider) do
    Einvoice::ECPay::Provider.new(
      merchant_id: ENV.fetch("ECPAY_MERCHANT_ID", Einvoice::ECPay::SANDBOX[:merchant_id]),
      hash_key: ENV.fetch("ECPAY_HASH_KEY", Einvoice::ECPay::SANDBOX[:hash_key]),
      hash_iv: ENV.fetch("ECPAY_HASH_IV", Einvoice::ECPay::SANDBOX[:hash_iv]),
      mode: Einvoice::ProviderMode::TEST
    )
  end

  # The sandbox is shared with every other developer, so order ids must not collide.
  def order_id(suffix = "")
    "RB#{Time.now.strftime('%y%m%d%H%M%S')}#{rand(1000..9999)}#{suffix}"
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

  it "issues, queries and voids an invoice" do
    order = order_id
    issued = provider.issue(issue_input(order))

    expect(issued.invoice_number).to match(/\A[A-Z]{2}\d{8}\z/)
    expect(issued.random_code).to match(/\A\d{4}\z/)
    expect(issued.status).to eq(Einvoice::InvoiceStatus::ISSUED)

    found = provider.query(order_id: order)
    expect(found.invoice_number).to eq(issued.invoice_number)
    expect(found.order_id).to eq(order)
    expect(found.amount.total_amount).to eq(100)
    expect(found.items.first.description).to eq("整合測試商品")
    expect(found.status).to eq(Einvoice::InvoiceStatus::ISSUED)

    by_number = provider.query(invoice_number: issued.invoice_number)
    expect(by_number.invoice_number).to eq(issued.invoice_number)

    voided = provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢")
    expect(voided.status).to eq(Einvoice::InvoiceStatus::VOIDED)
    expect(provider.query(order_id: order).status).to eq(Einvoice::InvoiceStatus::VOIDED)
  end

  it "credits an invoice and reverses the allowance" do
    order = order_id
    issued = provider.issue(issue_input(order))

    allowance = provider.allowance(
      invoice_number: issued.invoice_number,
      allowance_id: "AL_#{order}",
      items: [{ description: "整合測試商品", quantity: 1, unit_price: 50, amount: 50 }],
      amount: { sales_amount: 50, tax_amount: 0, total_amount: 50 }
    )
    expect(allowance.allowance_number).not_to be_empty
    expect(allowance.invoice_number).to eq(issued.invoice_number)
    expect(provider.query(order_id: order).status).to eq(Einvoice::InvoiceStatus::ALLOWANCE)

    # A credited invoice cannot be voided until its allowances are reversed —
    # the case the :void_blocked_by_allowance reason exists for.
    expect { provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢") }
      .to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE)
      }

    provider.void_allowance(invoice_number: issued.invoice_number,
                            allowance_number: allowance.allowance_number)
    expect(provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢").status)
      .to eq(Einvoice::InvoiceStatus::VOIDED)
  end

  describe "the error mapping" do
    it "maps a duplicate 自訂編號 to a duplicate-order conflict" do
      order = order_id
      provider.issue(issue_input(order))

      expect { provider.issue(issue_input(order)) }
        .to raise_error(Einvoice::ConflictError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
          expect(error.raw_code).to eq("5070357")
        }
    end

    it "maps a second void to an already-voided conflict" do
      order = order_id
      issued = provider.issue(issue_input(order))
      provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢")

      expect { provider.void(invoice_number: issued.invoice_number, reason: "整合測試作廢") }
        .to raise_error(Einvoice::ConflictError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::ALREADY_VOIDED)
        }
    end

    it "maps an unknown invoice to not found" do
      expect { provider.query(invoice_number: "ZZ00000000") }
        .to raise_error(Einvoice::NotFoundError)
    end

    it "maps an unknown 折讓單 to not found" do
      expect do
        provider.void_allowance(invoice_number: "ZZ00000000",
                                allowance_number: "9999999999999999")
      end.to raise_error(Einvoice::NotFoundError)
    end

    it "maps a bad hash key to an auth error" do
      wrong = Einvoice::ECPay::Provider.new(
        merchant_id: Einvoice::ECPay::SANDBOX[:merchant_id],
        hash_key: "0000000000000000", hash_iv: "1111111111111111",
        mode: Einvoice::ProviderMode::TEST
      )

      expect { wrong.issue(issue_input(order_id)) }
        .to raise_error(Einvoice::AuthError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::CREDENTIALS_INVALID)
          expect(error.raw_code).to eq("110")
        }
    end

    it "rejects an amount that disagrees with the items" do
      # Sent with local validation off, so it is ECPay rejecting it, not us.
      lax = Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX,
                                          mode: Einvoice::ProviderMode::TEST,
                                          validate_payload: false)

      expect do
        lax.issue(issue_input(order_id,
                              amount: { sales_amount: 999, tax_amount: 0, total_amount: 999 }))
      end.to raise_error(Einvoice::ValidationError, /金額/)
    end
  end

  describe "carrier validation" do
    it "confirms a registered 手機條碼" do
      expect(provider.validate_mobile_barcode("/ABC1234")).to be(true)
    end

    it "resolves the organisation behind a 愛心碼" do
      expect(provider.love_code_organ_name("168001")).to be_a(String)
    end
  end

  it "issues a B2B invoice carrying a 統一編號" do
    order = order_id
    issued = provider.issue(issue_input(order,
                                        buyer: { ubn: "53538851", name: "測試股份有限公司",
                                                 email: "test@example.com" }))

    expect(issued.invoice_number).to match(/\A[A-Z]{2}\d{8}\z/)
    expect(provider.query(order_id: order).buyer.ubn).to eq("53538851")
  end
end
