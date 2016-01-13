FactoryGirl.define do
  factory :invoice_item, class: Einvoice::Model::Neweb::InvoiceItem do
    sequence :description do |n|
      "item#{n}"
    end
    quantity "10"
    unit_price "100"
    amount "1000"
    sequence :sequence_number do |n|
      "#{n}"
    end
  end
end
