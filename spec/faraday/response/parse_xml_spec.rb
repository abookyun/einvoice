require 'spec_helper'

RSpec.describe Faraday::Response::ParseXml do
  def connection(body, content_type = 'application/xml')
    Faraday.new do |conn|
      conn.response :xml
      conn.adapter :test do |stub|
        stub.get('/api') { [200, { 'Content-Type' => content_type }, body] }
      end
    end
  end

  it "parses an XML body into a hash" do
    body = connection("<Root><Value>ok</Value></Root>").get('/api').body
    expect(body).to eq("Root" => { "Value" => "ok" })
  end

  it "leaves empty bodies untouched" do
    expect(connection("").get('/api').body).to eq ""
  end
end
