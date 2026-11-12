# frozen_string_literal: true

require "json"
require "uri"

# An in-process stand-in for Tradevan's DEFAULTAPI that speaks the wire
# protocol the 1.x client used in production: the +v+ query parameter, the two
# keys, NUL padding, and the +Success+ / +Message+ envelope. It keeps invoice
# and allowance state, so the shared contract can drive issue → allowance →
# void as a sequence.
#
# Unlike FakeECPay, nothing here was captured from the live API. The response
# shapes follow the 1.x README examples (2016). The failure texts are guesses,
# the same ones Einvoice::Tradevan::DefaultAPI::Errors matches. So a passing
# contract proves the adapter is consistent with those guesses, not that
# Tradevan agrees.
#
# The two keys differ on purpose. The 1.x specs used one value for both, so they
# could not catch a request or a response read with the wrong key.
class FakeTradevan
  BASE_URL = "https://tradevan.test"
  KEY1 = "0123456789abcdef"
  KEY2 = "fedcba9876543210"

  CREDENTIALS = {
    acnt: "acnt", acntp: "acntp", key1: KEY1, key2: KEY2, base_url: BASE_URL,
    company_un: "12345678", org_id: "ABCDE", paper_print_mode: "0", invoice_alarm_mode: "4",
    invoice_paper_returned: "N", allowance_paper_returned: "N", member_carrier_type: "1K0001"
  }.freeze

  Crypto = Einvoice::Tradevan::DefaultAPI::Crypto
  Rules = Einvoice::Tradevan::DefaultAPI::Rules

  attr_reader :requests

  def initialize
    @invoices = {}
    @allowances = {}
    @sequence = 0
    @requests = []
  end

  def install!
    WebMock.stub_request(:any, %r{\A#{Regexp.escape(BASE_URL)}/DEFAULTAPI/})
           .to_return { |request| handle(request) }
    self
  end

  # The decrypted parameters of the nth request.
  def params(index = -1)
    @requests[index][:params]
  end

  def path(index = -1)
    @requests[index][:path]
  end

  def http_method(index = -1)
    @requests[index][:method]
  end

  private

  def handle(request)
    uri = URI(request.uri.to_s)
    v = URI.decode_www_form(uri.query.to_s).to_h["v"]
    envelope = JSON.parse(Crypto.decrypt(v, KEY2))
    unless envelope["acnt"] == CREDENTIALS[:acnt] && envelope["acntp"] == CREDENTIALS[:acntp]
      return transport("帳號或密碼錯誤")
    end

    params = envelope.except("acnt", "acntp").transform_values { |value| Crypto.decrypt(value, KEY1) }
    path = uri.path.delete_prefix("/DEFAULTAPI/")
    @requests << { path: path, method: request.method, params: params }
    dispatch(path, request.method, params)
  rescue Einvoice::Error, JSON::ParserError
    transport("解密失敗")
  end

  def dispatch(path, method, params)
    expected = path.start_with?("post/") ? :post : :get
    return transport("HTTP method not allowed") unless method == expected

    case path
    when "post/issue" then issue(JSON.parse(params["issueData"]))
    when "post/cancel" then cancel(JSON.parse(params["voidData"]))
    when "get/searchInvoiceDetail" then search_invoice_detail(params["invoiceNumber"])
    else transport("unknown path #{path}")
    end
  end

  # --- post/issue --------------------------------------------------------------

  def issue(data)
    unknown = unknown_keys(data, Rules::ISSUE_FIELDS) +
              Array(data["itemList"]).flat_map { |item| unknown_keys(item, Rules::ITEM_FIELDS) }
    return failure("issueStatus", "unknown field: #{unknown.join(', ')}") if unknown.any?

    case data["type"]
    when "I" then issue_invoice(data)
    when "A" then issue_allowance(data)
    else failure("issueStatus", "type #{data['type']} not supported by the fake")
    end
  end

  def issue_invoice(data)
    sale = data["saleIdentifier"]
    return failure("issueStatus", "duplicated") if @invoices.values.any? { |i| i["sale"] == sale }

    @sequence += 1
    number = format("GX%08d", 38_551_000 + @sequence)
    total = data["total"].to_i
    exclusive = (total / 1.05).round
    @invoices[number] = {
      "number" => number, "sale" => sale, "data" => data, "date" => today, "time" => clock,
      "check" => format("%04d", (@sequence * 4229) % 10_000), "total" => total,
      "remaining" => total, "voided" => false
    }
    success(
      "saleIdentifier" => sale, "issueStatus" => "Y", "failReason" => "",
      "invoiceNumber" => number, "checkNumber" => @invoices[number]["check"],
      "invoiceDate" => today, "invoiceTime" => clock,
      "texclusiveAmount" => exclusive.to_s, "oexclusiveAmount" => "0", "zexclusiveAmount" => "0",
      "tax" => (total - exclusive).to_s, "inclusiveAmount" => total.to_s,
      "mainRemark" => "", "invoiceType" => "", "invoiceStatus" => "V",
      "allowanceNumber" => "", "allowanceDate" => "", "allowanceExclusiveAmount" => "",
      "allowanceTax" => "", "allowanceTotalAmount" => "0", "allowanceStatus" => ""
    )
  end

  def issue_allowance(data)
    item = data["itemList"].first
    invoice = @invoices[item["invoiceNumber"]]
    return failure("issueStatus", "查無發票資料") unless invoice
    return failure("issueStatus", "發票已作廢，不能折讓") if invoice["voided"]
    return failure("issueStatus", "saleIdentifier 不符") unless item["saleIdentifier"] == invoice["sale"]
    return failure("issueStatus", "發票日期不符") unless item["invoiceDate"] == invoice["date"]

    amount = data["allowanceInclusiveAmount"].to_i
    return failure("issueStatus", "折讓金額超過發票餘額") if amount > invoice["remaining"]

    @sequence += 1
    number = format("%s%s%03d", CREDENTIALS[:org_id], today, @sequence)
    invoice["remaining"] -= amount
    @allowances[number] = { "invoice" => invoice["number"], "amount" => amount, "voided" => false }
    success("allowanceIdentifier" => data["allowanceIdentifier"], "issueStatus" => "Y",
            "failReason" => "", "invoiceNumber" => invoice["number"],
            "allowanceNumber" => number, "allowanceDate" => today,
            "allowanceExclusiveAmount" => data["allowanceExclusiveAmount"],
            "allowanceTax" => data["allowanceTax"], "allowanceTotalAmount" => amount.to_s)
  end

  # --- post/cancel -------------------------------------------------------------

  def cancel(data)
    unknown = unknown_keys(data, Rules::VOID_FIELDS)
    return failure("voidStatus", "unknown field: #{unknown.join(', ')}") if unknown.any?

    data["type"] == "A" ? cancel_allowance(data) : cancel_invoice(data)
  end

  def cancel_invoice(data)
    invoice = @invoices[data["invoiceNumber"]]
    return failure("voidStatus", "查無發票資料") unless invoice
    return failure("voidStatus", "saleIdentifier 不符") unless data["saleIdentifier"] == invoice["sale"]
    return failure("voidStatus", "發票已作廢") if invoice["voided"]
    return failure("voidStatus", "發票已折讓，不能作廢") if invoice["remaining"] < invoice["total"]

    invoice["voided"] = true
    success("saleIdentifier" => invoice["sale"], "voidStatus" => "Y", "failReason" => "",
            "type" => "I", "invoiceNumber" => invoice["number"], "allowanceNumber" => "")
  end

  def cancel_allowance(data)
    record = @allowances[data["allowanceNumber"]]
    return failure("voidStatus", "查無折讓單資料") unless record
    return failure("voidStatus", "折讓單已作廢") if record["voided"]

    record["voided"] = true
    @invoices[record["invoice"]]["remaining"] += record["amount"]
    success("voidStatus" => "Y", "failReason" => "", "type" => "A",
            "invoiceNumber" => record["invoice"], "allowanceNumber" => data["allowanceNumber"])
  end

  # --- get/searchInvoiceDetail -------------------------------------------------

  def search_invoice_detail(number)
    invoice = @invoices[number]
    return failure(nil, "查無發票資料") unless invoice

    data = invoice["data"]
    total = invoice["total"]
    exclusive = (total / 1.05).round
    success(
      "saleIdentifier" => invoice["sale"], "invoiceNumber" => invoice["number"],
      "checkNumber" => invoice["check"], "invoiceDate" => invoice["date"],
      "invoiceTime" => invoice["time"], "exclusiveAmount" => exclusive.to_s,
      "tax" => (total - exclusive).to_s, "total" => total.to_s,
      "status" => invoice["voided"] ? "V" : "I",
      "hasAllowance" => invoice["remaining"] < total ? "Y" : "N",
      "receiverName" => data["receiverName"].to_s, "receiverAddr" => data["receiverAddrRoad"].to_s,
      "receiverPhone" => data["receiverMobile"].to_s, "paper" => "N", "win" => "N",
      "donate" => data["donate"].to_s, "carrierType" => data["carrierType"].to_s,
      "detailList" => Array(data["itemList"]).map do |item|
        item.slice("saleIdentifier", "serialNumber", "productName", "qty", "price", "taxType")
            .merge("total" => item["itemTotal"])
      end
    )
  end

  # --- envelope ----------------------------------------------------------------

  def unknown_keys(hash, allowed)
    hash.is_a?(Hash) ? hash.keys - allowed : []
  end

  def success(message)
    envelope("Success" => "Y", "Message" => Crypto.encrypt(JSON.generate(message), KEY1))
  end

  def failure(status_field, reason)
    message = { "failReason" => reason }
    message[status_field] = "N" if status_field
    envelope("Success" => "N", "Message" => Crypto.encrypt(JSON.generate(message), KEY1))
  end

  def transport(text)
    envelope("Success" => "E", "Message" => text)
  end

  def envelope(body)
    { status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(body) }
  end

  def today
    Time.now.getlocal("+08:00").strftime("%Y%m%d")
  end

  def clock
    Time.now.getlocal("+08:00").strftime("%H:%M:%S")
  end
end
