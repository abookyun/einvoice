# frozen_string_literal: true

require "vcr"

# Cassettes hold real traffic from the service under test, so the recorded specs
# replay genuine responses — actual field names, types and encodings — instead of
# our reading of them. They replay offline in CI.
#
# Re-recording (rare — only when a payload changes, or a new endpoint is covered):
#
#   VCR_RECORD=1 bundle exec rspec spec/einvoice/<service>/recorded_spec.rb
#
# Recorded suites only ever talk to a public sandbox or a public dataset, and
# hardcode those credentials rather than reading the environment, so a cassette
# can never capture a real merchant's traffic.
VCR.configure do |config|
  config.cassette_library_dir = File.join(__dir__, "..", "fixtures", "vcr_cassettes")
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # A request can carry a per-request timestamp, and with it a different body
  # every run, so the body can never match on replay — method and URI are what
  # identify an interaction here. Recorded interactions are still replayed in
  # order, which is what makes a same-endpoint sequence meaningful.
  config.default_cassette_options = {
    match_requests_on: %i[method uri],
    # Never reach for the network unless recording was explicitly asked for:
    # a missing cassette should fail loudly, not quietly hit the live service.
    record: ENV["VCR_RECORD"] == "1" ? :all : :none
  }
end
