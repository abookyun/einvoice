require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Download latest e-invoice donation unit list and convert it to JSON"
task :update_donation_unit do
  require "csv"
  require "json"
  require "faraday"

  # From https://data.gov.tw/dataset/31868
  url = "https://dataset.einvoice.nat.gov.tw/ods/portal/ODS303W/download/3886F055-EB77-4DF9-98E2-F3F49A7D3434/1/8B227A99-042A-4903-8B34-5715442A227D/0/?fileType=csv"
  response = Faraday.get(url)
  raise "Download failed: HTTP #{response.status}" unless response.status == 200

  body = response.body

  possible = ["UTF-8", "Big5"]
  chosen = nil
  utf8_text = nil

  possible.each do |code|
    begin
      str = body.dup.force_encoding(code)
      candidate = str.encode("UTF-8")
      if candidate.valid_encoding?
        chosen = code
        utf8_text = candidate
        break
      end
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      next
    end
  end

  unless chosen
    chosen = "fallback(replace)"
    utf8_text = body.dup.force_encoding("UTF-8").scrub("?")
    puts "::warning::Used fallback encoding with replacement; some characters may be lost"
  end

  utf8_text = utf8_text.delete_prefix("\uFEFF") # remove possible UTF-8 BOM
  csv = CSV.parse(utf8_text, headers: true)

  orgs = csv.map do |row|
    code = (row['捐贈碼'] || row[2]).to_s.strip
    name = (row['受捐贈機關或團體名稱'] || row[1]).to_s.strip
    [code, name]
  end.sort_by { |code, _| [code.to_i, code] }

  File.write "lib/einvoice/donation_unit_list.json", JSON.pretty_generate(orgs.to_h)

  puts "Wrote lib/einvoice/donation_unit_list.json (#{orgs.length} entries)"
end
