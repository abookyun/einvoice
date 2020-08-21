require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Download latest e-invoice donation unit list and convert it to JSON"
task :update_donation_unit do
  require "json"
  require "faraday"
  # From https://data.gov.tw/dataset/31868
  data = Faraday.get("https://www.einvoice.nat.gov.tw/home/DownLoad?fileName=1516074903969_0.csv",
                     nil, { "accept-encoding": "none" }).body.force_encoding("big5")
  orgs = data.encode("utf-8").split("\n")[1..-1].map do |line|
    line.split(",").values_at(2, 1)
  end.sort_by(&:first)

  File.write "lib/einvoice/donation_unit_list.json", JSON.pretty_generate(Hash[orgs])
end