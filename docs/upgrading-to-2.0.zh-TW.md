# 從 1.x 升級到 2.0

[English](upgrading-to-2.0.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

1.x 是只支援一家加值中心（關貿 Tradevan）的 client。你自己組關貿的 payload，也自己讀關貿的回應。2.0 用同一套介面支援多家加值中心。你用 unified model 描述發票，由 adapter 轉換成關貿的 payload。所以 2.0 不能直接替換：每一個呼叫都要改。

這份指南寫給想繼續使用關貿的 1.x 使用者。unified model 的完整說明請見 2.0 的 README。

## 現在該升級嗎？

2.0 的關貿 adapter 是**實驗性質**。關貿只提供 API 文件給客戶，所以這個 adapter 是依據 1.x client 和它的 README 寫成的，還沒有人對 live API 執行過。

如果你在正式環境需要關貿，又沒辦法先測試這個 adapter，請留在 1.x。鎖定版本後，[`1-x-stable`](https://github.com/abookyun/einvoice/tree/1-x-stable) branch 會繼續提供 bug 和安全性修正：

```ruby
gem "einvoice", "~> 1.4"
```

如果你可以用自己的關貿帳號測試 2.0，請繼續往下讀。也請回報你測試的結果，特別是下面 `qty` 問題的答案。

## 環境需求

- Ruby 3.2 以上。1.x 需要的是 3.1。
- 2.0 沒有執行期相依套件。faraday、multi_xml、activemodel 和 activesupport 都拿掉了。如果你的應用程式自己有用到其中之一，請加進你自己的 Gemfile。

## 設定

1.x 有全域設定和 `Client`。2.0 沒有全域設定。你用帳號設定建立一個 provider，每個帳號一個：

```ruby
# 1.x
Einvoice.configure do |config|
  config.endpoint = ENV["EINVOICE_ENDPOINT"]
  config.client_id = ENV["EINVOICE_CLIENT_ID"]
  config.client_secret = ENV["EINVOICE_CLIENT_SECRET"]
  config.encryption_keys = { key1: ENV["KEY1"], key2: ENV["KEY2"] }
end
client = Einvoice::Client.new(Einvoice::Tradevan::Provider.new)
```

```ruby
# 2.0
require "einvoice/tradevan"

provider = Einvoice::Tradevan::DefaultAPI::Provider.new(
  base_url: ENV["EINVOICE_ENDPOINT"],
  acnt: ENV["EINVOICE_CLIENT_ID"],
  acntp: ENV["EINVOICE_CLIENT_SECRET"],
  key1: ENV["KEY1"], key2: ENV["KEY2"],
  company_un: "12345678", org_id: "ABCDE",
  paper_print_mode: "0", invoice_alarm_mode: "4",
  invoice_paper_returned: "N", allowance_paper_returned: "N"
)
```

| 1.x | 2.0 |
| --- | --- |
| `endpoint` | `base_url`，值相同。必須使用 https |
| `client_id`、`client_secret` | `acnt`、`acntp` |
| `encryption_keys[:key1]`、`[:key2]` | `key1`、`key2` |
| `endpoint_url` | 拿掉了。`base_url` 可以指定任何主機 |
| `format` | 拿掉了。2.0 送出 JSON |
| `ssl_verify` | 拿掉了。2.0 一律檢查 TLS 憑證 |
| 每個 payload 裡的 `companyUn`、`orgId`、`paperPrintMode`、`invoiceAlarmMode`、`invoicePaperReturned`、`allowancePaperReturned` | 改成 constructor 的設定，只設定一次 |

會員載具另外需要 `member_carrier_type:`，也就是關貿給你的 6 碼代號。

## 開立發票

在 1.x，你要自己組完整的 `issueData`：`saleIdentifier`、日期和時間、總計，以及每個品項的稅額。在 2.0，你只要給訂單、買方和品項。core 會計算稅額和總計，adapter 會組出其他欄位。

```ruby
# 1.x
result = client.issue(
  companyUn: "12345678", orgId: "ABCDE", type: "I",
  saleIdentifier: "12345678_ABCDE_53b2a44e4b3c", transactionNumber: "53b2a44e4b3c",
  transactionDate: "20160425", transactionTime: "12:34:56", total: "20000",
  paperPrintMode: "0", invoiceAlarmMode: "4", donate: "N",
  carrierType: "3J0002", carrierId: "/ABC1234", carrierIdHidden: "/ABC1234",
  receiverEmail: "john@example.com",
  itemList: [{ saleIdentifier: "12345678_ABCDE_53b2a44e4b3c", serialNumber: "0001",
               productName: "Coffee Latte", qty: "4", price: "5000",
               itemTotal: "20000", taxType: "T" }]
)
result.data["invoiceNumber"]
```

```ruby
# 2.0
result = provider.issue(
  order_id: "53b2a44e4b3c",
  buyer: { email: "john@example.com" },
  carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" },
  tax_type: "TAXABLE",
  price_mode: "TAX_INCLUSIVE",
  items: [{ description: "Coffee Latte", quantity: 4, unit_price: 5000, amount: 20000 }]
)
result.invoice_number   # => "GX38551078"
store(result.reference.to_h)
```

- adapter 會把 `saleIdentifier` 組成 `"#{company_un}_#{org_id}_#{order_id}"`。你的 `order_id` 會當成 `transactionNumber` 送出。
- 請把 `result.reference.to_h` 和訂單一起存起來。作廢、折讓和查詢會從裡面取得需要的資料，所以你不用自己保存 `saleIdentifier` 或發票日期。
- 買方有 `ubn` 時，會開成 B2B 發票。關貿 adapter 只接受 5% 的稅率，也不支援混合稅率。

## 作廢、折讓和作廢折讓

1.x 用 `cancel` 處理兩種作廢，折讓則是用 `issue` 加上 `type: "A"`。2.0 每個操作各有一個方法：

```ruby
provider.void(invoice: reference, reason: "客戶取消")

allowance = provider.allowance(
  invoice: reference, allowance_id: "53b2a44e4b3d", price_mode: "TAX_INCLUSIVE",
  items: [{ description: "Coffee Latte", quantity: 1, unit_price: 5000, amount: 5000 }]
)

provider.void_allowance(allowance: allowance.reference)
```

- 作廢現在需要 `reason`，最多 20 個字。
- 折讓從 reference 取得稅別和稅率，`itemExclude`、`tax` 和總計由 core 計算。
- `allowance_id` 會當成 `transactionNumber` 送出，adapter 會用和 `saleIdentifier` 相同的前綴組出 `allowanceIdentifier`。

## 1.x 開立的發票

這些發票沒有 2.0 的 reference。請改傳你保存的資料：

```ruby
provider.void(
  invoice: { number: "GX38551078" },
  reason: "客戶取消",
  provider_options: { sale_identifier: "12345678_ABCDE_53b2a44e4b3c" }
)

provider.allowance(
  invoice: { number: "GX38551078" },
  tax_type: "TAXABLE", tax_rate: 0.05,
  allowance_id: "53b2a44e4b3d", price_mode: "TAX_INCLUSIVE",
  items: [{ description: "Coffee Latte", quantity: 1, unit_price: 5000, amount: 5000 }],
  provider_options: { sale_identifier: "12345678_ABCDE_53b2a44e4b3c" }
)
```

如果你在 1.x 的 `saleIdentifier` 是 `"#{companyUn}_#{orgId}_#{transactionNumber}"`，也可以改傳 `invoice: { number:, order_id: transactionNumber }`，adapter 會重新組出它。折讓時如果沒有發票日期，adapter 會先用發票號碼查詢。

## 回傳值和錯誤

1.x 回傳 `Result`。你要檢查 `successful?`、讀取 `data`，並比對 `failReason` 的文字。2.0 成功時回傳 value object，失敗時丟出 `Einvoice::Error`：

```ruby
begin
  provider.void(invoice: reference, reason: "客戶取消")
rescue Einvoice::ConflictError => e
  # 只有 :already_voided 代表發票已經作廢。其他 reason，
  # 例如 :void_blocked_by_allowance，代表沒有作廢。
  raise unless e.reason == :already_voided
rescue Einvoice::Error => e
  e.raw_message   # 關貿原始的文字
  raise
end
```

README 列出了每種錯誤類別代表的下一步。關貿沒有公開錯誤代碼，所以 adapter 會比對已知的文字，不認得的文字是 `ProviderError`。

## 1.x 的其他呼叫

unified model 有 `issue`、`void`、`allowance`、`void_allowance` 和 `query`。其他 DEFAULTAPI endpoint 仍然可以透過 `raw` 呼叫。它會加密參數，並回傳解密後的回應：

| 1.x | 2.0 |
| --- | --- |
| `search_invoice_detail(number)` | `provider.query(invoice: { number: })` |
| `search_invoice_by_member_id(payload)` | `provider.raw("get/searchInvoiceByMemberId", payload)` |
| `search_invoice_by_transaction_number(payload)` | `provider.raw("get/searchInvoiceInfoByTransactionnumber", payload)` |
| `send_card_info_to_cust(payload)` | `provider.raw("get/sendCardInfotoCust", payload)` |
| `get_invoice_mark_info(payload)` | `provider.raw("get/getInvoiceMarkInfo", payload)` |
| `get_invoice_content(payload)` | `provider.raw("get/getInvoiceContent", payload)` |
| `get_donate_unit_list(company_un)` | `Einvoice::MOF::DonationCodes`（見下方），或 `provider.raw("get/getDonateUnitList", { companyUn: })` |

## 愛心碼

1.x 內建了一份愛心碼清單 `donation_unit_list.json`，這份清單後來過時了。2.0 只檢查愛心碼的格式（3 到 7 位數字），不再內建清單。要確認愛心碼是否已經登記，請查詢財政部的開放資料：

```ruby
require "einvoice/mof"

Einvoice::MOF::DonationCodes.new.exist?("2718")  # => true
```

## 正式上線前

- **確認 `qty`。** 各來源對關貿的 `qty` 是件數，還是件數乘以 1000，說法不一致。adapter 送出的是件數，所以 4 件就是 `qty` `"4"`。如果你在 1.x 送的是件數乘以 1000，而且關貿接受了，請開一個 issue 告訴我們。正式上線前，請先開一張測試發票，到關貿的後台確認數量。
- **測試你會用到的每一個操作**，請用你自己的帳號。[`docs/providers/tradevan/defaultapi.zh-TW.md`](providers/tradevan/defaultapi.zh-TW.md) 列出了 adapter 推測的地方，以及每一項推測的把握程度。

## 換到其他加值中心

在 2.0，同樣的呼叫也適用於 ECPay、Amego 和 ezPay。換到其中一家，需要先和那一家簽約、開帳號，再改 `require` 和 constructor。README 列出了每一家支援的功能。
