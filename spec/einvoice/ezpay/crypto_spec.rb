# frozen_string_literal: true

# The rules from docs/providers/ezpay/invoice.md sections 2.2 and 2.4, and the
# two test vectors from the manual (EZP_INVI 1.2.2, 附件一 and 附件二).
RSpec.describe Einvoice::EzPay::Crypto do
  let(:key) { "abcdefghijklmnopqrstuvwxyz012345" }
  let(:iv) { "0123456789abcdef" }

  # The manual's 附件一 sample: the fields of a B2B issue, the key and IV, and
  # the PostData_ that ezPay's PHP sample prints for them.
  describe "the manual's encryption sample" do
    let(:manual_key) { "abcdefghijklmnopqrstuvwxyzabcdef" }
    let(:manual_iv) { "1234567891234567" }
    let(:fields) do
      { "RespondType" => "JSON", "Version" => "1.4", "TimeStamp" => "1444963784", "TransNum" => "",
        "MerchantOrderNo" => "201409170000001", "BuyerName" => "王大品", "BuyerUBN" => "54352706",
        "BuyerAddress" => "台北市南港區南港路二段97號8樓", "BuyerEmail" => "54352706@pay2go.com",
        "Category" => "B2B", "TaxType" => "1", "TaxRate" => "5", "Amt" => "490", "TaxAmt" => "10",
        "TotalAmt" => "500", "CarrierType" => "", "CarrierNum" => described_class.rawurlencode(""),
        "LoveCode" => "", "PrintFlag" => "Y", "ItemName" => "商品一|商品二", "ItemCount" => "1|2",
        "ItemUnit" => "個|個", "ItemPrice" => "300|100", "ItemAmt" => "300|200", "Comment" => "備註",
        "CreateStatusTime" => "", "Status" => "1" }
    end
    let(:post_data) do
      <<~HEX.delete("\n")
      70a61189d7dc0f6abefe7643da144af543470ddf87b1de14ae20cf104f730dee3f872d15ec141795895ca901e04b59bd
      691657557d884265e2c817b8db15b5563c846c88d228bec7d4c9aa57b9d3e5e22c73573e1dc4393c0057185920920fcf
      17438ec94c82de1b109594283c3df21dfc2e3d10a7748d5c9e2f0272e6ff34df191bb517a973671833c52dd4a67b27a1
      66f371488a3adc973f0277020dd528353ae88ae1dda9f88f0474f48e452d5a2e68f41e5c8033937dbb72607003610095
      b7c0717250e4c8c3611f699fceaa6fd88a687cc7b3ac5edff3a3a11ac7d040755c7f8c1725011645ea139ceb355e309b
      4bee95a8c37cf9b2f2027b1b7943bc5a946f5879416b2ddf45dd2f4163fe3d995bd189f3053a391463565d3f1e284056
      c21d031554f7d28ed2d674ff62c24b0e93943e20ddd6bf79e6d519fc03c590a70f40b2d559ced5a8cd0c1de0d4154112
      c2fe881c2f352369c23ef2a68cdeacea72d38c4349484793a93dbbf66078ac533a868cb7378c61c47b79a6c756a3aa48
      45006f97bb97ab43a43e17d512c65d2681ed5dd00ef4e0fe76c50f4c093452ee32bc34dadf31cb1d3c562d8d2149506a
      aa4f2d764ea8e189635aa61863155bec033a5fbeba58a463f1f3fc29184fbb85012f339fb57fe96a513ea64cb5b96b79
      89a2ede6a6a9c164bd170652f433688b435e8dcf5246890f2fb9a38fbfe67ed92150d939a690cacb5f3618a7e1234bef
      ad329e69e56da113cc2889e8ecc2bee9cd4c31eeb44f35817f4b2580510cf6b24189df119f07f8f6940e5cd24c23d3bc
      350975a20a51cd8e8a26254cb25a805929b84bc1bf16143ed4fb6c3875607ba7089889e24ab662469997cec4cb7f6cd1
      502eded8cd9ab50380305b71e1fa57c4
      HEX
    end

    it "builds the same query string and encrypts it to the same PostData_" do
      query = described_class.build_query(fields)
      expect(query.bytesize).to eq(631) # the manual: "補足 9 個 0x09" to reach 640
      expect(described_class.encrypt(query, manual_key, manual_iv)).to eq(post_data)
      expect(described_class.decrypt(post_data, manual_key, manual_iv)).to eq(query)
    end
  end

  describe ".encrypt / .decrypt" do
    it "pads with PKCS#7 to 32 bytes, encrypts with AES-256-CBC, and writes lower-case hex" do
      hex = described_class.encrypt("RespondType=JSON", key, iv)
      expect(hex).to match(/\A[0-9a-f]{64}\z/)

      cipher = OpenSSL::Cipher.new("aes-256-cbc").decrypt
      cipher.key = key
      cipher.iv = iv
      cipher.padding = 0
      plain = cipher.update([hex].pack("H*")) + cipher.final
      expect(plain).to eq("RespondType=JSON#{16.chr * 16}")
    end

    it "adds a full block when the text is already a multiple of 32 bytes" do
      expect(described_class.encrypt("x" * 32, key, iv).length).to eq(128)
    end

    it "round-trips UTF-8" do
      text = "BuyerName=%E6%B6%88%E8%B2%BB%E8%80%85&ItemName=商品"
      expect(described_class.decrypt(described_class.encrypt(text, key, iv), key, iv)).to eq(text)
    end

    it "refuses bad padding" do
      cipher = OpenSSL::Cipher.new("aes-256-cbc").encrypt
      cipher.key = key
      cipher.iv = iv
      cipher.padding = 0
      hex = (cipher.update("y" * 31 + 0.chr) + cipher.final).unpack1("H*")
      expect { described_class.decrypt(hex, key, iv) }.to raise_error(ArgumentError, /padding/)
    end
  end

  describe "URL encoding" do
    it "builds the query string as PHP http_build_query does" do
      expect(described_class.build_query({ "A" => "消費 者", "B" => "/x~*" }))
        .to eq("A=%E6%B6%88%E8%B2%BB+%E8%80%85&B=%2Fx%7E%2A")
    end

    it "rawurlencodes as PHP does: %20 for a space, ~ kept" do
      expect(described_class.rawurlencode("/AB C~")).to eq("%2FAB%20C~")
    end

    it "reads a query string back" do
      expect(described_class.parse_query("A=%E6%B6%88+%E8%B2%BB&B=")).to eq("A" => "消 費", "B" => "")
    end
  end

  describe ".check_code" do
    it "matches the manual's 附件二 sample" do
      result = { "MerchantID" => "3622183", "MerchantOrderNo" => "201409170000001",
                 "InvoiceTransNo" => "14061313541640927", "TotalAmt" => "500", "RandomNum" => "0142" }
      expect(described_class.check_code(result, "abcdefghijklmnopqrstuvwxyzabcdef", "1234567891234567"))
        .to eq("303AB800650B724733B5D91CBCE075D9EA09E4CDE9CD33461D45F07D5EC7EECB")
    end

    it "hashes the five sorted fields between HashIV and HashKey, upper case" do
      result = { "TotalAmt" => 348, "RandomNum" => "4253", "MerchantOrderNo" => "O1", "MerchantID" => "3502275",
                 "InvoiceTransNo" => "15110317583641325", "InvoiceNumber" => "DS12223139" }
      raw = "HashIV=#{iv}&InvoiceTransNo=15110317583641325&MerchantID=3502275&MerchantOrderNo=O1" \
            "&RandomNum=4253&TotalAmt=348&HashKey=#{key}"
      expect(described_class.check_code(result, key, iv)).to eq(Digest::SHA256.hexdigest(raw).upcase)
    end
  end
end
