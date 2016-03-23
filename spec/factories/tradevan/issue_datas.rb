FactoryGirl.define do
  factory :tradevan_issue_data, class: Einvoice::Tradevan::Model::IssueData do
    companyUn "53086054"
    orgId "ICKEC"
    orgUn "53086054"
    type "I"
    saleIdentifier "53086054_ICKEC_20160323014320"
    transactionNumber "1234567890"
    transactionDate "20160323"
    transactionTime "01:43:20"
    total "100"
    paperPrintMode "0"
    carrierType "0"
    carrierId "123456789012345678901234567890"
    carrierIdHidden "123456789012345678901234567890"
    invoiceAlarmMode "0"
    donate "N"
    receiverName "Jamie Oliver"
    receiverAddrZip "106"
    receiverAddrRoad "台北市大安區新生南路一段 50 號"
    itemList { [] }

    after(:build) do |data|
      data.itemList << FactoryGirl.build(:tradevan_issue_item)
    end
  end
end
