# frozen_string_literal: true

RSpec.describe Einvoice::Tradevan::DefaultAPI::Provider do
  subject(:provider) { described_class.new(**FakeTradevan::CREDENTIALS) }

  let!(:tradevan) { FakeTradevan.new.install! }

  # The contract over the DEFAULTAPI wire format: the v parameter, both keys,
  # the Success/Message envelope. The reference from issue has the order id
  # and the date that a void and an allowance need. An allowance number has
  # 16 characters (docs, section 4.8).
  it_behaves_like "an invoice provider",
                  unknown_reference: { number: "ZZ00000000" },
                  unknown_allowance_number: "ABCDE20260101999"

  let(:issue_input) do
    {
      order_id: "53b2a44e4b3c",
      buyer: { name: "John Appleseed", email: "john@example.com" },
      items: [{ description: "Coffee Latte", quantity: 4000, unit_price: 5, amount: 20_000 }],
      amount: { sales_amount: 20_000, tax_amount: 0, total_amount: 20_000 },
      tax_type: "TAXABLE", price_mode: "TAX_INCLUSIVE",
      carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" }
    }
  end

  def issue_data(index = -1)
    JSON.parse(tradevan.params(index)["issueData"])
  end

  # A Success Y reply to +path+ with +message+, encrypted as Tradevan does.
  def reply(path, message)
    body = JSON.generate("Success" => "Y",
                         "Message" => Einvoice::Tradevan::DefaultAPI::Crypto.encrypt(JSON.generate(message),
                                                                                     FakeTradevan::KEY1))
    stub_request(:any, %r{tradevan\.test/DEFAULTAPI/#{path}})
      .to_return(headers: { "Content-Type" => "application/json" }, body: body)
  end

  def search_reply(fields)
    reply("get/searchInvoiceDetail", { "invoiceNumber" => "GX38551078", "invoiceDate" => "20160425",
                                       "invoiceTime" => "12:00:00", "total" => "1" }.merge(fields))
  end

  it "identifies itself and declares what it can do" do
    expect(provider.name).to eq("tradevan")
    expect(provider.api_version).to eq("defaultapi")
    expect(provider).to be_supports(Einvoice::Capability::B2B)
    expect(provider).not_to be_supports(Einvoice::Capability::QUERY_BY_ORDER_ID)
    expect(provider).not_to be_supports(Einvoice::Capability::MIXED_TAX)
    expect(provider).not_to be_supports(Einvoice::Capability::FOREIGN_CURRENCY)
  end

  describe "#issue" do
    # Ported from the 1.x provider spec: the request goes through the whole
    # stack, and the response is decoded.
    it "sends the request through the full wire format and reads the response" do
      result = provider.issue(issue_input)

      expect(tradevan.path).to eq("post/issue")
      expect(tradevan.http_method).to eq(:post)
      expect(issue_data).to include("type" => "I", "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
                                    "total" => "20000", "carrierType" => "3J0002")
      expect(result.invoice_number).to match(/\AGX\d{8}\z/)
      expect(result.random_code).to match(/\A\d{4}\z/)
      expect(result.invoice_datetime).to be_a(Time)
      expect(result.order_id).to eq("53b2a44e4b3c")
      expect(result.total_amount).to eq(20_000)
      expect(result.status).to eq(Einvoice::InvoiceStatus::ISSUED)
      expect(result.raw["issueStatus"]).to eq("Y")
      expect(result.reference).to have_attributes(order_id: "53b2a44e4b3c", buyer_ubn: nil,
                                                  tax_type: Einvoice::TaxType::TAXABLE, tax_rate: Rational(5, 100))
    end

    it "sends the transaction time in UTC+8" do
      clock = Struct.new(:now).new(Time.utc(2016, 4, 25, 4, 34, 56))
      described_class.new(**FakeTradevan::CREDENTIALS, clock: clock).issue(issue_input)

      expect(issue_data.values_at("transactionDate", "transactionTime")).to eq(%w[20160425 12:34:56])
    end

    # 1.x returned an unsuccessful result here. 2.0 raises, and the failReason
    # decides the class.
    it "raises ConflictError when Tradevan reports the order as duplicated" do
      provider.issue(issue_input)

      expect { provider.issue(issue_input) }.to raise_error(Einvoice::ConflictError) { |error|
        expect(error.reason).to eq(Einvoice::Reason::DUPLICATE_ORDER)
        expect(error.raw_message).to eq("duplicated")
      }
    end

    # Ported from the 1.x provider spec: invalid data never reaches the network.
    it "raises ValidationError without a request when the data breaks the field rules" do
      expect { provider.issue(issue_input.merge(order_id: "x" * 51)) }
        .to raise_error(Einvoice::ValidationError, /transactionNumber/)
      expect(tradevan.requests).to be_empty
    end

    it "lets validate_payload: false send the data as it is" do
      lax = described_class.new(**FakeTradevan::CREDENTIALS, validate_payload: false)

      expect { lax.issue(issue_input.merge(order_id: "x" * 51)) }.not_to raise_error
      expect(tradevan.requests.size).to eq(1)
    end

    it "sends only DEFAULTAPI fields, so Tradevan does not reject the request (PR #38)" do
      provider.issue(issue_input)

      expect(issue_data.keys - Einvoice::Tradevan::DefaultAPI::Rules::ISSUE_FIELDS).to be_empty
      expect(issue_data["itemList"].flat_map(&:keys) - Einvoice::Tradevan::DefaultAPI::Rules::ITEM_FIELDS)
        .to be_empty
    end

    it "raises ProviderError when Tradevan reports success but returns no invoice number" do
      reply("post/issue", "issueStatus" => "Y", "invoiceNumber" => "")

      expect { provider.issue(issue_input) }.to raise_error(Einvoice::ProviderError, /no invoiceNumber/)
    end

    it "issues a B2B invoice, and its reference keeps the buyer's 統一編號" do
      result = provider.issue(issue_input.merge(buyer: { name: "Acme", ubn: "53538851" }, carrier: nil,
                                                amount: { sales_amount: 19_048, tax_amount: 952,
                                                          total_amount: 20_000 }))

      expect(issue_data).to include("buyerUn" => "53538851", "buyerTitle" => "Acme")
      expect(result.reference.buyer_ubn).to eq("53538851")
    end
  end

  describe "#void" do
    # Ported from the 1.x provider spec. The reference has the order id, so
    # the adapter builds the saleIdentifier without a query.
    it "voids an invoice through the full wire format" do
      issued = provider.issue(issue_input)
      result = provider.void({ invoice: issued.reference, reason: "客戶取消" })

      expect(tradevan.requests.map { |request| request[:path] }).to eq(%w[post/issue post/cancel])
      expect(JSON.parse(tradevan.params["voidData"])).to eq(
        "type" => "I", "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
        "invoiceNumber" => issued.invoice_number, "invoicePaperReturned" => "N"
      )
      expect(result.status).to eq(Einvoice::InvoiceStatus::VOIDED)
    end

    it "takes the saleIdentifier from provider_options, for invoices the 1.x client issued" do
      expect do
        provider.void({ invoice: "GX38551078", reason: "客戶取消",
                        provider_options: { sale_identifier: "12345678_ABCDE_other" } })
      end.to raise_error(Einvoice::NotFoundError)
      expect(JSON.parse(tradevan.params["voidData"])["saleIdentifier"]).to eq("12345678_ABCDE_other")
    end

    it "looks up the saleIdentifier when the reference has only the number" do
      issued = provider.issue(issue_input)
      provider.void({ invoice: issued.invoice_number, reason: "客戶取消" })

      expect(tradevan.requests.map { |request| request[:path] })
        .to eq(%w[post/issue get/searchInvoiceDetail post/cancel])
      expect(JSON.parse(tradevan.params["voidData"])["saleIdentifier"]).to eq("12345678_ABCDE_53b2a44e4b3c")
    end

    it "raises ProviderError with LOOKUP_FAILED when the lookup fails" do
      expect { provider.void({ invoice: "GX38551078", reason: "客戶取消" }) }
        .to raise_error(Einvoice::ProviderError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::LOOKUP_FAILED)
          expect(error.cause).to be_a(Einvoice::NotFoundError)
        }
    end

    it "needs the invoice number, and says so before any request" do
      expect { provider.void({ invoice: { order_id: "53b2a44e4b3c" }, reason: "客戶取消" }) }
        .to raise_error(Einvoice::ValidationError, /invoice\.number/)
      expect(tradevan.requests).to be_empty
    end

    it "raises ProviderError with LOOKUP_FAILED when the invoice found has no date" do
      message = Einvoice::Tradevan::DefaultAPI::Crypto.encrypt(
        %({"invoiceNumber":"GX38551078","saleIdentifier":"12345678_ABCDE_x"}), FakeTradevan::KEY1
      )
      stub_request(:get, %r{tradevan\.test/DEFAULTAPI/get/searchInvoiceDetail})
        .to_return(headers: { "Content-Type" => "application/json" },
                   body: JSON.generate("Success" => "Y", "Message" => message))

      expect do
        provider.allowance({ invoice: { number: "GX38551078", order_id: "x", tax_type: "taxable", tax_rate: "0.05" },
                             allowance_id: "AL_1",
                             items: [{ description: "A", quantity: 1, unit_price: 100, amount: 100 }],
                             amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
                             price_mode: "TAX_INCLUSIVE" })
      end.to raise_error(Einvoice::ProviderError, /invoiceDate/) { |error|
        expect(error.reason).to eq(Einvoice::Reason::LOOKUP_FAILED)
      }
    end

    it "voids with a saleIdentifier from the lookup, even when the invoice found has no date" do
      search_reply("saleIdentifier" => "12345678_ABCDE_x", "invoiceDate" => nil)

      expect { provider.void({ invoice: "GX38551078", reason: "客戶取消" }) }
        .to raise_error(Einvoice::NotFoundError)
      expect(JSON.parse(tradevan.params["voidData"])["saleIdentifier"]).to eq("12345678_ABCDE_x")
    end

    it "voids even when the invoice found has a date that is not valid, as a void does not need it" do
      search_reply("saleIdentifier" => "12345678_ABCDE_x", "invoiceDate" => "20160230")

      expect { provider.void({ invoice: "GX38551078", reason: "客戶取消" }) }
        .to raise_error(Einvoice::NotFoundError)
      expect(tradevan.path).to eq("post/cancel")
    end

    it "raises LOOKUP_FAILED when the invoice detail is not an object" do
      reply("get/searchInvoiceDetail", [])

      expect { provider.void({ invoice: "GX38551078", reason: "客戶取消" }) }
        .to raise_error(Einvoice::ProviderError) { |error| expect(error.reason).to eq(Einvoice::Reason::LOOKUP_FAILED) }
      expect { provider.query({ invoice: "GX38551078" }) }.to raise_error(Einvoice::ProviderError, /not an object/)
    end

    it "refuses to void an invoice that has an allowance" do
      issued = provider.issue(issue_input)
      provider.allowance({ invoice: issued.reference, allowance_id: "AL_V",
                           items: [{ description: "Coffee Latte", quantity: 1, unit_price: 100, amount: 100 }],
                           amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
                           price_mode: "TAX_INCLUSIVE" })

      expect { provider.void({ invoice: issued.reference, reason: "客戶取消" }) }
        .to raise_error(Einvoice::ConflictError) { |error|
          expect(error.reason).to eq(Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE)
        }
    end
  end

  describe "#allowance" do
    let(:issued) { provider.issue(issue_input) }

    def allowance(invoice: issued.reference, **overrides)
      provider.allowance({
        invoice: invoice, allowance_id: "AL_1",
        items: [{ description: "Coffee Latte", quantity: 1, unit_price: 100, amount: 100 }],
        amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
        price_mode: "TAX_INCLUSIVE"
      }.merge(overrides))
    end

    it "sends type A with the core's tax split, and reads the allowance number" do
      result = allowance

      expect(issue_data).to include("type" => "A", "allowanceExclusiveAmount" => "95", "allowanceTax" => "5",
                                    "allowanceInclusiveAmount" => "100")
      expect(issue_data["itemList"].first).to include("invoiceDate" => issued.invoice_datetime.strftime("%Y%m%d"),
                                                      "itemExclude" => "95", "tax" => "5", "itemTotal" => "100")
      expect(tradevan.requests.map { |request| request[:path] }).to eq(%w[post/issue post/issue])
      expect(result.allowance_number).to match(/\AABCDE\d{11}\z/)
      # The date Tradevan answered, not the clock again: midnight may pass.
      expect(result.allowance_date).to eq(Date.strptime(result.raw["allowanceDate"], "%Y%m%d"))
      expect(result.invoice_number).to eq(issued.invoice_number)
      expect(result.total_amount).to eq(100)
    end

    it "looks up the saleIdentifier and the date when the reference lacks them" do
      allowance(invoice: { number: issued.invoice_number, tax_type: "taxable", tax_rate: "0.05" })

      expect(tradevan.requests.map { |request| request[:path] })
        .to eq(%w[post/issue get/searchInvoiceDetail post/issue])
      expect(issue_data["itemList"].first).to include("saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
                                                      "invoiceDate" => issued.invoice_datetime.strftime("%Y%m%d"))
    end

    it "takes today in Taipei as the date when the response has no allowanceDate" do
      issued
      message = Einvoice::Tradevan::DefaultAPI::Crypto.encrypt(
        %({"issueStatus":"Y","allowanceNumber":"ABCDE20160502001"}), FakeTradevan::KEY1
      )
      stub_request(:post, %r{tradevan\.test/DEFAULTAPI/post/issue})
        .to_return(headers: { "Content-Type" => "application/json" },
                   body: JSON.generate("Success" => "Y", "Message" => message))
      clock = Struct.new(:now).new(Time.utc(2016, 5, 1, 17, 0, 0))
      result = described_class.new(**FakeTradevan::CREDENTIALS, clock: clock)
                              .allowance({ invoice: issued.reference, allowance_id: "AL_1",
                                           items: [{ description: "A", quantity: 1, unit_price: 100, amount: 100 }],
                                           amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
                                           price_mode: "TAX_INCLUSIVE" })

      expect(result.allowance_date).to eq(Date.new(2016, 5, 2))
    end

    it "raises ProviderError when the response has no allowanceNumber" do
      issued
      message = Einvoice::Tradevan::DefaultAPI::Crypto.encrypt(%({"issueStatus":"Y"}), FakeTradevan::KEY1)
      stub_request(:post, %r{tradevan\.test/DEFAULTAPI/post/issue})
        .to_return(headers: { "Content-Type" => "application/json" },
                   body: JSON.generate("Success" => "Y", "Message" => message))

      expect { allowance }.to raise_error(Einvoice::ProviderError, /no allowanceNumber/)
    end
  end

  describe "#void_allowance" do
    it "refuses an allowance number that is not 16 characters, before any request" do
      expect { provider.void_allowance({ allowance: "NOPE00000000" }) }
        .to raise_error(Einvoice::ValidationError, /allowanceNumber/)
      expect(tradevan.requests).to be_empty
    end
  end

  describe "#query" do
    it "reads searchInvoiceDetail into the unified result" do
      issued = provider.issue(issue_input)
      found = provider.query({ invoice: issued.invoice_number })

      expect(tradevan.path).to eq("get/searchInvoiceDetail")
      expect(tradevan.http_method).to eq(:get)
      expect(found.invoice_number).to eq(issued.invoice_number)
      expect(found.order_id).to eq("53b2a44e4b3c")
      expect(found.random_code).to eq(issued.random_code)
      expect(found.invoice_datetime).to eq(issued.invoice_datetime)
      expect(found.amount).to eq(Einvoice::AmountSummary.new(sales_amount: 19_048, tax_amount: 952,
                                                             total_amount: 20_000))
      expect(found.buyer.name).to eq("John Appleseed")
      expect(found.items.first).to have_attributes(description: "Coffee Latte", quantity: 4000, unit_price: 5,
                                                   amount: 20_000, tax_type: Einvoice::TaxType::TAXABLE)
      expect(found.reference).to have_attributes(order_id: "53b2a44e4b3c", tax_type: Einvoice::TaxType::TAXABLE,
                                                 tax_rate: Rational(5, 100))
    end

    it "leaves the tax type unknown when a line has none, and sees MIXED only from two known types" do
      line = { "productName" => "A", "qty" => "1", "price" => "1", "total" => "1" }
      search_reply("detailList" => [line.merge("taxType" => "T"), line])
      expect(provider.query({ invoice: "GX38551078" })).to have_attributes(tax_type: nil, tax_rate: nil)

      search_reply("detailList" => [line.merge("taxType" => "T"), line.merge("taxType" => "O")])
      expect(provider.query({ invoice: "GX38551078" }))
        .to have_attributes(tax_type: Einvoice::TaxType::MIXED, tax_rate: Rational(5, 100))
    end

    it "reads the rate of a mixed invoice without a taxable line as 0" do
      line = { "productName" => "A", "qty" => "1", "price" => "1", "total" => "1" }
      search_reply("detailList" => [line.merge("taxType" => "Z"), line.merge("taxType" => "O")])

      expect(provider.query({ invoice: "GX38551078" }))
        .to have_attributes(tax_type: Einvoice::TaxType::MIXED, tax_rate: 0)
    end

    it "raises ProviderError for a date that is not valid, and reads a missing one as nil" do
      search_reply("invoiceDate" => "20161325", "invoiceTime" => "12:00:00")
      expect { provider.query({ invoice: "GX38551078" }) }.to raise_error(Einvoice::ProviderError, /not valid/)

      search_reply("invoiceDate" => "20160230")
      expect { provider.query({ invoice: "GX38551078" }) }.to raise_error(Einvoice::ProviderError, /not valid/)

      search_reply("invoiceDate" => "")
      expect(provider.query({ invoice: "GX38551078" }).invoice_datetime).to be_nil
    end

    it "gives no order id for a saleIdentifier that this adapter did not build" do
      search_reply("saleIdentifier" => "12345678_OLD01_x")

      expect(provider.query({ invoice: "GX38551078" }).order_id).to be_nil
    end

    it "reads the rate of a tax-free invoice as 0" do
      issued = provider.issue(issue_input.merge(tax_type: "TAX_FREE"))

      found = provider.query({ invoice: issued.reference })
      expect(found).to have_attributes(tax_type: Einvoice::TaxType::TAX_FREE, tax_rate: 0)
      expect(found.amount).to eq(Einvoice::AmountSummary.new(sales_amount: 20_000, tax_amount: 0, total_amount: 20_000))
    end

    # The meaning of status I and V is unknown, so the adapter does not guess.
    it "leaves status nil, unless the invoice has an allowance" do
      issued = provider.issue(issue_input)
      expect(provider.query({ invoice: issued.reference }).status).to be_nil

      provider.allowance({ invoice: issued.reference, allowance_id: "AL_Q",
                           items: [{ description: "Coffee Latte", quantity: 1, unit_price: 100, amount: 100 }],
                           amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 },
                           price_mode: "TAX_INCLUSIVE" })
      found = provider.query({ invoice: issued.reference })
      expect(found.status).to eq(Einvoice::InvoiceStatus::ALLOWANCE)
      expect(found.raw["status"]).to eq("I")
    end

    it "refuses a query by order id, which this adapter does not declare" do
      expect { provider.query({ invoice: { order_id: "53b2a44e4b3c" } }) }.to raise_error(Einvoice::UnsupportedError)
    end
  end

  describe "#raw" do
    it "calls any path with the encryption and error mapping applied" do
      issued = provider.issue(issue_input)

      expect(provider.raw("get/searchInvoiceDetail", { invoiceNumber: issued.invoice_number })["invoiceNumber"])
        .to eq(issued.invoice_number)
    end
  end

  it "raises AuthError when the account is wrong" do
    wrong = described_class.new(**FakeTradevan::CREDENTIALS, acntp: "wrong")

    expect { wrong.issue(issue_input) }.to raise_error(Einvoice::AuthError)
  end

  it "needs 16-byte keys" do
    bad = described_class.new(**FakeTradevan::CREDENTIALS, key1: "short")

    expect { bad.issue(issue_input) }.to raise_error(Einvoice::ValidationError, /16 bytes/)
  end
end
