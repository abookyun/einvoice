# frozen_string_literal: true

RSpec.describe Einvoice::Tradevan::DefaultAPI::Errors do
  describe ".classify" do
    {
      "duplicated" => [:conflict, Einvoice::Reason::DUPLICATE_ORDER],
      "交易序號重複" => [:conflict, Einvoice::Reason::DUPLICATE_ORDER],
      "交易序號重覆" => [:conflict, Einvoice::Reason::DUPLICATE_ORDER],
      "發票已作廢，不能折讓" => [:conflict, Einvoice::Reason::ALLOWANCE_BLOCKED_BY_VOID],
      "發票已作廢" => [:conflict, Einvoice::Reason::ALREADY_VOIDED],
      "發票已被作廢" => [:conflict, Einvoice::Reason::ALREADY_VOIDED],
      "發票已折讓，不能作廢" => [:conflict, Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE],
      "發票不能作廢，因為已折讓" => [:conflict, Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE],
      "查無發票資料" => [:not_found, nil],
      "發票不存在" => [:not_found, nil],
      "Invoice not found" => [:not_found, nil],
      "something new" => [:provider, nil],
      "" => [:provider, nil]
    }.each do |message, expected|
      it "maps #{message.inspect} to #{expected.inspect}" do
        expect(described_class.classify(message)).to eq(expected)
      end
    end

    # A refusal that also mentions 已作廢 must not read as "already voided":
    # treating it as success would record a credit that never happened.
    it "reads a refusal before the plain already-voided case" do
      expect(described_class.classify("已作廢，不能折讓").last)
        .to eq(Einvoice::Reason::ALLOWANCE_BLOCKED_BY_VOID)
    end
  end

  describe ".classify_transport" do
    it "maps an account or password message to AuthError" do
      expect(described_class.classify_transport("帳號或密碼錯誤"))
        .to eq([:auth, Einvoice::Reason::CREDENTIALS_INVALID])
    end

    it "maps anything else to ProviderError" do
      expect(described_class.classify_transport("系統維護中")).to eq([:provider, nil])
    end

    it "matches whole English words only" do
      expect(described_class.classify_transport("Invalid key1")).to eq([:auth, Einvoice::Reason::CREDENTIALS_INVALID])
      expect(described_class.classify_transport("wrong password")).to eq([:auth, Einvoice::Reason::CREDENTIALS_INVALID])
      expect(described_class.classify_transport("Required keyword is missing")).to eq([:provider, nil])
    end
  end
end
