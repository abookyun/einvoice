# frozen_string_literal: true

require "json"
require "uri"
require "digest"

# An in-process stand-in for Amego's JSON API: the form envelope, the +sign+
# check, the +time+ window, and the response shapes from the docs
# (docs/providers/amego/api.md, section 2.3). It keeps invoice and allowance
# state, so the shared contract can drive issue → allowance → void as a
# sequence.
#
# The codes are Amego's documented ones. The checks on totals are our own
# reading of the docs: they catch an adapter that sends numbers that do not add
# up. The real API queues a void. This fake applies it at once.
class FakeAmego
  BASE_URL = "https://amego.test"
  CREDENTIALS = { ban: "12345678", app_key: "test-app-key", endpoint: BASE_URL }.freeze

  attr_reader :requests

  def initialize
    @invoices = {}
    @allowances = {}
    @sequence = 0
    @requests = []
  end

  def install!
    WebMock.stub_request(:post, %r{\A#{Regexp.escape(BASE_URL)}/json/}).to_return { |request| handle(request) }
    self
  end

  # The decoded +data+ of the nth request.
  def data(index = -1)
    @requests[index][:data]
  end

  def path(index = -1)
    @requests[index][:path]
  end

  def form(index = -1)
    @requests[index][:form]
  end

  def invoice(number)
    @invoices[number]
  end

  private

  def handle(request)
    form = URI.decode_www_form(request.body.to_s).to_h
    path = URI(request.uri.to_s).path
    return reply(code: 11, msg: "invoice 錯誤") unless form["invoice"] == CREDENTIALS[:ban]
    return reply(code: 15, msg: "time(時間戳記)錯誤") unless (Time.now.to_i - form["time"].to_i).abs <= 60

    expected = Digest::MD5.hexdigest("#{form['data']}#{form['time']}#{CREDENTIALS[:app_key]}")
    return reply(code: 16, msg: "sign 錯誤") unless form["sign"] == expected

    data = JSON.parse(form["data"].to_s)
    @requests << { path: path, form: form, data: data }
    dispatch(path, data)
  rescue JSON::ParserError
    reply(code: 20, msg: "data 不是 JSON")
  end

  def dispatch(path, data)
    case path
    when "/json/f0401" then issue(data)
    when "/json/f0501" then array!(data) { void(data.first) }
    when "/json/g0401" then array!(data) { allowance(data.first) }
    when "/json/g0501" then array!(data) { void_allowance(data.first) }
    when "/json/invoice_query" then query(data)
    when "/json/barcode" then barcode(data)
    else reply(code: 99, msg: "unknown path #{path}")
    end
  end

  def array!(data)
    return reply(code: 23, msg: "此 API 需傳陣列") unless data.is_a?(Array) && data.size == 1

    yield
  end

  # --- f0401 -------------------------------------------------------------------

  def issue(data)
    return reply(code: 23, msg: "此 API 需傳物件") unless data.is_a?(Hash)
    return reply(code: 3_040_171, msg: "訂單編號重複") if @invoices.values.any? { |i| i["order_id"] == data["OrderId"] }

    totals = %w[SalesAmount FreeTaxSalesAmount ZeroTaxSalesAmount TaxAmount].sum { |key| data[key].to_i }
    return reply(code: 3_040_172, msg: "總計金額錯誤") unless totals == data["TotalAmount"].to_i

    @sequence += 1
    number = format("AB%08d", 12_300_000 + @sequence)
    now = Time.now
    @invoices[number] = {
      "number" => number, "order_id" => data["OrderId"], "data" => data, "time" => now,
      "random" => format("%04d", (@sequence * 4229) % 10_000), "type" => "C0401",
      "remaining" => data["TotalAmount"].to_i
    }
    reply(code: 0, msg: "", invoice_number: number, invoice_time: now.to_i,
          random_number: @invoices[number]["random"], barcode: "", qrcode_left: "", qrcode_right: "")
  end

  # --- f0501 -------------------------------------------------------------------

  def void(entry)
    invoice = @invoices[entry["CancelInvoiceNumber"]]
    return reply(code: 3_050_125, msg: "發票不存在") unless invoice
    return reply(code: 3_050_122, msg: "發票已作廢") if invoice["type"] == "C0501"
    if @allowances.values.any? { |a| a["invoice"] == invoice["number"] && !a["voided"] }
      return reply(code: 3_050_141, msg: "發票已有折讓")
    end
    return reply(code: 3_050_113, msg: "作廢原因超過 20 字") if entry["CancelReason"].to_s.length > 20

    invoice["type"] = "C0501"
    reply(code: 0, msg: "")
  end

  # --- g0401 -------------------------------------------------------------------

  def allowance(entry)
    return reply(code: 4_040_145, msg: "折讓種類錯誤") unless entry["AllowanceType"] == "2"
    return reply(code: 4_040_161, msg: "折讓單號重複") if @allowances.key?(entry["AllowanceNumber"])

    items = Array(entry["ProductItem"])
    invoice = @invoices[items.first&.fetch("OriginalInvoiceNumber", nil)]
    return reply(code: 4_040_156, msg: "原發票不存在") unless invoice
    return reply(code: 4_040_153, msg: "原發票已作廢") if invoice["type"] == "C0501"
    return reply(code: 4_040_151, msg: "原發票日期錯誤") unless items.all? { |i| i["OriginalInvoiceDate"].to_s == ymd(invoice["time"]) }
    unless entry["BuyerIdentifier"] == invoice["data"]["BuyerIdentifier"]
      return reply(code: 4_040_157, msg: "買方統編與原發票不符")
    end
    unless items.sum { |i| i["Amount"].to_r } == entry["TotalAmount"].to_r &&
           items.sum { |i| i["Tax"].to_i } == entry["TaxAmount"].to_i
      return reply(code: 99, msg: "折讓金額加總錯誤")
    end

    credit = entry["TotalAmount"].to_i + entry["TaxAmount"].to_i
    return reply(code: 4_040_171, msg: "折讓金額超過發票金額") if credit > invoice["remaining"]

    invoice["remaining"] -= credit
    @allowances[entry["AllowanceNumber"]] = { "invoice" => invoice["number"], "credit" => credit,
                                              "date" => entry["AllowanceDate"], "voided" => false }
    reply(code: 0, msg: "")
  end

  # --- g0501 -------------------------------------------------------------------

  def void_allowance(entry)
    allowance = @allowances[entry["CancelAllowanceNumber"]]
    return reply(code: 4_050_134, msg: "折讓單不存在") unless allowance
    return reply(code: 4_050_132, msg: "折讓單已作廢") if allowance["voided"]

    allowance["voided"] = true
    @invoices[allowance["invoice"]]["remaining"] += allowance["credit"]
    reply(code: 0, msg: "")
  end

  # --- barcode -----------------------------------------------------------------

  # Every well-formed barcode is registered, except UNREGISTERED.
  UNREGISTERED = "/NOTREG0"

  def barcode(data)
    code = data["barCode"].to_s
    return reply(code: 9_000_111, msg: "手機條碼為空") if code.empty?
    return reply(code: 9_000_112, msg: "手機條碼格式錯誤") unless code.match?(%r{\A/[0-9A-Z+\-.]{7}\z})
    return reply(code: 9_000_113, msg: "手機條碼不存在") if code == UNREGISTERED

    reply(code: 0, msg: "")
  end

  # --- invoice_query -----------------------------------------------------------

  def query(data)
    invoice = case data["type"]
              when "invoice" then @invoices[data["invoice_number"]]
              when "order" then @invoices.values.find { |i| i["order_id"] == data["order_id"] }
              end
    return reply(code: 71, msg: "查無資料") unless invoice

    reply(code: 0, msg: "", data: query_data(invoice))
  end

  def query_data(invoice)
    data = invoice["data"]
    {
      "invoice_number" => invoice["number"], "invoice_type" => invoice["type"], "invoice_status" => 99,
      "invoice_date" => ymd(invoice["time"]), "invoice_time" => invoice["time"].getlocal("+08:00").strftime("%H:%M:%S"),
      "buyer_identifier" => data["BuyerIdentifier"], "buyer_name" => data["BuyerName"],
      "buyer_address" => data["BuyerAddress"], "buyer_telephone_number" => data["BuyerTelephoneNumber"],
      "buyer_email_address" => data["BuyerEmailAddress"],
      "sales_amount" => data["SalesAmount"], "free_tax_sales_amount" => data["FreeTaxSalesAmount"],
      "zero_tax_sales_amount" => data["ZeroTaxSalesAmount"], "tax_type" => data["TaxType"].to_i,
      "tax_rate" => data["TaxRate"], "tax_amount" => data["TaxAmount"], "total_amount" => data["TotalAmount"],
      "random_number" => invoice["random"], "order_id" => invoice["order_id"],
      "product_item" => data["ProductItem"].map do |item|
        { "tax_type" => item["TaxType"].to_i, "description" => item["Description"],
          "unit_price" => num(item["UnitPrice"]), "quantity" => num(item["Quantity"]),
          "unit" => item["Unit"], "amount" => num(item["Amount"]), "remark" => item["Remark"] }
      end,
      "wait" => [],
      "allowance" => @allowances.select { |_, a| a["invoice"] == invoice["number"] }.map do |number, a|
        { "invoice_type" => a["voided"] ? "D0501" : "D0401", "allowance_number" => number,
          "allowance_date" => a["date"] }
      end
    }
  end

  # Amego answers with JSON numbers.
  def num(value)
    rational = value.to_r
    rational.denominator == 1 ? rational.to_i : rational.to_f
  end

  def ymd(time)
    time.getlocal("+08:00").strftime("%Y%m%d")
  end

  def reply(**body)
    { status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(body) }
  end
end
