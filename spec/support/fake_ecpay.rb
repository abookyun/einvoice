# frozen_string_literal: true

require "json"

# An in-process stand-in for ECPay's B2C API that speaks the real wire protocol:
# it decrypts the AES envelope, keeps invoice/allowance state, and answers with
# the same two-layer envelope and the same RtnCodes the stage API returns.
#
# That makes it a contract test rather than a mock — a request only succeeds if
# the adapter's encryption, PHP url-encoding, envelope and field mapping are all
# correct, and every error path is driven by a real ECPay code. The codes and
# messages below were captured from the live stage API on 2026-08-15; the live
# spec re-checks them against the real thing.
class FakeECPay
  BASE_URL = "https://ecpay.test"
  MERCHANT_ID = "2000132"
  HASH_KEY = "ejCk326UnaZWKisg"
  HASH_IV = "q9jcZX8Ib9LM8wYk"

  # How far the envelope timestamp may drift before ECPay rejects it.
  MAX_CLOCK_SKEW = 600

  attr_reader :requests

  def initialize
    @invoices = {}
    @by_relate = {}
    @allowances = {}
    @sequence = 0
    @requests = []
  end

  # Register the stub. Returns self so specs can keep inspecting state.
  def install!
    WebMock.stub_request(:post, %r{\A#{Regexp.escape(BASE_URL)}/B2CInvoice/})
           .to_return { |request| handle(request) }
    self
  end

  # The decrypted Data payload of the nth request the adapter sent.
  def payload(index = -1)
    @requests[index][:data]
  end

  def path(index = -1)
    @requests[index][:path]
  end

  private

  def handle(request)
    envelope = JSON.parse(request.body)
    data = decrypt(envelope["Data"])
    return transport(110, "The parameter [Data] decrypt fail.") if data.nil?

    timestamp = envelope.dig("RqHeader", "Timestamp").to_i
    if (Time.now.to_i - timestamp).abs > MAX_CLOCK_SKEW
      return transport(104, "Timestamp is over 10 minutes than it just produced.")
    end

    path = URI(request.uri.to_s).path
    @requests << { path: path, data: data, envelope: envelope }
    dispatch(path, data)
  end

  def dispatch(path, data)
    case path
    when "/B2CInvoice/Issue" then issue(data)
    when "/B2CInvoice/GetIssue" then get_issue(data)
    when "/B2CInvoice/Invalid" then invalid(data)
    when "/B2CInvoice/Allowance" then allowance(data)
    when "/B2CInvoice/AllowanceInvalid" then allowance_invalid(data)
    when "/B2CInvoice/CheckBarcode" then check_barcode(data)
    when "/B2CInvoice/CheckLoveCode" then check_love_code(data)
    else business(9_999_999, "未支援的測試端點: #{path}")
    end
  end

  # --- operations ------------------------------------------------------------

  def issue(data)
    relate = data["RelateNumber"].to_s
    if @by_relate.key?(relate)
      return business(5_070_357, "B2C開立發票 自訂編號重覆，請重新設定",
                      "InvoiceNo" => "", "InvoiceDate" => "", "RandomNumber" => "")
    end

    @sequence += 1
    number = format("LA%08d", 25_000_000 + @sequence)
    issued_at = now
    @invoices[number] = {
      "number" => number, "relate" => relate, "data" => data, "issued_at" => issued_at,
      "random" => format("%04d", (@sequence * 1327) % 10_000),
      "sales" => data["SalesAmount"].to_i, "remaining" => data["SalesAmount"].to_i,
      "voided" => false
    }
    @by_relate[relate] = number
    success("開立發票成功", "InvoiceNo" => number, "InvoiceDate" => issued_at,
                            "RandomNumber" => @invoices[number]["random"])
  end

  def get_issue(data)
    invoice = lookup(data)
    return business(2, "查無發票資料，請重新確認") unless invoice

    stored = invoice["data"]
    success("查詢成功",
            "IIS_Number" => invoice["number"],
            "IIS_Relate_Number" => invoice["relate"],
            "IIS_Identifier" => presence(stored["CustomerIdentifier"], "0000000000"),
            "IIS_Customer_Name" => stored["CustomerName"].to_s,
            "IIS_Customer_Addr" => stored["CustomerAddr"].to_s,
            "IIS_Customer_Phone" => stored["CustomerPhone"].to_s,
            "IIS_Customer_Email" => stored["CustomerEmail"].to_s,
            "IIS_Category" => stored["CustomerIdentifier"].to_s.empty? ? "B2C" : "B2B",
            "IIS_Tax_Type" => stored["TaxType"],
            "IIS_Tax_Amount" => 0,
            "IIS_Sales_Amount" => invoice["sales"],
            "IIS_Create_Date" => invoice["issued_at"],
            "IIS_Random_Number" => invoice["random"],
            "IIS_Invalid_Status" => invoice["voided"] ? "1" : "0",
            "IIS_Remain_Allowance_Amt" => invoice["remaining"],
            "Items" => Array(stored["Items"]).map { |item| queried_item(item) })
  end

  def invalid(data)
    invoice = @invoices[data["InvoiceNo"].to_s]
    return business(1_600_003, "無發票號碼資料") unless invoice
    if invoice["voided"]
      return business(5_070_453, "B2C作廢發票 該發票已被作廢過",
                      "InvoiceNo" => invoice["number"])
    end
    if invoice["remaining"] < invoice["sales"]
      return business(5_070_450,
                      "B2C作廢發票 該發票已被折讓過，無法直接作廢發票並請確認該發票所開立的折讓單是否全部已作廢",
                      "InvoiceNo" => invoice["number"])
    end

    invoice["voided"] = true
    success("作廢發票成功", "InvoiceNo" => invoice["number"])
  end

  def allowance(data)
    invoice = @invoices[data["InvoiceNo"].to_s]
    return business(1_600_003, "無發票號碼資料") unless invoice

    amount = data["AllowanceAmount"].to_i
    if amount <= 0 || amount > invoice["remaining"]
      return business(2_000_016, "折讓金額有誤，請確認")
    end

    @sequence += 1
    number = format("%s%04d", Time.now.strftime("%Y%m%d%H%M"), @sequence)
    invoice["remaining"] -= amount
    @allowances[number] = { "invoice" => invoice["number"], "amount" => amount, "voided" => false }
    success("折讓單資料新增成功",
            "IA_Allow_No" => number, "IA_Invoice_No" => invoice["number"],
            "IA_Date" => now, "IA_Remain_Allowance_Amt" => invoice["remaining"])
  end

  def allowance_invalid(data)
    record = @allowances[data["AllowanceNo"].to_s]
    return business(2_000_039, "查無折讓單資料，請確認!") unless record
    return business(2_000_063, "該折讓單已作廢過，請確認") if record["voided"]

    record["voided"] = true
    @invoices[record["invoice"]]["remaining"] += record["amount"]
    # The live API really does answer a successful void with this wording — proof
    # that message matching must only ever run on a failing RtnCode.
    success("該折讓單已作廢", "IA_Invoice_No" => record["invoice"])
  end

  def check_barcode(data)
    success("", "IsExist" => data["BarCode"] == "/ABC1234" ? "Y" : "N")
  end

  def check_love_code(data)
    return success("", "IsExist" => "N") unless data["LoveCode"].to_s == "168001"

    success("成功取得查詢結果", "IsExist" => "Y", "OrganName" => "財團法人ＯＭＧ關懷社會愛心基金會")
  end

  # --- helpers ---------------------------------------------------------------

  # GetIssue takes either 自訂編號, or 發票號碼 paired with its issue date.
  def lookup(data)
    relate = data["RelateNumber"].to_s
    return @invoices[@by_relate[relate]] unless relate.empty?

    invoice = @invoices[data["InvoiceNo"].to_s]
    return nil unless invoice

    date = data["InvoiceDate"].to_s
    date.empty? || invoice["issued_at"].start_with?(date) ? invoice : nil
  end

  def queried_item(item)
    {
      "ItemName" => item["ItemName"], "ItemCount" => item["ItemCount"].to_f,
      "ItemWord" => item["ItemWord"], "ItemPrice" => item["ItemPrice"].to_f,
      "ItemTaxType" => item["ItemTaxType"], "ItemAmount" => item["ItemAmount"].to_f,
      "ItemRemark" => item["ItemRemark"]
    }
  end

  def decrypt(payload)
    Einvoice::ECPay::Crypto.decrypt_data(payload, HASH_KEY, HASH_IV)
  rescue Einvoice::Error
    nil
  end

  def presence(value, placeholder)
    value.to_s.empty? ? placeholder : value.to_s
  end

  def now
    Time.now.getlocal("+08:00").strftime("%Y-%m-%d %H:%M:%S")
  end

  def success(message, fields = {})
    business(1, message, fields)
  end

  def business(code, message, fields = {})
    encrypted = Einvoice::ECPay::Crypto.encrypt_data(
      { "RtnCode" => code, "RtnMsg" => message }.merge(fields), HASH_KEY, HASH_IV
    )
    envelope("MerchantID" => MERCHANT_ID, "TransCode" => 1, "TransMsg" => "Success",
             "Data" => encrypted)
  end

  def transport(code, message)
    envelope("MerchantID" => MERCHANT_ID, "TransCode" => code, "TransMsg" => message,
             "Data" => nil)
  end

  def envelope(body)
    { status: 200, headers: { "Content-Type" => "application/json" },
      body: JSON.generate(body) }
  end
end
