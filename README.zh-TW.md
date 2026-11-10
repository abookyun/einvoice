# Einvoice

[English](README.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

[![Build Status](https://github.com/abookyun/einvoice/actions/workflows/build.yml/badge.svg)](https://github.com/abookyun/einvoice/actions/workflows/build.yml) [![codecov](https://codecov.io/github/abookyun/einvoice/graph/badge.svg?token=yxJNmXiUyp)](https://codecov.io/github/abookyun/einvoice)

不綁定特定加值中心的**台灣電子發票 SDK**（財政部 MIG 4.0）。核心只定義一次五個操作：開立（issue）、作廢（void）、折讓（allowance）、折讓作廢（void-allowance）、查詢（query）。這些操作由一套 unified value model 和 `Einvoice::Provider` contract 表達。每一家加值中心是一個輕量的 adapter，負責在 unified model 和該家的傳輸格式之間轉換。所以更換加值中心只需要改一行 constructor，不會動到業務程式碼。

> **2.0 是全新改寫的版本，1.x 已經進入維護模式。** 1.x 是只支援關貿（Tradevan）一家的傳輸格式 client，API 也不一樣。如果你依賴 1.x，請鎖定 `~> 1.4`。1.x 會在 [`1-x-stable`](https://github.com/abookyun/einvoice/tree/1-x-stable) branch 繼續維護。2.0 的 unified model 和 1.x 不相容。

## 這是什麼

台灣每一家加值中心包裝的都是財政部同一份 MIG 規格，差別只在傳輸格式：欄位名稱、簽章、封包結構。這個 SDK 只定義一次操作，每一家加值中心都只是輕量的 adapter。應用程式只依賴 `Einvoice::Provider` 和 unified 型別，所以從一家加值中心換到另一家，只要換 constructor。

## 狀態

正在朝 2.0 積極開發。不綁定加值中心的**核心**已經完成，包括：value 型別、`Provider` contract、capabilities、統一的錯誤類別階層、輸入檢查，以及在記憶體中執行的 `MockProvider`。第一個真正的 adapter **ECPay（綠界）** 也一起提供：五個操作加上載具驗證，都已經對 ECPay 公開的 stage API 驗證過。

其他加值中心會陸續加入。它們的涵蓋範圍和完整度會不一樣：這些加值中心的文件比較不完整，也沒有公開的測試環境。所以只依文件寫出來的 adapter，在真正上線使用並確認之前，會有一些不確定性。

## 安裝

```ruby
gem "einvoice", ">= 2.0.0.alpha1"
```

## 使用方式

請依賴 `Einvoice::Provider` contract，不要依賴特定的 adapter。每個 provider 都是各自建立的實例（沒有全域設定），所以多商家的應用程式只要為每一組帳號各建立一個 provider。

```ruby
# Any adapter — here the in-memory reference provider — is an Einvoice::Provider.
provider = Einvoice::MockProvider.new

result = provider.issue(
  order_id: "ORDER_1",
  buyer: { email: "buyer@example.com" },       # a ubn present ⇒ B2B (三聯式)
  items: [
    { description: "咖啡拿鐵", quantity: 1, unit_price: 100, amount: 100 }
  ],
  amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }, # integer TWD
  tax_type: "TAXABLE",
  price_mode: "TAX_INCLUSIVE",
  carrier: { type: "MEMBER" }
)

result.invoice_number   # => "MK10000000"
result.status           # => :issued

invoice = provider.query(invoice: result.reference)
invoice.status          # => :issued

provider.void(invoice: result.reference, reason: "客戶取消")
```

`result.reference` 是一個 `InvoiceReference`。它記錄之後作廢、折讓或查詢這張發票時，加值中心會要的資料：號碼、`invoice_datetime`、`random_code`、`order_id`、`total_amount`、`buyer_ubn`，以及它的 `tax_type` 和 `tax_rate`。請把 `result.reference.to_h` 和訂單一起存起來。它只包含 JSON 安全的值（`invoice_datetime` 是 UTC+8 的 ISO 8601 字串），可以直接存進 JSON 欄位。之後原樣用 `invoice:` 傳回來，或直接傳 reference 本身。存起來的時間必須帶時區：`"2026-08-01 10:00"` 會被拒絕，不會被當成錯的時區；只有日期的 `"2026-08-01"` 視為台北當天。也可以只傳發票號碼，但如果加值中心需要更多資料，會丟出 `ValidationError` 並說明缺少哪個欄位。沒有發票號碼時，可以在宣告 `QUERY_BY_ORDER_ID` 的加值中心用 `invoice: { order_id: "ORDER_1" }` 查詢。`void_allowance` 收 `allowance:`，也就是 `AllowanceResult#reference` 回傳的 `AllowanceReference`。

輸入可以直接傳一般的 Hash，key 用字串或 symbol 都可以。列舉欄位可以傳標準的 symbol（`:taxable`），也可以傳傳輸格式的字串（`"TAXABLE"`）。在送出任何網路請求之前，輸入會先經過檢查，並轉換成不可變的 value object。格式錯誤的請求會在本地端丟出 `Einvoice::ValidationError`。用 `.new` 自己建立的 value object 也會經過同樣的檢查。

檢查的規則：

- 買方的 `ubn` 是 8 位數字，也就是企業的統一編號。（MIG 表 4-7 允許 8 到 10 位的 BAN，9 位和 10 位的形式不用在買方。）B2B 發票一定要有統編；明確指定 `category` 時，必須和統編一致。
- 總計是整數，而且不能是負數。品項的數量、單價、金額是數字，最多 7 位小數。
- 手機條碼是 `/` 加 7 個字元。自然人憑證是 2 個英文字母加 14 個數字。這些格式來自加值中心的文件，MIG 只列出載具類別。
- `tax_rate` 是小數，例如 `0.05`，而且必須是 MIG 規定的稅率。開立時，應稅的預設值是 `0.05`，零稅率和免稅是 `0`。特種稅額的發票一定要給。
- 金額必須和品項一致（見下一節）。
- 作廢原因最多 20 個字。作廢折讓的原因沒給時，預設是 `作廢折讓`。

### 金額與稅額

稅額由 core 依品項計算。`price_mode` 說明品項金額是否含稅，`tax_type` 是整張發票的稅別（品項可以有自己的），`tax_rate` 是稅率。計算結果是 `input.tax_breakdown`：每一列的未稅金額、稅額、含稅金額，以及 MIG 的各項合計。adapter 讀取它，不自己計算稅額。core 不會改動你的品項。

你給的 `amount` 會拿來和它核對。發票照 F0401：買方是消費者時，稅額含在 `sales_amount` 裡，`tax_amount` 是 `0`。買方是營業人時，`tax_amount` 是 `round(應稅銷售額 × tax_rate)`：

```ruby
amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }  # 含稅 100，開給營業人
```

折讓照 G0401：`sales_amount` 不含稅，買方是消費者時也一樣。折讓的 `tax_type` 和 `tax_rate` 從發票的 reference 取得，所以傳 `issued.reference` 即可，也可以自己給。沒有預設值，所以零稅率的發票不會被折讓出 5% 的稅。原發票是混合稅時，每個品項都要給 `tax_type`。

```ruby
provider.allowance(
  invoice: issued.reference, allowance_id: "AL_1", price_mode: "TAX_INCLUSIVE",
  items: [{ description: "退貨", quantity: 1, unit_price: 100, amount: 100 }],
  amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }
)
```

### 錯誤

每一種失敗都是 `Einvoice::Error` 的子類別，包含：

- 固定不變的 `#code`。
- 加值中心原始的 `#raw_code` 和 `#raw_message`。
- 選填的 `#reason`，說明呼叫端接下來該怎麼處理。
- `#group`，說明是哪一方失敗：`:invoice`（請求違反財政部的規則，或發票的狀態不對）或 `:provider`（帳號、連線，或加值中心自己的服務）。

可以只 rescue 特定類別，也可以一次 rescue 全部：

```ruby
begin
  provider.void(invoice: invoice.reference, reason: "customer cancelled")
rescue Einvoice::ConflictError => e
  e.reason   # => :already_voided  (idempotent — treat as success)
rescue Einvoice::Error => e
  e.code     # => :network, :auth, :not_found, …
end
```

### 帳號金鑰與買方資料

- 結果物件的 `inspect`、`to_s` 和 `pp` 會把 `raw` 顯示成 `[FILTERED]`，因為 `raw` 是加值中心的回應，裡面有買方的資料。需要時，請直接讀 `#raw`。adapter 的 client 也會把金鑰顯示成 `[FILTERED]`。
- `base_url` 必須使用 https。只有 localhost 可以用 http，方便測試。

### Capabilities

每個 provider 會宣告自己支援哪些功能。請先檢查功能是否支援，不要等到請求失敗才發現。

```ruby
provider.supports?(Einvoice::Capability::FOREIGN_CURRENCY)  # => true / false
provider.assert_supports!(Einvoice::Capability::B2B)        # raises UnsupportedError if absent
```

## 加值中心

### ECPay 綠界

```ruby
provider = Einvoice::ECPay::Provider.new(
  merchant_id: "2000132",
  hash_key: "...",          # 16 bytes, server-side only
  hash_iv: "...",           # 16 bytes, server-side only
  mode: :production         # :test (default) targets the stage host
)
```

上面的用法全部不用改。`issue`、`void`、`allowance`、`void_allowance`、`query` 收一樣的 unified 輸入，也回傳一樣的 value 型別。AES-128-CBC 封包、ECPay 的兩層結果代碼，以及它的欄位規則，都封裝在 adapter 裡面。

沒有帳號也可以試用。請用 ECPay 公開的測試帳號。這組帳號由所有開發者共用，不要用在任何正式的資料上：

```ruby
provider = Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX)
```

幾件需要知道的事：

- **紙本或電子由 adapter 判斷。** 有載具或捐贈的發票是電子發票（`Print=0`），其他的都會列印。列印時 ECPay 要求買方名稱和地址。
- **混合稅率也由 adapter 判斷。** 如果品項的 `tax_type` 不一致，就會開成混合稅率（TaxType 9）發票，不用另外指定。
- **作廢、折讓、用號碼查詢都需要發票的開立日期**，從 `invoice.invoice_datetime` 取得。如果 reference 沒有日期但有 `order_id`，adapter 會先查詢補上；查詢失敗時丟出 `ProviderError`，`reason` 是 `:lookup_failed`。只有號碼是不夠的。
- **作廢折讓需要發票號碼**，所以請傳 `AllowanceReference`，不要只傳折讓單號。
- **不支援外幣。** ECPay 的 B2C API 沒有外幣欄位，所以 `currency` 不是 TWD 時會丟出 `UnsupportedError`，不會被當成 TWD 開立。
- **應稅發票固定是 5%。** ECPay 依課稅別決定稅率，所以其他的 `tax_rate` 會丟出 `UnsupportedError`。
- **載具驗證**：`validate_carrier({ type: "MOBILE_BARCODE", code: "/ABC1234" })`（`CARRIER_VALIDATION` 對應的 `Provider` 方法；ECPay 只能檢查手機條碼）、`validate_love_code("168001")`、`love_code_organ_name("168001")`。這些方法會詢問 ECPay，所以需要這個 adapter 和它的帳號。捐贈碼（愛心碼）另外可以用下面的 `Einvoice::MOF::DonationCodes`，它直接詢問財政部，不需要 adapter，也不需要帳號。
- **其他功能**：ECPay 另外有大約 25 個 B2C endpoint（延遲開立、字軌設定、列印、通知……）。請用 `provider.raw(path, payload)` 呼叫。它會處理封包、加密和錯誤對應。

## 財政部查詢

直接使用財政部公開服務的 client，不綁定任何加值中心。它們不開立任何東西，也不需要帳號，所以不論你用哪一家加值中心都可以用，甚至還沒選定加值中心時也可以用。

```ruby
codes = Einvoice::MOF::DonationCodes.new

codes.lookup("2718")
# => #<data Einvoice::MOF::DonationCode code="2718",
#      name="社團法人台北市喜願協會", short_name="喜願協會",
#      ubn="92000392", city="臺北市">

codes.exist?("105")          # => false — well-formed, not registered
codes.for_ubn("92000392")    # => every 愛心碼 that organisation holds
codes.all                    # => the whole dataset (~2,000, five requests)
```

這個 client **刻意不**接到 `Input`。`Input` 的檢查在本地端同步執行，而開立發票絕對不能依賴第三方服務是否連得上。`Input` 只檢查捐贈碼的格式。這個捐贈碼是否已經*登記*，請在適合的時候自己查詢：可以在下訂單時查，也可以在啟動時用 `#all` 抓一次完整清單，之後在本地端檢查。

這份資料集目前不需要帳號。但是它公開的 OpenAPI 文件宣告了 `api_key` 和 `oauth2` 兩種驗證方式。所以如果收到 401 或 403，client 會丟出 `Einvoice::AuthError` 並說明原因，不會變成難以理解的解析錯誤。

## 開發

```bash
bin/setup          # install dependencies
bundle exec rspec  # run the specs
bundle exec rake   # default task: rspec
```

`"an invoice provider"` shared examples（`spec/support/shared_examples/`）是每個 adapter 都要執行的 contract。新的 adapter 只要加一行引用它，就能證明自己遵守 unified model。

要寫新的 adapter，請從 [`docs/providers/`](docs/providers/README.zh-TW.md) 的加值中心筆記開始。閱讀順序：先讀財政部 MIG 筆記（所有加值中心都遵循的規格），再讀 ECPay 筆記（唯一已經有 adapter 的加值中心，可以看筆記怎麼對應到程式碼），接著讀你要做的那一家的筆記，最後讀上面提到的 shared examples。

ECPay adapter 的測試分成三層，其中兩層在 CI 中離線執行：

1. **用模擬傳輸格式的 fake 跑 contract。** shared examples 透過一個在同一個 process 中執行的 fake 來跑。這個 fake 實作真正的協定：AES 封包、PHP URL encoding，以及 ECPay 自己的 RtnCode。所以只有加密和欄位對應都正確時，請求才會通過。fake 會保留狀態，所以 contract 可以依序執行開立、折讓、作廢。
2. **錄製的真實回應（VCR）。** `spec/einvoice/ecpay/recorded_spec.rb` 重播從 ECPay stage host 錄下來的 cassette。所以測試用到的欄位名稱、值的型別和錯誤代碼，都是 ECPay 實際回傳的，不是我們對文件的解讀。要重新錄製，請先調整該 spec 裡的 epoch，再用 `VCR_RECORD=1` 執行。cassette 只會包含測試環境的流量。
3. **選擇性執行的 live API 測試。** 用來確認前兩層沒有偏離真實的 API：

   ```bash
   ECPAY_LIVE=1 bundle exec rspec spec/einvoice/ecpay/live_spec.rb
   ```

   預設使用公開的測試帳號，所以不需要任何設定。如果要改用你自己的 stage 帳號，請設定 `ECPAY_MERCHANT_ID`、`ECPAY_HASH_KEY`、`ECPAY_HASH_IV`。這層不在 CI 中執行，因為它需要網路，而且測試帳號是共用的。

## 授權

本 gem 以 [MIT 授權](http://opensource.org/licenses/MIT)開放原始碼。
