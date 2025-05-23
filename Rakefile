require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Download latest e-invoice donation unit list and convert it to JSON"
task :update_donation_unit do
  require "json"
  require "faraday"
  # From https://data.gov.tw/dataset/31868
  data = Faraday.get("https://dataset.einvoice.nat.gov.tw/ods/portal/ODS303W/download/3886F055-EB77-4DF9-98E2-F3F49A7D3434/1/8B227A99-042A-4903-8B34-5715442A227D/0/?fileType=csv").body.force_encoding("utf-8")
  orgs = data.split("\n")[1..-1].map do |line|
    line.split(",").values_at(2, 1)
  end.sort_by(&:first)

  File.write "lib/einvoice/donation_unit_list.json", JSON.pretty_generate(Hash[orgs])
end