FactoryGirl.define do
  factory :neweb_invoice, class: Einvoice::Neweb::Model::Invoice do
    seller_id "53086054"
    buyer_name "aaaa"
    buyer_id "0000000000"
    invoice_type "07"
    donate_mark "0"
    n_p_o_b_a_n "53086054"
    print_mark "N"
    carrier_type ""
    carrier_id1 ""
    carrier_id2 ""
    sales_amount "1000"
    free_tax_sales_amount "0"
    zero_tax_sales_amount "0"
    tax_type "1"
    tax_rate "0.05"
    tax_amount "50"
    total_amount "1050"

    random_number "AAAA"

    invoice_item { [] }
    after(:build) do |invoice|
      invoice.invoice_item << FactoryGirl.build(:neweb_invoice_item)
      invoice.contact = FactoryGirl.build(:neweb_contact)
    end

    trait :b2c do
      buyer_id "0" * 10
      # random 4 ascii chars
      buyer_name { (0...4).map { (65 + rand(26)).chr }.join }
    end
  end
end
