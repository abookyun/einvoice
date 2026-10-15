# Amego 光貿：電子發票 API

[English](api.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

## 1. 狀態與來源

這是 Amego 在 `https://invoice-api.amego.tw` 的 JSON API。2.x 還沒有對應的 adapter。這裡的內容都沒有對 live API 驗證過。所以 4.2 和 6.4 是**建議**：依文件判斷 adapter 應該怎麼做。

文件屬於光貿科技 Amego，公開在 <https://invoice.amego.tw/api_doc/>。本筆記是我們的整理。

這個 API 非常貼近 MIG。endpoint 以 MIG 訊息命名（`f0401`、`f0501`、`g0401`、`g0501`），大部分欄位也用 MIG 的名稱。

| 標記 | 來源 | 日期 | 提供的內容 |
| --- | --- | --- | --- |
| `[doc]` | Amego API 文件，<https://invoice.amego.tw/api_doc/>。用 apiDoc 產生的網站。2026-10-14 讀取資料 bundle（`main.bundle.js?2026093003`）。 | 2026-09-30 產生，文件版本 1.0.0 | 所有 endpoint、欄位、範例和基本規則。 |
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

| Unified | Endpoint | `provider_options`（建議） | 說明 |
| --- | --- | --- | --- |
| `issue` | `f0401` | `track_api_code`、`customs_clearance_mark`、`zero_tax_rate_reason`、`brand_name`、`detail_amount_round`、`tax_adjustment` | 所有 MIG 總計都由 adapter 計算 |
| `void` | `f0501` | 無 | 一次一張發票 |
| `allowance` | `g0401` | `invoice_date`、`buyer`、`allowance_date` | 需要買方資料和發票日期。見 4.2 |
| `void_allowance` | `g0501` | 無 | 一次一張折讓 |
| `query` | `invoice_query` | 無 | 限 180 天內 |

### 4.2 欄位

下面每一列都是建議。

#### `issue`

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `order_id` | `OrderId` | 最多 40。在本地端檢查 |
| `buyer.ubn` | `BuyerIdentifier` | B2C 為 `0000000000` |
| `buyer.name` | `BuyerName` | M。B2C 沒有名稱時送 `消費者`。B2B 沒有名稱時送統一編號。不可以是 `0` 到 `0000` |
| `buyer.address`、`.phone`、`.email` | `BuyerAddress`、`BuyerTelephoneNumber`、`BuyerEmailAddress` | Amego 把開立通知寄到這個 email |
| `carrier`（`MOBILE_BARCODE`） | `CarrierType` `3J0002`，`CarrierId1` = `CarrierId2` = `code` | |
| `carrier`（`CITIZEN_CERTIFICATE`） | `CarrierType` `CQ0001`，兩個 id 都是 `code` | |
| `carrier`（`MEMBER`） | `CarrierType` `amego`，兩個 id 都是 `code` | 沒有 `code` 時，用買方的 email，再沒有就用 `a` 加買方的手機號碼（6.2）。兩者都沒有時丟出 `ValidationError` |
| `donation.npoban` | `NPOBAN` | |
| `remark` | `MainRemark` | 最多 200 |
| `tax_type`、`items[].tax_type` | `TaxType` | 品項的課稅別不一致時為 `9`，否則為該代碼（6.1） |
| `tax_rate` | `TaxRate` | 沒有值時為 `0.05` |
| `price_mode` | `DetailVat` | `TAX_EXCLUSIVE` 為 `0`，否則為 `1`。`0` 只能用在 B2B：B2C 加 `TAX_EXCLUSIVE` 時丟出 `ValidationError` |
| `amount` | `SalesAmount`、`FreeTaxSalesAmount`、`ZeroTaxSalesAmount`、`TaxAmount`、`TotalAmount` | 由品項計算。見 4.3 |
| `items[]` | `ProductItem` | `description` → `Description`（最多 256）、`quantity` → `Quantity`、`unit` → `Unit`、`unit_price` → `UnitPrice`、`amount` → `Amount`、`remark` → `Remark`、`tax_type` → `TaxType`（品項的，沒有就用發票的） |
| `currency` | （無） | 不是 TWD 時丟出 `UnsupportedError`（見第 7 節） |
| `category` | （無） | 決定是否為 B2B，和 core 相同 |
| `date`、`exchange_rate` | （無） | 不送。發票日期由 Amego 設定 |

結果：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `invoice_number` |
| `invoice_date` | `invoice_time`（Unix 時間） |
| `random_code` | `random_number` |
| `order_id`、`total_amount` | 輸入值 |
| `status` | `ISSUED` |

#### `void`

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `invoice_number` | `[0].CancelInvoiceNumber` | |
| `reason` | `[0].CancelReason` | 最多 20 |
| `date` | （無） | 不需要 |

結果：`invoice_number` 取自輸入值，`status` 為 `VOIDED`。

#### `allowance`

`g0401` 需要原發票的買方資料和發票日期，`AllowanceInput` 兩者都沒有。建議：先呼叫 `invoice_query`，從結果取得 `buyer_identifier`、`buyer_name` 和 `invoice_date`。也可以改由 `provider_options` 提供，這樣就不用查詢。查詢只能用在 180 天內的發票。

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `allowance_id` | `AllowanceNumber` | 最多 16。在帳號內不可重複。在本地端檢查 |
| `provider_options[:allowance_date]`，沒有就用今天（UTC+8） | `AllowanceDate` | `Ymd` |
| （固定） | `AllowanceType` | `2` |
| `provider_options[:buyer]`，沒有就用查詢結果 | `BuyerIdentifier`、`BuyerName` | 必須和原發票相符 |
| `invoice_number` | `ProductItem[].OriginalInvoiceNumber` | |
| `provider_options[:invoice_date]`，沒有就用 `date`，再沒有就用查詢結果 | `ProductItem[].OriginalInvoiceDate` | `Ymd`。把 `date` 當成發票日期，是沿用 ECPay adapter 的做法（見第 7 節） |
| `items[]` | `ProductItem[]` | `description` → `OriginalDescription`、`quantity` → `Quantity`、`unit_price` → `UnitPrice`、`amount` → `Amount`，加上 `Tax` 和 `TaxType`。所有金額都是未稅。見 4.3 |
| `amount` | `TaxAmount`、`TotalAmount` | 見 4.3 |

結果：

| Unified | 來源 |
| --- | --- |
| `allowance_number` | 輸入的 `allowance_id`。回應只有 `code` 和 `msg` |
| `invoice_number` | 輸入值 |
| `allowance_date` | adapter 送出的 `AllowanceDate` |
| `total_amount` | 輸入值 |

#### `void_allowance`

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `allowance_number` | `[0].CancelAllowanceNumber` | |
| `invoice_number`、`reason` | （無） | 不送 |

結果：`allowance_number` 取自輸入值。

#### `query`

| Unified | Amego | 規則或預設值 |
| --- | --- | --- |
| `order_id` | `{ "type": "order", "order_id": … }` | 有值時優先使用 |
| `invoice_number` | `{ "type": "invoice", "invoice_number": … }` | |

結果：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `invoice_number` |
| `invoice_date` | `invoice_date`（`YYYYMMDD`）和 `invoice_time`（`HH:mm:ss`），UTC+8 |
| `random_code` | `random_number` |
| `order_id` | `order_id` |
| `status` | 見 4.4 |
| `amount` | 見 4.3 |
| `buyer` | `buyer_name`、`buyer_identifier`（`0000000000` 變成 `nil`）、`buyer_address`、`buyer_telephone_number`、`buyer_email_address` |
| `items` | `product_item[]`：`description`、`quantity`、`unit_price`、`amount`、`unit`、`tax_type`、`remark` |

### 4.3 金額與稅額

unified 的 `AmountSummary` 必須符合 `sales + tax = total`。shared contract 開立 B2C 應稅發票時，傳的是 `sales 100, tax 0, total 100`。

**開立。** Amego 要求所有 MIG 總計，並提供計算公式 `[doc]`。單價含稅時（`DetailVat` 為 `1`）：

```
SalesAmount        = round(sum of Amount where TaxType = 1)
FreeTaxSalesAmount = round(sum of Amount where TaxType = 3)
ZeroTaxSalesAmount = round(sum of Amount where TaxType = 2)
B2C:  TaxAmount = 0
B2B:  TaxAmount = SalesAmount - round(SalesAmount / 1.05)
      SalesAmount = SalesAmount - TaxAmount
TotalAmount = SalesAmount + FreeTaxSalesAmount + ZeroTaxSalesAmount + TaxAmount
```

單價未稅時（`DetailVat` 為 `0`，只限 B2B），`TaxAmount = round(SalesAmount × 0.05)`，其他相同。

建議：用這個公式從品項計算總計。接著檢查 `TotalAmount` 是否等於 `amount.total_amount`；B2B 時另外檢查 `TaxAmount` 是否等於 `amount.tax_amount`。不一致時，在呼叫前丟出 `ValidationError`。B2C 用這個公式會得到 `tax 0`，正好是 contract 的形式。

除非 `DetailAmountRound` 為 `1`，品項金額會保留 7 位小數 `[doc]`。

**折讓。** 金額不含稅，每個品項有自己的整數 `Tax` `[doc]`。`TotalAmount` 是未稅合計，`TaxAmount` 是稅額。

contract 用 `sales 100, tax 0, total 100` 對 B2C 發票開折讓，所以稅額包含在 100 裡。這種情況的建議：用和 B2B 開立相同的方式拆出稅額。`tax = total - round(total / 1.05)`，`TotalAmount = total - tax`。每個品項也用同樣方式拆分，並把四捨五入的差額放在最後一個品項，讓品項的 `Tax` 加總等於 `TaxAmount`。這也是 core 的問題：見第 7 節。

**查詢。** `total_amount` 是總計。`tax_amount` 只有 B2B 才會拆出，和開立時相同。建議：`total = total_amount`、`tax = tax_amount`、`sales = total - tax`。

### 4.4 狀態

`invoice_query` 回報兩件事 `[doc]`：

- `invoice_type`：這張發票最後一次的 MIG 訊息。使用的是 **4.0 以前的名稱**：`C0401` 開立、`C0501` 作廢、`C0701` 註銷、B2B 存證用 `A0401` 和 `A0501`、B2B 交換用 `A0101` 到 `A0302`。
- `invoice_status`：上傳狀態（6.3）。

`wait` 列出還在佇列中的變更，例如還沒處理的作廢。`allowance` 列出這張發票的折讓，每筆有自己的種類和狀態（2024-10-24 新增）。

建議的對應（推論）：

| `invoice_type` | Unified `InvoiceStatus` |
| --- | --- |
| `C0401`、`A0401`、`A0101`、`A0102` | `allowance` 中有尚未作廢的項目（`D0401` / `G0401`，不是 `D0501` / `G0501`）時為 `ALLOWANCE`，否則為 `ISSUED` |
| `C0501`、`A0501`、`A0201`、`A0202` | `VOIDED` |
| `C0701` | 已註銷：沒有對應的 unified 狀態 |
| `A0301`、`A0302` | 已退回：沒有對應的 unified 狀態 |

在 `wait` 中的作廢還沒有完成。在 `invoice_type` 改變之前，發票仍然是 `ISSUED`。

### 4.5 時限

- 只能查詢 180 天內的發票。超過時回傳代碼 `51` `[doc]`。
- 作廢、開立或註銷會進入佇列等待處理。有變更在佇列中時，作廢會回傳 `3050131`。對還在開立中的發票作廢，會回傳 `3050121` `[info 71]`。所以開立後馬上作廢可能會失敗。見 4.8。
- 作廢有期限（`3050126`、`4050135`），但文件沒有寫期限多長（見第 7 節）。
- `invoice_modify` 只能在 180 天內、上傳之後使用 `[info 71]`。

### 4.6 Capabilities

| Capability | API | 說明 |
| --- | --- | --- |
| `ISSUE`、`VOID`、`ALLOWANCE`、`VOID_ALLOWANCE`、`QUERY` | 支援 | |
| `B2B` | 支援 | 在 `BuyerIdentifier` 填統一編號 |
| `MIXED_TAX` | 支援 | `TaxType` `9` |
| `QUERY_BY_ORDER_ID` | 支援 | `invoice_query` 加 `type: order` |
| `SCHEDULED_ISSUE` | 不支援 | 沒有這種 endpoint |
| `CARRIER_VALIDATION` | 部分支援 | `barcode` 可以檢查手機條碼。沒有捐贈碼檢查，這部分可以用 `Einvoice::MOF::DonationCodes` |
| `FOREIGN_CURRENCY` | 未知 | `f0401` 沒有幣別欄位。`f0401_custom` 有（見第 7 節） |

### 4.7 與 MIG 的差異

- **總計就是 MIG 的總計。** `f0401` 收 `SalesAmount`、`FreeTaxSalesAmount`、`ZeroTaxSalesAmount`、`TaxType`、`TaxRate`、`TaxAmount` 和 `TotalAmount`，全部必填，和 F0401 相同。
- **折讓就是 MIG G0401。** `AllowanceNumber` 由賣方指定（最多 16，不可重複）。`AllowanceDate` 必填。金額不含稅，每個品項有自己的 `Tax`。每個品項都需要 `OriginalInvoiceNumber` 和 `OriginalInvoiceDate`。
- **作廢需要的資料比 MIG 少。** `f0501` 只收號碼和選填的原因。`g0501` 只收折讓單號。因為 F0501 和 G0501 要求日期和原因，Amego 必須從自己的紀錄補上（推論）。
- **`AllowanceType` 必須是 `2`。** Amego 從 2025-01-01 起拒絕 `1` `[info 71: code 4040145]`。
- **一張折讓只對應一張發票。** 一張折讓只能折讓一張發票 `[info 71: codes 4040132, 4040133]`。MIG 允許品項來自多張發票。
- **`Description` 最多 256** `[doc]`。MIG 允許 500。
- **B2B 走存證（推論）。** `f0401` 允許統一編號搭配載具欄位和混合稅率，A0101 不允許。查詢仍然可能回報交換類別（A0101 到 A0302），所以 Amego 裡有些發票可能來自交換流程。

### 4.8 Contract 與 live 測試

- **共用的測試帳號。** 所有開發者都用 `12345678` 這個帳號。live spec 必須產生不重複的訂單編號和折讓單號。contract 使用固定的折讓 id（`AL_1`、`AL_AV`），在 live 帳號上可能和別人重複。
- **不存在的號碼。** 使用格式正確的發票號碼，例如 `unknown_invoice_number: "ZZ00000000"`。折讓單號是最多 16 字元的自由文字，所以預設的 `NOPE00000000` 可以用。
- **開立後馬上作廢。** contract 會作廢剛開立的發票。Amego 可能回傳 `3050121`（還在開立中）或 `3050131`（佇列中）`[info 71]`。live spec 可能需要等待後重試。fake 可以忽略這個情況。
- **對 B2C 發票開折讓。** contract 的折讓金額含稅，而且 `tax 0`。adapter 必須拆分（4.3）。
- **折讓需要買方資料。** 採用建議的「先查詢」做法（4.2）時，contract 不用額外的參數就能執行。
- **fake。** fake 需要實作表單封包、`sign` 檢查，以及 2.3 中的回應格式。

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

`[info 71]`。Unified 錯誤和 `Reason` 兩欄是建議。

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
| `3050121` | 發票還在開立中 | `ConflictError` | |
| `3050122` | 已作廢 | `ConflictError` | `ALREADY_VOIDED` |
| `3050123` | 已註銷 | `ConflictError` | |
| `3050125` | 發票不存在 | `NotFoundError` | |
| `3050126` | 超過可變更的期限 | `ConflictError` | `PAST_DEADLINE` |
| `3050131` | 等待佇列中的開立、作廢或註銷 | `ConflictError` | |
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
| `4050141` | 等待佇列中的變更 | `ConflictError` | |

`barcode` 的代碼：`9000111` 空白、`9000112` 格式錯誤、`9000113` 不存在。做載具檢查時，`9000113` 表示「未登記」，不是錯誤。

## 7. 待解問題

1. `invoice_modify` 送出的是哪一種 MIG 訊息？上傳後的修改，聽起來像是 F0701 加上一張新的 F0401。MIG 警告內容錯誤不可以這樣處理。
2. 發票可以作廢的期限是多久？代碼 `3050126` 表示有期限，但文件沒有寫。
3. `f0401` 沒有 `Currency` 或 `ExchangeRate`，但 `f0401_custom` 兩者都有。`f0401` 是否也接受？
4. 查詢把品項的 `remark` 列為最多 40，開立 API 列為最多 120。哪一個才對？
5. Amego 的自然人憑證規則是 `^TP[0-9]{14}$`。ECPay 的是「2 個大寫英文字母加 14 位數字」。MIG 沒有規定格式。哪一個才對？
6. 陣列型呼叫送多筆時，其中一筆失敗，其他筆會成功嗎？在確認之前，一次只送一筆。
7. **Core：** B2C 折讓的 `AmountSummary` 是什麼意思？contract 送的是 `tax 0`，稅額包含在總額裡。Amego 要求拆出稅額（4.3）。
8. **Core：** `AllowanceInput` 的 `date` 是什麼意思？ECPay adapter 把它當成原發票日期。Amego 同時需要原發票日期和折讓日期。
9. 這些內容都沒有 live 驗證過。可以用公開的測試帳號驗證。
