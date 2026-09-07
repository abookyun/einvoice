source 'https://rubygems.org'

# Specify your gem's dependencies in einvoice.gemspec
gemspec

# Remove this pin once we drop Ruby 3.1 support. json 3.0 dropped quirks_mode,
# which activesupport 7.2.3.2 still passes; 7.2.3.2 is the newest activesupport
# that works on Ruby 3.1.
gem "json", "< 3.0"

# Used by the update_donation_unit rake task; csv leaves the default gems in Ruby 3.4.
gem "csv", require: false, group: :development

gem "ostruct", require: false, group: :development
gem "simplecov", require: false, group: :test
gem "simplecov-lcov", require: false, group: :test
