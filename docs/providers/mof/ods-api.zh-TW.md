# 財政部 MOF：電子發票開放資料 API

[English](ods-api.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

## 1. 狀態與來源

> **可信度：** `Einvoice::MOF::DonationCodes` 使用這個 API。它發出的請求都實際執行並錄製過（2026-08-17）。

這是財政部提供電子發票資料集的開放資料 API。它不是加值中心，但 2.x 用到其中一個 endpoint：`Einvoice::MOF::DonationCodes`（`lib/einvoice/mof/donation_codes.rb`）從這裡讀取捐贈碼清單。

這個 API 和其資料屬於財政部財政資訊中心。API 的規格公開在一份 OpenAPI 文件中。本筆記是我們的整理。

| 標記 | 來源 | 日期 | 提供的內容 |
| --- | --- | --- | --- |
| `[doc]` | 電子發票開放資料Open API服務，OpenAPI 3.0.1，<https://www.einvoice.nat.gov.tw/portal/ods/openapi.json>。2026-10-14 讀取。 | 版本 `v1` | 所有 endpoint、參數和回應欄位。 |
| `[live]` | 我們的 live spec（`spec/einvoice/mof/live_spec.rb`）和它錄下的 cassette（`spec/fixtures/vcr_cassettes/mof/`） | 2026-08-17 | 真實的請求和回應。 |
| `[code]` | `Einvoice::MOF::DonationCodes` | 2026-08 | client 實際的做法。 |

捐贈碼清單同時也是 data.gov.tw 的資料集 31868（受捐贈機關或團體捐贈碼清單），採用「政府資料開放授權條款－第1版」。1.x 打包了一份這個清單，並在它的 README 中註明來源。

**更新檢查。** OpenAPI 文件有 `info.version`。檢查這個值，以及我們用到的 endpoint 的參數。

## 2. 連線

- 主機：`https://dataset.einvoice.nat.gov.tw/ods/portal/` `[doc]`。沒有測試主機。
- 所有 endpoint 都是 `GET` 加查詢參數，回傳 JSON 陣列。
- 預設最多回傳 100 筆。`limit` 最多可以設到 500，`offset` 用來跳過前面的筆數。兩者一起用來分頁 `[doc]`。
- OpenAPI 文件宣告了兩種驗證方式：`api_key` header 和 OAuth2。目前這個 endpoint 不需要它們也會回應 `[live]`。為了因應未來可能的變化，client 會把 HTTP 401 或 403 轉成 `AuthError` `[code]`。

## 3. 操作

client 只用到一個 endpoint：

| Endpoint | 用途 |
| --- | --- |
| `/api/v1/DonateCodeList` | 資料集 31868：受捐贈機關或團體捐贈碼清單 |

其他 27 個 endpoint 都是統計資料：發票張數、載具數量、捐贈、中獎，以及各地區的消費。另外有一個列出導入電子發票的營業人（`InvoiceBusinessList`，資料集 31869）。這些對 adapter 都沒有用處。

## 4. 對應到 unified API

`DonationCodes` 不屬於五個操作。它不透過任何加值中心就能檢查捐贈碼，所以不論使用哪一家加值中心都可以用 `[code]`。

| 方法 | 請求 | 說明 |
| --- | --- | --- |
| `lookup(code)` | `?donateCode=<code>` | 捐贈碼必須是 3 到 7 位數字。回傳空陣列表示「沒有登記」 |
| `exist?(code)` | 同上 | |
| `for_ubn(ubn)` | `?donateBan=<ubn>` | 一個統一編號可以有多個捐贈碼 |
| `all` | `?limit=500&offset=…` | 大約 2,000 筆，所以大約五次請求 |

結果是 `DonationCode`：`code` ← `donateCode`、`name` ← `donateNm`、`short_name` ← `donateShortNm`、`ubn` ← `donateBan`、`city` ← `hsnNm`。

有自己的捐贈碼檢查的加值中心：ECPay（`CheckLoveCode`）和 ezPay（`checkLoveCode`）。Amego 和關貿 DEFAULTAPI 沒有，所以由 `DonationCodes` 補上。

## 5. 欄位參考

### 5.1 `DonateCodeList`

參數 `[doc]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `donateBan` | O | 受捐贈機關或團體的統一編號 |
| `limit` | O | 1 到 500 |
| `offset` | O | 要跳過的筆數 |

OpenAPI 文件沒有列出 `donateCode`，但這個 endpoint 實際上可以用它篩選 `[live]`。

回應：一個陣列。每一筆有 `[doc]`：

| 欄位 | 意思 |
| --- | --- |
| `seq` | 序號 |
| `donateNm` | 受捐贈機關或團體名稱 |
| `donateCode` | 捐贈碼。OpenAPI 文件把它錯寫成「捐贈碼捐贈數量」 |
| `donateShortNm` | 簡稱 |
| `donateBan` | 統一編號 |
| `hsnNm` | 縣市 |

範例 `[live]`（`lookup.yml`）：

```
GET /ods/portal/api/v1/DonateCodeList?donateCode=2718
```

```json
[{ "donateBan": "92000392", "donateNm": "社團法人台北市喜願協會", "donateCode": "2718",
   "donateShortNm": "喜願協會", "hsnNm": "臺北市", "seq": 1 }]
```

不存在的捐贈碼會回傳 `[]`，HTTP 狀態是 200 `[live]`。

## 6. 代碼

| HTTP | 意思 | Unified 錯誤 | `Reason` |
| --- | --- | --- | --- |
| `200` | 成功。空陣列表示沒有符合的資料 | | |
| `401`、`403` | 這個 endpoint 開始需要帳號 | `AuthError` | `CREDENTIALS_INVALID` |
| 其他 | | `ProviderError` | |
| 沒有回應 | | `NetworkError` | |

`[code]`。

## 7. 待解問題

1. `donateCode` 篩選會一直保留嗎？它可以用，但 OpenAPI 文件沒有列出。
2. 這個 endpoint 會不會開始要求 OpenAPI 文件宣告的 `api_key` header？
