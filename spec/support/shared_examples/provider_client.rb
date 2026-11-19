# frozen_string_literal: true

# The transport rules of the unified model (docs/providers/README.md, "The
# unified model"), for every provider client. Each client keeps its own way to
# send a request and read a response. This contract only checks what the core
# promises about all of them, so the same bug cannot come back in one client.
#
# The host group must supply:
#   client           a client built with base_url "https://<host>"
#   stub_host        a Regexp that matches every request URL of the client
#   send_request     a method that sends one ordinary request
#   error_body       a method that returns a JSON String: an error response
#                    that the provider wrote, which the client can read
#   secrets          the credentials that inspect must not show
#   build_client     a method that takes base_url: and builds a client
RSpec.shared_examples "a provider client" do
  def respond(status, body)
    stub_request(:any, stub_host).to_return(status: status, headers: { "Content-Type" => "text/html" }, body: body)
  end

  describe "a body that the provider did not write" do
    it "is a NetworkError for HTTP 5xx, so the caller can retry" do
      respond(503, "<html>Service Unavailable</html>")
      expect { send_request }.to raise_error(Einvoice::NetworkError) { |error| expect(error.raw_code).to eq("503") }
    end

    it "is a NetworkError with RATE_LIMITED for HTTP 429" do
      respond(429, "<html>Too Many Requests</html>")
      expect { send_request }
        .to raise_error(Einvoice::NetworkError) { |error| expect(error.reason).to eq(Einvoice::Reason::RATE_LIMITED) }
    end

    it "is a ProviderError, not a NetworkError, for another status" do
      respond(200, "<html>maintenance</html>")
      expect { send_request }.to raise_error(Einvoice::ProviderError)
    end
  end

  it "lets a body that the provider wrote decide, whatever the HTTP status" do
    respond(500, error_body)
    expect { send_request }.to raise_error(Einvoice::Error) { |error| expect(error).not_to be_a(Einvoice::NetworkError) }
  end

  it "raises NetworkError when the connection fails" do
    stub_request(:any, stub_host).to_raise(Errno::ECONNREFUSED)
    expect { send_request }.to raise_error(Einvoice::NetworkError)

    stub_request(:any, stub_host).to_timeout
    expect { send_request }.to raise_error(Einvoice::NetworkError)
  end

  # Only connection errors are rescued: a bug must not look like a network
  # problem that the caller retries.
  it "lets a bug through as it is" do
    stub_request(:any, stub_host).to_raise(NoMethodError.new("a bug"))
    expect { send_request }.to raise_error(NoMethodError, "a bug")
  end

  it "hides the credentials in inspect and to_s" do
    [client.inspect, client.to_s, "#{client}"].each do |text|
      secrets.each { |secret| expect(text).not_to include(secret) }
    end
  end

  describe "base_url" do
    it "refuses http to another host, a user or password, and a query" do
      ["http://provider.example", "https://user:pass@provider.example", "https://provider.example/gw?a=1"]
        .each { |url| expect { build_client(base_url: url) }.to raise_error(Einvoice::ValidationError) }
    end

    it "keeps the checked value frozen, without a trailing slash" do
      url = build_client(base_url: "https://provider.example/gw/").base_url
      expect(url).to eq("https://provider.example/gw")
      expect(url).to be_frozen
    end
  end
end
