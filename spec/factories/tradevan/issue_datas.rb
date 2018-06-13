FactoryBot.define do
  factory :tradevan_issue_data, class: Einvoice::Tradevan::Model::IssueData do
    companyUn "53086054"
    orgId "ICKEC"
    saleIdentifier "53086054_ICKEC_20160323014320"
    transactionNumber "1234567890"
    transactionDate "20160323"
    transactionTime "01:43:20"
    total "100"
    paperPrintMode "0"
    carrierType "1K0001"
    invoiceAlarmMode "0"
    itemList { [] }

    after(:build) do |data|
      data.itemList << FactoryBot.build(:tradevan_issue_item)
    end

    trait :I do
      type "I"
      donate "N"
      donationUnit "12345"
      carrierId "123456789012345678901234567890"
      carrierIdHidden "123456789012345678901234567890"
      receiverName "Jamie Oliver"
      receiverAddrZip "106"
      receiverAddrRoad "台北市大安區新生南路一段 50 號"
      receiverEmail "hi@icook.tw"
      receiverMobile "0912123123"
    end

    trait :R do
      type "R"
      invoiceNumber "EM82930261"
      donate "N"
      donationUnit "12345"
      carrierId "123456789012345678901234567890"
      carrierIdHidden "123456789012345678901234567890"
      receiverName "Jamie Oliver"
      receiverAddrZip "106"
      receiverAddrRoad "台北市大安區新生南路一段 50 號"
      receiverEmail "hi@icook.tw"
      receiverMobile "0912123123"
    end

    trait :G do
      type "G"
      invoiceNumber "EM82930261"
      donate "N"
      donationUnit "12345"
      carrierId "123456789012345678901234567890"
      carrierIdHidden "123456789012345678901234567890"
      receiverName "Jamie Oliver"
      receiverAddrZip "106"
      receiverAddrRoad "台北市大安區新生南路一段 50 號"
      receiverEmail "hi@icook.tw"
      receiverMobile "0912123123"
      checkNumber "1234"
      invoiceDate "20160324"
      invoiceTime "01:43:30"
      texclusiveAmount "100"
      oeclusiveAmount "5"
      zexclusiveAmount "0"
      tax "5"
      mainRemark "remark"
      invoiceType "07"
    end

    trait :H do
      type "H"
      allowanceIdentifier "53086054_ICKEC_20160323014320"
      invoiceNumber "EM82930261"
      allowanceNumber "ICKEC20160324001"
      allowanceDate "20160324"
      allowanceExclusiveAmount "100"
      allowanceTax "5"
      allowanceInclusiveAmount "105"
      allowancePaperReturned "Y"
    end

    trait :A do
      type "A"
      allowanceIdentifier "53086054_ICKEC_20160323014320"
      allowanceExclusiveAmount "100"
      allowanceTax "5"
      allowanceInclusiveAmount "105"
      allowancePaperReturned "Y"
      allowaDeclaration "201803"
      invoicePaperReturned "Y"
    end
  end
end
