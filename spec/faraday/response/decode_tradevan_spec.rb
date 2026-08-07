require 'spec_helper'

RSpec.describe Faraday::Response::DecodeTradevan do
  let(:key) { "0123456789abcdef" }

  def encrypt(content)
    cipher = OpenSSL::Cipher::AES.new(128, :CBC)
    cipher.encrypt
    cipher.key = key
    cipher.iv = key
    cipher.padding = 0

    q, m = content.bytesize.divmod(cipher.block_size)
    if m != 0 || q == 0
      content = content.bytes.fill(0, content.bytesize..(cipher.block_size * (q + 1) - 1)).pack('C*')
    end

    Base64.strict_encode64(cipher.update(content) + cipher.final)
  end

  def connection(body)
    Faraday.new do |conn|
      conn.response :decode_tradevan, key
      conn.response :json
      conn.adapter :test do |stub|
        stub.get('/api') { [200, { 'Content-Type' => 'application/json' }, body.to_json] }
      end
    end
  end

  it "decrypts and parses the Message payload on success" do
    message = { "invoiceNumber" => "GX38551078", "issueStatus" => "Y" }
    body = { "Success" => "Y", "Message" => encrypt(message.to_json) }

    expect(connection(body).get('/api').body["Message"]).to eq message
  end

  it "leaves the body untouched on error responses" do
    body = { "Success" => "E", "Message" => "some error" }

    expect(connection(body).get('/api').body["Message"]).to eq "some error"
  end
end
