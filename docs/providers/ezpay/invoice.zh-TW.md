# ezPay 簡單行動支付：電子發票 API

[English](invoice.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

## 1. 狀態與來源

> **可信度：** 只依手冊。沒有 adapter，也沒有 live 執行過。4.2 和 6.4 是建議。

ezPay（簡單行動支付股份有限公司）經營 ezPay 電子發票加值服務平台。2.x 還沒有對應的 adapter。這裡的內容都沒有對 live API 驗證過。所以 4.2 和 6.4 是**建議**：依手冊判斷 adapter 應該怎麼做。

手冊屬於簡單行動支付 ezPay，PDF 中也註明版權屬於 ezPay。手冊公開在下載專區：<https://inv.ezpay.com.tw/Invoice_index/download>。本筆記是我們的整理。

| 標記 | 來源 | 版本與日期 | 提供的內容 |
| --- | --- | --- | --- |
| `[inv]` | 電子發票技術串接手冊 標準版，<https://inv.ezpay.com.tw/dw_files/info_api/EZP_INVI_1_2_2.pdf>，72 頁 | EZP_INVI_1.2.2，2024-04-22 | 開立、作廢、折讓、作廢折讓、查詢 |
| `[ces]` | 電子發票技術串接手冊 境外電商版，<https://inv.ezpay.com.tw/dw_files/info_api/EZP_CES_1_0_0.pdf>，65 頁 | EZP_CES_1.0.0，2021-01-26 | 境外電商 |
| `[track]` | 電子發票字軌管理 技術串接手冊，<https://inv.ezpay.com.tw/dw_files/info_api/EZP__Track__1_0_0.pdf>，38 頁 | EZP_Track_1.0.0，2018-10 | 字軌管理 |
| `[bdv]` | 手機條碼與捐贈碼驗證 技術串接手冊，<https://inv.ezpay.com.tw/dw_files/info_api/BDV_1_0_0.pdf>，24 頁 | EZP_BDV_1.0.0，2021-03-03 | 手機條碼與捐贈碼檢查 |

四份都在 2026-10-14 下載。`[inv]` 手冊從 2024 年 4 月以後就沒有更新，最後一次實質的欄位變更是在 2021 年。

**更新檢查。** 下載專區會列出每份手冊的版本和日期。新版本的檔名也會改變，例如 `EZP_INVI_1_2_2.pdf`。

## 2. 連線

### 2.1 主機與帳號

| 環境 | 主機 |
| --- | --- |
| 測試 | `https://cinv.ezpay.com.tw` |
| 正式 | `https://inv.ezpay.com.tw` |

沒有共用的測試帳號。開發者要自己在測試平台註冊、建立測試商店、取得 `HashKey` 和 `HashIV`，並在 管理設定 > 發票字軌號碼設定 新增測試用的字軌號碼 `[inv 三]`。測試和正式的商店是分開的。

商店有 `MerchantID_`（商店代號，最多 15）、`HashKey` 和 `HashIV`。AES-256 需要 32 bytes 的金鑰和 16 bytes 的 IV，和手冊的範例一致。檢查 API 使用相同的主機和商店 `[bdv]`。字軌 API 用會員編號 `CompanyID_`，不用 `MerchantID_` `[track 四]`。

### 2.2 請求

所有 API 都是 UTF-8 的標準表單 POST，有兩個欄位 `[inv 三, 四]`：

| 欄位 | 規則 |
| --- | --- |
| `MerchantID_` | 商店代號。注意結尾的 `_` |
| `PostData_` | 加密後的資料。注意結尾的 `_` |

資料**不是 JSON**，而是把欄位組成 URL query string，和 PHP `http_build_query` 產生的格式相同。接著 `[inv 附件一]`：

1. 用 PKCS#7 把 query string 補齊到 **32 bytes** 的倍數。
2. 用 AES-256-CBC 加密，金鑰為 `HashKey`，IV 為 `HashIV`，不再另外補齊。
3. 轉成小寫的十六進位字串。這就是 `PostData_`。

每份資料都要帶：

| 欄位 | 規則 |
| --- | --- |
| `RespondType` | `JSON` 或 `String`。adapter 應該用 `JSON` |
| `Version` | 每個 API 固定：開立用 `1.5`，折讓和查詢用 `1.3`，其他用 `1.0` |
| `TimeStamp` | Unix 時間 |

`CarrierNum` 的值要先用 `rawurlencode()` 編碼，資料才不會遺失 `[inv 四]`。

### 2.3 回應

`RespondType` 為 `JSON` 時：

```json
{ "Status": "SUCCESS", "Message": "...", "Result": "<a JSON string>" }
```

- `Status` 是 `SUCCESS` 或錯誤代碼（6.4）。
- `Result` 本身是 JSON 字串，所以要再解析一次。查詢結果中的 `ItemDetail` 是包在裡面的另一層 JSON 字串，所以要解析第三次 `[inv 八(二)]`。
- `String` 時，相同的欄位以 query string 回傳，結尾是 `EndStr` `##` `[inv 四]`。

**開立是冪等的。** 如果再次收到資料完全相同的 `PostData_`，ezPay 會回傳 `SUCCESS` 和原本的 `Result` `[inv 四(二)]`。

### 2.4 檢查碼

開立和查詢的結果會帶 `CheckCode`，讓呼叫端確認資料確實由 ezPay 回傳 `[inv 附件二]`：

1. 從結果中取出 `InvoiceTransNo`、`MerchantID`、`MerchantOrderNo`、`RandomNum` 和 `TotalAmt`。
2. 依欄位名稱排序，組成 query string。
3. 在前面加上 `HashIV=...&`，在後面加上 `&HashKey=...`。
4. 做 SHA-256，轉成大寫十六進位。

作廢和折讓的結果也有 `CheckCode`，但它們沒有上面這五個欄位。手冊沒有提供其他算法，所以這些結果沒辦法驗證（見第 7 節）。

檢查 API 改用 `CheckValue`：`HashKey=...&<Result>&HashIV=...` 的 SHA-256，轉成大寫 `[bdv 附件三]`。

### 2.5 範例

手冊中開立發票的回應範例 `[inv 四(二)]`，`Result` 以解析後的內容顯示：

```json
{ "Status": "SUCCESS", "Message": "電子發票開立成功",
  "Result": { "CheckCode": "00E108DF7DE8756AF003312206DA77A4C37AE33990EA04A944C414113D512228",
              "MerchantID": "3502275", "MerchantOrderNo": "201511031758110280",
              "InvoiceNumber": "DS12223139", "TotalAmt": 348,
              "InvoiceTransNo": "15110317583641325", "RandomNum": "4253",
              "CreateTime": "2015-11-03 17:58:36", "BarCode": "10412DS122231394253",
              "QRcodeL": "…", "QRcodeR": "…" } }
```

請求端在加密前是一個 query string，例如（B2C、一個品項、手機條碼）：

```
RespondType=JSON&Version=1.5&TimeStamp=1729000000&MerchantOrderNo=ORDER_1&Status=1
&Category=B2C&BuyerName=消費者&PrintFlag=N&CarrierType=0&CarrierNum=%2FABC1234
&TaxType=1&TaxRate=5&Amt=95&TaxAmt=5&TotalAmt=100
&ItemName=商品一&ItemCount=1&ItemUnit=個&ItemPrice=100&ItemAmt=100
```

這個請求是我們依欄位規則寫的，不是手冊裡的範例。

## 3. 操作

五個 unified 操作使用下列 endpoint。欄位見第 5 節。

| Endpoint | 用途 | 來源 |
| --- | --- | --- |
| `/Api/invoice_issue` | 立即開立、等待觸發開立，或預約開立 | `[inv 四]` |
| `/Api/invoice_invalid` | 作廢發票 | `[inv 五]` |
| `/Api/allowance_issue` | 開立折讓，立即確認或稍後確認 | `[inv 六]` |
| `/Api/allowanceInvalid` | 作廢已確認的折讓 | `[inv 七]` |
| `/Api/invoice_search` | 查詢一張發票，以資料、ezPay 網頁或網址的形式回傳 | `[inv 八]` |

其他 endpoint。adapter 可以透過 `raw` 方法呼叫：

| Endpoint | 用途 | 來源 |
| --- | --- | --- |
| `/Api/invoice_touch_issue` | 立即開立等待觸發或預約的發票 | `[inv 四(三)]` |
| `/Api/allowance_touch_issue` | 確認（`C`）或取消（`D`）待確認的折讓 | `[inv 六(三)]` |
| `/Api/crossBorderInvoiceIssue`、`/Api/crossBorderAllowanceIssue`、`/Api/crossBorderInvoiceSearch` | 境外電商的對應版本 | `[ces]` |
| `/Api_number_management/createNumber`、`manageNumber`、`searchNumber` | 新增、修改和列出字軌 | `[track]` |
| `/Api_inv_application/checkBarCode`、`checkLoveCode` | 手機條碼或捐贈碼是否已登記 | `[bdv]` |

## 4. 對應到 unified API

### 4.1 操作

| Unified | Endpoint | `provider_options`（建議） | 說明 |
| --- | --- | --- | --- |
| `issue` | `invoice_issue`，`Status` `1` | `customs_clearance` | |
| `void` | `invoice_invalid` | 無 | 隔天上傳之前不能作廢 |
| `allowance` | `allowance_issue`，`Status` `1` | `order_id`（M）、`tax_type_for_mixed`、`buyer_email` | 折讓單號由 ezPay 指定 |
| `void_allowance` | `allowanceInvalid` | 無 | |
| `query` | `invoice_search` | `random_code`（用號碼查詢）、`total_amount`（用訂單編號查詢） | 一定需要第二個查詢條件 |

### 4.2 欄位

下面每一列都是建議。

#### `issue`

| Unified | ezPay | 規則或預設值 |
| --- | --- | --- |
| `order_id` | `MerchantOrderNo` | 最多 **20**，英文字母、數字和 `_`。在本地端檢查。其他加值中心允許更長的編號 |
| `category`（或買方的統一編號） | `Category` | `B2B` / `B2C` |
| `buyer.name` | `BuyerName` | M。B2C 沒有名稱時送 `消費者`。B2B 送公司名稱，最多 60 |
| `buyer.ubn` | `BuyerUBN` | 只限 B2B |
| `buyer.address` | `BuyerAddress` | |
| `buyer.email` | `BuyerEmail` | 最多 50。ezPay 會員載具時 M |
| `buyer.phone` | （無） | 開立時沒有這個欄位。捨棄 |
| `carrier.type` | `CarrierType` | `MOBILE_BARCODE` `0`、`CITIZEN_CERTIFICATE` `1`、`MEMBER` `2`。只限 B2C |
| `carrier.code` | `CarrierNum` | 先做 `rawurlencode`。`MEMBER` 沒有 code 時，用買方的 email |
| `donation.npoban` | `LoveCode` | 只限 B2C。不能和載具同時使用 |
| （推導） | `PrintFlag` | B2B 為 `Y`，B2C 沒有載具也沒有捐贈時為 `Y`，其他為 `N` |
| `tax_type`、`items[].tax_type` | `TaxType` | 品項不一致時為 `9`（只限 B2C，否則丟出 `ValidationError`）。`SPECIAL`：見 6.1 |
| `tax_rate` | `TaxRate` | 百分比：`tax_rate × 100`，沒有值時為 `5`。零稅率和免稅為 `0` |
| `amount` | `Amt`、`TaxAmt`、`TotalAmt` | 見 4.3 |
| `items[]` | `ItemName`、`ItemCount`、`ItemUnit`、`ItemPrice`、`ItemAmt`、`ItemTaxType` | 每個欄位都是一個字串，品項之間用 `\|` 分隔。見下方 |
| `price_mode` | （無） | ezPay 依 `Category` 固定：B2B 價格未稅，B2C 價格含稅。不一致的 `price_mode` 丟出 `ValidationError` |
| `remark` | `Comment` | 最多 200 |
| `currency` | （無） | 不是 TWD 時丟出 `UnsupportedError`。境外電商用另一個 API |
| `date`、`exchange_rate` | （無） | 不送 |

品項，每個欄位以 `|` 串接：

| Unified | ezPay | 規則 |
| --- | --- | --- |
| `description` | `ItemName` | 最多 **30**。超過丟出 `ValidationError` |
| `quantity` | `ItemCount` | **整數**。有小數時丟出 `ValidationError` |
| `unit` | `ItemUnit` | M。最多 2 個中文字或 6 個英文字。沒有值時為 `個` |
| `unit_price` | `ItemPrice` | **整數** |
| `amount` | `ItemAmt` | 整數。必須等於 `ItemCount × ItemPrice` |
| `tax_type` | `ItemTaxType` | 只用在混合稅率 |
| `remark` | （無） | 沒有這個欄位。捨棄 |

結果：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `InvoiceNumber` |
| `invoice_date` | `CreateTime`，UTC+8 |
| `random_code` | `RandomNum` |
| `order_id` | `MerchantOrderNo` |
| `total_amount` | `TotalAmt` |
| `status` | `ISSUED` |

先檢查 `CheckCode`（2.4）。

#### `void`

| Unified | ezPay | 規則或預設值 |
| --- | --- | --- |
| `invoice_number` | `InvoiceNumber` | |
| `reason` | `InvalidReason` | 最多 **6 個中文字**或 20 個英文字。在本地端檢查 |
| `date` | （無） | 不需要 |

結果：`invoice_number` 取自 `InvoiceNumber`，`status` 為 `VOIDED`。

#### `allowance`

| Unified | ezPay | 規則或預設值 |
| --- | --- | --- |
| `invoice_number` | `InvoiceNo` | |
| `provider_options[:order_id]` | `MerchantOrderNo` | M。原發票的訂單編號。`AllowanceInput` 沒有這個值，而沒有隨機碼也查不到它 |
| `items[]` | `ItemName`、`ItemCount`、`ItemUnit`、`ItemPrice`、`ItemAmt` | 和開立相同 |
| （計算） | `ItemTaxAmt` | 見 4.3 |
| `amount.total_amount` | `TotalAmt` | 見 4.3 |
| `provider_options[:tax_type_for_mixed]` | `TaxTypeForMixed` | 混合稅率發票時 M |
| `provider_options[:buyer_email]` | `BuyerEmail` | ezPay 把通知寄到這裡 |
| （固定） | `Status` | `1`：立即確認 |
| `allowance_id`、`date` | （無） | 不送。號碼和日期由 ezPay 指定 |

結果：

| Unified | 來源 |
| --- | --- |
| `allowance_number` | `AllowanceNo` |
| `invoice_number` | `InvoiceNumber` |
| `allowance_date` | `nil`。結果中沒有日期 |
| `total_amount` | `AllowanceAmt` |

#### `void_allowance`

| Unified | ezPay | 規則或預設值 |
| --- | --- | --- |
| `allowance_number` | `AllowanceNo` | 最多 25 |
| `reason` | `InvalidReason` | 沒有值時為 `作廢折讓`。最多 6 個中文字 |
| `invoice_number` | （無） | 不送 |

結果：`allowance_number` 取自 `AllowanceNo`。

#### `query`

| Unified | ezPay | 規則或預設值 |
| --- | --- | --- |
| `invoice_number` + `provider_options[:random_code]` | `SearchType` `0`、`InvoiceNumber`、`RandomNum` | |
| `order_id` + `provider_options[:total_amount]` | `SearchType` `1`、`MerchantOrderNo`、`TotalAmt` | |
| 兩組都沒有 | | `ValidationError` |

結果：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `InvoiceNumber` |
| `invoice_date` | `CreateTime`，UTC+8 |
| `random_code` | `RandomNum` |
| `order_id` | `MerchantOrderNo` |
| `status` | 見 4.4 |
| `amount` | `sales = Amt`、`tax = TaxAmt`、`total = TotalAmt` |
| `buyer` | `BuyerName`、`BuyerUBN`、`BuyerAddress`、`BuyerPhone`、`BuyerEmail` |
| `items` | `ItemDetail`（JSON 字串）：`ItemName`、`ItemCount`、`ItemWord`（單位）、`ItemPrice`、`ItemAmount`、`ItemTaxType` |

### 4.3 金額與稅額

unified 的 `AmountSummary` 必須符合 `sales + tax = total`。shared contract 開立 B2C 應稅發票時，傳的是 `sales 100, tax 0, total 100`。

**開立。** ezPay 一律拆出稅額，B2C 也一樣 `[inv 四]`：

- `Amt` 是**未稅**的銷售額合計。混合稅率時，`Amt = AmtSales + AmtZero + AmtFree`。
- `TaxAmt` 是稅額。`TotalAmt = Amt + TaxAmt`。
- B2B 的品項價格未稅，B2C 的品項價格含稅。所以 B2C 的品項合計和 `TotalAmt` 都含稅，但 `Amt` 不含稅。
- ezPay 只檢查 `ItemAmt = ItemCount × ItemPrice` 和 `TotalAmt = Amt + TaxAmt`。其他都由呼叫端負責 `[inv 三]`。

建議：如果 unified 金額是應稅發票但 `tax 0`（contract 的 B2C 形式），計算 `TaxAmt = total - round(total / 1.05)`、`Amt = total - TaxAmt`。其他情況直接送 `sales_amount`、`tax_amount` 和 `total_amount`。

查詢回傳的 B2C 發票也是拆分後的形式：`Amt 1333`、`TaxAmt 67`、`TotalAmt 1400` `[inv 八(二)]`。

**折讓。**

- 品項價格可以含稅，也可以未稅 `[inv 六]`。含稅時，`ItemTaxAmt` 必須是 `0`，買方不能扣抵這筆稅額。
- 未稅時，`ItemTaxAmt = ItemAmt × 稅率`。
- `TotalAmt` 是品項合計加上品項稅額。

建議：B2C 送含稅價格，`ItemTaxAmt` 為 `0`。B2C 發票的買方不會扣抵稅額。B2B 送未稅價格和品項稅額。

**整數。** 品項數量和價格都是整數。unified model 允許小數，所以要在呼叫前檢查。

### 4.4 狀態

`invoice_search` 回傳 `[inv 八(二)]`：

| ezPay | Unified `InvoiceStatus` |
| --- | --- |
| `InvoiceStatus` `1` | `ISSUED` |
| `InvoiceStatus` `2` | `VOIDED` |

查詢結果沒有折讓資料，也沒有註銷狀態。所以 adapter 沒辦法從查詢結果回報 `ALLOWANCE`。

`UploadStatus` 顯示上傳到財政部的狀態：`0` 未上傳、`1` 上傳成功、`2` 上傳中、`3` 上傳失敗、`4` 上傳逾時。

### 4.5 時限

- ezPay 在隔天 01:00 起，把當天的開立、作廢和折讓上傳到財政部。06:00 起，依財政部的回覆更新上傳狀態 `[inv 三]`。
- 發票要**上傳之後**才能作廢（`LIB10009`）`[inv 九]`。所以今天開立的發票，今天不能作廢。
- 上傳失敗的發票不能作廢（`INV70002`）。
- 奇數月 14 日以前，仍然可以作廢前兩個月的發票。例如 7 月 13 日還可以作廢 5、6 月的發票 `[inv 一]`。
- 有折讓的發票不能作廢（`LIB10007`）。
- 待確認的折讓（`Status` `0`）會留在 ezPay，確認之前不會上傳。確認的隔天才上傳 `[inv 一]`。

### 4.6 Capabilities

| Capability | API | 說明 |
| --- | --- | --- |
| `ISSUE`、`VOID`、`ALLOWANCE`、`VOID_ALLOWANCE` | 支援 | 作廢要等到隔天 |
| `QUERY` | 部分支援 | 用號碼查詢時需要隨機碼 |
| `B2B` | 支援 | `Category` `B2B` |
| `MIXED_TAX` | 部分支援 | 只限 B2C |
| `QUERY_BY_ORDER_ID` | 部分支援 | 用訂單編號查詢時需要總額 |
| `SCHEDULED_ISSUE` | 支援 | `Status` `3` 加 `CreateStatusTime` |
| `CARRIER_VALIDATION` | 支援 | `checkBarCode`、`checkLoveCode` |
| `FOREIGN_CURRENCY` | 不支援 | 只有獨立的境外電商 API 支援 |

capability 只有「支援」和「不支援」兩種。遇到「部分支援」時，adapter 要自己決定：宣告支援並在文件寫明需要的額外條件，或是不宣告。

### 4.7 與 MIG 的差異

- **作廢不需要日期。** `invoice_invalid` 和 `allowanceInvalid` 只收號碼和原因。因為 MIG F0501 和 G0501 需要日期，ezPay 會從自己的紀錄補上（推論）。
- **作廢原因很短。** `InvalidReason` 最多 6 個中文字或 20 個英文字 `[inv 五, 七]`。MIG 允許任何 20 個字元。7 到 20 個中文字的原因可以通過 unified 的檢查，但在這裡會失敗。
- **品項欄位比 MIG 小很多。** `ItemName` 最多 30，`ItemUnit` 最多 2 個中文字或 6 個英文字，`ItemCount` 和 `ItemPrice` 是**整數** `[inv 四]`。MIG 允許 500 字元和 7 位小數。
- **`TaxRate` 是百分比。** 送 `5`，不是 `0.05` `[inv 四]`。查詢回傳的是 `0.05` `[inv 八]`。MIG 和其他加值中心都用 `0.05`。
- **混合稅率發票的折讓要拆開。** 一張折讓只涵蓋一種課稅別（`TaxTypeForMixed`）。混合稅率發票的每一種課稅別都要各開一張折讓 `[inv 六]`。
- **折讓價格可以含稅。** MIG G0401 要求未稅金額，以及每個品項的稅額。
- **折讓單號比 MIG 長。** ezPay 回傳的 `AllowanceNo` 最多 20 字元（`allowanceInvalid` 最多 25）。MIG 的 `AllowanceNumber` 最多 16。手冊的範例是 16 字元（`A151015111705007`）。
- **沒有零稅率原因。** 手冊最後一次更新早於 MIG 4.0，沒有 `ZeroTaxRateReason` 欄位。

### 4.8 Contract 與 live 測試

ezPay 不符合 shared contract 的幾個假設：

- **用號碼查詢。** contract 只送 `invoice_number`，ezPay 還需要隨機碼。除非 contract 送 `provider_options`，或 adapter 記住自己開過的發票的隨機碼，否則 adapter 無法通過這個測試。目前兩者都沒有。
- **開立後馬上作廢。** contract 會作廢剛開立的發票。在 live 環境，ezPay 要等隔天上傳後才允許作廢（`LIB10009`）。fake 可以允許。live spec 無法在同一次執行中測試作廢。
- **對已作廢的發票開折讓。** 這個測試要先作廢，所以在 live 環境有同樣的問題。ezPay 沒有「對已作廢發票開折讓」的錯誤代碼，所以不知道能不能對應到預期的 `ConflictError`（見第 7 節）。
- **不存在的發票。** contract 只用 `invoice_number` 查詢不存在的發票，並預期 `NotFoundError`。沒有隨機碼時，建議的 adapter 會在呼叫前丟出 `ValidationError`（4.2）。所以這個測試也會失敗，原因和用號碼查詢相同。
- **不存在的折讓。** ezPay 沒有「查無折讓」的錯誤代碼。最接近的是 `IAI10002`（查詢失敗）（見第 7 節）。
- **折讓需要訂單編號。** contract 不會送這個值。adapter 需要 `provider_options[:order_id]`，或記住自己開過的發票的訂單編號。
- **訂單編號。** 最多 20 字元。contract 的編號（`ORDER_A`……）符合。live spec 產生的長編號可能不符合。
- **測試商店。** 沒有共用的帳號。每位開發者都要在 `cinv.ezpay.com.tw` 開測試商店，並新增測試字軌。

## 5. 欄位參考

### 5.1 `invoice_issue`

`[inv 四(一)]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `RespondType`、`Version`（`1.5`）、`TimeStamp` | M | |
| `TransNum` | O | ezPay 金流交易序號，只限同時使用 ezPay 金流的商店 |
| `MerchantOrderNo` | M | 最多 20。英文字母、數字和 `_`。在商店內不可重複 |
| `Status` | M | `1` 立即開立、`0` 等待觸發開立、`3` 預約開立 |
| `CreateStatusTime` | O | `YYYY-MM-DD`。`Status` 為 `3` 時 M |
| `Category` | M | `B2B` 或 `B2C` |
| `BuyerName` | M | B2B：公司名稱，最多 60，放不下時填統一編號。B2C：姓名或商店使用的識別碼，最多 30 |
| `BuyerUBN` | O | 8 位數字。B2B 時 M |
| `BuyerAddress` | O | 最多 100 |
| `BuyerEmail` | O | 最多 50。ezPay 把開立通知寄到這裡。ezPay 會員載具時 M |
| `CarrierType` | O | 只限 B2C。`0` 手機條碼、`1` 自然人憑證、`2` ezPay 會員載具。沒有載具時空白。有 `LoveCode` 時必須空白 |
| `CarrierNum` | O | 最多 50。有 `CarrierType` 時 M。見 6.2 |
| `LoveCode` | O | 3 到 7 位數字。只限 B2C。有 `CarrierType` 時必須空白 |
| `PrintFlag` | M | `Y` / `N`。B2B 必須是 `Y`，B2C 沒有載具也沒有捐贈時也必須是 `Y` |
| `KioskPrintFlag` | O | `1`：中獎發票可以在全家 FamiPort 列印。只能和 `CarrierType` `2` 一起使用 |
| `TaxType` | M | `1` 應稅、`2` 零稅率、`3` 免稅、`9` 混合（只限 B2C） |
| `TaxRate` | M | 百分比：一般稅額填 `5`，特種稅額填特種稅率（例如 `18`），零稅率和免稅填 `0` |
| `CustomsClearance` | O | `1` / `2`。零稅率時 M |
| `Amt` | M | 未稅銷售額合計。混合稅率時為 `AmtSales + AmtZero + AmtFree` |
| `AmtSales`、`AmtZero`、`AmtFree` | O | 只用在混合稅率。應稅（未稅）、零稅率和免稅銷售額 |
| `TaxAmt` | M | 稅額 |
| `TotalAmt` | M | 含稅總額。`Amt + TaxAmt` |
| `ItemName` | M | 每筆最多 30。品項之間用 `\|` 分隔 |
| `ItemCount` | M | 整數。品項之間用 `\|` 分隔 |
| `ItemUnit` | M | 最多 2 個中文字或 6 個英文字。品項之間用 `\|` 分隔 |
| `ItemPrice` | M | 整數。B2B 未稅，B2C 含稅。品項之間用 `\|` 分隔 |
| `ItemAmt` | M | 整數。`ItemCount × ItemPrice`。品項之間用 `\|` 分隔 |
| `ItemTaxType` | O | 只用在混合稅率。`1`、`2`、`3`。品項之間用 `\|` 分隔 |
| `Comment` | O | 最多 200 |

結果：`InvoiceTransNo`（ezPay 電子發票開立序號）、`MerchantID`、`MerchantOrderNo`、`TotalAmt`、`InvoiceNumber`（只在立即開立時回傳）、`RandomNum`、`CreateTime`（`yyyy-MM-dd HH:mm:ss`）、`CheckCode`，以及列印發票時的 `BarCode`、`QRcodeL`、`QRcodeR`。範例見 2.5。

`invoice_touch_issue` 收等待中發票的 `InvoiceTransNo`、`MerchantOrderNo` 和 `TotalAmt`，全部都是 M。適用於等待觸發（`Status` `0`）和預約（`Status` `3`）的發票 `[inv 四(三)]`。

### 5.2 `invoice_invalid`

`InvoiceNumber` 和 `InvalidReason`（最多 6 個中文字或 20 個英文字），都是 M。結果：`MerchantID`、`InvoiceNumber`、`CreateTime`、`CheckCode` `[inv 五]`。

手冊中的結果範例，`Result` 以解析後的內容顯示：

```json
{ "CheckCode": "01DD7B45A33B9647536D81656C6B3E93B218802480B94EE0674D92D6BDB3204A",
  "MerchantID": "3459997", "InvoiceNumber": "OU00122220", "CreateTime": "2015-07-16 17:00:33" }
```

### 5.3 `allowance_issue`

`[inv 六(一)]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `Version` | M | `1.3` |
| `InvoiceNo` | M | 要折讓的發票 |
| `MerchantOrderNo` | M | 該發票的訂單編號 |
| `ItemName`、`ItemCount`、`ItemUnit`、`ItemPrice`、`ItemAmt` | M | 和開立相同，品項之間用 `\|` 分隔。`ItemPrice` 可以含稅或未稅 |
| `TaxTypeForMixed` | O | 混合稅率發票時 M：這張折讓的課稅別，`1`、`2` 或 `3` |
| `ItemTaxAmt` | M | 價格未稅時為 `ItemAmt × 稅率`。價格含稅時為 `0` |
| `TotalAmt` | M | 折讓總額 |
| `BuyerEmail` | O | ezPay 把折讓通知寄到這裡 |
| `Status` | M | `1` 立即確認、`0` 等待確認 |

結果：`MerchantID`、`AllowanceNo`、`InvoiceNumber`、`MerchantOrderNo`、`AllowanceAmt`、`RemainAmt`（發票剩餘的金額）、`CheckCode`。

手冊中的結果範例，`Result` 以解析後的內容顯示：

```json
{ "MerchantID": "3622183", "AllowanceNo": "A151015111705007", "MerchantOrderNo": "202E19",
  "AllowanceAmt": "500", "RemainAmt": "0", "CheckCode": "F3BB07F4…" }
```

### 5.4 `allowanceInvalid`

`AllowanceNo`（最多 25）和 `InvalidReason`（最多 6 個中文字或 20 個英文字），都是 M。結果：`AllowanceNo`、`CreateTime`、`CheckCode` `[inv 七]`。

### 5.5 `invoice_search`

`[inv 八(一)]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `Version` | M | `1.3` |
| `SearchType` | O | `0` 用號碼加隨機碼（預設），`1` 用訂單編號加總額 |
| `MerchantOrderNo`、`TotalAmt` | O | `SearchType` 為 `1` 時 M |
| `InvoiceNumber`、`RandomNum` | O | `SearchType` 為 `0` 時 M |
| `DisplayFlag` | O | 空白：回傳資料。`1`：呼叫端以表單 POST，由 ezPay 顯示網頁。`2`：回傳該網頁的網址 |

結果欄位 `[inv 八(二)]`：`MerchantID`、`InvoiceTransNo`、`MerchantOrderNo`、`InvoiceNumber`、`RandomNum`、`BuyerName`、`BuyerUBN`、`BuyerAddress`、`BuyerPhone`、`BuyerEmail`、`InvoiceType`（`07` / `08`）、`Category`、`TaxType`、`TaxRate`（這裡是 `0.05` 的形式）、`Amt`、`AmtSales`、`AmtZero`、`AmtFree`（只限混合稅率）、`TaxAmt`、`TotalAmt`、`CarrierType`、`CarrierNum`、`LoveCode`、`PrintFlag`、`KioskPrintFlag`、`CreateTime`、`ItemDetail`、`InvoiceStatus`、`UploadStatus`、`CheckCode`、`BarCode`、`QRcodeL`、`QRcodeR`。

`ItemDetail` 是品項的 JSON 字串：`ItemNum`、`ItemName`、`ItemCount`、`ItemWord`（單位）、`ItemPrice`、`ItemAmount`、`ItemTaxType`。手冊的範例另外有 `ItemTaxRate`、`ItemRateAmt` 和 `ItemAmt`，都是空的。

手冊中的範例（省略部分欄位，`Result` 和 `ItemDetail` 以解析後的內容顯示）：

```json
{ "MerchantID": "3757976", "InvoiceTransNo": "20020310232543048", "MerchantOrderNo": "1580696208",
  "InvoiceNumber": "BA00000007", "RandomNum": "4234", "InvoiceType": "07", "Category": "B2C",
  "TaxType": "1", "TaxRate": "0.05000", "Amt": "1333", "TaxAmt": "67", "TotalAmt": "1400",
  "PrintFlag": "Y", "CreateTime": "2020-02-03 10:23:25",
  "ItemDetail": [{ "ItemNum": "", "ItemName": "商品1", "ItemCount": 1, "ItemWord": "",
                   "ItemPrice": 100, "ItemAmount": 100 }, "…"] }
```

### 5.6 境外電商（`crossBorderInvoiceIssue`）

給境外電商使用（營業稅法第 6 條第 4 款）。流程相同，但 `Currency` 必填，另外有備註用的 `OriginalCurrencyAmount`（2 位小數）和 `ExchangeRate`（5 位小數）。金額可以用外幣。`Comment` 最多 71 `[ces 四]`。

## 6. 代碼

### 6.1 課稅別

| Unified | ezPay `TaxType` | MIG |
| --- | --- | --- |
| `TAXABLE` | `1` | `1` |
| `ZERO_RATED` | `2` | `2` |
| `TAX_FREE` | `3` | `3` |
| `SPECIAL` | `1` 加特種的 `TaxRate`（從 `TaxRate` 的說明推論） | `4` |
| （混合，推導） | `9` | `9` |

手冊沒有列出 `4`（特種稅率）。

### 6.2 載具類別

| Unified | ezPay | 意思 | `CarrierNum` |
| --- | --- | --- | --- |
| `MOBILE_BARCODE` | `0` | 手機條碼（`3J0002`） | `/` 加 7 個 `0-9`、`A-Z`、`+`、`-`、`.` |
| `CITIZEN_CERTIFICATE` | `1` | 自然人憑證（`CQ0001`） | 2 個大寫英文字母加 14 位數字 |
| `MEMBER` | `2` | ezPay 會員載具 | 商店替買方選定的任何識別碼（email、手機、會員編號）。ezPay 用商店的統一編號加上這個識別碼產生載具 |

ezPay 的代碼是它自己定義的，不是 MIG 的代碼，也和 ECPay 的不同。

### 6.3 狀態

`InvoiceStatus`：`1` 已開立、`2` 已作廢。`UploadStatus`：`0` 未上傳、`1` 上傳成功、`2` 上傳中、`3` 上傳失敗、`4` 上傳逾時。見 4.4。

### 6.4 錯誤代碼

`[inv 九]`。Unified 錯誤和 `Reason` 兩欄是建議。`CheckCode` 不符時是 `ProviderError`。

| 代碼 | 意思 | Unified 錯誤 | `Reason` |
| --- | --- | --- | --- |
| `KEY10002` | 資料解密失敗 | `AuthError` | `CREDENTIALS_INVALID` |
| `KEY10004` | 資料不齊全 | `ValidationError` | |
| `KEY10006` | 商店未申請電子發票 | `AuthError` | `NOT_ENROLLED` |
| `KEY10007` | 頁面停留超過 30 分鐘 | `ValidationError` | `STALE_TIMESTAMP` |
| `KEY10010`、`KEY10011`、`KEY10013` | 商店代號、`PostData_` 或資料空白 | `ValidationError` | |
| `KEY10012` | 資料傳遞錯誤 | `ProviderError` | |
| `KEY10014` | 逾時 | `NetworkError` | |
| `KEY10015` | 發票金額格式錯誤 | `ValidationError` | |
| `INV10003`、`INV10004` | 品項資料錯誤，或品項合計錯誤 | `ValidationError` | |
| `INV10006` | 稅率格式錯誤 | `ValidationError` | |
| `INV10012` | 金額和課稅別不符 | `ValidationError` | |
| `INV10013` | 欄位缺少或錯誤 | `ValidationError` | |
| `INV10014` | 訂單編號格式錯誤 | `ValidationError` | |
| `INV10015`、`INV10016` | 沒有銷售額，或沒有稅額 | `ValidationError` | |
| `INV10017` | 這個 `Version` 不支援混合稅率 | `ValidationError` | |
| `INV10019` | 資料含有控制字元 | `ValidationError` | |
| `INV10020`、`INV10021` | 暫停使用，或停止使用 | `AuthError` | `ACCOUNT_SUSPENDED` |
| `INV20006` | 查無發票 | `NotFoundError` | |
| `INV70001` | 欄位格式錯誤 | `ValidationError` | |
| `INV70002` | 上傳失敗的發票不能作廢 | `ConflictError` | |
| `INV90005` | 未簽約，或合約已到期 | `AuthError` | `CONTRACT_EXPIRED` |
| `INV90006` | 可開立的張數已用完 | `NumberExhaustedError` | |
| `NOR10001` | 網路錯誤 | `NetworkError` | |
| `LIB10003` | 訂單編號重複 | `ConflictError` | `DUPLICATE_ORDER` |
| `LIB10005` | 已作廢 | `ConflictError` | `ALREADY_VOIDED` |
| `LIB10007` | 已有折讓，不能作廢 | `ConflictError` | `VOID_BLOCKED_BY_ALLOWANCE` |
| `LIB10008` | 超過作廢期限 | `ConflictError` | `PAST_DEADLINE` |
| `LIB10009` | 尚未上傳，不能作廢 | `ConflictError` | |
| `IAI10001` 到 `IAI10006` | 作廢折讓的錯誤：缺少參數、查詢失敗、更新失敗、參數錯誤、新增失敗、停用 | `ProviderError` | |

錯誤代碼表沒有下列情況的代碼：對已作廢的發票開折讓、折讓不存在，以及折讓重複。

## 7. 待解問題

1. 手冊最後一次更新早於 ezPay 改用 MIG 4.0。ezPay 怎麼補上它不收的 MIG 欄位，例如 `ZeroTaxRateReason`？
2. ezPay 怎麼把 20 字元的 `AllowanceNo` 放進 MIG 的 16 字元？
3. 特種稅額真的是 `TaxType` `1` 加上特種的 `TaxRate` 嗎？
4. 作廢和折讓結果的 `CheckCode` 是怎麼算的？它們沒有手冊算法需要的五個欄位。
5. 對已作廢的發票開折讓，以及作廢不存在的折讓，會回傳哪些代碼？contract 在這兩種情況需要 `ConflictError` 和 `NotFoundError`。
6. **Contract：** 用號碼查詢需要隨機碼，開折讓需要訂單編號。shared contract 應該傳 `provider_options`，還是 adapter 應該記住自己開過的發票？
7. **Core：** 對一律拆出稅額的加值中心來說，`tax 0` 的 B2C `AmountSummary` 代表什麼（4.3）？
8. 這些內容都沒有 live 驗證過。需要在 `cinv.ezpay.com.tw` 開一間測試商店。
