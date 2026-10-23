# Tradevan 關貿：DEFAULTAPI

[English](defaultapi.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

## 1. 狀態與來源

> **可信度：** 沒有公開文件，也沒有帳號。這個 API 透過 1.x client 在正式環境使用中（`[prod]`）。2.x 的 adapter 是實驗性質：它對我們的 fake 通過了 shared contract，但這裡的內容在 2026 年都沒有對 live API 實際執行過。

這是 1.x client 包裝的 API。所有路徑都以 `/DEFAULTAPI/` 開頭。2.x 有一個**實驗性質**的 adapter：`Einvoice::Tradevan::DefaultAPI::Provider`（`lib/einvoice/tradevan/`）。4.2 和 6.4 說明這個 adapter 的做法 `[code]`。

API 文件屬於關貿網路 Tradevan。關貿沒有公開這份文件，也拒絕提供較新的版本給我們。所以沒有公開的連結。本筆記依據 1.x 現有的資料，以及一份正式環境使用者的回報整理而成。本專案目前沒有人有關貿帳號，所以這裡的內容在 2026 年都沒有對 live API 驗證過。

關貿有較新的 API 版本。本筆記只涵蓋 DEFAULTAPI。

| 標記 | 來源 | 日期 | 提供的內容 |
| --- | --- | --- | --- |
| `[summary]` | 我們對關貿 API 文件的摘要，當初為 1.x 撰寫。這份摘要已經不在 repository 中，請見 [v1.5.0](https://github.com/abookyun/einvoice/blob/v1.5.0/docs/Tradevan%20E-Invoice%20APIs.md) 的 `docs/Tradevan E-Invoice APIs.md`。 | 最後修改 2016-05-03 | 加密方式、封包、endpoint 清單、GET 參數。沒有 `issueData` 或 `voidData` 的欄位，也沒有回應格式。 |
| `[readme]` | 1.x README 中的範例（[v1.5.0](https://github.com/abookyun/einvoice/blob/v1.5.0/README.md)） | 2016-04-26 | 開立、作廢、兩種查詢和字軌查詢的請求與回應。看起來是真實的回應，但其中的個人資料是假的。沒有人保存原始回應。 |
| `[rules]` | 1.x 的 validator：`IssueData`、`IssueItem`、`VoidData` 和 `issue_data_validator.rb`（[v1.5.0](https://github.com/abookyun/einvoice/tree/v1.5.0/lib/einvoice/tradevan)） | 2016 | `issueData` 和 `voidData` 欄位及其規則的唯一來源。 |
| `[1x-code]` | 1.x 的 provider、connection 和回應解碼器 | 2016，仍在正式環境使用 | client 實際怎麼組請求、怎麼讀回應。`[1x-code]` 和 `[summary]` 不一致時，`[1x-code]` 是在正式環境執行過的。 |
| `[prod]` | PR [#38](https://github.com/abookyun/einvoice/pull/38)，來自正式環境的使用者 | 2026-09 | 這個 API 在 2026 年仍然可以用。開立、作廢、折讓和作廢折讓都在使用中。API 會拒絕不認得的欄位（見 2.4）。 |
| `[code]` | 2.x adapter（`lib/einvoice/tradevan/`）和它的 fake（`spec/support/fake_tradevan.rb`） | 2026-10 | adapter 怎麼做。不能證明 API 實際的行為。 |
| `[readme-2026]` | 1.x README 中的折讓範例，2026 年加入（[199b803](https://github.com/abookyun/einvoice/commit/199b803)） | 2026-08 | 只有請求。依 `[rules]` 寫成，不是來自真實流量。 |

1.x 的 spec 不算是來源。它們的回應是 2026 年手寫的 stub。

財政部規格見 [../mof/mig-4.1/](../mof/mig-4.1/README.zh-TW.md)，引用時用 `[mig]` 標記。我們手上的 DEFAULTAPI 資料來自 2016 年，比 MIG 4.0（2024）早了好幾年。關貿必須把 DEFAULTAPI 的欄位對應到新的訊息，但我們不知道它怎麼對應。

**更新檢查。** 沒有公開的來源可以追蹤。新的文件只能來自關貿，或來自有帳號的使用者。

## 2. 連線

### 2.1 帳號

關貿給每個特店四個值 `[summary]`：

| 值 | 用途 |
| --- | --- |
| `acnt` | 帳號名稱。放在外層加密的 JSON 裡 |
| `acntp` | 帳號密碼。放在外層加密的 JSON 裡 |
| `key1` | 用來加密每個參數值的 AES 金鑰，也用來解密回應 `[1x-code]` |
| `key2` | 用來加密外層 JSON 的 AES 金鑰 |

特店另外有 `companyUn`（統一編號，8 字元）和 `orgId`（5 字元）。大部分請求都會帶這兩個值。

主機：未知。1.x client 從設定讀取 endpoint，沒有內建預設值。

### 2.2 加密

兩把金鑰使用相同的加密方式 `[summary]` `[1x-code]`：

- AES-128-CBC。IV 就是金鑰本身。
- 不用 PKCS padding。明文用 `\0` 補齊到 16 bytes 的倍數。明文是空字串時，補到 16 bytes。長度已經是 16 的倍數時，不補。
- 密文做 Base64（strict）編碼。

### 2.3 請求

所有 endpoint 都只收一個參數 `v`。它放在 URL query string，POST 的 endpoint 也一樣 `[1x-code]`。1.x client 會送 `Accept: application/json; charset=utf-8`。

`v` 的組法 `[summary]` `[1x-code]`：

1. 每個 API 參數：值是 Hash 時轉成 JSON，否則用 `to_s`。再用 `key1` 加密。
2. 組成一個 JSON 物件：`{ "acnt": ..., "acntp": ..., <名稱>: <加密後的值>, ... }`。這裡的 `acnt` 和 `acntp` 是明文，不用 `key1` 加密。
3. 用 `key2` 加密這個 JSON。結果就是 `v`。

### 2.4 回應

回應的 body 是 JSON `[summary]`：

```json
{ "Success": "Y", "Message": "<text>" }
```

| `Success` | 意思 | `Message` |
| --- | --- | --- |
| `Y` | 成功 | 加密的 JSON |
| `N` | 失敗 | 加密的 JSON |
| `E` | 錯誤 | 明文 |

讀取加密的 `Message`：Base64 解碼、解密、去掉結尾的 `\0`、解析 JSON。

`[summary]` 說要用 `key2` 解密。`[1x-code]` 用的是 `key1`，而這段程式碼在正式環境執行過。請以 `[1x-code]` 為準。1.x 的 spec 兩把金鑰用同一個值，所以分辨不出差別。

`Success` 只是外層的結果。內層的 JSON 有自己的狀態欄位，例如 `issueStatus` 或 `voidStatus` `[readme]`。完整的檢查要兩層都讀。

只要 `issueData` 或 `voidData` 有 schema 以外的欄位，關貿就會拒絕整個請求 `[prod]`。所以絕對不要把不認得的 key 直接傳過去。

### 2.5 範例

1.x README 中的開立範例 `[readme]`，以加密前的內容顯示。`issueData`：

```json
{ "companyUn": "12345678", "orgId": "ABCDE", "type": "I",
  "saleIdentifier": "12345678_ABCDE_53b2a44e4b3c", "transactionNumber": "53b2a44e4b3c",
  "transactionDate": "20160425", "transactionTime": "12:34:56", "total": "20000",
  "paperPrintMode": "0", "invoiceAlarmMode": "4", "donate": "N",
  "carrierType": "3J0002", "carrierId": "TP03000001234567", "carrierIdHidden": "TP03000001234567",
  "receiverName": "John Appleseed", "receiverEmail": "john@gmail.com",
  "itemList": [{ "saleIdentifier": "12345678_ABCDE_53b2a44e4b3c", "serialNumber": "0001",
                 "productName": "Coffee Latte", "qty": "4000", "price": "5",
                 "itemTotal": "20000", "taxType": "T", "tax": "952" }] }
```

解密後的 `Message`：

```json
{ "saleIdentifier": "12345678_ABCDE_53b2a44e4b3c", "issueStatus": "Y", "failReason": "",
  "invoiceNumber": "GX38551078", "checkNumber": "4229",
  "invoiceDate": "20160425", "invoiceTime": "12:34:58",
  "texclusiveAmount": "19048", "oexclusiveAmount": "0", "zexclusiveAmount": "0",
  "tax": "952", "inclusiveAmount": "20000", "mainRemark": "", "invoiceType": "",
  "invoiceStatus": "V", "allowanceNumber": "", "allowanceDate": "",
  "allowanceExclusiveAmount": "", "allowanceTax": "", "allowanceTotalAmount": "0",
  "allowanceStatus": "" }
```

範例中的 `carrierId` 是自然人憑證的格式，但 `carrierType` 卻是手機條碼的代碼。範例資料是假的，不要照抄這個組合。

## 3. 操作

五個 unified 操作使用下列 endpoint。欄位見第 5 節。

| Endpoint | Method | 用途 | 來源 |
| --- | --- | --- | --- |
| `post/issue` | POST | 開立發票或折讓。一個 endpoint，五種類型（見 5.1） | `[summary]` `[rules]` `[readme]` `[prod]` |
| `post/cancel` | POST | 作廢發票或折讓 | `[summary]` `[rules]` `[readme]` `[prod]` |
| `get/searchInvoiceDetail` | GET | 用號碼查詢一張發票，含品項 | `[summary]` `[readme]` |
| `get/searchInvoiceInfoByTransactionnumber` | GET | 用特店的交易編號查詢一張發票 | 只有 `[1x-code]`。`[summary]` 沒有 |

其他 endpoint。adapter 可以透過 `raw` 方法提供：

| Endpoint | Method | 用途 | 來源 |
| --- | --- | --- | --- |
| `get/searchInvoiceByMemberId` | GET | 用會員 ID、載具或 `sellTargetCode`，查詢某段日期內的發票 | `[summary]` `[readme]` |
| `get/getInvoiceContent` | GET | 用號碼或 `sellTargetCode` 查詢發票內容 | `[summary]`。沒有回應範例 |
| `get/sendCardInfotoCust` | GET | 載具歸戶／中獎通知 | `[summary]`。沒有回應範例 |
| `get/getInvoiceMarkInfo` | GET | 某一期的字軌配號 | `[summary]` `[readme]` |
| `get/getDonateUnitList` | GET | 捐贈碼清單。和 `Einvoice::MOF::DonationCodes` 功能重疊 | `[summary]`。沒有回應範例 |

`post/issue` 的 `R`、`G`、`H` 類型（為既有的發票或折讓開立）也沒有對應的 unified 操作。

## 4. 對應到 unified API

### 4.1 操作

| Unified | Endpoint | `provider_options` | 說明 |
| --- | --- | --- | --- |
| `issue` | `post/issue`，type `I` | 無 | 特店設定放在 constructor（見下方） |
| `void` | `post/cancel`，type `I` | `order_id` 或 `sale_identifier`（M） | `VoidInvoiceInput` 沒有訂單編號 |
| `allowance` | `post/issue`，type `A` | `order_id`、`invoice_date` | 回應格式未知 |
| `void_allowance` | `post/cancel`，type `A` | 無 | |
| 用號碼 `query` | `get/searchInvoiceDetail` | 無 | `status` 的意思未知 |
| 用訂單編號 `query` | `get/searchInvoiceInfoByTransactionnumber` | 無 | 不支援：回應格式未知，所以 adapter 丟出 `UnsupportedError`。可以透過 `raw` 呼叫 |

constructor 設定：`acnt`、`acntp`、`key1`、`key2`、`endpoint`（沒有預設值，見 2.1）、`company_un`、`org_id`、`paper_print_mode`、`invoice_alarm_mode`、`invoice_paper_returned`、`allowance_paper_returned`，以及 `member_carrier_type`（特店自己的載具代碼）。

### 4.2 欄位

下表是 adapter 的實際做法 `[code]`。和最初的建議不同的地方，會在該列註明。

#### `issue`

| Unified | 關貿 | 規則或預設值 |
| --- | --- | --- |
| （constructor） | `companyUn`、`orgId` | |
| （固定） | `type` | `I` |
| `order_id` | `transactionNumber` | 最多 50 |
| `order_id` | `saleIdentifier` | `"#{companyUn}_#{orgId}_#{order_id}"`，最多 100。前綴是規則 `[rules]`。後半段是我們的選擇，這樣 `void` 可以從訂單編號重新組出來 |
| `date`，沒有就用現在（UTC+8） | `transactionDate`、`transactionTime` | `yyyyMMdd`、`HH:MM:SS` |
| `amount.total_amount` | `total` | 必須等於 `itemTotal` 的加總 `[rules]` |
| （constructor） | `paperPrintMode`、`invoiceAlarmMode`、`invoicePaperReturned` | 各個值的意思未知（見第 7 節）。在 constructor 中設為必填，不要猜預設值 |
| `buyer.ubn` | `buyerUn` | 只限 B2B |
| `buyer.name` | `buyerTitle`（B2B）、`receiverName` | |
| `buyer.address` | `receiverAddrRoad` | |
| `buyer.email` | `receiverEmail` | |
| `buyer.phone` | `receiverMobile` | 最多 15 |
| `donation.npoban` | `donate` `Y`、`donationUnit` | 否則 `donate` 為 `N`。沒有載具的 B2B 發票不送 `donate`，因為 `donate` 為 `N` 時一定要有載具（已改） |
| `carrier.type` | `carrierType` | `MOBILE_BARCODE` `3J0002`、`CITIZEN_CERTIFICATE` `CQ0001`、`MEMBER` 用 constructor 的 `member_carrier_type` |
| `carrier.code` | `carrierId`、`carrierIdHidden` | 兩者相同。沒有 code 的 `MEMBER` 載具，依序用買方的 email、電話（新增） |
| `items[]` | `itemList` | 見下方 |
| `remark` | （無） | `mainRemark` 只用在 type `G`。捨棄 |
| `tax_type` `SPECIAL` | （無） | 沒有代碼（6.1）。丟出 `UnsupportedError` |
| `price_mode` `TAX_EXCLUSIVE` | （無） | `itemTotal` 含稅，所以丟出 `ValidationError` |
| `currency` | （無） | 不是 TWD 時丟出 `UnsupportedError` |

品項：

| Unified | 關貿 | 規則 |
| --- | --- | --- |
| （表頭） | `saleIdentifier` | 和表頭相同 |
| （序號） | `serialNumber` | 4 位數字：`0001`、`0002`…… |
| `description` | `productName` | 最多 300 |
| `quantity` | `qty` | 見第 7 節第 4 題 |
| `unit_price` | `price` | |
| `amount` | `itemTotal` | 含稅 |
| `tax_type` | `taxType` | `T`、`Z`、`O`（6.1） |
| （計算） | `tax` | 選填。這個品項分攤的稅額 |

結果：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `invoiceNumber` |
| `invoice_date` | `invoiceDate` 和 `invoiceTime`，UTC+8 |
| `random_code` | `checkNumber` |
| `order_id`、`total_amount` | 輸入值 |
| `status` | `ISSUED`。不要讀 `invoiceStatus`（6.3） |

#### `void`

| Unified | 關貿 | 規則或預設值 |
| --- | --- | --- |
| （固定） | `type` | `I` |
| `invoice_number` | `invoiceNumber` | |
| `provider_options[:sale_identifier]`，沒有就用前綴加 `provider_options[:order_id]` | `saleIdentifier` | M。兩者都沒有時丟出 `ValidationError` |
| （constructor） | `invoicePaperReturned` | |
| `reason`、`date` | （無） | 沒有對應欄位。捨棄 |

結果：收到 `voidStatus` `Y` 後，`invoice_number` 取自輸入值，`status` 為 `VOIDED`。

#### `allowance`

| Unified | 關貿 | 規則或預設值 |
| --- | --- | --- |
| （固定） | `type` | `A` |
| `allowance_id` | `transactionNumber`、`allowanceIdentifier` | identifier 使用和 `saleIdentifier` 相同的前綴 |
| 現在（UTC+8） | `transactionDate` | |
| `amount` | `allowanceExclusiveAmount`、`allowanceTax`、`allowanceInclusiveAmount` | 見 4.3 |
| （constructor） | `allowancePaperReturned`、`invoicePaperReturned`、`paperPrintMode`、`invoiceAlarmMode` | |
| 前綴加 `provider_options[:order_id]` | `itemList[].saleIdentifier` | 原發票的 identifier `[readme-2026]` |
| `invoice_number` | `itemList[].invoiceNumber` | |
| `provider_options[:invoice_date]`，沒有就用 `date` | `itemList[].invoiceDate` | M。沒有預設值。把 `date` 當成發票日期，是沿用 ECPay adapter 的做法 |
| `items[]` | `itemList[]` | 和開立相同，另外加上 `itemExclude`（未稅） |

結果：沒有任何來源顯示 type `A` 的回應。adapter 讀取 `allowanceNumber`（type `I` 的回應有這個欄位），日期讀取 `allowanceDate`。如果 `allowanceNumber` 是空的，就丟出 `ProviderError`，並附上原始回應。

#### `void_allowance`

| Unified | 關貿 | 規則或預設值 |
| --- | --- | --- |
| （固定） | `type` | `A` |
| （constructor） | `companyUn`、`allowancePaperReturned` | |
| `allowance_number` | `allowanceNumber` | 16 字元 |
| `invoice_number`、`reason` | （無） | 不送 |

#### `query`

| Unified | 關貿 | 規則或預設值 |
| --- | --- | --- |
| `invoice_number` | `searchInvoiceDetail`：`invoiceNumber` | |
| `order_id` | `searchInvoiceInfoByTransactionnumber`：`companyUn`、`orgId`、`transactionNumber` | 不支援（`UnsupportedError`） |

結果，取自 `searchInvoiceDetail` `[readme]`：

| Unified | 來源 |
| --- | --- |
| `invoice_number` | `invoiceNumber` |
| `invoice_date` | `invoiceDate`、`invoiceTime` |
| `random_code` | `checkNumber` |
| `order_id` | 去掉前綴的 `saleIdentifier` |
| `status` | 見 4.4 |
| `amount` | `sales = exclusiveAmount`、`tax = tax`、`total = total` |
| `buyer` | `receiverName`、`receiverAddr`、`receiverPhone`。回應中沒有 email 和統一編號 |
| `items` | `detailList[]`：`productName`、`qty`、`price`、`total`、`taxType` |

### 4.3 金額與稅額

unified 的 `AmountSummary` 必須符合 `sales + tax = total`。

**開立。**

- 金額放在每個品項上：`itemTotal`（含稅）和選填的 `tax` `[rules]`。
- 表頭的 `total` 必須等於 `itemTotal` 的加總 `[rules]`。
- `[readme]` 中，`itemTotal` 為 20000、`tax` 為 952。回應的 `texclusiveAmount` 為 19048、`tax` 為 952、`inclusiveAmount` 為 20000。所以關貿會自己拆出稅額：`20000 / 1.05 = 19047.6`，四捨五入為 19048。
- adapter 送含稅的 `itemTotal`，不送品項的 `tax`，由關貿計算拆分。

**折讓。**

- 表頭有 `allowanceExclusiveAmount`、`allowanceTax` 和 `allowanceInclusiveAmount` `[rules]`。每個品項有 `itemExclude`（未稅）和 `itemTotal`。
- adapter 把 `sales_amount`、`tax_amount` 和 `total_amount` 對應到這三個表頭欄位。
- 所有品項都是應稅，而且 `tax_amount` 為 `0` 時（contract 的 B2C 形式），稅額包含在總額裡。adapter 會拆出稅額：`exclusive = round(total / 1.05)`、`tax = total - exclusive`。這和 Amego、ezPay 遇到的是同一個 core 問題。
- 每個品項的 `itemExclude` 依金額比例分攤未稅總額。最後一個品項承擔四捨五入的差額，讓品項加總一致。

**查詢。** `exclusiveAmount`、`tax` 和 `total` 直接對應。

### 4.4 狀態

| 關貿 | Unified `InvoiceStatus` |
| --- | --- |
| `hasAllowance` `Y` | `ALLOWANCE` |
| `status` `I` / `V` | `nil`。意思未知（6.3） |

`status` 決定是 `ISSUED` 還是 `VOIDED`，但我們不知道哪個代碼代表哪一個。猜錯的話，會把已作廢的發票回報成已開立。所以 adapter 宣告 `QUERY`，但不猜：除非 `hasAllowance` 為 `Y`，否則 `status` 是 `nil`。原始代碼保留在 `raw["status"]`。

### 4.5 時限

未知。來源沒有提到上傳時間或作廢期限。財政部的規定仍然適用（見 MIG 筆記）。

### 4.6 Capabilities

| Capability | API | Adapter | 說明 |
| --- | --- | --- | --- |
| `ISSUE`、`VOID`、`VOID_ALLOWANCE` | 支援 | 宣告 | 正式環境使用中 `[prod]` |
| `ALLOWANCE` | 支援 | 宣告 | 正式環境使用中 `[prod]`，但回應格式未知 |
| `QUERY` | 部分支援 | 宣告 | 狀態代碼的意思未知，所以 `status` 常常是 `nil` |
| `B2B` | 支援 | 宣告 | `buyerUn` |
| `MIXED_TAX` | 未知 | 不宣告 | 品項有各自的 `taxType`，所以或許可以（推論） |
| `QUERY_BY_ORDER_ID` | 部分支援 | 不宣告 | 只出現在 `[1x-code]`。回應格式未知 |
| `SCHEDULED_ISSUE` | 不支援 | 不宣告 | |
| `CARRIER_VALIDATION` | 不支援 | 不宣告 | 沒有手機條碼檢查。捐贈碼可以用 `Einvoice::MOF::DonationCodes` |
| `FOREIGN_CURRENCY` | 不支援 | 不宣告 | 沒有幣別欄位 |

### 4.7 與 MIG 的差異

- **課稅別是英文字母。** `T`、`Z`、`O` 分別代表 MIG 的 `1`、`2`、`3`（推論）。MIG 的 `4` 和 `9` 沒有對應的字母（6.1）。
- **載具類別就是 MIG 的代碼**（6.2）。
- **type `G` 的 `checkNumber`。** MIG 4.0 已經從 F0401 拿掉 `CheckNumber` `[mig]`。我們不知道關貿現在怎麼處理這個欄位。
- **沒有零稅率的資料。** `issueData` 沒有 `CustomsClearanceMark` 和 `ZeroTaxRateReason` 的欄位，但 F0401 規定零稅率發票必須有這兩個欄位 `[mig 表 15-3]`。關貿必須自己補上，不然零稅率發票無法透過這個 API 開立。
- **沒有作廢原因。** `voidData` 沒有原因欄位。MIG F0501 要求 `CancelReason`，所以由關貿補上（推論）。
- **沒有作廢的發票日期。** `voidData` 沒有發票日期。關貿用 `saleIdentifier` 和 `invoiceNumber` 找出日期（推論）。
- **折讓的每個品項都帶發票日期**，和 MIG G0401 相同。

### 4.8 Contract 與 live 測試

- **沒有 live 測試。** 我們沒有帳號，也沒有主機。
- **只能用 fake。** `spec/support/fake_tradevan.rb` 依照 1.x 的程式碼和 `[readme]` 的範例寫成。它的兩把金鑰用不同的值，所以 `key1` 和 `key2` 用反了會被發現。它會拒絕 schema 以外的欄位，和 `[prod]` 的回報一致。但它的失敗訊息是我們猜的（6.4），所以 contract 通過只能證明「猜的訊息被一致地分類了」。
- **作廢和折讓需要訂單編號和發票日期。** contract 用 `follow_up` 選項傳入：`->(issued) { { order_id: issued.order_id, invoice_date: issued.invoice_date } }`。
- **不存在的折讓單號。** adapter 會在呼叫前檢查折讓單號是否為 16 字元。所以 contract 傳入 16 字元的 `unknown_allowance_number`（`ABCDE20260101999`）。
- **加密。** `crypto_spec.rb` 把密文和 1.x 程式碼的輸出逐 byte 比對。
- **查詢的狀態。** contract 檢查 `found.amount.total_amount`，但不檢查狀態。所以即使狀態代碼的意思還不清楚，也能通過。

## 5. 欄位參考

### 5.1 `post/issue`：`issueData`

只有一個參數 `issueData`，是一個 JSON 物件 `[summary]`。所有值都是字串 `[readme]`。

`type` 決定操作。`[summary]` 列出四種用途，`[rules]` 有五個代碼。下面的對應是從各類型必填的欄位推論出來的。

| `type` | 用途（推論） | 必填 |
| --- | --- | --- |
| `I` | 開立新發票 | `saleIdentifier`、`transactionTime`、`total` |
| `R` | 為既有的發票開立 | 同 `I`，加上 `invoiceNumber` |
| `G` | 為既有的發票開立，含完整表頭 | 同 `R`。允許 `checkNumber`、`invoiceDate`、金額 |
| `A` | 開立新折讓 | `allowanceIdentifier`、折讓金額 |
| `H` | 為既有的折讓開立 | 同 `A`，加上 `saleIdentifier`、`invoiceNumber`、`allowanceNumber`、`allowanceDate` |

表頭欄位 `[rules]`：

| 欄位 | M/O | 規則 | 類型 |
| --- | --- | --- | --- |
| `companyUn` | M | 8 字元 | 全部 |
| `orgId` | M | 5 字元 | 全部 |
| `orgUn` | O | 8 字元 | 全部 |
| `type` | M | `I` `R` `G` `H` `A` | 全部 |
| `transactionNumber` | M | 最多 50 | 全部 |
| `transactionDate` | M | `yyyyMMdd` | 全部 |
| `transactionTime` | M | `HH:MM:SS` | I R G |
| `transactionSource`、`transactionTarget` | O | 最多 50 | 全部 |
| `saleIdentifier` | M | 最多 100，以 `{companyUn}_{orgId}_` 開頭 | I R G H |
| `allowanceIdentifier` | M | 最多 100，相同前綴 | A H |
| `invoiceNumber` | M | 10 字元 | R G H |
| `allowanceNumber` | M | 16 字元，以 `orgId` 開頭 | H |
| `allowanceDate` | M | `yyyyMMdd` | H |
| `allowaDeclaration` | O | 6 位數字（例如 `201803`） | A |
| `total` | M | 最多 20，等於品項 `itemTotal` 的加總 | I R G |
| `allowanceExclusiveAmount` | M | 最多 20 | A H |
| `allowanceTax` | M | 最多 8 | A H |
| `allowanceInclusiveAmount` | M | 最多 20 | A H |
| `allowancePaperReturned` | M | `Y` / `N` | A H |
| `paperPrintMode` | M | `0` 到 `4` | 全部 |
| `invoiceAlarmMode` | M | `0` 到 `6` | 全部 |
| `invoicePaperReturned` | O | `Y` / `N`。`A` 時 M；`buyerUn` 空白且 `paperPrintMode` 不是 `0` 時也是 M | 全部 |
| `donate` | O | 1 字元（`Y` / `N`）。類型為 I R G、`buyerUn` 空白且 `paperPrintMode` 為 `0` 時 M | I R G |
| `donationUnit` | O | 最多 10。`donate` 為 `Y` 時 M | I R G |
| `carrierType` | O | 6 字元。`paperPrintMode` 為 `0`、`donate` 為 `N` 且類型不是 `A` 時 M | A 以外 |
| `carrierId`、`carrierIdHidden` | O | 最多 64。`paperPrintMode` 為 `0` 且 `donate` 為 `N` 時 M | I R G |
| `buyerUn` | O | 8 字元 | A H 以外 |
| `buyerTitle` | O | 最多 60 | A H 以外 |
| `receiverName` | O | 最多 30 | I R G A |
| `receiverAddrZip` | O | 最多 6 | I R G A |
| `receiverAddrRoad` | O | 最多 100 | I R G A |
| `receiverEmail` | O | 最多 80 | I R G A |
| `receiverMobile` | O | 最多 15 | I R G A |
| `idViewId` | O | 最多 10 | 全部 |
| `memberId` | O | 最多 50 | 全部 |
| `tax` | O | 最多 20 | I G |
| `checkNumber` | O | 4 字元 | G |
| `invoiceDate` | O | 8 字元 | G |
| `invoiceTime` | O | 8 字元 | G |
| `texclusiveAmount`、`oeclusiveAmount`、`zexclusiveAmount` | O | 最多 20 | G |
| `mainRemark` | O | 最多 300 | G |
| `invoiceType` | O | `07` / `08` | G |
| `itemList` | M | 陣列，見下方 | 全部 |

`paperPrintMode` 和 `invoiceAlarmMode`：各個值的意思未知。`[readme]` 使用 `0` 和 `4`。

`itemList` 的品項 `[rules]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `saleIdentifier` | M | 最多 100。和表頭相同（`A` 時為原發票的 `saleIdentifier` `[readme-2026]`） |
| `serialNumber` | M | 4 位數字（`0001`） |
| `productName` | M | 最多 300 |
| `qty` | M | 最多 20 |
| `price` | M | 最多 20 |
| `itemTotal` | M | 最多 20 |
| `taxType` | M | `T` / `O` / `Z` |
| `tax` | O | 最多 20 |
| `itemExclude` | O | 最多 20。`A` 和 `H` 時 M |
| `invoiceNumber` | O | 10 字元。`A` 和 `H` 時 M |
| `invoiceDate` | O | 8 位數字。`A` 和 `H` 時 M |
| `invoiceTime` | O | `HH:MM:SS` |
| `productCode` | O | 最多 30 |
| `description` | O | 最多 300 |

1.x 還會拿 `donationUnit` 去比對內建的捐贈碼清單。這是 client 的規則，不是 API 的規則。

### 5.2 `post/issue`：回應

type `I`，成功時 `[readme]`（完整範例見 2.5）：

| 欄位 | 範例 | 說明 |
| --- | --- | --- |
| `saleIdentifier` | `12345678_ABCDE_53b2a44e4b3c` | 原樣回傳 |
| `issueStatus` | `Y` | 內層結果 |
| `failReason` | `""` | 成功時也會有這個欄位 |
| `invoiceNumber` | `GX38551078` | |
| `checkNumber` | `4229` | 隨機碼 |
| `invoiceDate` | `20160425` | |
| `invoiceTime` | `12:34:58` | |
| `texclusiveAmount` | `19048` | 應稅銷售額，未稅 |
| `oexclusiveAmount` | `0` | 免稅銷售額。注意拼字：type `G` 的請求欄位是 `oeclusiveAmount` |
| `zexclusiveAmount` | `0` | 零稅率銷售額 |
| `tax` | `952` | |
| `inclusiveAmount` | `20000` | |
| `mainRemark`、`invoiceType` | `""` | |
| `invoiceStatus` | `V` | 意思未知（6.3） |
| `allowanceNumber`、`allowanceDate`、`allowanceExclusiveAmount`、`allowanceTax`、`allowanceStatus` | `""` | type `I` 時是空的 |
| `allowanceTotalAmount` | `0` | |

其他類型：沒有範例。

### 5.3 `post/cancel`：`voidData`

只有一個參數 `voidData`，是一個 JSON 物件 `[summary]` `[rules]`：

| 欄位 | M/O | 規則 | 類型 |
| --- | --- | --- | --- |
| `type` | M | `C` / `I` / `A` | 全部 |
| `saleIdentifier` | M | 最多 100 | C I |
| `invoiceNumber` | M | 10 字元 | C I |
| `invoicePaperReturned` | M | `Y` / `N` | C I |
| `companyUn` | M | 8 字元 | A |
| `allowanceNumber` | M | 16 字元 | A |
| `allowancePaperReturned` | M | `Y` / `N` | A |

`I` 作廢發票 `[readme]`。`A` 作廢折讓 `[readme-2026]`。`C` 的欄位和 `I` 相同，意思未知。

type `I` 的回應 `[readme]`：

```json
{ "saleIdentifier": "12345678_ABCDE_53b2a44e4b3c", "voidStatus": "Y", "failReason": "",
  "type": "I", "invoiceNumber": "GX38551078", "allowanceNumber": "" }
```

### 5.4 GET endpoint

參數 `[summary]`，另有標記的除外：

| Endpoint | 參數 |
| --- | --- |
| `searchInvoiceDetail` | `invoiceNumber`（M） |
| `searchInvoiceInfoByTransactionnumber` | `companyUn`、`orgId`、`transactionNumber` `[1x-code]` |
| `searchInvoiceByMemberId` | `companyUn`（M）；`memberId`、`carrierId`、`sellTargetCode` 擇一；O `invoiceStartDate`、`invoiceEndDate`（`yyyyMMdd`） |
| `getInvoiceContent` | `invoiceNumber` 或 `sellTargetCode`；O `invoiceStartDate`、`invoiceEndDate`（`yyyyMMdd`） |
| `sendCardInfotoCust` | `companyUn`、`sellTargetCode`（M）；`receiverEmail` 或 `receiverMobile`；O `invoiceStartYM`、`invoiceEndYM`（`yyyyMM`） |
| `getInvoiceMarkInfo` | `companyUn`、`orgId`、`uniFiedNumber`、`bookType`、`period`（`yyyymm`），全部 M |
| `getDonateUnitList` | `companyUn`（M） |

`searchInvoiceDetail` 的回應，一個物件 `[readme]`：

`saleIdentifier`、`invoiceNumber`、`checkNumber`、`invoiceDate`、`invoiceTime`、`exclusiveAmount`、`tax`、`total`、`status`、`hasAllowance`（`Y` / `N`）、`sellerName`、`sellerUN`、`sellerAddr`、`sellerTel`、`receiverName`、`receiverAddr`、`receiverPhone`、`paper`（`Y` / `N`）、`win`（`Y` / `N`）、`donate`（`Y` / `N`）、`carrierType`，以及 `detailList`。每筆 `detailList` 有 `saleIdentifier`、`serialNumber`、`productName`、`qty`、`price`、`total`、`taxType`。

`searchInvoiceByMemberId` 的回應，一個陣列 `[readme]`：表頭欄位和 `searchInvoiceDetail` 相同，但沒有 `receiverPhone` 和 `detailList`，另外多了 `carrierId`。

`getInvoiceMarkInfo` 的回應，一個陣列 `[readme]`：`unifiedNumber`、`bookNumber`、`bookType`、`period`、`duration`、`mark`（字軌，例如 `GX`）、`start`、`end`。

## 6. 代碼

### 6.1 課稅別（`taxType`）

沒有任何來源列出這些代碼。我們從 type `G` 的金額欄位推論：`texclusiveAmount`、`oeclusiveAmount` 和 `zexclusiveAmount`。

| Unified | 關貿 | 意思 | MIG |
| --- | --- | --- | --- |
| `TAXABLE` | `T` | 應稅 | `1` |
| `ZERO_RATED` | `Z` | 零稅率 | `2` |
| `TAX_FREE` | `O` | 免稅 | `3` |
| `SPECIAL` | （無） | | `4` |

三個字母都是推論的。MIG 另外有 `9`（混合，只用在表頭）`[mig 表 4-12]`。DEFAULTAPI 沒有表頭層級的課稅別。

### 6.2 載具類別（`carrierType`）

| Unified | 代碼 | 意思 | 狀態 |
| --- | --- | --- | --- |
| `MOBILE_BARCODE` | `3J0002` | 手機條碼 | MIG 代碼 `[mig 表 4-13]`，`[readme]` 有使用 |
| `CITIZEN_CERTIFICATE` | `CQ0001` | 自然人憑證 | MIG 代碼 `[mig 表 4-13]`，`[readme]` 有使用 |
| `MEMBER` | 特店代碼 | 會員載具 | MIG 說明財政部平台會核發給每個賣方或加值中心自己的 6 字元代碼 `[mig 表 15-3]`。1.x 的 factory 使用 `1K0001` |

`carrierType` 就是 MIG 的欄位，所以 DEFAULTAPI 會原樣傳給財政部（推論）。

### 6.3 狀態

| 欄位 | 看過的值 | 意思 |
| --- | --- | --- |
| `invoiceStatus`（開立回應） | `V` | 未知 |
| `status`（查詢回應） | `I`、`V` | 未知 |
| `issueStatus`、`voidStatus` | `Y` | `Y` 表示成功，`N` 表示失敗。這來自 1.x 的 spec stub，沒有人在真實的回應中看過 |

財政部自己的狀態清單（E0502 `CurrentStatus`）使用數字 `1` 到 `7` `[mig 表 23-2]`。所以 `I` 和 `V` 是關貿自己的代碼，MIG 無法告訴我們它們的意思。

### 6.4 錯誤

沒有錯誤代碼表。失敗時 `Success` 為 `N` 或 `E`，並附上自由文字的 `failReason` 或 `Message`。目前唯一有記錄的失敗訊息是 `duplicated`，而且來自 1.x 的 spec stub，不是真實的回應。

adapter 使用的分類 `[code]`。在知道真實的失敗訊息之前，下表全部都是猜測：

| 情況 | Unified 錯誤 | `Reason` |
| --- | --- | --- |
| HTTP 或 JSON 失敗 | `NetworkError` / `ProviderError` | |
| `Success` 為 `E`，訊息提到帳號、密碼或金鑰 | `AuthError` | `CREDENTIALS_INVALID` |
| `Success` 為 `E`，其他訊息 | `ProviderError` | |
| `failReason` 為 `duplicated`，或包含「重複」／「重覆」 | `ConflictError` | `DUPLICATE_ORDER` |
| 訊息包含「已作廢」／「已被作廢」 | `ConflictError` | `ALREADY_VOIDED` |
| 訊息包含「查無」／「不存在」／not found | `NotFoundError` | |
| 其他 | `ProviderError` | |

預設是 `ProviderError`，不是 `ValidationError`。樣本這麼少，不認得的失敗比較可能是加值中心的問題，而不是輸入錯誤。

## 7. 待解問題

1. 狀態代碼 `V` 和 `I` 是什麼意思？adapter 猜錯的話，會把已作廢的發票回報成已開立。
2. type `A` 的開立回應長什麼樣子？會回傳折讓單號嗎？
3. 關貿會送出哪些失敗訊息？沒有這些訊息，錯誤就無法對應到 `NotFoundError` 或 `ConflictError`。
4. `qty` 有放大嗎？`[readme]` 中的品項 `qty` 為 4000、`price` 為 5、`itemTotal` 為 20000，所以 `qty × price = itemTotal`。`[readme-2026]` 中的品項 `qty` 為 1000、`price` 為 100、`itemTotal` 為 100，看起來 `qty` 是數量乘以 1000。兩者對不上。
5. 測試和正式環境的主機是什麼？
6. 回應要用哪一把金鑰解密，`key1`（`[1x-code]`）還是 `key2`（`[summary]`）？
7. 作廢類型 `C` 和 `I` 有什麼差別？開立類型 `R` 和 `G` 呢？
8. `paperPrintMode` 和 `invoiceAlarmMode` 的各個值是什麼意思？`sellTargetCode` 是什麼？
9. `[summary]` 整理的是關貿文件的哪一個版本？當時沒有記錄。
10. DEFAULTAPI 沒有送零稅率欄位和作廢原因，關貿怎麼補上 MIG 要求的這些欄位？
11. **Core：** 作廢和折讓需要訂單編號，但 unified 輸入沒有這個欄位。contract 現在用 `follow_up` 傳入，但呼叫端仍然要自己放在 `provider_options`。和 ezPay 是同一個問題。
