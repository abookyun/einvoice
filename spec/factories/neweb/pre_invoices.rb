FactoryGirl.define do
  factory :neweb_pre_invoice, class: Einvoice::Neweb::Model::PreInvoice, parent: :neweb_invoice do
    sequence :data_number do |n|
      "data_number#{n}"
    end
    data_date "2015/12/31"
  end
end
