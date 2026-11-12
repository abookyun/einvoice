# frozen_string_literal: true

require "json"
require "uri"

# An in-process stand-in for ezPay's e-invoice API, built from
# docs/providers/ezpay/invoice.md only: the MerchantID_ / PostData_ form, the
# AES-256 hex payload, the Status / Message / Result answer with Result as a
# JSON string, and the CheckCode. It keeps invoice and allowance state, so the
# shared contract can drive issue → allowance → void as a sequence.
#
# Nothing here was captured from ezPay. Where the note gives no code (an
# allowance on a voided invoice, an unknown allowance), the fake answers with
# the same guesses as Einvoice::EzPay::Errors::CONTEXT. The real API refuses a
# void until the next day's upload (LIB10009). This fake voids at once.
class FakeEzPay
  BASE_URL = "https://ezpay.test"
  HASH_KEY = "abcdefghijklmnopqrstuvwxyz012345"
  HASH_IV = "0123456789abcdef"
  CREDENTIALS = { merchant_id: "3502275", hash_key: HASH_KEY, hash_iv: HASH_IV, base_url: BASE_URL }.freeze

  Crypto = Einvoice::EzPay::Crypto
  VERSIONS = { "/Api/invoice_issue" => "1.5", "/Api/invoice_invalid" => "1.0", "/Api/allowance_issue" => "1.3",
               "/Api/allowanceInvalid" => "1.0", "/Api/invoice_search" => "1.3" }.freeze

  attr_reader :requests

  def initialize
    @invoices = {}
    @allowances = {}
    @sequence = 0
    @requests = []
  end

  def install!
    WebMock.stub_request(:post, %r{\A#{Regexp.escape(BASE_URL)}/Api/}).to_return { |request| handle(request) }
    self
  end

  # The decrypted fields of the nth request.
  def fields(index = -1)
    @requests[index][:fields]
  end

  def path(index = -1)
    @requests[index][:path]
  end

  def invoice(number)
    @invoices[number]
  end

  private

  def handle(request)
    form = URI.decode_www_form(request.body.to_s).to_h
    return reply("KEY10010", "商店代號空白") if form["MerchantID_"].to_s.empty?
    return reply("KEY10011", "PostData_ 空白") if form["PostData_"].to_s.empty?

    fields = Crypto.parse_query(Crypto.decrypt(form["PostData_"], HASH_KEY, HASH_IV))
    path = URI(request.uri.to_s).path
    @requests << { path: path, fields: fields }
    return reply("KEY10004", "Version 錯誤") unless fields["Version"] == VERSIONS[path]
    return reply("KEY10004", "RespondType 錯誤") unless fields["RespondType"] == "JSON"
    return reply("KEY10007", "頁面停留超過 30 分鐘") if (Time.now.to_i - fields["TimeStamp"].to_i).abs > 1800

    dispatch(path, fields)
  rescue OpenSSL::Cipher::CipherError, ArgumentError
    reply("KEY10002", "資料解密錯誤")
  end

  def dispatch(path, fields)
    case path
    when "/Api/invoice_issue" then issue(fields)
    when "/Api/invoice_invalid" then void(fields)
    when "/Api/allowance_issue" then allowance(fields)
    when "/Api/allowanceInvalid" then void_allowance(fields)
    when "/Api/invoice_search" then search(fields)
    else reply("KEY10004", "unknown path #{path}")
    end
  end

  # --- invoice_issue -------------------------------------------------------------

  def issue(fields)
    return reply("LIB10003", "商店訂單編號重複") if @invoices.values.any? { |i| i["MerchantOrderNo"] == fields["MerchantOrderNo"] }
    return reply("INV10004", "商品資料錯誤") unless items_add_up?(fields)
    return reply("KEY10015", "發票金額格式錯誤") unless fields["TotalAmt"].to_i == fields["Amt"].to_i + fields["TaxAmt"].to_i

    @sequence += 1
    now = Time.now.getlocal("+08:00")
    invoice = {
      "MerchantID" => CREDENTIALS[:merchant_id], "InvoiceTransNo" => format("%017d", 15_110_317_583_641_325 + @sequence),
      "MerchantOrderNo" => fields["MerchantOrderNo"], "InvoiceNumber" => format("DS%08d", 12_223_139 + @sequence),
      "RandomNum" => format("%04d", (@sequence * 4253) % 10_000), "TotalAmt" => fields["TotalAmt"].to_i,
      "CreateTime" => now.strftime("%Y-%m-%d %H:%M:%S"), "fields" => fields, "status" => "1", "remain" => fields["TotalAmt"].to_i
    }
    @invoices[invoice["InvoiceNumber"]] = invoice
    result = invoice.slice("MerchantID", "MerchantOrderNo", "InvoiceNumber", "TotalAmt", "InvoiceTransNo", "RandomNum",
                           "CreateTime")
    reply("SUCCESS", "電子發票開立成功", with_check_code(result))
  end

  # --- invoice_invalid -----------------------------------------------------------

  def void(fields)
    invoice = @invoices[fields["InvoiceNumber"]]
    return reply("INV20006", "查無發票資料") unless invoice
    return reply("LIB10005", "發票已作廢") if invoice["status"] == "2"
    return reply("LIB10007", "發票已有折讓，無法作廢") if live_allowance?(invoice)
    return reply("INV70001", "作廢原因格式錯誤") if fields["InvalidReason"].to_s.empty?

    invoice["status"] = "2"
    reply("SUCCESS", "作廢成功", "MerchantID" => CREDENTIALS[:merchant_id], "InvoiceNumber" => invoice["InvoiceNumber"],
                                 "CreateTime" => Time.now.strftime("%Y-%m-%d %H:%M:%S"), "CheckCode" => "")
  end

  # --- allowance_issue -----------------------------------------------------------

  def allowance(fields)
    invoice = @invoices[fields["InvoiceNo"]]
    return reply("INV20006", "查無發票資料") unless invoice
    return reply("LIB10005", "發票已作廢") if invoice["status"] == "2"
    return reply("INV10013", "商店訂單編號不符") unless invoice["MerchantOrderNo"] == fields["MerchantOrderNo"]
    return reply("INV10004", "商品資料錯誤") unless items_add_up?(fields)

    items = fields["ItemAmt"].split("|").map(&:to_i)
    taxes = fields["ItemTaxAmt"].to_s.split("|").map(&:to_i)
    return reply("INV10004", "ItemTaxAmt 與品項數不符") unless taxes.size == items.size
    return reply("KEY10015", "折讓金額錯誤") unless fields["TotalAmt"].to_i == items.sum + taxes.sum
    return reply("INV10013", "折讓金額超過發票剩餘金額") if fields["TotalAmt"].to_i > invoice["remain"]

    invoice["remain"] -= fields["TotalAmt"].to_i
    number = format("A%015d", 151_015_111_705_000 + @allowances.size + 1)
    @allowances[number] = { "invoice" => invoice["InvoiceNumber"], "amount" => fields["TotalAmt"].to_i, "voided" => false }
    reply("SUCCESS", "折讓開立成功",
          "MerchantID" => CREDENTIALS[:merchant_id], "AllowanceNo" => number, "InvoiceNumber" => invoice["InvoiceNumber"],
          "MerchantOrderNo" => invoice["MerchantOrderNo"], "AllowanceAmt" => fields["TotalAmt"],
          "RemainAmt" => invoice["remain"].to_s, "CheckCode" => "")
  end

  # --- allowanceInvalid ----------------------------------------------------------

  def void_allowance(fields)
    allowance = @allowances[fields["AllowanceNo"]]
    return reply("IAI10002", "查詢失敗") unless allowance
    # The manual has no code for this. Assumed to be the code of a voided
    # invoice (docs, section 7).
    return reply("LIB10005", "折讓已作廢") if allowance["voided"]

    allowance["voided"] = true
    @invoices[allowance["invoice"]]["remain"] += allowance["amount"]
    reply("SUCCESS", "折讓作廢成功", "AllowanceNo" => fields["AllowanceNo"],
                                     "CreateTime" => Time.now.strftime("%Y-%m-%d %H:%M:%S"), "CheckCode" => "")
  end

  # --- invoice_search ------------------------------------------------------------

  def search(fields)
    invoice = case fields["SearchType"]
              when "1"
                @invoices.values.find do |i|
                  i["MerchantOrderNo"] == fields["MerchantOrderNo"] && i["TotalAmt"] == fields["TotalAmt"].to_i
                end
              else
                found = @invoices[fields["InvoiceNumber"]]
                found if found && found["RandomNum"] == fields["RandomNum"]
              end
    return reply("INV20006", "查無發票資料") unless invoice

    reply("SUCCESS", "查詢成功", with_check_code(search_result(invoice)))
  end

  def search_result(invoice)
    fields = invoice["fields"]
    names = fields["ItemName"].split("|")
    counts = fields["ItemCount"].split("|")
    units = fields["ItemUnit"].split("|")
    prices = fields["ItemPrice"].split("|")
    amounts = fields["ItemAmt"].split("|")
    types = fields["ItemTaxType"].to_s.split("|")
    items = names.each_index.map do |i|
      { "ItemNum" => "", "ItemName" => names[i], "ItemCount" => counts[i].to_i, "ItemWord" => units[i],
        "ItemPrice" => prices[i].to_i, "ItemAmount" => amounts[i].to_i, "ItemTaxType" => types[i].to_s }
    end
    invoice.slice("MerchantID", "InvoiceTransNo", "MerchantOrderNo", "InvoiceNumber", "RandomNum", "TotalAmt",
                  "CreateTime").merge(
                    "BuyerName" => fields["BuyerName"], "BuyerUBN" => fields["BuyerUBN"],
                    "BuyerAddress" => fields["BuyerAddress"], "BuyerPhone" => "", "BuyerEmail" => fields["BuyerEmail"],
                    "Category" => fields["Category"], "TaxType" => fields["TaxType"], "TaxRate" => "0.05000",
                    "Amt" => fields["Amt"], "TaxAmt" => fields["TaxAmt"], "TotalAmt" => fields["TotalAmt"],
                    "CarrierType" => fields["CarrierType"], "CarrierNum" => Crypto.urldecode(fields["CarrierNum"]),
                    "LoveCode" => fields["LoveCode"], "PrintFlag" => fields["PrintFlag"],
                    "ItemDetail" => JSON.generate(items), "InvoiceStatus" => invoice["status"], "UploadStatus" => "0"
                  )
  end

  # --- helpers -------------------------------------------------------------------

  # The only item check ezPay documents: ItemAmt = ItemCount × ItemPrice.
  def items_add_up?(fields)
    counts = fields["ItemCount"].to_s.split("|")
    prices = fields["ItemPrice"].to_s.split("|")
    amounts = fields["ItemAmt"].to_s.split("|")
    sizes = [fields["ItemName"].to_s.split("|"), counts, fields["ItemUnit"].to_s.split("|"), prices, amounts].map(&:size)
    return false unless sizes.uniq.size == 1 && sizes.first.positive?

    counts.zip(prices, amounts).all? { |count, price, amount| count.to_i * price.to_i == amount.to_i }
  end

  def live_allowance?(invoice)
    @allowances.values.any? { |a| a["invoice"] == invoice["InvoiceNumber"] && !a["voided"] }
  end

  def with_check_code(result)
    result.merge("CheckCode" => Crypto.check_code(result, HASH_KEY, HASH_IV))
  end

  def reply(status, message, result = nil)
    body = { "Status" => status, "Message" => message, "Result" => result ? JSON.generate(result) : "" }
    { status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(body) }
  end
end
