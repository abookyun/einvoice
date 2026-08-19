# frozen_string_literal: true

RSpec.describe Einvoice::ECPay::Crypto do
  let(:key) { Einvoice::ECPay::SANDBOX[:hash_key] }
  let(:iv) { Einvoice::ECPay::SANDBOX[:hash_iv] }

  # Cross-language parity vectors: the expected values were produced by the
  # TypeScript SDK (@paid-tw/einvoice-ecpay) and match ECPay's own published
  # AES vectors where the two overlap. They pin the whole
  # JSON → PHP urlencode → AES-128-CBC → Base64 chain, so a regression in any
  # step — padding, encoding, byte handling — fails here rather than at ECPay.
  vectors = [
    {
      name: "an ASCII payload",
      payload: { "MerchantID" => "2000132", "BarCode" => "/1234567" },
      encoded: "%7B%22MerchantID%22%3A%222000132%22%2C%22BarCode%22%3A%22%2F1234567%22%7D",
      base64: "XeEOdHpTRvxKEqs/JD9RSd16s7VtpyWVCN6AV44pKTW3DVa6yI7vKmjBRp2eulDhXoru/qBqFDBH3fEqlkMn3bbJfJBfGAq+v+SvttutYnc="
    },
    {
      name: "UTF-8 Chinese item names",
      payload: { "MerchantID" => "2000132", "ItemName" => "綠界科技測試商品" },
      encoded: "%7B%22MerchantID%22%3A%222000132%22%2C%22ItemName%22%3A%22%E7%B6%A0%E7%95%8C%E7%A7%91%E6%8A%80%E6%B8%AC%E8%A9%A6%E5%95%86%E5%93%81%22%7D",
      base64: "XeEOdHpTRvxKEqs/JD9RSd16s7VtpyWVCN6AV44pKTVKsXddZRgV+Cle9oeB2PqsEC2O0oDi4kObiCtdGznG9aAX69Kj0//VjGXhieBYZ3RuGW9v20xQyBevaBwtOvg1lYjlDw6jsgfToGMUvlGsIJ2DO6/tbXjNZumnRgj2GCSj7LLDRBU3KlkUWji16nO1"
    },
    {
      name: "characters only PHP's urlencode escapes",
      payload: { "Name" => "test!*'()~value" },
      encoded: "%7B%22Name%22%3A%22test%21%2A%27%28%29%7Evalue%22%7D",
      base64: "uvI4yrErM37XNQkXGAgRgBuDOiJoVs72Xn/rum9Ejl1DSna4HyLSoY7764PmhTR7JXb9jJWLSjCGcZEDeFiABg=="
    },
    {
      name: "spaces, which encode as + rather than %20",
      payload: { "Remark" => "a b  c" },
      encoded: "%7B%22Remark%22%3A%22a+b++c%22%7D",
      base64: "0gCIxdVbozMuJQxOmmWoXYjTS+z4/XL2Zwh39rYNyWjjwlQKP0v9Cqr+MUMNc8Wa"
    },
    {
      # 32 encoded bytes is exactly two AES blocks, so PKCS7 must add a whole
      # extra block of padding. Implementations that pad only to the boundary
      # produce a shorter ciphertext and fail to decrypt at the far end.
      name: "a payload landing exactly on a block boundary",
      payload: { "N" => "1234567890" },
      encoded: "%7B%22N%22%3A%221234567890%22%7D",
      base64: "gVwWJnIpl1m3ZDypcRAjiCctilYnQhHn4h8OzJP5IxQPov7HuysXX+jPONvrHS7Z"
    }
  ].freeze

  describe "cross-language parity" do
    vectors.each do |vector|
      context "with #{vector[:name]}" do
        it "url-encodes exactly as PHP does" do
          expect(described_class.php_url_encode(JSON.generate(vector[:payload])))
            .to eq(vector[:encoded])
        end

        it "encrypts to the same ciphertext as the other SDKs" do
          expect(described_class.encrypt_data(vector[:payload], key, iv)).to eq(vector[:base64])
        end

        it "decrypts the reference ciphertext back to the payload" do
          expect(described_class.decrypt_data(vector[:base64], key, iv)).to eq(vector[:payload])
        end
      end
    end
  end

  describe ".php_url_encode" do
    it "leaves the unreserved set alone" do
      expect(described_class.php_url_encode("aZ09-_.")).to eq("aZ09-_.")
    end

    it "encodes each byte of a multi-byte character separately" do
      expect(described_class.php_url_encode("界")).to eq("%E7%95%8C")
    end
  end

  describe ".php_url_decode" do
    it "round-trips a string through encode" do
      original = "發票 remark: a+b&c=d/e~f!"
      expect(described_class.php_url_decode(described_class.php_url_encode(original)))
        .to eq(original)
    end

    it "returns UTF-8, not binary" do
      expect(described_class.php_url_decode("%E7%95%8C").encoding).to eq(Encoding::UTF_8)
    end
  end

  describe "credential validation" do
    it "rejects a hash key that is not 16 bytes" do
      expect { described_class.encrypt_data({}, "too-short", iv) }
        .to raise_error(Einvoice::ValidationError, /hash_key must be 16 bytes.*got 9/)
    end

    it "rejects a hash iv that is not 16 bytes" do
      expect { described_class.encrypt_data({}, key, "#{iv}extra") }
        .to raise_error(Einvoice::ValidationError, /hash_iv must be 16 bytes/)
    end
  end

  describe "decrypting a payload we cannot read" do
    it "raises a ProviderError rather than leaking an OpenSSL error" do
      expect { described_class.decrypt_data("bm90LWEtY2lwaGVydGV4dA==", key, iv) }
        .to raise_error(Einvoice::ProviderError, /Could not decrypt/)
    end

    it "raises a ProviderError when the plaintext is not JSON" do
      garbage = described_class.encrypt("not json at all", key, iv)
      expect { described_class.decrypt_data(garbage, key, iv) }
        .to raise_error(Einvoice::ProviderError, /malformed JSON/)
    end
  end
end
