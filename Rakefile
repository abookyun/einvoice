require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Convert E-Invoice donation unit CSV to JSON"
task :convert_donation_unit do
  require 'json'
  orgs = File.readlines('xca.csv', encoding: "big5")[1..-1].map do |line|
    line.encode('utf-8').split(',').values_at(2, 1)
  end.sort_by(&:first)

  File.write 'lib/einvoice/donation_unit_list.json', JSON.pretty_generate(Hash[orgs])
end