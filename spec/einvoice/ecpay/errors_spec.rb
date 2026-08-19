# frozen_string_literal: true

RSpec.describe Einvoice::ECPay::Errors do
  describe ".classify_transport" do
    it "reads a decrypt failure as bad credentials, not a provider fault" do
      expect(described_class.classify_transport(110))
        .to eq([:auth, Einvoice::Reason::CREDENTIALS_INVALID])
    end

    it "reads a rejected timestamp as a stale clock the caller can fix" do
      expect(described_class.classify_transport(104))
        .to eq([:validation, Einvoice::Reason::STALE_TIMESTAMP])
    end

    it "falls back to a provider error for anything else" do
      expect(described_class.classify_transport(999)).to eq([:provider, nil])
    end
  end

  describe ".classify" do
    # Every code/message pair below was captured from the live stage API on
    # 2026-08-15 — see the live spec, which re-runs the same scenarios for real.
    {
      [5_070_357, "B2C開立發票 自訂編號重覆，請重新設定"] =>
        [:conflict, Einvoice::Reason::DUPLICATE_ORDER],
      [5_070_450, "B2C作廢發票 該發票已被折讓過，無法直接作廢發票"] =>
        [:conflict, Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE],
      [5_070_453, "B2C作廢發票 該發票已被作廢過"] =>
        [:conflict, Einvoice::Reason::ALREADY_VOIDED],
      [2_000_063, "該折讓單已作廢過，請確認"] =>
        [:conflict, Einvoice::Reason::ALREADY_VOIDED],
      [2_000_039, "查無折讓單資料，請確認!"] => [:not_found, nil],
      [2_000_042, "作廢發票號碼不能折讓"] =>
        [:conflict, Einvoice::Reason::ALLOWANCE_BLOCKED_BY_VOID],
      [1_600_003, "無發票號碼資料"] => [:not_found, nil],
      [2, "查無發票資料，請重新確認"] => [:not_found, nil],
      [5_000_022, "驗證發票金額發現錯誤，與商品合計金額不符"] => [:validation, nil],
      [2_011_002, "發票號碼長度錯誤"] => [:validation, nil],
      [9_000_001, "呼叫財政部API失敗"] => [:network, nil]
    }.each do |(code, message), expected|
      it "maps #{code} (#{message}) to #{expected.first}" do
        expect(described_class.classify(code, message)).to eq(expected)
      end
    end

    # ECPay writes "重覆" here, not the "重複" spelling a mapping is likely to be
    # written against. Matching only one demotes a duplicate-order conflict — the
    # signal to query and adopt the existing invoice — into a generic validation
    # error, so both spellings have to resolve the same way.
    it "recognises both spellings of 重複/重覆" do
      expect(described_class.classify(999, "自訂編號重覆"))
        .to eq([:conflict, Einvoice::Reason::DUPLICATE_ORDER])
      expect(described_class.classify(999, "自訂編號重複"))
        .to eq([:conflict, Einvoice::Reason::DUPLICATE_ORDER])
    end

    it "treats 財政部 outages as retryable rather than the caller's fault" do
      expect(described_class.classify(0, "呼叫財政部API失敗，請稍後再試").first).to eq(:network)
    end

    it "separates an unknown merchant from an unknown record" do
      expect(described_class.classify(0, "特店不存在"))
        .to eq([:auth, Einvoice::Reason::NOT_ENROLLED])
      expect(described_class.classify(0, "不存在此交易單號")).to eq([:not_found, nil])
    end

    # The same conditions again, but arriving under codes the table does not know —
    # the fallback has to reach the same verdict from the message alone.
    it "recognises a credential failure from the message alone" do
      expect(described_class.classify(0, "簽章驗證失敗"))
        .to eq([:auth, Einvoice::Reason::CREDENTIALS_INVALID])
    end

    it "recognises an already-voided invoice from the message alone" do
      expect(described_class.classify(0, "該發票已作廢"))
        .to eq([:conflict, Einvoice::Reason::ALREADY_VOIDED])
    end

    # "作廢…不能…" is the other way ECPay says it: the invoice is voided, so the
    # operation is refused. Reading only 已作廢 files this as a field error.
    it "recognises a refusal caused by the invoice being voided" do
      expect(described_class.classify(0, "作廢發票號碼不能折讓"))
        .to eq([:conflict, Einvoice::Reason::ALLOWANCE_BLOCKED_BY_VOID])
    end

    # The two 作廢 conflicts imply opposite responses — "already in the state you
    # wanted" versus "refused, and nothing happened" — so a message carrying both
    # has to resolve to the refusal.
    it "prefers the refusal when a message reads as both" do
      expect(described_class.classify(0, "該發票已作廢，不能折讓"))
        .to eq([:conflict, Einvoice::Reason::ALLOWANCE_BLOCKED_BY_VOID])
      expect(described_class.classify(0, "該發票已被作廢過"))
        .to eq([:conflict, Einvoice::Reason::ALREADY_VOIDED])
    end

    it "does not mistake a field error that merely mentions 作廢 for a conflict" do
      expect(described_class.classify(0, "作廢原因長度錯誤")).to eq([:validation, nil])
    end

    it "recognises a void blocked by an allowance from the message alone" do
      expect(described_class.classify(0, "該發票已被折讓過"))
        .to eq([:conflict, Einvoice::Reason::VOID_BLOCKED_BY_ALLOWANCE])
    end

    it "treats an already-issued invoice as a conflict with no finer reason" do
      expect(described_class.classify(0, "該筆訂單已開立發票")).to eq([:conflict, nil])
    end

    it "maps an exhausted 字軌 to its own error class" do
      expect(described_class.classify(0, "發票號碼已用罄").first).to eq(:number_exhausted)
    end

    it "flags a busy provider as rate limited" do
      expect(described_class.classify(0, "系統忙碌中，請稍後再試"))
        .to eq([:provider, Einvoice::Reason::RATE_LIMITED])
    end

    # ECPay's codes are inconsistent enough that guessing from an unknown one is
    # worse than admitting it is a field problem — which is what most of the tail is.
    it "defaults an unrecognised failure to validation" do
      expect(described_class.classify(1_234_567, "某個未知的錯誤")).to eq([:validation, nil])
    end
  end
end
