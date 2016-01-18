FactoryGirl.define do
  factory :neweb_invoice, class: Einvoice::Neweb::Model::Invoice do
    seller_id "53086054"
    buyer_name "Polydice, Inc."
    buyer_id "0000000000"
    invoice_type "07"
    donate_mark "0"
    print_mark "N"
    sales_amount "1000"
    free_tax_sales_amount "0"
    zero_tax_sales_amount "0"
    tax_type "1"
    tax_rate "0.05"
    tax_amount "50"
    total_amount "1050"

    random_number "AAAA"

    FactoryGirl.build(:invoice_item_neweb)
    FactoryGirl.build(:contact_neweb)

    trait :b2c do
      buyer_id "0" * 10
      # random 4 ascii chars
      buyer_name { (0...4).map { (65 + rand(26)).chr }.join }
    end
  end
end
