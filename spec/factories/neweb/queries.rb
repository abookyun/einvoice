FactoryGirl.define do
  factory :neweb_query, class: Einvoice::Neweb::Model::Query do
    invoice_date_time_s "2015/12/31"
    invoice_date_time_e "2015/12/31"
    sequence :data_number_s do |n|
      "data_number#{n}"
    end
    data_number_e { data_number_s }
    sync_status_update "N"
  end
end
