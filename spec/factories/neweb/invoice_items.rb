FactoryGirl.define do
  factory :neweb_invoice_item, class: Einvoice::Neweb::Model::InvoiceItem do
    sequence :description do |n|
      "item#{n}"
    end
    quantity "10.0"
    unit_price "100.0"
    amount "1000.0"
    sequence :sequence_number do |n|
      "#{n + 1}"
    end
  end
end
