# ECPay 綠界：B2C 電子發票 API

[English](b2c.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

## 1. 狀態與來源

> **可信度：** 2.x 已有這個 API 的 adapter。五個操作都對 stage API 實際執行並錄製過（2026-08-15）。只標 `[doc]` 的內容沒有實際執行過。

這是 ECPay 的 B2C 電子發票 API，也就是 `/B2CInvoice/` 底下的 AES JSON API。2.x 有對應的 adapter：`Einvoice::ECPay::Provider`（`lib/einvoice/ecpay/`）。

文件屬於綠界科技 ECPay，公開在 <https://developers.ecpay.com.tw/7809/>。本筆記是我們的整理。

B2C API 也可以開立給營業人買方的發票：在 `CustomerIdentifier` 送統一編號即可。ECPay 首頁說明，賣方不需要為此另外使用 B2B API `[doc 7809]`。本筆記不涵蓋 B2B API。

| 標記 | 來源 | 日期 | 提供的內容 |
| --- | --- | --- | --- |
| `[doc]` | ECPay B2C電子發票API技術文件，<https://developers.ecpay.com.tw/7809/>。每個 endpoint 一頁。2026-10-14 讀完全部 44 頁。 | 首頁更新於 2026-03-12，開立發票頁更新於 2026-05-20 | 下面所有沒有其他標記的內容。 |
| `[live]` | 我們的 live spec（`spec/einvoice/ecpay/live_spec.rb`）和它錄下的 VCR cassette（`spec/fixtures/vcr_cassettes/ecpay/`） | 2026-08-15，stage | 真實的請求、回應和錯誤代碼。 |
| `[code]` | 2.x adapter（`lib/einvoice/ecpay/`） | 2026-08 | adapter 目前的做法。它的註解說有些代碼已經 live 驗證過，但沒有 cassette 錄到這些代碼。 |
| `[fixture]` | 另一個 SDK 針對同一個 API 的 wire 與錯誤 fixture。副本放在 `spec/fixtures/shared/ecpay/`，附有來源。我們在 2026-10-28 讀過。 | 傳輸層錯誤由該 SDK 的作者於 2026-08-15 在 stage 實際執行過 | 對方實際看到的錯誤代碼和訊息。 |

`[doc 7896]` 指的是 `https://developers.ecpay.com.tw/7896/` 這一頁。各頁的編號列在第 3 節。

ECPay 把完整的錯誤代碼表放在特店後台，沒有放在公開文件裡 `[doc 7954]`。所以 6.4 的錯誤代碼來自個別頁面和 `[live]`。

**更新檢查。** ECPay 在「更新歷程」頁列出變更：<https://developers.ecpay.com.tw/36050/>。每個 endpoint 頁面也會顯示最後更新的日期。

## 2. 連線

### 2.1 主機與帳號

| 環境 | 主機 |
| --- | --- |
| 測試（stage） | `https://einvoice-stage.ecpay.com.tw` |
| 正式 | `https://einvoice.ecpay.com.tw` |

特店有 `MerchantID`（特店編號）、`HashKey` 和 `HashIV` `[doc 7849]`。正式環境的值在後台的 系統設定 → 系統介接設定 → 介接資訊。

ECPay 公開了共用的測試帳號 `[doc 7849]`。adapter 中的 `Einvoice::ECPay::SANDBOX` 就是這組帳號。

| 帳號 | MerchantID | HashKey | HashIV |
| --- | --- | --- | --- |
| 特店 | `2000132` | `ejCk326UnaZWKisg` | `q9jcZX8Ib9LM8wYk` |
| 平台商 | `3085340`（PlatformID） | `HwiqPsywG1hLQNuN` | `YqITWD4TyKacYXpn` |

stage 環境的財政部平台經常失敗。所以 stage 會把每張發票都標成已上傳，但實際上從來不送到財政部 `[doc 7849]`。stage 也不寄送 email 或簡訊 `[doc 7938, 15391]`。

平台商要送自己的 `PlatformID` 和子特店的 `MerchantID`。一般特店的 `PlatformID` 留空。

### 2.2 請求

所有 endpoint 都是 `POST`、`Content-Type: application/json`，透過 TLS 1.2、port 443 `[doc 7854]`。

```json
{ "MerchantID": "2000132", "RqHeader": { "Timestamp": 1525168923 }, "Data": "<encrypted>" }
```

- `Timestamp` 是 Unix 時間。ECPay 只接受 10 分鐘內的時間。請保持伺服器時鐘同步 `[doc 7896]`。
- `Data` 是加密後的業務資料（2.3）。裡面也必須帶 `MerchantID`。
- 文件的 `RqHeader` 裡沒有 `Revision`。adapter 會送 `"Revision": "3.0.0"`，回應也會原樣回傳 `[live]`。見第 7 節。
- 選填欄位沒有值時，直接不送，不要送 `null`。adapter 會拿掉第一層中值為 `nil` 的欄位 `[code]`。

### 2.3 加密

`[doc 7958]`：

- AES-128-CBC，PKCS7 padding，使用特店的 `HashKey` 和 `HashIV`。兩者都必須是 16 bytes。
- 加密：JSON → URL encode → AES → Base64。
- 解密：Base64 → AES → URL decode → JSON。
- URL encode 的十六進位可以用大寫或小寫。兩者的密文不同，但解密後是同一份 JSON。文件為兩種寫法各提供一組測試向量。

URL encode 用的是 PHP 的 `urlencode`，這是實作最容易出錯的地方 `[code]`：

- 空白要變成 `+`，不是 `%20`。
- 只有 `a-z`、`A-Z`、`0-9`、`-`、`_` 和 `.` 保持原樣。其他每個 byte 都變成 `%XX`，包括 `~` 和 `!*'()`。Ruby 的 `CGI.escape` 不會編碼 `~`，所以結果不一樣。
- 對 UTF-8 的 bytes 做編碼，中文才不會壞掉。

**官方測試向量** `[doc 7958]`。MerchantID `2000132`、HashKey `ejCk326UnaZWKisg`、HashIV `q9jcZX8Ib9LM8wYk`，JSON 為 `{"Name":"Test","ID":"A123456789"}`：

| URL 編碼 | 編碼結果 | 密文 |
| --- | --- | --- |
| 十六進位大寫 | `%7B%22Name%22%3A%22Test%22%2C%22ID%22%3A%22A123456789%22%7D` | `uvI4yrErM37XNQkXGAgRgJAgHn2t72jahaMZzYhWL1HmvH4WV18VJDP2i9pTbC+tby5nxVExLLFyAkbjbS2Dvg==` |
| 十六進位小寫 | `%7b%22Name%22%3a%22Test%22%2c%22ID%22%3a%22A123456789%22%7d` | `ZD/z07UvdmL3aYz0tsVo+bFXF5VldNcns6ezyfea777KOmLiizrUNDYe+v1bh2QTT4AySf1NICgXxWXB6f7c6A==` |

PHP `urlencode` 產生大寫的十六進位，所以加密的結果必須是第一個值。解密時兩個都要能接受。這組向量沒有空白、`~` 或中文，所以測不到上面的規則。crypto spec 另外用自己的向量涵蓋這些情況。

**API 的限制。** 回應沒有簽章。`Data` 是沒有 MAC 的 AES-CBC，`TransCode` 和 `RtnCode` 也不在任何檢查範圍內。`HashIV` 是固定的，所以同樣的請求一定得到同樣的密文。因此，回應的完整性只能靠 TLS。

只有線上折讓的伺服器回呼會用到 `CheckMacValue` `[doc 38242, 15391]`。它是把參數排序並 URL encode 後，前後加上 `HashKey` 和 `HashIV`，再算 MD5。

### 2.4 回應

```json
{ "PlatformID": 0, "MerchantID": 2000132,
  "RpHeader": { "Timestamp": 1786807739, "RqID": "c62778a1-…", "Revision": "3.0.0" },
  "TransCode": 1, "TransMsg": "Success", "Data": "<encrypted>" }
```

結果分成兩層，adapter 兩層都會檢查：

1. `TransCode` 是傳輸層的結果。`1` 表示 ECPay 成功讀取封包。
2. 解密 `Data` 之後的 `RtnCode` 是業務層的結果。`1` 表示成功，少數例外見 6.4。

HTTP 狀態碼也有意義 `[doc 7854]`：

- **403**：呼叫太頻繁。請等 30 分鐘後再呼叫。adapter 丟出帶有 `Reason::RATE_LIMITED` 的 `NetworkError`，讓呼叫端稍後重試。
- **500**：資料格式錯誤、`MerchantID` 和金鑰不符，或加密錯誤。金鑰錯誤時，回傳 HTTP 500 和 `TransCode` 110，`Data` 是空的 `[live]`。

### 2.5 範例

在 stage 開立一張發票，`Data` 以解密後的內容顯示 `[live]`（`issue.yml`）。

請求的 `Data`：

```json
{ "MerchantID": "2000132", "RelateNumber": "RBVCR20260815issue",
  "CustomerID": "", "CustomerIdentifier": "", "CustomerName": "", "CustomerAddr": "",
  "CustomerPhone": "", "CustomerEmail": "test@example.com",
  "Print": "0", "Donation": "0", "LoveCode": "", "CarrierType": "1", "CarrierNum": "",
  "TaxType": "1", "SalesAmount": 100, "InvoiceRemark": "",
  "Items": [{ "ItemSeq": 1, "ItemName": "整合測試商品", "ItemCount": 2, "ItemWord": "式",
              "ItemPrice": 50, "ItemTaxType": "1", "ItemAmount": 100 }],
  "InvType": "07", "vat": "1" }
```

回應的 `Data`：

```json
{ "RtnCode": 1, "RtnMsg": "開立發票成功", "InvoiceNo": "LA25008597",
  "InvoiceDate": "2026-08-15 23:28:58", "RandomNumber": "6049" }
```

其他操作的範例在第 5 節。

### 2.6 回呼

有兩個 endpoint 會回呼特店：延遲開立（`NotifyURL`）和線上折讓（`ReturnURL`）。特店要回覆 `1|OK` `[doc 15369, 15391]`。stage 不會發送 `NotifyURL` 回呼。延遲開立的回呼來自 `postgate.ecpay.com.tw`（stage：`postgate-stage.ecpay.com.tw`）。adapter 不處理回呼。

## 3. 操作

五個 unified 操作使用下列 endpoint。欄位見第 5 節。

| Endpoint | 用途 | 頁面 |
| --- | --- | --- |
| `/B2CInvoice/Issue` | 立即開立發票（一般開立） | 7896 |
| `/B2CInvoice/Invalid` | 作廢發票 | 7906 |
| `/B2CInvoice/Allowance` | 開立紙本折讓（紙本開立） | 7901 |
| `/B2CInvoice/AllowanceInvalid` | 作廢折讓 | 7911 |
| `/B2CInvoice/GetIssue` | 查詢一張發票，用訂單編號，或用號碼加日期 | 7923 |

adapter 另外對應了兩個檢查：`/B2CInvoice/CheckBarcode`（手機條碼是否已登記，頁面 7886）和 `/B2CInvoice/CheckLoveCode`（捐贈碼是否已登記，以及受捐贈單位名稱，頁面 7891）。

其他 endpoint。adapter 可以透過 `Provider#raw` 呼叫：

| Endpoint | 用途 | 頁面 |
| --- | --- | --- |
| `DelayIssue`、`EditDelayIssue`、`TriggerIssue`、`CancelDelayIssue` | 延遲開立、修改、觸發、取消 | 15369, 47979, 15371, 15382 |
| `AllowanceByCollegiate`、`AllowanceInvalidByCollegiate` | 線上折讓：買方透過 email 確認。在確認前取消 | 15391, 7913 |
| `VoidWithReIssue` | 註銷後以同一個號碼重開（註銷重開） | 7918 |
| `GetIssueList`、`GetAllowanceList`、`GetInvalid`、`GetAllowanceInvalid` | 列出發票或折讓，查詢一筆作廢 | 17229, 7928, 7933, 7943 |
| `GetCompanyNameByTaxID` | 檢查統一編號並取得公司名稱 | 32089 |
| `InvoiceNotify`、`InvoicePrint` | 發送通知、取得可列印的頁面 | 7938, 7949 |
| `GetGovInvoiceWordSetting`、`AddInvoiceWordSetting`、`UpdateInvoiceWordStatus`、`GetInvoiceWordSetting` | 字軌與號碼區間 | 7859, 7870, 7875, 7881 |
| `GetInvoiceNotifySetting`、`InvoiceNotifySetting`、`GetRemainNotifySetting`、`RemainNotifySetting` | 通知設定與號碼不足提醒（2026-06-23 新增） | 63356, 64067, 64079, 64088 |
| `QueryBlankInvoiceList`、`BlankInvAutoUploadSetting`、`DownLoadBlankInvList` | 空白未使用字軌（E0402） | 64106, 64122, 64133 |

所有路徑都以 `/B2CInvoice/` 開頭。頁面 49890 是開立發票頁的舊版副本（「一般開立發票 - MIG 4.0」，2025-01-22 更新），缺少較新的欄位。請用 7896。

## 4. 對應到 unified API

### 4.1 操作

| Unified | Endpoint | Reference 欄位 | `provider_options` |
| --- | --- | --- | --- |
| `issue` | `Issue` | | `customer_id`、`clearance_mark`、`zero_tax_rate_reason`、`special_tax_type`、`data`（合併任何 `Issue` 的原始欄位） |
| `void` | `Invalid` | `invoice_datetime` | |
| `allowance` | `Allowance` | `invoice_datetime` | `allowance_notify`、`notify_mail`、`notify_phone`、`customer_name`、`reason` |
| `void_allowance` | `AllowanceInvalid` | 折讓 reference 的 `invoice_number` | |
| `query` | `GetIssue` | `order_id`，或 `number` 加上 `invoice_datetime` | |

`provider_options` 的鍵可以是字串或 symbol。

**缺少發票日期時。** `void`、`allowance` 和用號碼查詢都需要發票日期。如果 reference 沒有 `invoice_datetime`，但有 `order_id`，adapter 會先用 `RelateNumber` 呼叫 `GetIssue`，取得 `IIS_Create_Date`。否則丟出 `ValidationError`，指出缺少 `invoice_datetime`。只給發票號碼是不夠的。查詢失敗時，adapter 丟出帶有 `LOOKUP_FAILED` 的 `ProviderError`（[unified model](../README.zh-TW.md#unified-model)）。

**作廢折讓缺少發票號碼時。** `AllowanceInvalid` 需要 `InvoiceNo`。只給折讓單號時沒有這個值，所以丟出 `ValidationError`，指出缺少 `invoice_number`。

### 4.2 欄位

#### `issue`

| Unified | ECPay | 規則或預設值 |
| --- | --- | --- |
| `order_id` | `RelateNumber` | 最多 50 |
| `buyer.ubn` | `CustomerIdentifier` | 只有 B2B 才送。B2C 為空 |
| `buyer.name`、`.address`、`.phone`、`.email` | `CustomerName`、`CustomerAddr`、`CustomerPhone`、`CustomerEmail` | 沒有時送空字串。列印的發票（`Print` 為 `1`）需要姓名和地址 `[doc 7896]` |
| `carrier.type` | `CarrierType` | `MEMBER` 為 `1`、`CITIZEN_CERTIFICATE` 為 `2`、`MOBILE_BARCODE` 為 `3` |
| `carrier.code` | `CarrierNum` | `MEMBER` 時為空，ECPay 用 email 或手機建立載具 |
| `donation.npoban` | `LoveCode` | 同時送 `Donation` `1`。可以同時帶載具（4.7） |
| （推導） | `Print` | 有載具或捐贈時為 `0`，否則為 `1` |
| `tax_type`、`items[].tax_type` | `TaxType` | 品項的課稅別不同時為 `9`，否則為對應代碼（6.1） |
| `tax_type` | `InvType` | `SPECIAL` 為 `08`，否則為 `07` |
| `price_mode` | `vat` | `TAX_EXCLUSIVE` 為 `0`，否則為 `1` |
| `amount.total_amount` | `SalesAmount` | 見 4.3 |
| `tax_rate` | （無） | ECPay 依 `TaxType` 決定稅率。應稅發票的稅率不是 `0.05` 時，丟出 `UnsupportedError`。`SPECIAL` 用 `special_tax_type` |
| `provider_options[:clearance_mark]` | `ClearanceMark` | 有零稅率品項時必填 |
| `provider_options[:zero_tax_rate_reason]` | `ZeroTaxRateReason` | `71` 到 `79`，原樣送出。自 2026-01-01 起，`TaxType` 為 `2` 和 `9` 時 ECPay 要求必填，但也可以在後台設定，所以 adapter 無法檢查 |
| `remark` | `InvoiceRemark` | |
| `items[]` | `Items` | 見下方 |
| `currency` | （無） | 不是新台幣時丟出 `UnsupportedError` |
| `amount.sales_amount`、`amount.tax_amount`、`exchange_rate` | （無） | 不送出 |

品項：

| Unified | ECPay | 規則或預設值 |
| --- | --- | --- |
| （序號） | `ItemSeq` | 1、2、3、… |
| `description` | `ItemName` | |
| `quantity` | `ItemCount` | |
| `unit` | `ItemWord` | 沒有時為 `式` |
| `unit_price` | `ItemPrice` | |
| `tax_type` | `ItemTaxType` | 品項的課稅別，沒有時用發票的，再沒有就是應稅 |
| `amount` | `ItemAmount` | |
| `remark` | `ItemRemark` | 有給才送 |

結果：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `InvoiceNo` |
| `invoice_datetime` | `InvoiceDate`（日期和時間），UTC+8 |
| `random_code` | `RandomNumber` |
| `order_id`、`total_amount` | 輸入值 |
| `status` | `ISSUED` |
| `reference` | 用上面的欄位組成 |

#### `void`

| Unified | ECPay | 規則或預設值 |
| --- | --- | --- |
| `invoice` | `InvoiceNo` | |
| `invoice.invoice_datetime` | `InvoiceDate` | UTC+8 的 `yyyy-MM-dd`。缺少時見 4.1 |
| `reason` | `Reason` | 最多 20 |

結果：`invoice_number` 取自輸入值，`status` 為 `VOIDED`，`cancel_datetime` 為 `nil`。回應裡沒有作廢時間。

#### `allowance`

| Unified | ECPay | 規則或預設值 |
| --- | --- | --- |
| `invoice` | `InvoiceNo` | |
| `invoice.invoice_datetime` | `InvoiceDate` | 原發票日期，UTC+8 的 `yyyy-MM-dd` |
| `provider_options[:allowance_notify]` | `AllowanceNotify` | 沒有時為 `N`（不通知） |
| `provider_options[:customer_name]`、`[:notify_mail]`、`[:notify_phone]`、`[:reason]` | `CustomerName`、`NotifyMail`、`NotifyPhone`、`Reason` | 有給才送 |
| `amount.total_amount` | `AllowanceAmount` | 含稅。見 4.3 |
| `items[]` | `Items` | 同 `issue`。`ItemAmount` 是品項金額加上它的稅額（4.3） |
| `allowance_id` | （無） | 不送出。ECPay 自己配折讓單號 |

結果：

| Unified | 來源 |
| --- | --- |
| `allowance_number` | `IA_Allow_No`（16 位數字） |
| `invoice_number` | `IA_Invoice_No`，沒有時用輸入值 |
| `allowance_date` | `IA_Date` 的日期部分，UTC+8 |
| `total_amount` | 輸入值 |
| `reference` | `allowance_number`、`allowance_date`、`invoice_number` |

#### `void_allowance`

| Unified | ECPay | 規則或預設值 |
| --- | --- | --- |
| `allowance.invoice_number` | `InvoiceNo` | 缺少時見 4.1 |
| `allowance` | `AllowanceNo` | |
| `reason` | `Reason` | 最多 20。沒有時 core 補上 `作廢折讓` |

結果：`allowance_number` 取自輸入值，`cancel_datetime` 為 `nil`。

#### `query`

| Unified | ECPay | 規則或預設值 |
| --- | --- | --- |
| `invoice.order_id` | `RelateNumber` | 有就使用 |
| `invoice.number` | `InvoiceNo` | 沒有訂單編號時才用 |
| `invoice.invoice_datetime` | `InvoiceDate` | 只和 `InvoiceNo` 一起送，此時必填 |

結果：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `IIS_Number` |
| `invoice_datetime` | `IIS_Create_Date`，UTC+8 |
| `random_code` | `IIS_Random_Number` |
| `order_id` | `IIS_Relate_Number` |
| `status` | 見 4.4 |
| `amount` | 見 4.3 |
| `buyer` | `IIS_Customer_Name`、`_Addr`、`_Phone`、`_Email`，以及作為 `ubn` 的 `IIS_Identifier`。`0000000000` 和空字串轉成 `nil` |
| `items` | `Items`：`ItemName`、`ItemCount`、`ItemPrice`、`ItemAmount`、`ItemWord`、`ItemTaxType`、`ItemRemark`。整數維持整數 |
| `reference` | 用上面的欄位組成，`total_amount` 取 `IIS_Sales_Amount` |

### 4.3 金額與稅額

unified 的規則見 [unified model](../README.zh-TW.md#unified-model)。

**開立。**

- B2C 和 B2B 都把 `amount.total_amount` 當成 `SalesAmount` 送出，也就是含稅金額 `[doc 7896]`。`sales_amount` 和 `tax_amount` 不送出。稅額由 ECPay 計算：`round(SalesAmount / 1.05 × 0.05)`。混合稅率時，用應稅品項的合計計算 `[doc 7896]`。
- `vat` 為 `1` 時，`SalesAmount` 必須等於 `ItemAmount` 加總後四捨五入的值，否則 ECPay 回傳 `5000022` `[live]`。adapter 在呼叫前會檢查。
- `vat` 為 `0` 時，總計由 ECPay 自己計算。
- 品項金額最多可以有 7 位小數，只有加總會四捨五入 `[doc 7896]`。

**折讓。**

- 經過 core 處理後，每個折讓品項都有不含稅的金額，以及自己的稅額（G0401）。ECPay 要的是含稅金額 `[doc 7901]`。所以 `ItemAmount` 是品項金額加上它的稅額，`AllowanceAmount` 是 `amount.total_amount`。
- `ItemAmount` 和 `ItemPrice × ItemCount` 最多可以差 1。`ItemAmount` 的加總必須等於 `AllowanceAmount`。adapter 在呼叫前會檢查。
- ECPay 會再替財政部把稅額拆出來（4.7）。

**查詢。**

- `IIS_Sales_Amount` 是含稅總計。`IIS_Tax_Amount` 只有 B2B 才有值，B2C 為 `0` `[doc 7923]` `[live]`。
- 結果是 `total = IIS_Sales_Amount`、`tax = IIS_Tax_Amount`、`sales = total - tax`。B2C 發票讀回來時稅額為 `0`，和 F0401 給消費者看的格式一致。

### 4.4 狀態

`GetIssue` 用三個欄位回報狀態 `[doc 7923]`。adapter 依照這個順序判斷：

| ECPay | Unified `InvoiceStatus` |
| --- | --- |
| `IIS_Issue_Status` 為 `0`（註銷） | `nil` |
| `IIS_Invalid_Status` 為 `1` | `VOIDED` |
| `IIS_Remain_Allowance_Amt` 小於 `IIS_Sales_Amount`（且銷售額大於 0） | `ALLOWANCE` |
| 其他 | `ISSUED` |

實際看到的情況 `[live]`：作廢的發票 `IIS_Invalid_Status` 為 `1`，`IIS_Remain_Allowance_Amt` 為 `0`。總計 100 的發票折讓 50 之後，`IIS_Remain_Allowance_Amt` 為 `50`。

`IIS_Upload_Status`（`1` 表示已上傳）和 `IIS_Turnkey_Status`（`C` 表示財政部已接受，`E` 表示上傳失敗）顯示上傳到財政部的狀況。adapter 不讀這兩個欄位。

### 4.5 時限

- 作廢、折讓和作廢折讓會在隔天上傳到財政部 `[doc 7906, 7901, 7911]`。開立的發票在 48 小時內上傳 `[doc 7809]`。
- 發票開立後可以馬上作廢 `[live]`。折讓開立後可以馬上作廢 `[live]`。
- 奇數月 13 日 23:59:59 之後，前兩個月的發票和折讓就不能作廢。例如 3 月 14 日起，1、2 月的發票就關帳了 `[doc 7906, 7911]`。
- 註銷重開必須在該期結束後下個月 13 日之前完成 `[doc 7918]`。
- 紙本折讓（`Allowance`）仍然需要買方在紙本上簽名，由賣方寄送並保存。線上折讓（`AllowanceByCollegiate`）改用 email 連結取代簽名，連結 72 小時內有效 `[doc 7901, 15391]`。

### 4.6 Capabilities

| Capability | API | Adapter | 說明 |
| --- | --- | --- | --- |
| `ISSUE`、`VOID`、`ALLOWANCE`、`VOID_ALLOWANCE`、`QUERY` | 有 | 有 | |
| `B2B` | 有 | 有 | 透過 B2C API 帶統一編號 |
| `MIXED_TAX` | 有 | 有 | `TaxType` `9` 需要 ECPay 核准 `[doc 7896]`。品項的課稅別不同時，adapter 送出 `9` |
| `QUERY_BY_ORDER_ID` | 有 | 有 | `RelateNumber` |
| `SCHEDULED_ISSUE` | 有 | 無 | 有 `DelayIssue`，adapter 沒有對應 |
| `CARRIER_VALIDATION` | 有 | 有 | `validate_carrier` 對手機條碼呼叫 `CheckBarcode` |
| `FOREIGN_CURRENCY` | 無 | 無 | B2C API 沒有幣別欄位 |

### 4.7 與 MIG 的差異

- **B2B 走存證（F0401），不走交換（推論）。** B2C API 接受統一編號加上載具，也允許混合稅率。MIG A0101 兩者都不允許。所以 ECPay 一定是用 F0401 上傳這些發票。這回答了 MIG 筆記待解問題第 4 條在 ECPay 的情況。
- **捐贈的發票可以帶載具** `[doc 7896]`，表示買方事後才捐出發票。MIG 也允許。
- **折讓金額含稅。** `AllowanceAmount` 和 `ItemAmount` 都含稅 `[doc 7901]`。MIG G0401 要求未稅金額，以及每個品項的稅額。拆稅由 ECPay 處理。它的折讓查詢兩者都會回傳：`IA_Total_Amount`（未稅）和 `IA_Total_Tax_Amount`（含稅），以及每個品項的 `ItemRateAmt` `[doc 7928]`。
- **作廢折讓不需要折讓日期。** MIG G0501 要求必填，所以 ECPay 一定是從自己的紀錄補上 `[doc 7911]`。
- **作廢和用號碼查詢需要發票日期**，和 MIG F0501 一樣 `[doc 7906, 7923]`。
- **最多 999 個品項** `[doc 7896]`。MIG 允許 9999 個。
- **作廢和作廢折讓的原因是 1 到 20 字元** `[doc 7906, 7911]`，和 MIG 一樣。折讓的原因（`Allowance` 的 `Reason`）最多 50 字元。

### 4.8 Contract 與 live 測試

- **離線 contract。** `spec/einvoice/ecpay/provider_spec.rb` 對 `spec/support/fake_ecpay.rb` 執行 shared contract。fake 使用真實的外層格式、加密方式和 `RtnCode`。
- **不存在的號碼。** ECPay 會先檢查格式，所以 contract 收到 `unknown_invoice_number: "ZZ00000000"` 和 `unknown_allowance_number: "9999999999999999"`。
- **Reference。** contract 會把 `issue` 回傳的 reference 傳給後面的步驟，所以一定有 `invoice_datetime`。
- **共用 fixture。** 另一個 SDK 公開了這個 API 的 wire fixture。spec 會執行放在 `spec/fixtures/shared/ecpay/` 的副本。unified model 刻意不同的 case 會跳過，並寫出原因。
- **Live spec。** `spec/einvoice/ecpay/live_spec.rb` 在設定 `ECPAY_LIVE=1` 時對 stage 執行。stage 帳號和所有開發者共用，所以每次執行都會產生不重複的訂單編號（`RB` 加上時間和亂數）。
- **錄製的 spec。** `spec/einvoice/ecpay/recorded_spec.rb` 重播 `spec/fixtures/vcr_cassettes/ecpay/` 裡的 cassette。
- **stage 測不到的事。** stage 不會上傳到財政部，也不會寄 email、簡訊或 `NotifyURL` 回呼 `[doc 7849, 15369]`。所以上傳狀態、通知和回呼都無法在 stage 上檢查。

## 5. 欄位參考

### 5.1 `Issue`

`Data` 的欄位 `[doc 7896]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `MerchantID` | M | 最多 10 |
| `RelateNumber` | M | 最多 50。不可重複。不可有特殊符號。不分大小寫（`abc` = `ABC`） |
| `ChannelPartner` | O | `1` 蝦皮。其他值會被忽略 |
| `CustomerID` | O | 最多 20。英文字母、數字、`_` |
| `ProductServiceID` | O | 1 到 10 個英文字母或數字。只在特店開啟「B2C系統多組字軌」時使用 |
| `CustomerIdentifier` | O | 8 位數字。買方的統一編號 |
| `CustomerName` | O | 最多 60。`Print` 為 `1` 時 M。有統一編號時填公司名稱 |
| `CustomerAddr` | O | 最多 100。`Print` 為 `1` 時 M |
| `CustomerPhone` | O | 最多 20，數字。`CustomerEmail` 空白時 M |
| `CustomerEmail` | O | 最多 80，一個地址。`CustomerPhone` 空白時 M |
| `ClearanceMark` | O | `1` / `2`。`TaxType` 為 `2` 或 `9` 時 M |
| `Print` | M | `0` / `1`。只標示特店會列印這張發票。ECPay 不會列印或寄送 |
| `Donation` | M | `0` / `1` |
| `LoveCode` | O | 3 到 7 位數字，可以 `0` 開頭。`Donation` 為 `1` 時 M |
| `CarrierType` | O | 空白、`1` 綠界載具、`2` 自然人憑證、`3` 手機條碼、`4` 悠遊卡、`5` 一卡通 |
| `CarrierNum` | O | 最多 64。見下方 |
| `CarrierNum2` | O | 最多 64。`4` 和 `5` 時 M：卡片的顯碼。`1` 到 `3` 時留空 |
| `TaxType` | M | `1` 應稅、`2` 零稅率、`3` 免稅、`4` 特種稅率、`9` 混合（需要核准）。`InvType` 為 `07` 時：`1`、`2`、`3` 或 `9`。為 `08` 時：`3` 或 `4` |
| `ZeroTaxRateReason` | O | `71` 到 `79`。2026-01-01 起，`TaxType` 為 `2` 或 `9` 時 M，除非已在後台設定 |
| `SpecialTaxType` | O | `TaxType` 為 `1`、`2`、`9` 時為 `0`。為 `3` 時為 `8`。為 `4` 時為 `1` 到 `8`（6.3） |
| `SalesAmount` | M | 整數，含稅，只能是新台幣，最多 12 位 |
| `TaxAmount` | O | 整數，最多 11 位。沒有提供時由 ECPay 計算。有提供時，和 ECPay 的計算結果最多差 1。特種稅額時為 `0` |
| `InvoiceRemark` | O | 最多 200。`\r\n`、`\r` 或 `\n` 會換行 |
| `Items` | M | 1 到 999 筆 |
| `InvType` | M | `07` 一般稅額、`08` 特種稅額 |
| `vat` | O | `1` 單價含稅（預設）、`0` 單價未稅 |

`CarrierNum` 依 `CarrierType`：

| 類別 | `CarrierNum` |
| --- | --- |
| 空白 | 空白 |
| `1` | 空白。ECPay 用 email 或手機產生載具，email 優先 |
| `2` | 16 字元：2 個大寫英文字母加 14 位數字 |
| `3` | 8 字元：`/` 加 7 個 `0-9`、`A-Z`、`+`、`-`、`.` |
| `4`、`5` | M。卡片的隱碼。不檢查 |

品項欄位：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `ItemSeq` | O | 1 到 999 |
| `ItemName` | M | 最多 500 |
| `ItemCount` | M | 8 位，小數點後最多 7 位 |
| `ItemWord` | M | 最多 6。單位 |
| `ItemPrice` | M | 10 位，小數點後最多 7 位。是否含稅依 `vat` |
| `ItemTaxType` | O | `1`、`2`、`3`。`TaxType` 為 `9` 時 M，其他情況會被忽略 |
| `ItemAmount` | M | 含稅。12 位，小數點後最多 7 位 |
| `ItemRemark` | O | 最多 120 |

跨欄位規則 `[doc 7896]`：

- `ItemAmount` 的加總四捨五入後，必須等於 `SalesAmount`。`vat` 為 `0` 且 `TaxType` 為 `1` 時，`ItemPrice × ItemCount × 1.05 = ItemAmount`。
- 混合稅率（`9`）可以是應稅加免稅，或應稅加零稅率。不能是免稅加零稅率。
- 捐贈（`Donation` 為 `1`）：`Print` 必須是 `0`，`CustomerIdentifier` 必須空白。可以有載具：表示買方之後才把發票捐出。
- 有統一編號時：`Donation` 必須是 `0`。沒有載具時 `Print` 為 `1`。載具為 `1` 或 `2` 時 `Print` 為 `0`。載具為 `3` 時兩者都可以。
- 有統一編號且 `Print` 為 `1` 時，只允許載具 `3`。

文件和 API 的行為不一定一致。adapter 的檢查依照 stage 實際的行為 `[live]`：

- B2C 有載具的發票不可以列印（`5000015`）。
- 不列印的 B2B 發票需要載具（`5000028`）。
- 零稅率發票需要 `ClearanceMark`（`5000007`）。adapter 只在有零稅率品項時要求這個欄位，`TaxType` 為 `9` 時也一樣（見第 7 節）。

回應的 `Data`：`RtnCode`、`RtnMsg`、`InvoiceNo`、`InvoiceDate`（`yyyy-MM-dd HH:mm:ss` 或 `yyyy/MM/dd HH:mm:ss`）、`RandomNumber`。範例見 2.5。

### 5.2 `Invalid`（作廢發票）

`InvoiceNo`（10）、`InvoiceDate`（`yyyy-MM-dd` 或 `yyyy/MM/dd`）和 `Reason`（最多 20）都是 M。回應有 `InvoiceNo` `[doc 7906]`。

有折讓的發票，要等它的所有折讓都作廢後才能作廢。

範例 `[live]`（`void.yml`）：

```json
{ "MerchantID": "2000132", "InvoiceNo": "LA25008598", "InvoiceDate": "2026-08-15", "Reason": "整合測試作廢" }
{ "RtnCode": 1, "RtnMsg": "作廢發票成功", "InvoiceNo": "LA25008598" }
```

### 5.3 `Allowance`（紙本折讓）

`[doc 7901]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `InvoiceNo` | M | 10 |
| `InvoiceDate` | M | `yyyy-MM-dd` 或 `yyyy/MM/dd` |
| `AllowanceNotify` | M | `S` 簡訊、`E` email、`A` 兩者、`N` 不通知 |
| `CustomerName` | O | 最多 60 |
| `NotifyMail` | O | 最多 100。多個地址以 `;` 分隔。`E` 時 M |
| `NotifyPhone` | O | 最多 20，數字。`S` 時 M |
| `AllowanceAmount` | M | 整數，含稅，大於 0。最多為發票總額，或扣除先前折讓後的剩餘金額 |
| `Reason` | O | 最多 50 |
| `Items` | M | `ItemSeq`、`ItemName`、`ItemCount`、`ItemWord`、`ItemPrice` 和 `ItemAmount` 是 M。混合稅率時 `ItemTaxType` 是 M |

- `ItemAmount` 含稅，和 `ItemPrice × ItemCount` 的差距最多 1。
- `ItemAmount` 的加總必須等於 `AllowanceAmount`。
- ECPay 建議使用整數，因為財政部要求折讓金額是整數。

回應：`IA_Allow_No`（16）、`IA_Invoice_No`、`IA_Date`（`yyyy-MM-dd HH:mm:ss`）、`IA_Remain_Allowance_Amt`。

範例 `[live]`（`allowance.yml`）：

```json
{ "MerchantID": "2000132", "InvoiceNo": "LA25008600", "InvoiceDate": "2026-08-15",
  "AllowanceNotify": "N", "AllowanceAmount": 50,
  "Items": [{ "ItemSeq": 1, "ItemName": "整合測試商品", "ItemCount": 1, "ItemWord": "式",
              "ItemPrice": 50, "ItemTaxType": "1", "ItemAmount": 50 }] }
{ "RtnCode": 1, "RtnMsg": "折讓單資料新增成功", "IA_Allow_No": "2026081523293352",
  "IA_Invoice_No": "LA25008600", "IA_Date": "2026-08-15 23:29:03", "IA_Remain_Allowance_Amt": 50 }
```

`AllowanceByCollegiate` 使用相同的欄位，但 `AllowanceNotify` 固定為 `E`，並多一個回呼用的 `ReturnURL`。買方點擊連結後，折讓才會成立 `[doc 15391]`。

### 5.4 `AllowanceInvalid`（作廢折讓）

`InvoiceNo`（10）、`AllowanceNo`（16）和 `Reason`（最多 20）都是 M。回應有 `IA_Invoice_No` `[doc 7911]`。

範例 `[live]`（`allowance.yml`）。成功時的訊息看起來像錯誤，所以只在 `RtnCode` 不是 `1` 時才比對訊息：

```json
{ "MerchantID": "2000132", "InvoiceNo": "LA25008600", "AllowanceNo": "2026081523293352", "Reason": "作廢折讓" }
{ "RtnCode": 1, "RtnMsg": "該折讓單已作廢", "IA_Invoice_No": "LA25008600" }
```

### 5.5 `GetIssue`（查詢）

請求：`RelateNumber`，或 `InvoiceNo` 加 `InvoiceDate` `[doc 7923]`。

unified model 會用到的回應欄位：

| 欄位 | 意思 |
| --- | --- |
| `IIS_Number` | 發票號碼 |
| `IIS_Relate_Number` | 訂單編號 |
| `IIS_Identifier` | 買方統一編號。沒有時為 `0000000000` |
| `IIS_Customer_Name`、`IIS_Customer_Addr`、`IIS_Customer_Phone`、`IIS_Customer_Email` | 買方 |
| `IIS_Category` | 有統一編號為 `B2B`，沒有為 `B2C` |
| `IIS_Type` | `07` / `08` |
| `IIS_Tax_Type` | `1`、`2`、`3`、`4`、`9` |
| `IIS_Tax_Rate` | 稅率，2 位小數 |
| `IIS_Tax_Amount` | 稅額。**只有 B2B 發票才有值。** B2C 為 `0`，因為稅額包含在金額裡 |
| `IIS_Sales_Amount` | 發票金額，含稅 |
| `IIS_Create_Date` | 開立時間，`yyyy-MM-dd HH:mm:ss` |
| `IIS_Random_Number` | 隨機碼 |
| `IIS_Issue_Status`、`IIS_Invalid_Status`、`IIS_Remain_Allowance_Amt` | 狀態（4.4） |
| `IIS_Upload_Status`、`IIS_Turnkey_Status` | 上傳到財政部的狀態（4.4） |
| `IIS_Carrier_Type`、`IIS_Carrier_Num` | 載具。卡片（`4`、`5`）只有顯碼 |
| `IIS_Love_Code` | 捐贈碼 |
| `IIS_Print_Flag` | `1` / `0` |
| `IIS_Award_Flag`、`IIS_Award_Type` | 中獎結果 |
| `Items` | `ItemSeq`、`ItemName`、`ItemCount`、`ItemWord`、`ItemPrice`（含稅）、`ItemTaxType`、`ItemAmount`（含稅）、`ItemRemark` |

`IIS_Check_Number` 已經不再使用 `[doc 7923]`。stage 仍然在這個欄位回傳 `"P"` `[live]`。

範例 `[live]`（`void.yml`，作廢之後；省略部分欄位）：

```json
{ "MerchantID": "2000132", "RelateNumber": "RBVCR20260815void" }
{ "IIS_Number": "LA25008598", "IIS_Relate_Number": "RBVCR20260815void", "IIS_Identifier": "0000000000",
  "IIS_Customer_Email": "test@example.com", "IIS_Type": "07", "IIS_Category": "B2C",
  "IIS_Tax_Type": "1", "IIS_Tax_Rate": 0.05, "IIS_Tax_Amount": 0, "IIS_Sales_Amount": 100,
  "IIS_Carrier_Type": "1", "IIS_Create_Date": "2026-08-15 23:28:59",
  "IIS_Issue_Status": "1", "IIS_Invalid_Status": "1", "IIS_Upload_Status": "1", "IIS_Turnkey_Status": "C",
  "IIS_Remain_Allowance_Amt": 0, "IIS_Print_Flag": "0", "IIS_Random_Number": "1457",
  "RtnCode": 1, "RtnMsg": "查詢成功" }
```

查詢回應的 `RtnCode` 和 `RtnMsg` 在最後面，排在 `Items` 之後 `[live]`。

## 6. 代碼

### 6.1 課稅別

| Unified | ECPay `TaxType` | MIG |
| --- | --- | --- |
| `TAXABLE` | `1` | `1` |
| `ZERO_RATED` | `2` | `2` |
| `TAX_FREE` | `3` | `3` |
| `SPECIAL` | `4` | `4` |
| （混合，推導） | `9` | `9` |

這些就是 MIG 的代碼。

### 6.2 載具類別

| Unified | ECPay | 意思 | MIG `CarrierType` |
| --- | --- | --- | --- |
| `MEMBER` | `1` | 綠界會員載具 | ECPay 自己的代碼 |
| `CITIZEN_CERTIFICATE` | `2` | 自然人憑證 | `CQ0001` |
| `MOBILE_BARCODE` | `3` | 手機條碼 | `3J0002` |
| （無） | `4` | 悠遊卡，2025-04-17 起 | 卡片載具代碼 |
| （無） | `5` | 一卡通，2025-04-17 起 | 卡片載具代碼 |

### 6.3 特種稅額類別（`SpecialTaxType`）

`1` 25%、`2` 15%、`3` 2%、`4` 1%、`5` 5%、`6` 和 `7` 5%、`8` 免稅或非銷項特種稅額。各代碼對應的行業列在頁面 7896 `[doc 7896]`。adapter 透過 `provider_options[:special_tax_type]` 直接傳遞。

### 6.4 結果代碼

adapter 先查代碼表，查不到再比對訊息。同一種狀況在不同 endpoint 可能回傳不同的代碼，所以訊息比對很重要。只在代碼不是成功時才比對訊息。

`TransCode`（傳輸層）：

| 代碼 | 意思 | Unified 錯誤 | `Reason` | 來源 |
| --- | --- | --- | --- | --- |
| `1` | 封包已接受 | | | `[doc]` |
| `104` | Timestamp 誤差超過 10 分鐘。HTTP 500 | `AuthError` | `STALE_TIMESTAMP` | `[fixture]` |
| `110` | `Data` 無法解密（金鑰或 IV 錯誤）。HTTP 500 | `AuthError` | `CREDENTIALS_INVALID` | `[live]` |
| `111` | `Data` 是空的。HTTP 500 | `ProviderError` | | `[fixture]` |
| `115` | 商店尚未開通 B2C 或 B2B 功能（B2C/B2B功能尚未開通）。HTTP 500 | `AuthError` | `NOT_ENROLLED` | `[fixture]` |
| 其他 | | `ProviderError` | | |

`RtnCode`（業務層）：

| 代碼 | 意思 | Unified 錯誤 | `Reason` | 來源 |
| --- | --- | --- | --- | --- |
| `1` | 成功 | | | `[doc]` |
| `4000003` | 延遲開立的發票已觸發，將在 `DelayDay` 天後開立。對 `TriggerIssue` 而言是成功 | | | `[doc 15371]` |
| `4000004` | 延遲開立的發票已觸發並開立。對 `TriggerIssue` 而言是成功 | | | `[doc 15371]` |
| `2` | `GetIssue`：查無發票資料 | `NotFoundError`（依訊息） | | `[live]` |
| `1600003` | 無發票號碼資料 | `NotFoundError` | | `[code]` |
| `2000039` | 查無折讓單資料 | `NotFoundError` | | `[live]` |
| `2000042` | 已作廢的發票不能折讓 | `ConflictError` | `ALLOWANCE_BLOCKED_BY_VOID` | `[live]` |
| `2000063` | 折讓單已作廢 | `ConflictError` | `ALREADY_VOIDED` | `[fixture]` |
| `4000001` | 交易單號不存在（不存在此交易單號） | `NotFoundError` | | `[fixture]` |
| `1100040` | 字軌已用完（發票字軌已用完） | `NumberExhaustedError` | | `[fixture]` |
| `5070250` | 已經同意的線上折讓單無法取消 | `ConflictError` | | `[fixture]` |
| `5000007` | 零稅率缺少通關方式 | `ValidationError` | | `[code]` |
| `5000015` | B2C 載具發票不可列印 | `ValidationError` | | `[code]` |
| `5000022` | `SalesAmount` 和品項金額不符 | `ValidationError` | | `[live]` |
| `5000028` | 不列印的 B2B 發票需要載具 | `ValidationError` | | `[code]` |
| `5070350`、`1500047` | 沒有可用的字軌或號碼。請確認字軌已新增並啟用，而且還沒用完 | `NumberExhaustedError`（依訊息） | | `[doc 7954]` |
| `5070357` | `RelateNumber` 重複 | `ConflictError` | `DUPLICATE_ORDER` | `[live]` |
| `5070450` | 發票已有折讓，不能作廢 | `ConflictError` | `VOID_BLOCKED_BY_ALLOWANCE` | `[live]` |
| `5070453` | 發票已作廢 | `ConflictError` | `ALREADY_VOIDED` | `[live]` |
| `9000001` | 財政部 API 失敗（維護中）。請稍後再試 | `NetworkError` | | `[doc 7886]` |
| `1200125` | 統一編號檢查碼錯誤。請停止開立 | | | `[doc 32089]` |
| `2027000` | 統一編號不是 8 位數字。請停止開立 | | | `[doc 32089]` |
| `7` | 統一編號不在公開資料中。可以繼續開立 | | | `[doc 32089]` |

對 `GetCompanyNameByTaxID` 來說，`RtnCode` `1` 表示找到公司名稱。ECPay 找不到名稱時，號碼仍然可能是正確的。有些職工福利委員會、政府機關和醫院不在公開資料中 `[doc 32089]`。

不在代碼表中的代碼，依訊息比對 `[code]`：

| 訊息包含 | Unified 錯誤 | `Reason` |
| --- | --- | --- |
| 財政部 … 失敗 或 維護、呼叫 … API失敗 | `NetworkError` | |
| 金鑰、簽章、未授權 | `AuthError` | `CREDENTIALS_INVALID` |
| 特店 … 不存在、平台商 … 不存在 | `AuthError` | `NOT_ENROLLED` |
| 字軌 … 用罄 / 用完 / 不足 / 已滿 | `NumberExhaustedError` | |
| 作廢 … 不能 | `ConflictError` | `ALLOWANCE_BLOCKED_BY_VOID` |
| 已作廢、已被作廢 | `ConflictError` | `ALREADY_VOIDED` |
| 已折讓、折讓過 | `ConflictError` | `VOID_BLOCKED_BY_ALLOWANCE` |
| 重複、重覆 | `ConflictError` | `DUPLICATE_ORDER` |
| 已開立、已存在、同意 | `ConflictError` | |
| 查無、查不到、無 … 資料、不存在 | `NotFoundError` | |
| 系統錯誤 / 異常 / 忙碌、請稍後 | `ProviderError` | `RATE_LIMITED` |
| 其他 | `ValidationError` | |

**預設類別。** 不認得的業務代碼視為 `ValidationError`。在 stage 上，代碼表以外的代碼幾乎都是欄位錯誤 `[live]`，共用 fixture 也鎖定同樣的預設值 `[fixture]`。

ECPay 會寫「重複」也會寫「重覆」，會寫「已作廢」也會寫「已被作廢」。兩種寫法都要比對。

## 7. 待解問題

1. **`RqHeader.Revision`。** adapter 送出 `Revision: "3.0.0"`，註解說文件標示為必填。但目前的文件完全沒有列出 `Revision` `[doc 7896]`。stage 接受沒有這個欄位的請求 `[code]`。註解要修改，這個欄位也許可以拿掉。
2. **混合稅率的通關方式。** 文件要求只要 `TaxType` 是 `9` 就必須有 `ClearanceMark`。adapter 只在混合的品項裡有零稅率時才要求，並說明有 live 驗證過（`5000007`）。應稅加免稅的情況，哪一個才對？
3. **卡片載具。** 悠遊卡和一卡通（`4`、`5`）沒有對應的 unified `CarrierType`。
4. **B2B API。** ECPay 另外有 B2B 發票 API。它走的是 MIG 的交換流程嗎？我們需要它嗎？
5. **403 的 body。** ECPay 會送什麼？adapter 用不到，但有樣本可以讓 fake 更貼近真實。
