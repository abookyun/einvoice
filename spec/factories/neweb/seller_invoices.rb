FactoryGirl.define do
  factory :neweb_seller_invoice, class: Einvoice::Neweb::Model::SellerInvoice, parent: :neweb_invoice do
    sequence :invoice_number do |n|
      "invoice_number#{n}"
    end
    invoice_date "2015/12/31"
  end
end
