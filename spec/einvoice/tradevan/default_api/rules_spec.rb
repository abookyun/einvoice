# frozen_string_literal: true

# Ported from the 1.x specs for IssueData, IssueItem and the IssueData#payload
# regression (PR #38), with the same factories. 1.x used shoulda matchers
# (validate_presence_of, validate_length_of); here each one is a row in a table.
RSpec.describe Einvoice::Tradevan::DefaultAPI::Rules do
  prefix = "53086054_ICKEC_"

  # spec/factories/tradevan/issue_items.rb in 1.x.
  item = {
    "saleIdentifier" => "53086054_ICKEC_20160323014320", "serialNumber" => "0001",
    "productCode" => "98765", "productName" => "銷售費", "qty" => "1", "price" => "100",
    "tax" => "5", "itemTotal" => "100", "itemExclude" => "95", "taxType" => "T"
  }.freeze

  # spec/factories/tradevan/issue_datas.rb in 1.x: the base factory.
  base = {
    "companyUn" => "53086054", "orgId" => "ICKEC",
    "saleIdentifier" => "53086054_ICKEC_20160323014320", "transactionNumber" => "1234567890",
    "transactionDate" => "20160323", "transactionTime" => "01:43:20", "total" => "100",
    "paperPrintMode" => "0", "carrierType" => "1K0001", "invoiceAlarmMode" => "0",
    "itemList" => [item]
  }.freeze

  invoice = {
    "donate" => "N", "donationUnit" => "12345",
    "carrierId" => "123456789012345678901234567890",
    "carrierIdHidden" => "123456789012345678901234567890",
    "receiverName" => "Jamie Oliver", "receiverAddrZip" => "106",
    "receiverAddrRoad" => "台北市大安區新生南路一段 50 號", "receiverEmail" => "hi@icook.tw",
    "receiverMobile" => "0912123123"
  }.freeze

  # The traits. 1.x left invoiceNumber, invoiceDate and itemExclude off the
  # H and A items, so those factories were never valid as a whole. Here they
  # are, and the spec checks it.
  allowance_item = item.merge("invoiceNumber" => "EM82930261", "invoiceDate" => "20160324")
  traits = {
    "I" => invoice.merge("type" => "I"),
    "R" => invoice.merge("type" => "R", "invoiceNumber" => "EM82930261"),
    "G" => invoice.merge(
      "type" => "G", "invoiceNumber" => "EM82930261", "checkNumber" => "1234",
      "invoiceDate" => "20160324", "invoiceTime" => "01:43:30", "texclusiveAmount" => "100",
      "oeclusiveAmount" => "5", "zexclusiveAmount" => "0", "tax" => "5", "mainRemark" => "remark",
      "invoiceType" => "07"
    ),
    "H" => {
      "type" => "H", "allowanceIdentifier" => "53086054_ICKEC_20160323014320",
      "invoiceNumber" => "EM82930261", "allowanceNumber" => "ICKEC20160324001",
      "allowanceDate" => "20160324", "allowanceExclusiveAmount" => "100", "allowanceTax" => "5",
      "allowanceInclusiveAmount" => "105", "allowancePaperReturned" => "Y",
      "itemList" => [allowance_item]
    },
    "A" => {
      "type" => "A", "allowanceIdentifier" => "53086054_ICKEC_20160323014320",
      "allowanceExclusiveAmount" => "100", "allowanceTax" => "5", "allowanceInclusiveAmount" => "105",
      "allowancePaperReturned" => "Y", "allowaDeclaration" => "201803", "invoicePaperReturned" => "Y",
      "itemList" => [allowance_item]
    }
  }.freeze

  define_method(:issue_data) { |type, overrides = {}| base.merge(traits.fetch(type)).merge(overrides) }

  def errors_on(data, field)
    described_class.issue_errors(data)[field] || []
  end

  def length_errors(messages)
    messages.grep(/characters|format/)
  end

  # The 1.x matchers, as helpers.
  def expect_required(data, field)
    expect(errors_on(data.merge(field => nil), field)).to include("is required")
    expect(errors_on(data.merge(field => ""), field)).to include("is required")
  end

  def expect_length(data, field, valid, invalid)
    expect(length_errors(errors_on(data.merge(field => valid), field))).to be_empty
    Array(invalid).each do |value|
      expect(errors_on(data.merge(field => value), field)).not_to be_empty,
                                                              "#{field} accepted #{value.inspect}"
    end
  end

  def expect_exact(data, field, size, char = "1")
    expect_length(data, field, char * size, [char * (size - 1), char * (size + 1)])
  end

  def expect_at_most(data, field, size, char = "x")
    expect_length(data, field, char * size, char * (size + 1))
  end

  describe ".issue_errors" do
    %w[I R G H A].each do |type|
      it "accepts the 1.x factory for type #{type}" do
        expect(described_class.issue_errors(issue_data(type))).to eq({})
      end
    end

    context "for every type (shown on type I)" do
      let(:data) { issue_data("I") }

      %w[companyUn orgId type transactionNumber transactionDate paperPrintMode invoiceAlarmMode
         saleIdentifier transactionTime total carrierType].each do |field|
        it("requires #{field}") { expect_required(data, field) }
      end

      it("checks companyUn is 8 characters") { expect_exact(data, "companyUn", 8) }
      it("checks orgId is 5 characters") { expect_exact(data, "orgId", 5, "A") }
      it("checks orgUn is 8 characters") { expect_exact(data, "orgUn", 8) }
      it("checks transactionNumber is at most 50") { expect_at_most(data, "transactionNumber", 50) }
      it("checks transactionDate is 8 digits") { expect_exact(data, "transactionDate", 8) }
      it("checks transactionSource is at most 50") { expect_at_most(data, "transactionSource", 50) }
      it("checks transactionTarget is at most 50") { expect_at_most(data, "transactionTarget", 50) }
      it("checks carrierType is 6 characters") { expect_exact(data, "carrierType", 6, "X") }
      it("checks buyerUn is 8 characters") { expect_exact(data, "buyerUn", 8) }
      it("checks buyerTitle is at most 60") { expect_at_most(data, "buyerTitle", 60) }
      it("checks idViewId is at most 10") { expect_at_most(data, "idViewId", 10) }
      it("checks memberId is at most 50") { expect_at_most(data, "memberId", 50) }
      it "checks total is at most 20" do
        long = "1" * 21
        matching = data.merge("total" => long, "itemList" => [data["itemList"].first.merge("itemTotal" => long)])
        expect(errors_on(matching, "total")).to include(/20 characters or fewer/)
      end

      it "checks transactionTime is HH:MM:SS" do
        expect_length(data, "transactionTime", "01:43:20", %w[1:43:20 014320 01:43:200])
      end

      it "checks saleIdentifier is at most 100" do
        expect_length(data, "saleIdentifier", prefix + ("x" * (100 - prefix.size)),
                      prefix + ("x" * (101 - prefix.size)))
      end

      it "checks saleIdentifier starts with companyUn_orgId_" do
        expect(errors_on(data.merge("saleIdentifier" => "99999999_ICKEC_1"), "saleIdentifier"))
          .to include("must start with #{prefix}")
      end

      it "checks type is one of I R G H A" do
        expect(errors_on(data.merge("type" => "X"), "type")).to include(/one of/)
      end

      it "checks paperPrintMode is 0 to 4, and invoiceAlarmMode 0 to 6" do
        expect(errors_on(data.merge("paperPrintMode" => "5"), "paperPrintMode")).not_to be_empty
        expect(errors_on(data.merge("invoiceAlarmMode" => "7"), "invoiceAlarmMode")).not_to be_empty
      end

      it "accepts a total matching the sum of item totals" do
        expect(errors_on(data.merge("total" => "100"), "total")).to be_empty
      end

      it "compares the total with the item totals as decimals" do
        halves = data.merge("total" => "1", "itemList" => [data["itemList"].first.merge("itemTotal" => "0.5"),
                                                          data["itemList"].first.merge("itemTotal" => "0.5")])
        expect(errors_on(halves, "total")).to be_empty
        expect(errors_on(halves.merge("total" => "1.4"), "total")).to include(/sum of itemTotal \(1\)/)
      end

      it "refuses a total or an itemTotal that is not a decimal number" do
        expect(errors_on(data.merge("total" => "100oops"), "total")).to include(/decimal numbers/)
        bad_item = data.merge("itemList" => [data["itemList"].first.merge("itemTotal" => "1e2")])
        expect(errors_on(bad_item, "total")).to include(/decimal numbers/)
      end

      it "rejects a total that does not match the sum of item totals" do
        expect(errors_on(data.merge("total" => "999"), "total")).to include(/sum of itemTotal/)
      end

      it "accepts items with itemTotal and taxType present" do
        expect(errors_on(data, "itemList")).to be_empty
      end

      it "rejects items with a blank taxType" do
        data["itemList"] = [item.merge("taxType" => nil)]
        expect(errors_on(data, "itemList")).to include("needs taxType on every item")
      end

      it "rejects items with a blank itemTotal" do
        data["itemList"] = [item.merge("itemTotal" => nil)]
        expect(errors_on(data.merge("total" => "0"), "itemList")).to include("needs itemTotal on every item")
      end

      it "requires a non-empty itemList" do
        expect(errors_on(data.merge("itemList" => []), "itemList")).to include("is required")
      end

      it "reports an item's own errors with its index" do
        data["itemList"] = [item.merge("serialNumber" => "1")]
        expect(described_class.issue_errors(data)).to include("itemList[0].serialNumber")
      end

      it "accepts symbol keys" do
        expect(described_class.issue_errors(data.transform_keys(&:to_sym))).to eq({})
      end
    end

    %w[I R G].each do |type|
      context "on type #{type}" do
        let(:data) { issue_data(type) }

        it("requires donate") { expect_required(data, "donate") }
        it("checks donate is 1 character") { expect_exact(data, "donate", 1, "N") }
        it("requires carrierId") { expect_required(data, "carrierId") }
        it("checks carrierId is at most 64") { expect_at_most(data, "carrierId", 64) }
        it("requires carrierIdHidden") { expect_required(data, "carrierIdHidden") }
        it("checks carrierIdHidden is at most 64") { expect_at_most(data, "carrierIdHidden", 64) }
        it("checks receiverName is at most 30") { expect_at_most(data, "receiverName", 30) }
        it("checks receiverAddrZip is at most 6") { expect_at_most(data, "receiverAddrZip", 6) }
        it("checks receiverAddrRoad is at most 100") { expect_at_most(data, "receiverAddrRoad", 100) }
        it("checks receiverEmail is at most 80") { expect_at_most(data, "receiverEmail", 80) }
        it("checks receiverMobile is at most 15") { expect_at_most(data, "receiverMobile", 15) }

        context "with donate 'Y'" do
          let(:data) { issue_data(type, "donate" => "Y") }

          it("requires donationUnit") { expect_required(data, "donationUnit") }
          it("checks donationUnit is at most 10") { expect_at_most(data, "donationUnit", 10, "1") }

          # 1.x also checked donationUnit against a bundled list of donation
          # codes. 2.0 has no list: Input checks the format, and
          # Einvoice::MOF::DonationCodes checks the registry.
          it "does not look the donation code up" do
            expect(described_class.issue_errors(data.merge("donationUnit" => "5566183"))).to eq({})
          end

          it "does not need a carrier" do
            expect(described_class.issue_errors(data.merge("carrierId" => nil, "carrierIdHidden" => nil,
                                                           "carrierType" => nil))).to eq({})
          end
        end

        it "does not need donate for a B2B invoice" do
          expect(errors_on(data.merge("donate" => nil, "buyerUn" => "12345678"), "donate")).to be_empty
        end

        it "does not need donate or a carrier when paperPrintMode is not 0" do
          changed = data.merge("paperPrintMode" => "1", "donate" => nil, "carrierType" => nil,
                               "carrierId" => nil, "carrierIdHidden" => nil, "invoicePaperReturned" => "Y")
          expect(described_class.issue_errors(changed)).to eq({})
        end

        it "needs invoicePaperReturned when there is no buyerUn and paperPrintMode is not 0" do
          expect(errors_on(data.merge("paperPrintMode" => "1"), "invoicePaperReturned"))
            .to include("is required")
        end
      end
    end

    %w[R G H].each do |type|
      context "on type #{type}" do
        let(:data) { issue_data(type) }

        it("requires invoiceNumber") { expect_required(data, "invoiceNumber") }
        it("checks invoiceNumber is 10 characters") { expect_exact(data, "invoiceNumber", 10, "A") }
      end
    end

    context "on type G" do
      let(:data) { issue_data("G") }

      it("checks checkNumber is 4 characters") { expect_exact(data, "checkNumber", 4) }
      it("checks invoiceDate is 8 characters") { expect_exact(data, "invoiceDate", 8) }
      it("checks invoiceTime is 8 characters") { expect_exact(data, "invoiceTime", 8) }
      it("checks texclusiveAmount is at most 20") { expect_at_most(data, "texclusiveAmount", 20) }
      it("checks oeclusiveAmount is at most 20") { expect_at_most(data, "oeclusiveAmount", 20) }
      it("checks zexclusiveAmount is at most 20") { expect_at_most(data, "zexclusiveAmount", 20) }
      it("checks tax is at most 20") { expect_at_most(data, "tax", 20) }
      it("checks mainRemark is at most 300") { expect_at_most(data, "mainRemark", 300) }

      it "checks invoiceType is 07 or 08" do
        expect_length(data, "invoiceType", "08", %w[7 09 007])
      end
    end

    %w[H A].each do |type|
      context "on type #{type}" do
        let(:data) { issue_data(type) }

        it("requires allowanceIdentifier") { expect_required(data, "allowanceIdentifier") }
        it("requires allowanceExclusiveAmount") { expect_required(data, "allowanceExclusiveAmount") }
        it("requires allowanceTax") { expect_required(data, "allowanceTax") }
        it("requires allowancePaperReturned") { expect_required(data, "allowancePaperReturned") }
        it("requires allowanceInclusiveAmount") { expect_required(data, "allowanceInclusiveAmount") }
        it("checks allowanceExclusiveAmount is at most 20") { expect_at_most(data, "allowanceExclusiveAmount", 20) }
        it("checks allowanceTax is at most 8") { expect_at_most(data, "allowanceTax", 8) }
        it("checks allowanceInclusiveAmount is at most 20") { expect_at_most(data, "allowanceInclusiveAmount", 20) }

        it "checks allowancePaperReturned is Y or N" do
          expect_length(data, "allowancePaperReturned", "N", %w[X YY])
        end

        it "checks allowanceIdentifier is at most 100, with the prefix" do
          expect_length(data, "allowanceIdentifier", prefix + ("x" * (100 - prefix.size)),
                        [prefix + ("x" * (101 - prefix.size)), "x"])
        end

        %w[invoiceNumber invoiceDate itemExclude].each do |field|
          it "needs #{field} on every item" do
            data["itemList"] = [allowance_item.merge(field => nil)]
            expect(errors_on(data, "itemList")).to include("needs #{field} on every item")
          end
        end

        it "does not check the buyer fields" do
          expect(errors_on(data.merge("buyerUn" => "1"), "buyerUn")).to be_empty
        end
      end
    end

    context "on type H" do
      let(:data) { issue_data("H") }

      it("requires allowanceNumber") { expect_required(data, "allowanceNumber") }
      it("requires allowanceDate") { expect_required(data, "allowanceDate") }

      it "accepts an allowanceNumber prefixed with orgId" do
        expect(errors_on(data.merge("allowanceNumber" => "ICKEC20160324001"), "allowanceNumber")).to be_empty
      end

      it "rejects an allowanceNumber not prefixed with orgId" do
        expect(errors_on(data.merge("allowanceNumber" => "XXXXX20160324001"), "allowanceNumber"))
          .to include("must start with ICKEC")
      end

      it "checks allowanceNumber is 16 characters" do
        expect(errors_on(data.merge("allowanceNumber" => "ICKEC2016032400"), "allowanceNumber"))
          .to include("must be 16 characters")
      end
    end

    context "on type A" do
      let(:data) { issue_data("A") }

      it("requires invoicePaperReturned") { expect_required(data, "invoicePaperReturned") }
      it("checks allowaDeclaration is 6 digits") { expect_exact(data, "allowaDeclaration", 6) }

      it "checks invoicePaperReturned is Y or N" do
        expect_length(data, "invoicePaperReturned", "N", %w[X YY])
      end

      it "does not need a carrier" do
        expect(errors_on(data.merge("carrierType" => nil), "carrierType")).to be_empty
      end

      it "checks the receiver fields" do
        expect(errors_on(data.merge("receiverName" => "x" * 31), "receiverName")).not_to be_empty
      end
    end

    # 1.x IssueData#payload: Tradevan rejects a request with any field outside
    # its schema (PR #38), so a stray key must fail here, before the call.
    context "with a key outside the DEFAULTAPI schema" do
      it "rejects it in the header" do
        data = issue_data("I", "context_for_validation" => nil)
        expect(described_class.issue_errors(data)).to include("context_for_validation")
      end

      it "rejects it in an item" do
        data = issue_data("I", "itemList" => [item.merge("validation_context" => nil)])
        expect(described_class.issue_errors(data)).to include("itemList[0].validation_context")
      end
    end
  end

  # 1.x spec/einvoice/tradevan/model/issue_item_spec.rb
  describe ".item_errors" do
    def item_errors_on(data, field)
      described_class.item_errors(data)[field] || []
    end

    it "accepts the 1.x factory" do
      expect(described_class.item_errors(item)).to eq({})
    end

    %w[saleIdentifier serialNumber productName qty price].each do |field|
      it "requires #{field}" do
        expect(item_errors_on(item.merge(field => nil), field)).to include("is required")
      end
    end

    {
      "saleIdentifier" => 100, "productCode" => 30, "productName" => 300, "qty" => 20, "price" => 20,
      "tax" => 20, "itemExclude" => 20, "itemTotal" => 20, "description" => 300
    }.each do |field, size|
      it "checks #{field} is at most #{size}" do
        expect(item_errors_on(item.merge(field => "1" * size), field)).to be_empty
        expect(item_errors_on(item.merge(field => "1" * (size + 1)), field)).not_to be_empty
      end
    end

    { "serialNumber" => 4, "invoiceNumber" => 10, "invoiceDate" => 8 }.each do |field, size|
      it "checks #{field} is #{size} characters" do
        expect(item_errors_on(item.merge(field => "1" * size), field)).to be_empty
        expect(item_errors_on(item.merge(field => "1" * (size + 1)), field)).not_to be_empty
        expect(item_errors_on(item.merge(field => "1" * (size - 1)), field)).not_to be_empty
      end
    end

    it "checks serialNumber and invoiceDate are digits" do
      expect(item_errors_on(item.merge("serialNumber" => "000A"), "serialNumber")).not_to be_empty
      expect(item_errors_on(item.merge("invoiceDate" => "2016032A"), "invoiceDate")).not_to be_empty
    end

    it "accepts an invoiceTime of HH:MM:SS" do
      expect(item_errors_on(item.merge("invoiceTime" => "01:43:30"), "invoiceTime")).to be_empty
    end

    it "rejects an invoiceTime that is not HH:MM:SS" do
      expect(item_errors_on(item.merge("invoiceTime" => "2016/1/1"), "invoiceTime")).not_to be_empty
    end

    it "checks taxType is T, O or Z" do
      %w[T O Z].each { |code| expect(item_errors_on(item.merge("taxType" => code), "taxType")).to be_empty }
      expect(item_errors_on(item.merge("taxType" => "X"), "taxType")).not_to be_empty
    end
  end

  describe ".void_errors" do
    invoice_void = {
      "type" => "I", "saleIdentifier" => "12345678_ABCDE_53b2a44e4b3c",
      "invoiceNumber" => "GX38551078", "invoicePaperReturned" => "Y"
    }.freeze
    allowance_void = {
      "type" => "A", "companyUn" => "12345678", "allowanceNumber" => "ABCDE20260101001",
      "allowancePaperReturned" => "N"
    }.freeze

    def void_errors_on(data, field)
      described_class.void_errors(data)[field] || []
    end

    it "accepts the 1.x README void and the 2026 README allowance void" do
      expect(described_class.void_errors(invoice_void)).to eq({})
      expect(described_class.void_errors(allowance_void)).to eq({})
      expect(described_class.void_errors(invoice_void.merge("type" => "C"))).to eq({})
    end

    it "checks type is C, I or A" do
      expect(void_errors_on(invoice_void.merge("type" => "X"), "type")).not_to be_empty
    end

    %w[saleIdentifier invoiceNumber invoicePaperReturned].each do |field|
      it "requires #{field} on type I" do
        expect(void_errors_on(invoice_void.merge(field => nil), field)).to include("is required")
      end
    end

    %w[companyUn allowanceNumber allowancePaperReturned].each do |field|
      it "requires #{field} on type A" do
        expect(void_errors_on(allowance_void.merge(field => nil), field)).to include("is required")
      end
    end

    it "checks the lengths" do
      expect(void_errors_on(invoice_void.merge("saleIdentifier" => "x" * 101), "saleIdentifier")).not_to be_empty
      expect(void_errors_on(invoice_void.merge("invoiceNumber" => "GX3855107"), "invoiceNumber")).not_to be_empty
      expect(void_errors_on(allowance_void.merge("companyUn" => "1234567"), "companyUn")).not_to be_empty
      expect(void_errors_on(allowance_void.merge("allowanceNumber" => "ABCDE"), "allowanceNumber"))
        .not_to be_empty
    end

    it "rejects a key outside the schema" do
      expect(described_class.void_errors(invoice_void.merge("reason" => "x"))).to include("reason")
    end
  end

  describe ".validate!" do
    it "raises one ValidationError that names every problem" do
      expect { described_class.validate!({ "a" => ["is required"], "b" => ["is bad"] }, "issueData") }
        .to raise_error(Einvoice::ValidationError, /issueData — a is required; b is bad/)
    end

    it "passes an empty error list" do
      expect(described_class.validate!({}, "issueData")).to be_nil
    end
  end
end
