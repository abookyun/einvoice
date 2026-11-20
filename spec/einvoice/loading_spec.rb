# frozen_string_literal: true

require "open3"
require "rbconfig"

# The spec helper loads every adapter, so these checks run in a new Ruby
# process: an app that requires the core gets no adapter, and an app that
# requires one adapter gets that adapter and the core.
RSpec.describe "Loading" do
  lib = File.expand_path("../../lib", __dir__)

  def run_ruby(lib, code)
    out, status = Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", code)
    raise "ruby failed: #{out}" unless status.success?

    out.split
  end

  adapters = {
    "einvoice/ecpay" => "ECPay",
    "einvoice/amego" => "Amego",
    "einvoice/ezpay" => "EzPay",
    "einvoice/tradevan" => "Tradevan",
    "einvoice/mof" => "MOF"
  }

  it "loads the core only for require \"einvoice\"" do
    names = adapters.values.map(&:inspect).join(", ")
    loaded = run_ruby(lib, <<~RUBY)
      require "einvoice"
      puts Einvoice::MockProvider.name
      puts [#{names}].select { |name| Einvoice.const_defined?(name, false) }
    RUBY
    expect(loaded).to eq(["Einvoice::MockProvider"])
  end

  adapters.each do |path, name|
    it "loads #{name} and the core for require #{path.inspect}, and no other adapter" do
      others = (adapters.values - [name]).map(&:inspect).join(", ")
      loaded = run_ruby(lib, <<~RUBY)
        require #{path.inspect}
        puts Einvoice.const_defined?(#{name.inspect}, false)
        puts Einvoice.const_defined?(:Provider, false)
        puts [#{others}].select { |other| Einvoice.const_defined?(other, false) }
      RUBY
      expect(loaded).to eq(%w[true true])
    end
  end
end
