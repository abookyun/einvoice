# Amego 光貿：電子發票 API

[English](api.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

## 1. 狀態與來源

> **可信度：** adapter 進行中。它的 live spec 在 2026-10-22 於公開的測試帳號上通過，看到的事實標為 `[live]`。第 4 節和 6.4 的錯誤類別欄是 adapter 要遵守的對應方式。live spec 沒有檢查每一列。

這是 Amego 在 `https://invoice-api.amego.tw` 的 JSON API。2.x 的 adapter 會是 `Einvoice::Amego::Provider`。標 `[live]` 的事實是在公開測試帳號上實際看到的。

文件屬於光貿科技 Amego，公開在 <https://invoice.amego.tw/api_doc/>。本筆記是我們的整理。

這個 API 非常貼近 MIG。endpoint 以 MIG 訊息命名（`f0401`、`f0501`、`g0401`、`g0501`），大部分欄位也用 MIG 的名稱。

| 標記 | 來源 | 日期 | 提供的內容 |
| --- | --- | --- | --- |
| `[doc]` | Amego API 文件，<https://invoice.amego.tw/api_doc/>。用 apiDoc 產生的網站。2026-10-14 讀取資料 bundle（`main.bundle.js?2026093003`）。 | 2026-09-30 產生，文件版本 1.0.0 | 所有 endpoint、欄位、範例和基本規則。 |
| `[live]` | 我們的 live spec（`spec/einvoice/amego/live_spec.rb`），在公開的測試帳號上執行，2026-10-22。 | 2026-10-22 | Amego 實際接受的內容和回應。 |
| `[info]` | Amego 線上說明頁。文件中有連結：<https://invoice.amego.tw/info_detail?mid=70>（開立方式）、`mid=71`（錯誤代碼）、`mid=73`（會員載具規則）、`mid=74`（檢查規則）。2026-10-14 讀取。 | | 錯誤代碼和格式規則。 |

**更新檢查。** 文件網站沒有更新記錄。bundle 的網址帶有建置編號（`main.bundle.js?2026093003`）。編號改變表示文件重新建置過。

## 2. 連線

### 2.1 主機與帳號

測試和正式環境用同一個主機：`https://invoice-api.amego.tw`。環境由帳號決定，不是由網址決定 `[doc]`。

賣方有自己的統一編號，以及由 Amego 客服提供的 App Key。共用的測試帳號 `[doc]`：

| 項目 | 值 |
| --- | --- |
| 統一編號 | `12345678` |
| App Key | `sHeq7t8G1wiQvhAuIM27` |
| 後台 | <https://invoice.amego.tw/>，`test@amego.tw` / `12345678` |

測試環境不寄 email。要收測試信，請在測試後台打開該張發票，按下「補發發票開立通知」`[doc]`。

### 2.2 請求

所有 API 都是 `POST`，`Content-Type: application/x-www-form-urlencoded`。不要送 `application/json` `[doc]`。

| 欄位 | 型別 | 規則 |
| --- | --- | --- |
| `invoice` | String | 賣方的統一編號 |
| `data` | String | API 資料的 JSON 字串，經過 URL encode |
| `time` | Number | Unix 時間。和伺服器時鐘的差距必須在 ±60 秒以內 |
| `sign` | String | `md5(data + time + AppKey)`，其中 `data` 是 URL encode 之前的 JSON 字串 |

Amego 會在它那一端對 POST 資料做一次 URL decode。`/json/time` 回傳伺服器時間，可以用來修正時鐘誤差。

有些 API 的 `data` 是陣列，例如 `f0501`、`g0401` 和 `g0501`。有些是單一物件，例如 `f0401` `[info 71: codes 23, 3040112]`。

沒有加密。`sign` 只證明呼叫端知道 App Key。

**API 的限制。** payload 是明文 JSON，所以買方資料只靠 TLS 保護。`sign` 用的是 MD5，回應則完全沒有簽章。測試和正式環境共用同一台主機，只靠帳號區分。如果應用程式不小心用了共用的測試帳號，開出的會是測試發票，而且不會有任何錯誤。

### 2.3 回應

JSON，每個回應都有 `code` 和 `msg`。`code` 為 `0` 表示成功，其他代碼是錯誤（6.4）`[doc]`。

結果放在哪裡，依 endpoint 而不同 `[doc]`：

| Endpoint | 結果 |
| --- | --- |
| `f0401` | 在最外層，和 `code`、`msg` 同一層：`invoice_number`、`invoice_time`……只在成功時出現 |
| `f0501`、`g0401`、`g0501` | 除了 `code` 和 `msg` 之外沒有其他內容 |
| `invoice_query`、`allowance_query`、列表、`f0401_custom` | 在 `data` 裡 |

陣列型的 endpoint 整次呼叫只回傳一個 `code`。文件沒有說明送多筆時，其中一筆失敗會發生什麼事。錯誤訊息會指出是哪一筆（「第n筆」），所以 adapter 應該一次只送一筆（見第 7 節）。

### 2.4 MIG 4.0 路徑

Amego 從 2025-01-01 起使用 MIG 4.0。舊路徑仍然可以用 `[doc]`：

| 舊 | 新 |
| --- | --- |
| `/json/c0401` | `/json/f0401` |
| `/json/c0501` | `/json/f0501` |
| `/json/d0401` | `/json/g0401` |
| `/json/d0501` | `/json/g0501` |
| `/json/c0401_custom` | `/json/f0401_custom` |

### 2.5 範例

取自文件 `[doc]`。一張要列印的 B2C 發票，含一筆折扣品項。

表單欄位：

```
invoice=12345678
data=<the JSON below, URL encoded>
time=1729000000
sign=md5(<the JSON below> + "1729000000" + AppKey)
```

`data`：

```json
{ "OrderId": "A20200817101021", "BuyerIdentifier": "0000000000", "BuyerName": "客人",
  "BuyerAddress": "", "BuyerTelephoneNumber": "", "BuyerEmailAddress": "", "MainRemark": "",
  "CarrierType": "", "CarrierId1": "", "CarrierId2": "", "NPOBAN": "",
  "ProductItem": [
    { "Description": "測試商品1", "Quantity": "1", "UnitPrice": "170", "Amount": "170", "Remark": "", "TaxType": "1" },
    { "Description": "會員折抵", "Quantity": "1", "UnitPrice": "-2", "Amount": "-2", "Remark": "", "TaxType": "1" } ],
  "SalesAmount": "168", "FreeTaxSalesAmount": "0", "ZeroTaxSalesAmount": "0",
  "TaxType": "1", "TaxRate": "0.05", "TaxAmount": "0", "TotalAmount": "168" }
```

文件沒有提供 `f0401` 完整的回應範例。依欄位清單，回應應該是：

```json
{ "code": 0, "msg": "", "invoice_number": "…", "invoice_time": 1729000000,
  "random_number": "…", "barcode": "…", "qrcode_left": "…", "qrcode_right": "…" }
```

失敗時：`{ "code": 3040171, "msg": "…" }`。查無資料時：`{ "code": 71, "msg": "查無資料" }`。

### 2.6 官方測試向量

範例頁 <https://invoice.amego.tw/api_doc/example> 有一組結果已知的範例。它的 Python 程式寫著 `sign` 是 `f53a336934b2af0589b845638d1495cc` `[doc]`。輸入是：

- `data`：一張 B2B 發票（`OrderId` `A20200817105934`、`BuyerIdentifier` `28080623`、兩個品項），格式是 Python `json.dumps(indent=0)` 的輸出。也就是在每個 `{`、`[` 和每個項目後面換行，每個非 ASCII 字元寫成 `\uXXXX`。
- `time`：`1628136135`，寫在範例的註解裡。
- App Key：公開的測試金鑰。

Amego 對實際送出的字串計算簽章。JSON 的排版也是輸入的一部分，任何合法的 JSON 排版都可以。client spec 驗證了這組範例（`spec/einvoice/amego/client_spec.rb`）。文件沒有其他結果已知的範例。

## 3. 操作

五個 unified 操作使用下列 endpoint。欄位見第 5 節。

| Endpoint | 用途 |
| --- | --- |
| `/json/f0401` | 開立發票。號碼由 Amego 指定（自動配號） |
| `/json/f0501` | 作廢發票（陣列） |
| `/json/g0401` | 開立折讓（陣列） |
| `/json/g0501` | 作廢折讓（陣列） |
| `/json/invoice_query` | 查詢一張發票，用訂單編號或號碼，限 180 天內 |

其他 endpoint。adapter 可以透過 `raw` 方法呼叫：

| Endpoint | 用途 |
| --- | --- |
| `/json/invoice_status`、`/json/allowance_status` | 發票或折讓的上傳狀態（陣列） |
| `/json/invoice_list`、`/json/allowance_list` | 某段日期內的發票或折讓，分頁 |
| `/json/allowance_query` | 查詢一張折讓 |
| `/json/invoice_file`、`/json/invoice_print`、`/json/allowance_file`、`/json/allowance_print` | 檔案與熱感應機列印資料 |
| `/json/invoice_modify` | 修改已開立的發票（見下方） |
| `/json/lottery_status`、`/json/lottery_type` | 某一期的中獎發票、獎項代碼 |
| `/json/barcode` | 手機條碼是否已登記 |
| `/json/ban_query` | 統一編號對應的公司名稱 |
| `/json/track_all`、`/json/track_get`、`/json/track_status` | 字軌：列表、取號（只限 API 配號）、狀態 |
| `/json/f0401_custom` | 用賣方自己的號碼、日期、時間和隨機碼開立 |
| `/json/time` | 伺服器時間 |

發票號碼有兩種配號方式 `[info 70]`：

- **自動配號**：賣方送出發票，Amego 回傳號碼、日期和隨機碼。使用 `f0401`。
- **API 配號**：賣方先用 `track_get` 取得一段號碼，再用 `f0401_custom` 送出自己的號碼、日期、時間和隨機碼。適合需要離線列印的 POS。

每個字軌在後台設定成其中一種方式（發票作業 > 發票字軌列表）。unified API 的 adapter 使用自動配號。

`invoice_modify` 用來修改 `f0401` 開立的發票。只能在 180 天內、上傳之後使用，而且不適用於已列印的 B2C 發票、特種稅額發票，以及有折讓的發票 `[info 71: codes 43 to 50]`。文件沒有說明它送出的是哪一種 MIG 訊息。

## 4. 對應到 unified API

### 4.1 操作

| Unified | Endpoint | Reference 欄位 | `provider_options` |
| --- | --- | --- | --- |
| `issue` | `f0401` | | `track_api_code`、`customs_clearance_mark`、`zero_tax_rate_reason`、`brand_name`、`detail_amount_round`、`tax_adjustment` |
| `void` | `f0501` | `number` | |
| `allowance` | `g0401` | `number`、`invoice_datetime` | `buyer_identifier`、`buyer_name` |
| `void_allowance` | `g0501` | `allowance_number` | |
| `query` | `invoice_query` | `order_id` 或 `number` | |

每次呼叫只送一筆資料，接受陣列的 endpoint 也一樣（2.3）。

**折讓資料從查詢取得。** `g0401` 需要原發票的日期和買方（`BuyerIdentifier`、`BuyerName`）。reference 有日期，但沒有買方。所以 adapter 會先呼叫 `invoice_query`，取得買方；reference 沒有日期時，也一起取得日期。如果 `provider_options` 給了 `buyer_identifier` 和 `buyer_name`，而且 reference 有 `invoice_datetime`，adapter 就不查詢。查詢只能查 180 天內的發票。超過之後，呼叫端必須三個都給，否則 adapter 丟出 `ValidationError`。

### 4.2 欄位

#### `issue`

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `order_id` | `OrderId` | 最多 40 |
| `buyer.ubn` | `BuyerIdentifier` | B2C 為 `0000000000` |
| `buyer.name` | `BuyerName` | 必填。B2C 沒有名稱時送 `消費者`。B2B 沒有名稱時送統一編號。不能是 `0` 到 `0000` |
| `buyer.address`、`.phone`、`.email` | `BuyerAddress`、`BuyerTelephoneNumber`、`BuyerEmailAddress` | Amego 會把發票通知寄到這個 email |
| `carrier`（`MOBILE_BARCODE`） | `CarrierType` `3J0002`，`CarrierId1` = `CarrierId2` = `code` | |
| `carrier`（`CITIZEN_CERTIFICATE`） | `CarrierType` `CQ0001`，兩個 id 都是 `code` | |
| `carrier`（`MEMBER`） | `CarrierType` `amego`，兩個 id 都是 `code` | 沒有 `code` 時，用買方的 email；沒有 email 時，用 `a` 加上買方的手機號碼（6.2）。兩個都沒有：`ValidationError` |
| `donation.npoban` | `NPOBAN` | 可以同時帶載具 |
| `remark` | `MainRemark` | 最多 200 |
| `tax_type`、`items[].tax_type` | `TaxType` | 品項的課稅別不同時為 `9`，否則為對應代碼（6.1）。`SPECIAL`：`UnsupportedError` |
| `tax_rate` | `TaxRate` | 小數字串，例如 `0.05`。只接受 `0` 和 `0.05`，其他稅率：`UnsupportedError` |
| `price_mode` | `DetailVat` | `TAX_EXCLUSIVE` 為 `0`，否則為 `1`。`0` 只能用在 B2B：B2C 用 `TAX_EXCLUSIVE` 會丟出 `ValidationError` |
| `amount` | `SalesAmount`、`FreeTaxSalesAmount`、`ZeroTaxSalesAmount`、`TaxAmount`、`TotalAmount` | 從品項計算。見 4.3 |
| `provider_options[:customs_clearance_mark]` | `CustomsClearanceMark` | `1` 或 `2`。有零稅率品項時必填 |
| `provider_options[:zero_tax_rate_reason]` | `ZeroTaxRateReason` | `71` 到 `79`。有零稅率品項時必填 |
| `items[]` | `ProductItem` | `description` → `Description`（最多 256）、`quantity` → `Quantity`、`unit` → `Unit`、`unit_price` → `UnitPrice`、`amount` → `Amount`、`remark` → `Remark`、`tax_type` → `TaxType`（品項的課稅別，沒有時用發票的） |
| `currency` | （無） | 不是新台幣時丟出 `UnsupportedError`（見第 7 節） |
| `category` | （無） | 和 core 一樣，用來判斷是否為 B2B |
| `exchange_rate` | （無） | 不送出 |

結果：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `invoice_number` |
| `invoice_datetime` | `invoice_time`（Unix time），UTC+8 |
| `random_code` | `random_number` |
| `order_id`、`total_amount` | 輸入值 |
| `status` | `ISSUED` |
| `reference` | 用上面的欄位組成 |

#### `void`

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `invoice.number` | `[0].CancelInvoiceNumber` | |
| `reason` | `[0].CancelReason` | 最多 20 |

結果：`invoice_number` 取自輸入值，`status` 為 `VOIDED`，`cancel_datetime` 為 `nil`。回應只有 `code` 和 `msg`。

作廢是非同步的。`code` 為 `0` 表示 Amego 已經把作廢放進佇列，不表示作廢已經完成。作廢後馬上查詢，可能仍然回報 `ISSUED`（4.4）。

#### `allowance`

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `allowance_id` | `AllowanceNumber` | 最多 16。在帳號內不能重複 |
| （當下） | `AllowanceDate` | UTC+8 的今天，`Ymd`。Amego 要求必填，它就是這次折讓的日期 |
| （固定） | `AllowanceType` | `2` |
| `provider_options[:buyer_identifier]`、`[:buyer_name]`，沒有時取自查詢 | `BuyerIdentifier`、`BuyerName` | 必須和原發票一致 |
| `invoice.number` | `ProductItem[].OriginalInvoiceNumber` | |
| `invoice.invoice_datetime`，沒有時取自查詢 | `ProductItem[].OriginalInvoiceDate` | UTC+8 的 `Ymd` |
| `items[]` | `ProductItem[]` | `description` → `OriginalDescription`、`quantity` → `Quantity`、`unit_price` → `UnitPrice`、`amount` → `Amount`，再加上品項的 `Tax` 和 `TaxType`。金額不含稅。見 4.3 |
| `amount` | `TaxAmount`、`TotalAmount` | 見 4.3 |

結果：

| Unified | 來源 |
| --- | --- |
| `allowance_number` | 輸入的 `allowance_id`。回應只有 `code` 和 `msg` |
| `invoice_number` | 輸入值 |
| `allowance_date` | adapter 送出的 `AllowanceDate` |
| `total_amount` | 輸入值 |
| `reference` | `allowance_number`、`allowance_date`、`invoice_number` |

#### `void_allowance`

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `allowance.allowance_number` | `[0].CancelAllowanceNumber` | |
| `reason` | （無） | 不送出。`g0501` 沒有原因欄位 |

結果：`allowance_number` 取自輸入值，`cancel_datetime` 為 `nil`。

#### `query`

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `invoice.order_id` | `{ "type": "order", "order_id": … }` | 有就使用 |
| `invoice.number` | `{ "type": "invoice", "invoice_number": … }` | |

結果：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `invoice_number` |
| `invoice_datetime` | `invoice_date`（`YYYYMMDD`）和 `invoice_time`（`HH:mm:ss`），UTC+8 |
| `random_code` | `random_number` |
| `order_id` | `order_id` |
| `status` | 見 4.4 |
| `amount` | 見 4.3 |
| `buyer` | `buyer_name`、`buyer_identifier`（`0000000000` 轉成 `nil`）、`buyer_address`、`buyer_telephone_number`、`buyer_email_address` |
| `items` | `product_item[]`：`description`、`quantity`、`unit_price`、`amount`、`unit`、`tax_type`、`remark` |
| `reference` | 用上面的欄位組成 |

### 4.3 金額與稅額

unified 的規則見 [unified model](../README.zh-TW.md#unified-model)。

**開立。** Amego 要求所有 MIG 總計欄位，並提供計算公式 `[doc]`。品項價格含稅（`DetailVat` 為 `1`）時：

```
SalesAmount        = round(sum of Amount where TaxType = 1)
FreeTaxSalesAmount = round(sum of Amount where TaxType = 3)
ZeroTaxSalesAmount = round(sum of Amount where TaxType = 2)
B2C:  TaxAmount = 0
B2B:  TaxAmount = SalesAmount - round(SalesAmount / 1.05)
      SalesAmount = SalesAmount - TaxAmount
TotalAmount = SalesAmount + FreeTaxSalesAmount + ZeroTaxSalesAmount + TaxAmount
```

品項價格未稅（`DetailVat` 為 `0`，只限 B2B）時，`TaxAmount = round(SalesAmount × 0.05)`，其他相同。

adapter 用 core 的稅額 helper，從品項算出這些總計，再檢查 `TotalAmount` 是否等於 `amount.total_amount`；B2B 時也檢查 `TaxAmount` 是否等於 `amount.tax_amount`。不一致就在呼叫前丟出 `ValidationError`。B2C 時公式算出的稅額為 `0`，和 F0401 一致。

除非 `DetailAmountRound` 為 `1`，否則品項金額保留 7 位小數 `[doc]`。

**折讓。** 金額不含稅，每個品項有自己的整數 `Tax` `[doc]`。這正是 core 給出的格式（G0401）。adapter 直接送出每個品項的金額和稅額。`TotalAmount` 是未稅金額的合計，`TaxAmount` 是品項稅額的合計。99 元拆成 94 加稅額 5 的折讓，Amego 接受了 `[live]`。

**查詢。** `total_amount` 是總計。`tax_amount` 只有 B2B 才會拆出來，和開立時一樣。結果是 `total = total_amount`、`tax = tax_amount`、`sales = total - tax`。

### 4.4 狀態

`invoice_query` 回報兩件事 `[doc]`：

- `invoice_type`：這張發票最後一個 MIG 訊息。它用的是 **4.0 版以前的名稱**：`C0401` 開立、`C0501` 作廢、`C0701` 註銷，B2B 存證用 `A0401` 和 `A0501`，B2B 交換用 `A0101` 到 `A0302`。
- `invoice_status`：上傳狀態（6.3）。

`wait` 列出還在佇列中的變更，例如還沒處理的作廢。`allowance` 列出這張發票的折讓，每一筆都有自己的類型和狀態（2024-10-24 新增）。

對應方式（推論）：

| `invoice_type` | Unified `InvoiceStatus` |
| --- | --- |
| `C0401`、`A0401`、`A0101`、`A0102` | `allowance` 裡有尚未作廢的折讓（`D0401` / `G0401`，不是 `D0501` / `G0501`）時為 `ALLOWANCE`，否則為 `ISSUED` |
| `C0501`、`A0501`、`A0201`、`A0202` | `VOIDED` |
| `C0701`（註銷） | `nil` |
| `A0301`、`A0302`（退回） | `nil` |

`wait` 裡的作廢還沒完成。在 `invoice_type` 改變之前，發票仍然是 `ISSUED`。

### 4.5 時限

- 只能查詢 180 天內的發票，超過會回傳代碼 `51` `[doc]`。
- 作廢、開立或註銷會進入佇列等待處理。有變更在佇列中時，作廢會回傳 `3050131`。對還在開立中的發票作廢，會回傳 `3050121` `[info 71]`。兩者都表示「晚一點再試」（6.4）。
- 作廢有時間限制（`3050126`、`4050135`），但文件沒有寫是多久（見第 7 節）。
- `invoice_modify` 只能在 180 天內、而且上傳之後使用 `[info 71]`。

### 4.6 Capabilities

| Capability | API | Adapter | 說明 |
| --- | --- | --- | --- |
| `ISSUE`、`VOID`、`ALLOWANCE`、`VOID_ALLOWANCE`、`QUERY` | 有 | 有 | |
| `B2B` | 有 | 有 | `BuyerIdentifier` 帶統一編號 |
| `MIXED_TAX` | 有 | 有 | `TaxType` `9` |
| `QUERY_BY_ORDER_ID` | 有 | 有 | `invoice_query` 用 `type: order` |
| `SCHEDULED_ISSUE` | 無 | 無 | 沒有這種 endpoint |
| `CARRIER_VALIDATION` | 有 | 有 | `validate_carrier` 對手機條碼呼叫 `barcode`。`9000113` 表示未註冊。愛心碼由 `Einvoice::MOF::DonationCodes` 處理 |
| `FOREIGN_CURRENCY` | 未知 | 無 | `f0401` 沒有幣別欄位，`f0401_custom` 有（見第 7 節） |

### 4.7 與 MIG 的差異

- **總計欄位就是 MIG 的總計欄位。** `f0401` 接受 `SalesAmount`、`FreeTaxSalesAmount`、`ZeroTaxSalesAmount`、`TaxType`、`TaxRate`、`TaxAmount` 和 `TotalAmount`，全部必填，和 F0401 一樣。
- **折讓就是 MIG G0401。** `AllowanceNumber` 由賣方指定（最多 16，不能重複）。`AllowanceDate` 必填。金額不含稅，每個品項有自己的 `Tax`。每個品項都需要 `OriginalInvoiceNumber` 和 `OriginalInvoiceDate`。
- **作廢需要的資料比 MIG 少。** `f0501` 只需要發票號碼和選填的原因，`g0501` 只需要折讓單號。F0501 和 G0501 要求日期和原因，所以 Amego 一定是從自己的紀錄補上（推論）。
- **`AllowanceType` 必須是 `2`。** 自 2025-01-01 起，Amego 拒絕 `1` `[info 71: code 4040145]`。
- **一張折讓只能對應一張發票** `[info 71: codes 4040132, 4040133]`。MIG 允許品項來自多張發票。unified model 也是一張折讓對應一張發票。
- **`Description` 最多 256** `[doc]`。MIG 允許 500。
- **B2B 走存證（推論）。** `f0401` 接受統一編號加上載具欄位和混合稅率，A0101 不允許這些。但查詢仍可能回報交換類型（A0101 到 A0302），所以 Amego 裡可能有部分發票來自交換。

### 4.8 Contract 與 live 測試

- **共用的測試帳號。** 所有開發者都用帳號 `12345678`。live spec 必須產生不重複的訂單編號和折讓單號。contract 用固定的折讓 id（`AL_1`、`AL_AV`），在 live 帳號上可能會重複。
- **不存在的號碼。** 使用格式正確的發票號碼，例如 `unknown_invoice_number: "ZZ00000000"`。折讓單號是最多 16 字元的自由文字，所以預設的 `NOPE00000000` 可以用。
- **開立後馬上作廢。** contract 會作廢剛開立的發票。Amego 可能回傳 `3050121`（還在開立中）或 `3050131`（佇列中）`[info 71]`。2026-10-22 實測時，開立後馬上作廢直接成功，第二次作廢丟出 `ConflictError` `[live]`。live spec 遇到 `RETRY_LATER` 仍會重試。fake 不模擬佇列。
- **折讓。** `issue` 回傳的 reference 提供發票日期。adapter 仍會查詢買方，所以 fake 必須回應 `invoice_query`。
- **fake。** fake 需要表單外層格式、`sign` 檢查，以及 2.3 的回應格式。

## 5. 欄位參考

### 5.1 `f0401`

`data` 是單一物件 `[doc]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `OrderId` | M | 最多 40，不可重複 |
| `TrackApiCode` | O | 用 API 代碼（在後台設定）指定字軌。沒有指定時，Amego 依後台的字軌排序開立 |
| `BuyerIdentifier` | M | 統一編號，消費者填 `0000000000` |
| `BuyerName` | M | 消費者可以填任何名稱（客人、消費者）。營業人填公司名稱，無法提供名稱時填統一編號。不可以是 `0`、`00`、`000` 或 `0000` |
| `BuyerAddress`、`BuyerTelephoneNumber` | O | |
| `BuyerEmailAddress` | O | Amego 把開立通知寄到這裡。留空就不寄 |
| `MainRemark` | O | 最多 200 |
| `CarrierType` | O | `3J0002` 手機條碼、`CQ0001` 自然人憑證、`amego` 光貿會員載具，或賣方自己的會員載具代碼 |
| `CarrierId1`、`CarrierId2` | O | 顯碼和隱碼。見 6.2 |
| `NPOBAN` | O | 捐贈碼 |
| `ProductItem` | M | 最多 9999 筆 |
| `SalesAmount` | M | 應稅銷售額合計 |
| `FreeTaxSalesAmount` | M | 免稅銷售額合計 |
| `ZeroTaxSalesAmount` | M | 零稅率銷售額合計 |
| `TaxType` | M | `1`、`2`、`3`、`4`、`9` |
| `TaxRate` | M | 5% 填 `0.05` |
| `TaxAmount` | M | 只有 B2B 發票要拆出稅額。B2C 一律填 `0` |
| `TotalAmount` | M | |
| `CustomsClearanceMark` | O | `1` / `2`。零稅率時 M |
| `ZeroTaxRateReason` | O | `71` 到 `79`。零稅率時 M |
| `BrandName` | O | 品牌名稱 |
| `DetailVat` | O | `1` 品項價格含稅（預設）、`0` 未稅。`0` 只允許用在 B2B |
| `DetailAmountRound` | O | `0` 品項金額保留 7 位小數（預設）、`1` 每筆都四捨五入到整數 |
| `TaxAdjustment` | O | `1` 讓稅額減 1。只限 B2B 加 `DetailVat` `0`，且 `SalesAmount` 尾數是 10、30、50、70 或 90 時 |
| `PrinterType`、`PrinterLang`、`PrintDetail` | O | 熱感應機輸出 |

品項欄位：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `Description` | M | 最多 256 |
| `Quantity` | M | 最多 7 位小數 |
| `Unit` | O | 最多 6 |
| `UnitPrice` | M | 最多 7 位小數。除非 `DetailVat` 為 `0`，否則含稅 |
| `Amount` | M | 最多 7 位小數 |
| `Remark` | O | 最多 120 |
| `TaxType` | M | `1`、`2`、`3` |

回應（最外層，只在成功時）：`invoice_number`、`invoice_time`（Unix 時間）、`random_number`、`barcode`、`qrcode_left`、`qrcode_right`，以及給列印機用的 `base64_data`。金額為 0 的發票，QR code 是空字串，也沒有 `base64_data`。

### 5.2 `f0501`

`data` 是 `{ CancelInvoiceNumber, CancelReason }` 的陣列。`CancelReason` 是 O，最多 20 `[doc]`。回應只有 `code` 和 `msg`。

```json
[{ "CancelInvoiceNumber": "AB00001111", "CancelReason": "作廢原因" }]
```

### 5.3 `g0401`

`data` 是折讓的陣列 `[doc]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `AllowanceNumber` | M | 最多 16，不可重複 |
| `AllowanceDate` | M | `Ymd` |
| `AllowanceType` | M | `2` |
| `BuyerIdentifier` | M | 必須和原發票相符。消費者填 `0000000000` |
| `BuyerName` | M | |
| `BuyerAddress`、`BuyerTelephoneNumber`、`BuyerEmailAddress` | O | |
| `ProductItem` | M | 最多 9999 筆 |
| `TaxAmount` | M | |
| `TotalAmount` | M | 未稅 |

品項：`OriginalInvoiceNumber`、`OriginalInvoiceDate`（`Ymd`）、`OriginalDescription`（最多 256）、`Quantity`、`UnitPrice`（未稅）、`Amount`（未稅）、`Tax`（整數）和 `TaxType` 全部都是 M。

折讓總額，不論單獨計算或和同一張發票的其他折讓合計，都不可以超過發票總額 `[info 71: codes 4040171, 4040173]`。

回應只有 `code` 和 `msg`。文件中的範例，兩台未稅單價 2180 元的機器：

```json
[{ "AllowanceNumber": "3821061800001", "AllowanceDate": "20210618", "AllowanceType": "2",
   "BuyerIdentifier": "0000000000", "BuyerName": "蕭XX",
   "ProductItem": [{ "OriginalInvoiceDate": 20210520, "OriginalInvoiceNumber": "NW93016392",
                     "OriginalDescription": "超聲波清洗機", "Quantity": 2, "UnitPrice": "2180",
                     "Amount": "4360", "Tax": 218, "TaxType": 1 }],
   "TaxAmount": "218", "TotalAmount": "4360" }]
```

### 5.4 `g0501`

`data` 是 `{ CancelAllowanceNumber }` 的陣列 `[doc]`。回應只有 `code` 和 `msg`。

### 5.5 `invoice_query`

請求：`{ "type": "order", "order_id": … }` 或 `{ "type": "invoice", "invoice_number": … }` `[doc]`。

回應的 `data`：

| 欄位 | 意思 |
| --- | --- |
| `invoice_number`、`invoice_date`（`YYYYMMDD`）、`invoice_time`（`HH:mm:ss`） | 發票 |
| `invoice_type`、`invoice_status` | 見 4.4 和 6.3 |
| `order_id` | 訂單編號 |
| `buyer_identifier`、`buyer_name`、`buyer_zip`、`buyer_address`、`buyer_telephone_number`、`buyer_email_address` | 買方 |
| `sales_amount`、`free_tax_sales_amount`、`zero_tax_sales_amount`、`tax_type`、`tax_rate`、`tax_amount`、`total_amount` | MIG 總計 |
| `print_mark`、`random_number`、`main_remark`、`customs_clearance_mark`（非零稅率時為 `0`） | |
| `carrier_type`、`carrier_id1`、`carrier_id2`、`npoban` | |
| `cancel_date` | 作廢時間，Unix 時間 |
| `invoice_lottery` | 獎項代碼（見 `lottery_type`） |
| `detail_vat`、`detail_amount_round`、`create_date` | |
| `product_item` | `tax_type`、`description`、`unit_price`、`quantity`、`unit`、`amount`、`remark` |
| `wait` | 佇列中的變更：`invoice_type`、`create_date` |
| `allowance` | `invoice_type`、`invoice_status`、`allowance_type`、`allowance_number`、`allowance_date`、`tax_amount`、`total_amount` |

文件中的範例（一個品項，佇列中有一筆作廢）：

```json
{ "code": 0, "msg": "", "data": {
  "invoice_number": "AA12301393", "invoice_type": "C0401", "invoice_status": 31,
  "invoice_date": "20221201", "invoice_time": "09:56:38",
  "buyer_identifier": "0000000000", "buyer_name": "客人",
  "sales_amount": 100, "free_tax_sales_amount": 0, "zero_tax_sales_amount": 0,
  "tax_type": 1, "tax_rate": "0.05", "tax_amount": 0, "total_amount": 100,
  "print_mark": "Y", "random_number": "2729", "order_id": "P202212010001",
  "detail_vat": 1, "detail_amount_round": 0, "create_date": 1669859798,
  "product_item": [{ "tax_type": 1, "description": "紅利儲值", "unit_price": 100, "quantity": 1,
                     "unit": "", "amount": 100, "remark": "" }],
  "wait": [{ "invoice_type": "C0501", "create_date": 1670486981 }] } }
```

## 6. 代碼

### 6.1 課稅別

MIG 的代碼：`1` 應稅、`2` 零稅率、`3` 免稅、`4` 特種稅率、`9` 混合。

| Unified | Amego |
| --- | --- |
| `TAXABLE` | `1` |
| `ZERO_RATED` | `2` |
| `TAX_FREE` | `3` |
| `SPECIAL` | `4`（只用在表頭。品項只能是 `1` 到 `3`） |
| （混合，推導） | `9` |

### 6.2 載具類別

| Unified | `CarrierType` | `CarrierId1` 和 `CarrierId2` | 規則 |
| --- | --- | --- | --- |
| `MOBILE_BARCODE` | `3J0002` | 手機條碼 | `^\/[0-9A-Z\+\-\.]{7}$` `[info 74]` |
| `CITIZEN_CERTIFICATE` | `CQ0001` | 自然人憑證 | `^TP[0-9]{14}$` `[info 74]` |
| `MEMBER` | `amego` | `a` 加手機號碼 | `^a09[0-9]{8}$` `[info 73]` |
| `MEMBER` | `amego` | Email | email 地址 |
| （無） | `amego` | 蝦皮帳號 | `^shopee_[A-Za-z0-9_\.]{5,30}$` |
| （無） | `amego` | 露天帳號 | `^ruten_[a-z0-9_\-]{4,24}$` |
| （無） | `amego` | Yahoo 拍賣帳號 | `^yahoo_[Yy][0-9]{10}$` |
| （無） | `amego` | 8591 買家編號 | `^8591_\d{5,7}$` |

顯碼和隱碼必須相同 `[info 71: codes 3040131, 3040133]`。載具中的 email 不會觸發通知信 `[doc]`。

### 6.3 上傳狀態

`1` 待處理、`2` 上傳中、`3` 已上傳、`31` 處理中、`32` 處理完成／待確認、`91` 錯誤、`99` 完成。`-1` 加上類別 `NOT_FOUND` 表示查無此發票 `[doc]`。

### 6.4 錯誤代碼

`[info 71]`。Unified 錯誤和 `Reason` 兩欄是對應方式。代碼 `15` 和 `71` 有 live 實測過。查詢或作廢不存在的發票、作廢不存在的折讓，都得到 `NotFoundError` `[live]`。

**預設類別。** 表外的代碼視為 `ProviderError`。Amego 的常見代碼列得很完整，欄位錯誤也有自己的代碼範圍，所以不認得的代碼比較可能是伺服器的問題，而不是欄位錯誤。

共通代碼：

| 代碼 | 意思 | Unified 錯誤 | `Reason` |
| --- | --- | --- | --- |
| `0` | 成功 | | |
| `10` | 系統維護中 | `ProviderError` | |
| `11`、`12` | `invoice`（統一編號）空白或錯誤 | `AuthError` | `CREDENTIALS_INVALID` |
| `13` | 狀態未啟用 | `AuthError` | `NOT_ENROLLED` |
| `14` | IP 不允許 | `AuthError` | `IP_BLOCKED` |
| `15` | `time` 超出範圍 | `ValidationError` | `STALE_TIMESTAMP` |
| `16` | 簽章錯誤 | `AuthError` | `CREDENTIALS_INVALID` |
| `17` | 資料空白 | `ValidationError` | |
| `18` | 資料庫連線失敗 | `ProviderError` | |
| `19` | 公司已停用 | `AuthError` | `ACCOUNT_SUSPENDED` |
| `20` | `data` 不是 JSON | `ValidationError` | |
| `21` | 使用人數過多，請稍後再試 | `ProviderError` | `RATE_LIMITED` |
| `22` | 尚未申請 API | `AuthError` | `NOT_ENROLLED` |
| `23` | 這個 API 需要陣列 | `ValidationError` | |
| `51` | 超過 180 天查詢期限 | `ProviderError` | |
| `71` | 查無資料 | `NotFoundError` | |
| `99` | 其他錯誤，附訊息 | `ProviderError` | |

`f0401` 的代碼是 `3040xxx`。其他 `30401xx` 代碼都是欄位格式錯誤：`ValidationError`。

| 代碼 | 意思 | Unified 錯誤 | `Reason` |
| --- | --- | --- | --- |
| `3040111` | 字軌不足 | `NumberExhaustedError` | |
| `3040131`、`3040133` | 載具顯碼和隱碼不同 | `ValidationError` | |
| `3040132` | 載具不存在 | `ValidationError` | `CARRIER_NOT_REGISTERED` |
| `3040136`、`3040137` | 捐贈碼格式錯誤，或不存在 | `ValidationError` | |
| `3040162` | 未稅價只限 B2B | `ValidationError` | |
| `3040171` | `OrderId` 重複（註銷重開期間也是） | `ConflictError` | `DUPLICATE_ORDER` |
| `3040172` 到 `3040178` | 金額或總計加總不符 | `ValidationError` | |
| `3040179` | 零稅率缺少通關方式 | `ValidationError` | |
| `3040191` | 無法取得下一個號碼 | `NumberExhaustedError` | |

`f0501` 的代碼：

| 代碼 | 意思 | Unified 錯誤 | `Reason` |
| --- | --- | --- | --- |
| `3050111` | 發票號碼錯誤 | `ValidationError` | |
| `3050113` | 原因超過 20 字 | `ValidationError` | |
| `3050121` | 發票還在開立中 | `ConflictError` | `RETRY_LATER` |
| `3050122` | 已作廢 | `ConflictError` | `ALREADY_VOIDED` |
| `3050123` | 已註銷 | `ConflictError` | |
| `3050125` | 發票不存在 | `NotFoundError` | |
| `3050126` | 超過可變更的期限 | `ConflictError` | `PAST_DEADLINE` |
| `3050131` | 等待佇列中的開立、作廢或註銷 | `ConflictError` | `RETRY_LATER` |
| `3050141` | 發票已有折讓 | `ConflictError` | `VOID_BLOCKED_BY_ALLOWANCE` |

`g0401` 的代碼是 `4040xxx`：

| 代碼 | 意思 | Unified 錯誤 | `Reason` |
| --- | --- | --- | --- |
| `4040145` | 不允許 `AllowanceType` `1` | `ValidationError` | |
| `4040151` | 原發票日期錯誤 | `ValidationError` | |
| `4040153` | 原發票已作廢 | `ConflictError` | `ALLOWANCE_BLOCKED_BY_VOID` |
| `4040154` | 原發票已註銷 | `ConflictError` | |
| `4040156` | 原發票不存在 | `NotFoundError` | |
| `4040157` | 買方統一編號和發票不同 | `ValidationError` | |
| `4040161` | 折讓單號已使用 | `ConflictError` | `DUPLICATE_ALLOWANCE` |
| `4040171`、`4040173` | 折讓金額超過發票總額 | `ValidationError` | |

`g0501` 的代碼：

| 代碼 | 意思 | Unified 錯誤 | `Reason` |
| --- | --- | --- | --- |
| `4050132` | 已作廢 | `ConflictError` | `ALREADY_VOIDED` |
| `4050134` | 折讓不存在 | `NotFoundError` | |
| `4050135` | 超過期限 | `ConflictError` | `PAST_DEADLINE` |
| `4050141` | 等待佇列中的變更 | `ConflictError` | `RETRY_LATER` |

`barcode` 的代碼：`9000111` 空白、`9000112` 格式錯誤、`9000113` 不存在。做載具檢查時，`9000113` 表示「未登記」，不是錯誤。

## 7. 待解問題

1. `invoice_modify` 送出的是哪一種 MIG 訊息？上傳後的修改，聽起來像是 F0701 加上一張新的 F0401。MIG 警告內容錯誤不可以這樣處理。
2. 發票可以作廢的期限是多久？代碼 `3050126` 表示有期限，但文件沒有寫。
3. `f0401` 沒有 `Currency` 或 `ExchangeRate`，但 `f0401_custom` 兩者都有。`f0401` 是否也接受？
4. 查詢把品項的 `remark` 列為最多 40，開立 API 列為最多 120。哪一個才對？
5. Amego 的自然人憑證規則是 `^TP[0-9]{14}$`。ECPay 的是「2 個大寫英文字母加 14 位數字」，core 也照這個檢查。MIG 沒有規定格式。Amego 會拒絕其他英文字母嗎？
6. 陣列型呼叫送多筆時，其中一筆失敗，其他筆會成功嗎？在確認之前，一次只送一筆。
7. live spec 只檢查了主要流程，沒有檢查零稅率、混合稅率、載具和小數數量。
8. payload 裡的空白用 `%20` 送出可以正常運作，對原始 JSON 計算的 `sign` 也能通過 `[live]`。我們沒有測試 `+`，所以不知道 Amego 用的是哪一種 PHP decoder。
