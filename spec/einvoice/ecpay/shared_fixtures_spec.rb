# frozen_string_literal: true

require "date"

# Checks the ECPay adapter against the wire fixtures that the TypeScript SDK
# also runs. They pin what ECPay receives for a given input, and how ECPay's
# error codes are classified. See spec/fixtures/shared/README.md for the source.
#
# The fixture inputs use the TypeScript input shape. #to_ruby turns each one
# into the Ruby input. The Ruby shape is different on purpose: the original
# invoice is an InvoiceReference, not invoiceNumber with
# providerOptions.invoiceDate. Only the input is translated. The wire data and
# the error classes are compared as they are.
RSpec.describe "ECPay against the shared fixtures" do
  dir = File.expand_path("../../fixtures/shared/ecpay", __dir__)
  load_cases = ->(name) { JSON.parse(File.read(File.join(dir, "#{name}.json")))["cases"] }

  let(:provider) do
    Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX, base_url: "https://ecpay.test")
  end

  def snake(value)
    case value
    when Hash then value.to_h { |key, item| [key.to_s.gsub(/([A-Z])/) { "_#{::Regexp.last_match(1).downcase}" }, snake(item)] }
    when Array then value.map { |item| snake(item) }
    else value
    end
  end

  # The original invoice, from invoiceNumber and providerOptions.invoiceDate.
  def invoice_reference(input, options)
    { "number" => input["invoice_number"],
      "invoice_datetime" => options.delete("invoice_date")&.then { |date| Date.parse(date) } }.compact
  end

  def to_ruby(operation, fixture_input)
    input = snake(fixture_input)
    options = input.delete("provider_options") || {}
    case operation
    when "issue"
      input.merge("provider_options" => options)
    when "void"
      { "invoice" => invoice_reference(input, options), "reason" => input["reason"], "provider_options" => options }
    when "allowance"
      { "invoice" => invoice_reference(input, options), "allowance_id" => input["allowance_id"],
        "items" => input["items"], "amount" => input["amount"], "provider_options" => options }
    when "voidAllowance"
      { "allowance" => { "allowance_number" => input["allowance_number"], "invoice_number" => input["invoice_number"] },
        "reason" => input["reason"] }.compact
    when "query"
      reference = input["order_id"] ? { "order_id" => input["order_id"] } : invoice_reference(input, options)
      { "invoice" => reference }
    end
  end

  # Sends the input and returns the path and the decrypted data that reached
  # ECPay. The stub answers with a body that is not JSON, so the call fails
  # after the request is captured. Only the request matters here.
  def capture(operation, input)
    captured = nil
    stub_request(:post, %r{\Ahttps://ecpay\.test/}).to_return do |request|
      envelope = JSON.parse(request.body)
      data = Einvoice::ECPay::Crypto.decrypt_data(envelope["Data"], Einvoice::ECPay::SANDBOX[:hash_key],
                                                  Einvoice::ECPay::SANDBOX[:hash_iv])
      captured ||= [URI(request.uri.to_s).path, data]
      { status: 200, body: "captured" }
    end
    method = operation == "voidAllowance" ? :void_allowance : operation.to_sym
    begin
      provider.public_send(method, input)
    rescue Einvoice::ProviderError
      nil
    end
    captured
  end

  # A subset match for objects. Arrays match by length and by index.
  def match_subset(expected, actual, path = "data")
    case expected
    when Hash
      expect(actual).to be_a(Hash), "#{path} is not an object"
      expected.each { |key, value| match_subset(value, actual[key], "#{path}.#{key}") }
    when Array
      expect(actual&.size).to eq(expected.size), "#{path} has #{actual&.size} items, not #{expected.size}"
      expected.each_with_index { |value, index| match_subset(value, actual[index], "#{path}[#{index}]") }
    else
      expect(actual).to eq(expected), "#{path} is #{actual.inspect}, not #{expected.inspect}"
    end
  end

  %w[issue void-allowance query].each do |file|
    load_cases.call(file).each do |fixture|
      it fixture["name"] do
        input = to_ruby(fixture["operation"], fixture["input"])
        path, data = capture(fixture["operation"], input)
        expected = fixture["expect"]

        expect(path).to eq(expected["endpoint"])
        match_subset(expected["data"], data)
        Array(expected["dataAbsent"]).each { |key| expect(data).not_to have_key(key) }
        Array(expected["itemsAbsent"]).each do |rule|
          rule["keys"].each { |key| expect(data["Items"][rule["index"]]).not_to have_key(key) }
        end
        expect(data.keys).to match_array(expected["data"].keys) if expected["dataExact"]
      end
    end
  end

  def unified(expect)
    [expect["code"].downcase.to_sym, expect["reason"]&.to_sym]
  end

  load_cases.call("errors").each do |fixture|
    it "classifies #{fixture['name']}" do
      expect(Einvoice::ECPay::Errors.classify(fixture["rtnCode"], fixture["rtnMsg"]))
        .to eq(unified(fixture["expect"]))
    end
  end

  load_cases.call("transport-errors").each do |fixture|
    it "classifies the transport error #{fixture['name']}" do
      expect(Einvoice::ECPay::Errors.classify_transport(fixture["transCode"])).to eq(unified(fixture["expect"]))
    end
  end
end
