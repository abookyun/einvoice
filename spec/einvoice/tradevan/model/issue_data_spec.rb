require "spec_helper"

RSpec.describe Einvoice::Tradevan::Model::IssueData, type: :model do
  subject { build(:tradevan_issue_data, :I) }

  context "validations" do
    it { is_expected.to validate_presence_of(:companyUn) }
    it { is_expected.to validate_length_of(:companyUn).is_equal_to(8) }
    it { is_expected.to validate_presence_of(:orgId) }
    it { is_expected.to validate_length_of(:orgId).is_equal_to(5) }
    it { is_expected.to validate_length_of(:orgUn).is_equal_to(8) }
    it { is_expected.to validate_presence_of(:type) }
    it { is_expected.to validate_length_of(:type).is_equal_to(1) }
    it { is_expected.to validate_presence_of(:saleIdentifier) }
    it { is_expected.to validate_length_of(:saleIdentifier).is_at_most(100) }
    it { is_expected.to validate_presence_of(:transactionNumber) }
    it { is_expected.to validate_length_of(:transactionNumber).is_at_most(50) }
    it { is_expected.to validate_presence_of(:transactionDate) }
    it { is_expected.to validate_length_of(:transactionDate).is_equal_to(8) }
    it { is_expected.to validate_presence_of(:transactionTime) }
    it { is_expected.to validate_length_of(:transactionTime).is_equal_to(8) }
    it { is_expected.to validate_presence_of(:total) }
    it { is_expected.to validate_length_of(:total).is_at_most(20) }
    it { is_expected.to validate_length_of(:transactionSource).is_at_most(50) }
    it { is_expected.to validate_length_of(:transactionTarget).is_at_most(50) }
    it { is_expected.to validate_presence_of(:paperPrintMode) }
    it { is_expected.to validate_length_of(:paperPrintMode).is_equal_to(1) }
    it { is_expected.to validate_presence_of(:invoiceAlarmMode) }
    it { is_expected.to validate_length_of(:invoiceAlarmMode).is_equal_to(1) }
    it { is_expected.to validate_presence_of(:carrierType) }
    it { is_expected.to validate_length_of(:carrierType).is_equal_to(6) }
    it { is_expected.to validate_length_of(:buyerUn).is_equal_to(8) }
    it { is_expected.to validate_length_of(:buyerTitle).is_at_most(60) }
    it { is_expected.to validate_length_of(:idViewId).is_at_most(10) }
    it { is_expected.to validate_length_of(:memberId).is_at_most(50) }
    # it { is_expected.to validate_presence_of(:itemList) }

    context "on type I" do
      it { is_expected.to validate_presence_of(:donate) }
      it { is_expected.to validate_length_of(:donate).is_equal_to(1) }

      context "with donate 'Y'" do
        before { subject.donate = 'Y' }

        it { is_expected.to validate_presence_of(:donationUnit) }
        it { is_expected.to validate_length_of(:donationUnit).is_at_most(10) }

        it "returns true when donation unit is on list" do
          subject.donationUnit = "9999"
          expect(subject.valid?).to be_truthy
        end

        it "returns false when donation unit isn't on list" do
          subject.donationUnit = "5566183"
          expect(subject.valid?).to be_falsey
        end
      end

      it { is_expected.to validate_presence_of(:carrierId) }
      it { is_expected.to validate_length_of(:carrierId).is_at_most(64) }
      it { is_expected.to validate_presence_of(:carrierIdHidden) }
      it { is_expected.to validate_length_of(:carrierIdHidden).is_at_most(64) }
      it { is_expected.to validate_length_of(:receiverName).is_at_most(30) }
      it { is_expected.to validate_length_of(:receiverAddrZip).is_at_most(6) }
      it { is_expected.to validate_length_of(:receiverAddrRoad).is_at_most(100) }
      it { is_expected.to validate_length_of(:receiverEmail).is_at_most(80) }
      it { is_expected.to validate_length_of(:receiverMobile).is_at_most(15) }
    end

    context "on type R" do
      subject { build(:tradevan_issue_data, :R) }

      it { is_expected.to validate_presence_of(:invoiceNumber) }
      it { is_expected.to validate_length_of(:invoiceNumber).is_equal_to(10) }
      it { is_expected.to validate_presence_of(:donate) }
      it { is_expected.to validate_length_of(:donate).is_equal_to(1) }

      context "with donate 'Y'" do
        before { subject.donate = 'Y' }

        it { is_expected.to validate_presence_of(:donationUnit) }
        it { is_expected.to validate_length_of(:donationUnit).is_at_most(10) }
      end

      it { is_expected.to validate_presence_of(:carrierId) }
      it { is_expected.to validate_length_of(:carrierId).is_at_most(64) }
      it { is_expected.to validate_presence_of(:carrierIdHidden) }
      it { is_expected.to validate_length_of(:carrierIdHidden).is_at_most(64) }
      it { is_expected.to validate_length_of(:receiverName).is_at_most(30) }
      it { is_expected.to validate_length_of(:receiverAddrZip).is_at_most(6) }
      it { is_expected.to validate_length_of(:receiverAddrRoad).is_at_most(100) }
      it { is_expected.to validate_length_of(:receiverEmail).is_at_most(80) }
      it { is_expected.to validate_length_of(:receiverMobile).is_at_most(15) }
    end

    context "on type G" do
      subject { build(:tradevan_issue_data, :G) }

      it { is_expected.to validate_presence_of(:invoiceNumber) }
      it { is_expected.to validate_length_of(:invoiceNumber).is_equal_to(10) }
      it { is_expected.to validate_presence_of(:donate) }
      it { is_expected.to validate_length_of(:donate).is_equal_to(1) }

      context "with donate 'Y'" do
        before { subject.donate = 'Y' }

        it { is_expected.to validate_presence_of(:donationUnit) }
        it { is_expected.to validate_length_of(:donationUnit).is_at_most(10) }
      end

      it { is_expected.to validate_presence_of(:carrierId) }
      it { is_expected.to validate_length_of(:carrierId).is_at_most(64) }
      it { is_expected.to validate_presence_of(:carrierIdHidden) }
      it { is_expected.to validate_length_of(:carrierIdHidden).is_at_most(64) }
      it { is_expected.to validate_length_of(:receiverName).is_at_most(30) }
      it { is_expected.to validate_length_of(:receiverAddrZip).is_at_most(6) }
      it { is_expected.to validate_length_of(:receiverAddrRoad).is_at_most(100) }
      it { is_expected.to validate_length_of(:receiverEmail).is_at_most(80) }
      it { is_expected.to validate_length_of(:receiverMobile).is_at_most(15) }
      it { is_expected.to validate_length_of(:checkNumber).is_equal_to(4) }
      it { is_expected.to validate_length_of(:invoiceDate).is_equal_to(8) }
      it { is_expected.to validate_length_of(:invoiceTime).is_equal_to(8) }
      it { is_expected.to validate_length_of(:texclusiveAmount).is_at_most(20) }
      it { is_expected.to validate_length_of(:oeclusiveAmount).is_at_most(20) }
      it { is_expected.to validate_length_of(:zexclusiveAmount).is_at_most(20) }
      it { is_expected.to validate_length_of(:tax).is_at_most(20) }
      it { is_expected.to validate_length_of(:mainRemark).is_at_most(300) }
      it { is_expected.to validate_length_of(:invoiceType).is_equal_to(2) }
    end

    context "on type H" do
      subject { build(:tradevan_issue_data, :H) }

      it { is_expected.to validate_presence_of(:allowanceIdentifier) }
      it { is_expected.to validate_length_of(:allowanceIdentifier).is_at_most(100) }
      it { is_expected.to validate_presence_of(:invoiceNumber) }
      it { is_expected.to validate_length_of(:invoiceNumber).is_equal_to(10) }
      it { is_expected.to validate_presence_of(:allowanceNumber) }
      # it { is_expected.to validate_length_of(:allowanceNumber).is_at_most(16) }
      it { is_expected.to validate_presence_of(:allowanceDate) }
      # it { is_expected.to validate_length_of(:allowanceDate).is_at_most(8) }
      it { is_expected.to validate_presence_of(:allowanceExclusiveAmount) }
      it { is_expected.to validate_length_of(:allowanceExclusiveAmount).is_at_most(20) }
      it { is_expected.to validate_presence_of(:allowanceTax) }
      it { is_expected.to validate_length_of(:allowanceTax).is_at_most(8) }
      it { is_expected.to validate_presence_of(:allowancePaperReturned) }
      it { is_expected.to validate_length_of(:allowancePaperReturned).is_equal_to(1) }
    end

    context "on type A" do
      subject { build(:tradevan_issue_data, :A) }

      it { is_expected.to validate_presence_of(:allowanceIdentifier) }
      it { is_expected.to validate_length_of(:allowanceIdentifier).is_at_most(100) }
      it { is_expected.to validate_presence_of(:allowanceExclusiveAmount) }
      it { is_expected.to validate_length_of(:allowanceExclusiveAmount).is_at_most(20) }
      it { is_expected.to validate_presence_of(:allowanceTax) }
      it { is_expected.to validate_length_of(:allowanceTax).is_at_most(8) }
      it { is_expected.to validate_presence_of(:allowancePaperReturned) }
      it { is_expected.to validate_length_of(:allowancePaperReturned).is_equal_to(1) }
      it { is_expected.to validate_length_of(:allowaDeclaration).is_equal_to(6) }
      it { is_expected.to validate_presence_of(:invoicePaperReturned) }
      it { is_expected.to validate_length_of(:invoicePaperReturned).is_at_most(1) }
    end
  end
end
