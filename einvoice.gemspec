# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "einvoice/version"

Gem::Specification.new do |spec|
  spec.name          = "einvoice"
  spec.version       = Einvoice::VERSION
  spec.authors       = ["David Yun"]
  spec.email         = ["abookyun@gmail.com"]

  spec.summary       = "Provider-agnostic Taiwan e-invoice SDK (unified model + per-provider adapters)."
  spec.homepage      = "https://github.com/abookyun/einvoice"
  spec.license       = "MIT"

  spec.metadata = {
    "source_code_uri" => "https://github.com/abookyun/einvoice",
    "changelog_uri" => "https://github.com/abookyun/einvoice/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/abookyun/einvoice/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Data.define (Ruby 3.2) is the backbone of the value model.
  spec.required_ruby_version = ">= 3.2"

  # The core has zero runtime dependencies — the unified model, validation, and
  # error handling are plain Ruby + stdlib. Adapters add only what their wire
  # format needs (openssl/json are stdlib); HTTP is stdlib Net::HTTP.

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "vcr", "~> 6.3"
  spec.add_development_dependency "webmock", "~> 3.23"
end
