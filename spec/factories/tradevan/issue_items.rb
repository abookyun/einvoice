FactoryGirl.define do
  factory :tradevan_issue_item, class: Einvoice::Tradevan::Model::IssueItem do
    saleIdentifier "53086054_ICKEC_20160323014320"
    serialNumber "0001"
    productCode "98765"
    productName "銷售費"
    qty "1"
    price "100"
    tax "5"
    itemTotal "100"
    taxType "T"
  end
end
