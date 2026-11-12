# frozen_string_literal: true

# Drives Amego's real API with its published shared test account. Skipped
# unless AMEGO_LIVE=1, so CI and a normal `rspec` run stay offline. The fake in
# the provider spec covers the same ground deterministically.
#
#   AMEGO_LIVE=1 bundle exec rspec spec/einvoice/amego/live_spec.rb
#
# Override with AMEGO_BAN / AMEGO_APP_KEY to run it against your own test
# account. Amego has one host for test and production, so never point it at a
# production account.
#
# What it is for: the fake can only prove that the adapter agrees with our
# reading of the docs. This checks the reading itself: the sign, the form
# encoding, the totals, the response shapes and the codes the error mapping
# uses. docs/providers/amego/api.md lists the open questions it answers.
RSpec.describe "Amego live API", :live do
  before(:all) do
    skip "set AMEGO_LIVE=1 to run the live Amego specs" unless ENV["AMEGO_LIVE"] == "1"
  end

  let(:provider) do
    Einvoice::Amego::Provider.new(ban: ENV.fetch("AMEGO_BAN", Einvoice::Amego::SANDBOX[:ban]),
                                  app_key: ENV.fetch("AMEGO_APP_KEY", Einvoice::Amego::SANDBOX[:app_key]))
  end

  # The test account is shared with every other developer, so ids must not
  # collide. Allowance numbers are max 16: 2 + 12 + 2.
  def unique_id(prefix)
    "#{prefix}#{Time.now.strftime('%y%m%d%H%M%S')}#{rand(10..99)}"
  end

  def issue_input(order, overrides = {})
    {
      order_id: order,
      buyer: { email: "test@example.com" },
      items: [{ description: "整合 測試 商品", quantity: 2, unit_price: 50, amount: 100 }],
      amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 },
      tax_type: "TAXABLE",
      price_mode: "TAX_INCLUSIVE"
    }.merge(overrides)
  end

  # A change waits in Amego's queue (3050121, 3050131). Retry a few times.
  def retry_queued(attempts: 6, wait: 5)
    yield
  rescue Einvoice::ConflictError => e
    raise unless %w[3050121 3050131 4050141].include?(e.raw_code) && (attempts -= 1).positive?

    sleep wait
    retry
  end

  it "issues a B2C invoice and reads it back by order id and by number" do
    order = unique_id("RB")
    issued = provider.issue(issue_input(order))

    expect(issued.invoice_number).to match(/\A[A-Z]{2}\d{8}\z/)
    expect(issued.random_code).to match(/\A\d{4}\z/)
    expect(issued.invoice_datetime).to be_within(300).of(Time.now)

    found = provider.query({ invoice: { order_id: order } })
    expect(found.invoice_number).to eq(issued.invoice_number)
    expect(found.order_id).to eq(order)
    expect(found.amount).to eq(Einvoice::AmountSummary.new(sales_amount: 100, tax_amount: 0, total_amount: 100))
    # The space survives the form encoding, and the sign was accepted with it.
    expect(found.items.first.description).to eq("整合 測試 商品")
    expect(found.status).to eq(Einvoice::InvoiceStatus::ISSUED)
    expect(found.reference).to have_attributes(tax_type: Einvoice::TaxType::TAXABLE, tax_rate: Rational(5, 100))

    expect(provider.query({ invoice: issued.reference }).invoice_number).to eq(issued.invoice_number)
  end

  # Amego takes TaxRate 0 for an invoice with no taxed item (docs, section 4.2).
  it "issues a tax-free invoice with a rate of 0" do
    order = unique_id("RB")
    provider.issue(issue_input(order, tax_type: "TAX_FREE"))

    found = provider.query({ invoice: { order_id: order } })
    expect(found.reference).to have_attributes(tax_type: Einvoice::TaxType::TAX_FREE, tax_rate: 0)
  end

  it "issues a B2B invoice with the tax split out" do
    order = unique_id("RB")
    provider.issue(issue_input(order, buyer: { ubn: "28080623", name: "光貿科技" },
                                      items: [{ description: "整合測試商品", quantity: 1, unit_price: 1050,
                                                amount: 1050 }],
                                      amount: { sales_amount: 1000, tax_amount: 50, total_amount: 1050 }))

    found = provider.query({ invoice: { order_id: order } })
    expect(found.amount).to eq(Einvoice::AmountSummary.new(sales_amount: 1000, tax_amount: 50, total_amount: 1050))
    expect(found.buyer.ubn).to eq("28080623")
  end

  it "credits a B2C invoice, splitting the tax, then cancels the allowance" do
    issued = provider.issue(issue_input(unique_id("RB"), items: [
                                          { description: "整合測試商品", quantity: 1, unit_price: 99, amount: 99 }
                                        ], amount: { sales_amount: 99, tax_amount: 0, total_amount: 99 }))
    number = unique_id("AL")

    allowance = retry_queued do
      provider.allowance({ invoice: issued.reference, allowance_id: number,
                           items: [{ description: "整合測試商品", quantity: 1, unit_price: 99, amount: 99 }],
                           amount: { sales_amount: 94, tax_amount: 5, total_amount: 99 },
                           price_mode: "TAX_INCLUSIVE" })
    end
    expect(allowance.allowance_number).to eq(number)

    cancelled = retry_queued do
      provider.void_allowance({ allowance: allowance.reference })
    end
    expect(cancelled.allowance_number).to eq(number)
  end

  it "voids an invoice, and refuses a second void" do
    issued = provider.issue(issue_input(unique_id("RB")))
    voided = retry_queued { provider.void({ invoice: issued.reference, reason: "整合測試作廢" }) }
    expect(voided.status).to eq(Einvoice::InvoiceStatus::VOIDED)

    expect { provider.void({ invoice: issued.reference, reason: "整合測試作廢" }) }
      .to raise_error(Einvoice::ConflictError)
  end

  it "maps unknown invoices and allowances to NotFoundError" do
    expect { provider.query({ invoice: "ZZ00000000" }) }.to raise_error(Einvoice::NotFoundError)
    expect { provider.void({ invoice: "ZZ00000000", reason: "整合測試" }) }
      .to raise_error(Einvoice::NotFoundError)
    expect { provider.void_allowance({ allowance: "NOPE0000000000" }) }
      .to raise_error(Einvoice::NotFoundError)
  end
end
