# frozen_string_literal: true

RSpec.describe Einvoice::Tradevan::DefaultAPI::Crypto do
  let(:key1) { "0123456789abcdef" }
  let(:key2) { "fedcba9876543210" }

  # Cipher text produced by the 1.x client's own #encrypt (copied as is from
  # 1-x-stable lib/einvoice/tradevan/provider.rb), which ran in production. The
  # 2.0 port must produce the same bytes.
  vectors_from_1x = {
    "" => "cnJ+iB7c/QEApxhoeQm1ZQ==",
    "a" => "gKy7HQzcQHvu2qAFJuOTtg==",
    "0123456789abcdef" => "C5sV2ktEoPUVHc/EwB811Q==",
    "0123456789abcdefg" => "C5sV2ktEoPUVHc/EwB811T3XGOiek7rfSF0H5zlXQmg=",
    "咖啡拿鐵" => "XeIB5RNGVzlHKmxMM/OibQ==",
    %({"invoiceNumber":"GX38551078"}) => "dxH4yLvK65BXclLzLVshQuQ+mteOTCWgHSy0v/1gGRM="
  }.freeze

  describe ".encrypt" do
    vectors_from_1x.each do |plain, cipher|
      it "matches the 1.x client for #{plain.inspect}" do
        expect(described_class.encrypt(plain, key1)).to eq(cipher)
      end
    end

    it "pads an empty text to one block, and a full block not at all" do
      expect(described_class.encrypt("", key1).unpack1("m").bytesize).to eq(16)
      expect(described_class.encrypt("x" * 16, key1).unpack1("m").bytesize).to eq(16)
      expect(described_class.encrypt("x" * 17, key1).unpack1("m").bytesize).to eq(32)
    end

    it "refuses a key that is not 16 bytes" do
      expect { described_class.encrypt("a", "short") }
        .to raise_error(Einvoice::ValidationError, /16 bytes/)
    end
  end

  describe ".decrypt" do
    vectors_from_1x.each do |plain, cipher|
      it "reads back #{plain.inspect} without the NUL padding" do
        expect(described_class.decrypt(cipher, key1)).to eq(plain)
      end
    end

    it "returns UTF-8" do
      expect(described_class.decrypt(vectors_from_1x["咖啡拿鐵"], key1).encoding).to eq(Encoding::UTF_8)
    end

    it "raises ProviderError on a cipher text it cannot read" do
      expect { described_class.decrypt("not base64 at all", key1) }
        .to raise_error(Einvoice::ProviderError, /decrypt/)
    end
  end

  describe ".encode_params" do
    it "matches the v that the 1.x client built for the same call" do
      v = described_class.encode_params({ invoiceNumber: "GX38551078" },
                                        acnt: "acnt", acntp: "acntp", key1: key1, key2: key2)

      expect(v).to eq("/HjBiSmW841YZiHgowq9ifbU+yg5bIOkzAwNK8qoeC1dWjnscx4M6pmLwXHWI5eOabpJglx2F4eM" \
                      "ppaqk4Yd8POY1lMTNcgMnpvB44Hrt8s=")
    end

    it "encrypts each parameter with key1 and the envelope with key2" do
      v = described_class.encode_params({ issueData: { "type" => "I" }, invoiceNumber: 12 },
                                        acnt: "acnt", acntp: "acntp", key1: key1, key2: key2)
      envelope = JSON.parse(described_class.decrypt(v, key2))

      expect(envelope.slice("acnt", "acntp")).to eq("acnt" => "acnt", "acntp" => "acntp")
      expect(described_class.decrypt(envelope["issueData"], key1)).to eq(%({"type":"I"}))
      expect(described_class.decrypt(envelope["invoiceNumber"], key1)).to eq("12")
    end
  end

  describe ".decrypt_message" do
    it "parses the decrypted JSON" do
      message = described_class.encrypt(%({"issueStatus":"Y"}), key1)

      expect(described_class.decrypt_message(message, key1)).to eq("issueStatus" => "Y")
    end

    it "raises ProviderError when the text is not JSON" do
      message = described_class.encrypt("not json", key1)

      expect { described_class.decrypt_message(message, key1) }
        .to raise_error(Einvoice::ProviderError, /malformed JSON/)
    end

    it "keeps an Array, which some raw endpoints answer" do
      expect(described_class.decrypt_message(described_class.encrypt("[1]", key1), key1)).to eq([1])
    end

    it "raises ProviderError for a message that is not an object or an array" do
      %w[null 1 "text"].each do |text|
        expect { described_class.decrypt_message(described_class.encrypt(text, key1), key1) }
          .to raise_error(Einvoice::ProviderError, /not a JSON object or array/)
      end
    end
  end
end
