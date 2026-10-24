# 加值中心參考筆記

[English](README.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

這些筆記是給開發或維護 adapter 的人看的，不是使用者文件。

每一家加值中心公開 API 的方式都不一樣。有些公開完整的文件，有些只把 PDF 寄給客戶，有些什麼都不公開。我們讀過加值中心提供的資料後，把 adapter 開發需要的部分寫下來，每一家都用同一種格式。

加值中心的文件屬於該加值中心。我們只附上連結，不把他們的原文複製進這個 repository。每一份筆記都是我們自己的整理。

## 財政部規格

所有加值中心都依照 MIG 的格式，把發票送到財政部。所以當某一家的文件寫得不清楚，或兩家的說法不一致時，以 MIG 為準。請先讀 MIG。

| 規格 | 版本 | 筆記 |
| --- | --- | --- |
| MIG 電子發票資料交換標準訊息建置指引 | 4.1 | [mof/mig-4.1/](mof/mig-4.1/README.zh-TW.md) |

財政部另外提供開放資料 API。`Einvoice::MOF::DonationCodes` 用它來檢查捐贈碼：[mof/ods-api.zh-TW.md](mof/ods-api.zh-TW.md)。

## 加值中心

| 加值中心 | API | 2.x 的 adapter | 筆記 |
| --- | --- | --- | --- |
| Amego 光貿 | 電子發票 API | 進行中 | [amego/api.zh-TW.md](amego/api.zh-TW.md) |
| ECPay 綠界 | B2C 電子發票 API | `Einvoice::ECPay::Provider` | [ecpay/b2c.zh-TW.md](ecpay/b2c.zh-TW.md) |
| ezPay 簡單行動支付 | 電子發票 API (EZP_INVI 1.2.2) | 進行中 | [ezpay/invoice.zh-TW.md](ezpay/invoice.zh-TW.md) |
| Tradevan 關貿 | DEFAULTAPI | 進行中 | [tradevan/defaultapi.zh-TW.md](tradevan/defaultapi.zh-TW.md) |

### 四家比較

細節和來源見各份筆記。

| | ECPay | Amego | ezPay | 關貿 DEFAULTAPI |
| --- | --- | --- | --- | --- |
| 驗證程度 | 已有 adapter。已錄製 stage 的實際執行（2026-08） | 公開測試帳號實際執行過（2026-10） | 只有文件。我們的加密和手冊範例吻合。沒有 live 執行過 | 1.x 程式碼在正式環境使用中。目前沒有帳號 |
| 請求格式 | JSON，`Data` 用 AES-128-CBC 加密 | 表單，`data` 放 JSON，MD5 `sign` | 表單，query string 用 AES-256-CBC 加密（十六進位） | query 參數 `v`，AES-128-CBC 補零，兩把金鑰 |
| 測試帳號 | 公開、共用 | 公開、共用 | 自己開測試商店 | 沒有。主機未知 |
| 作廢需要 | 號碼、發票日期、原因（最多 20） | 號碼。原因選填 | 號碼、原因（最多 6 個中文字） | 號碼、訂單編號（`saleIdentifier`） |
| 作廢時機 | 可以立即作廢 | 進入佇列，可能還沒完成 | 隔天上傳之後才能作廢 | 未知 |
| 折讓金額 | 含稅 | 未稅，每個品項另有稅額 | 都可以 | 表頭三個都有：未稅、稅額、含稅 |
| 折讓單號 | ECPay 指定 | 賣方指定 | ezPay 指定 | 未知 |
| 用號碼查詢還需要 | 發票日期 | 不需要（限 180 天內） | 隨機碼 | 不需要 |

## unified model

每份筆記的第 4 節，都是把加值中心對應到下面這些規則。core 的型別也照這些規則定義。

**Reference。** 作廢、折讓、查詢收 `invoice:`，可以是 `InvoiceReference`，也可以只是發票號碼。作廢折讓收 `allowance:`，可以是 `AllowanceReference`，也可以只是折讓單號。開立、查詢、折讓的結果都用 `#reference` 回傳 reference。reference 裡放的是加值中心會要求、關於既有文件的資料：

| Reference | 欄位 |
| --- | --- |
| `InvoiceReference` | `number`、`invoice_datetime`、`random_code`、`order_id`、`total_amount` |
| `AllowanceReference` | `allowance_number`、`allowance_date`、`invoice_number` |

加值中心需要某個欄位、呼叫端卻沒有給時，adapter 可以向加值中心查詢補上。補不到就丟出 `ValidationError`，並說明缺少哪個欄位。adapter 絕不用猜的值補上。

**日期。** Input 不帶「這次操作本身的時間」。這個時間由加值中心記錄。如果加值中心要求送出，adapter 就送出當下的時間（UTC+8）。名稱和型別照 MIG：

| 欄位 | 型別 | MIG |
| --- | --- | --- |
| `invoice_datetime` | `Time`，UTC+8 | `InvoiceDate` 和 `InvoiceTime` |
| `allowance_date` | `Date` | `AllowanceDate` |
| `cancel_datetime` | `Time`，UTC+8。加值中心沒有回傳時為 `nil` | `CancelDate` 和 `CancelTime` |

**金額。** 發票照 F0401。買方是消費者時，`sales_amount` 含稅，`tax_amount` 為 `0`。買方是營業人時，`sales_amount` 不含稅，`tax_amount` 是稅額。折讓照 G0401：金額不含稅。如果呼叫端給的 `tax_amount` 是 `0`，由 core 從應稅品項拆出稅額，四捨五入，尾差放在最後一個應稅品項。只有 core 計算稅額，adapter 使用它的結果。

**稅率。** `tax_rate` 是小數，例如 `0.05`。core 只接受 MIG 的稅率：`0`、`0.01`、`0.02`、`0.05`、`0.15`、`0.25` `[mig 表 4-18]`。應稅的預設值是 `0.05`，零稅率和免稅是 `0`。加值中心無法送出某個稅率時，adapter 丟出 `UnsupportedError`。

**Input 檢查。** adapter 執行前，core 會先檢查：

- `ubn` 是 8 位數字。B2B 發票一定要有。如果呼叫端指定了 `category`，必須和 `ubn` 一致。
- 總計是整數，而且不能是負數。品項的數量、單價、金額是數字，最多 7 位小數。
- 手機條碼是 `/` 加 7 個字元。自然人憑證是 2 個英文字母加 14 個數字。
- 作廢原因是 1 到 20 個字元。作廢折讓的原因可以不給，沒給時 core 補上 `作廢折讓`。
- 捐贈和載具可以同時給，MIG 允許這樣做。

**狀態。** 加值中心的狀態無法對應到 `InvoiceStatus` 時，`QueryInvoiceResult#status` 為 `nil`。

**錯誤。** 每一種失敗都是 `Einvoice::Error`，不會是 Ruby 原生的錯誤。

- 遇到我們不認得的錯誤代碼時，每家加值中心有自己的預設類別。第 6.4 節寫明預設類別和依據。
- HTTP 5xx 和 429 是 `NetworkError`，呼叫端可以重試。
- `Reason::RETRY_LATER` 表示加值中心說「現在不行，晚一點再試」，例如發票上傳前就作廢。

**Capability。**

- `QUERY_BY_ORDER_ID` 表示加值中心可以只靠呼叫端知道的資料找到發票，不需要發票號碼。呼叫端傳一個帶有 `order_id` 的 `InvoiceReference`；加值中心需要時，再加上 `total_amount`。
- `CARRIER_VALIDATION` 表示 adapter 實作了 `Provider#validate_carrier`。

**連線。** `base_url` 一定要用 https，只有 localhost 可以用 http。

## 來源與可信度

筆記裡的每一項事實都有來源標記。標記告訴你這項事實有多可信。每份筆記的開頭都會列出它用到的標記。

| 來源類型 | 標記範例 | 可信度 |
| --- | --- | --- |
| 加值中心的文件 | `[doc]`，或每份文件一個短標記，例如 `[inv]` | documented：加值中心這樣說，但沒有人實際驗證過 |
| 我們的 live 測試與錄製的回應 | `[live]` | verified：我們親眼看過。筆記會寫明日期 |
| 正式環境中執行的程式碼，或正式環境使用者的回報 | `[prod]` | 在正式環境驗證過 |
| 我們的 2.x adapter 程式碼 | `[code]` | 我們的 adapter 怎麼做。不能證明 API 實際的行為 |
| 1.x client 的程式碼 | `[1x-code]` | 舊版 client 怎麼做。它在正式環境執行了很多年 |
| 財政部規格 | `[mig 表 x-y]` | 規格本身。見 MIG 筆記 |
| 其他 SDK 的 wire fixture，由該 SDK 的作者實際執行過 | `[fixture]` | 由對方驗證過。筆記會寫明時間和來源 |

另外有兩個沒有標記的註明：

- **（推論）**：我們從其他事實推論出來的。內文會寫明是從哪些事實推論的。這是關於加值中心的說法。
- **unknown（未知）**：我們不知道。會列在待解問題裡。

第 4 節和 6.4 的錯誤類別欄不是關於加值中心的事實，而是 adapter 要遵守的對應方式：要送哪個欄位、要丟哪個錯誤類別。這些內容要在寫 adapter 之前，依照加值中心的文件和 unified model 寫好。adapter 不得不採用不同做法時，就在同一個 pull request 裡修改筆記。

`[doc]` 一律指加值中心自己的文件。我們自己過去寫的摘要用別的標記。

如果 live 測試顯示加值中心的文件寫錯了，兩者都要保留：先寫文件怎麼說，再寫 API 實際怎麼做。

## 加值中心筆記的格式

每份加值中心筆記都依序使用下面這些段落。段落可以很短，但不要刪掉。

### 1. 狀態與來源

- 哪一個 API、哪一個版本，以及 2.x 有沒有對應的 adapter。
- 一行說明這份筆記可以信到什麼程度：有沒有 adapter，有沒有任何內容經過 live 驗證。
- 文件屬於誰，附上連結，並註明本筆記是我們的整理。
- 來源表：標記、來源、日期、提供了哪些內容。
- 怎麼檢查官方有沒有更新：更新記錄頁、版本號或檔案日期。

### 2. 連線

主機、帳號、測試帳號、簽章或加密，以及請求和回應的封包結構。附上一組真實或文件上的完整請求與完整回應範例。如果有幫助，同時列出加密前和加密後的內容。

**API 的限制。** 寫明 API 沒有保護的地方，讓使用者知道自己要防範什麼：例如回應沒有簽章、帳號密碼放在 URL 裡，或固定的 IV。

**官方測試向量。** 列出文件裡每一個同時給出輸入和輸出的範例，包括簽章、加密或檢查碼：金鑰、輸入，以及預期的結果。註明哪個 spec 用了它。如果文件沒有，也要寫明。測試向量不需要測試帳號就能驗證傳輸格式，所以寫 adapter 之前，先到附錄裡找。

### 3. 操作

列出 endpoint。只詳細說明五個 unified 操作會用到的 endpoint。其他的整理成一張表，每個一行，讓 adapter 可以透過 `raw` 呼叫。

### 4. 對應到 unified API

這是最主要的段落，放 adapter 必須做的每一個決定。能用表格就用表格，不要用長段文字。

- **4.1 操作。** 每個 unified 操作一列：使用哪個 endpoint、需要 reference 的哪些欄位，以及呼叫端還必須在 `provider_options` 傳什麼。
- **4.2 欄位。** 每個操作一張表，請求和結果都要：unified 欄位、加值中心欄位、規則或預設值。註明哪些 unified 欄位不會送出，以及哪些結果欄位由 adapter 自己填。日期和 reference 照 [unified model](#unified-model)。
- **4.3 金額與稅額。** `AmountSummary` 和品項金額怎麼對應到加值中心的總計，發票和折讓都要寫。註明金額是否含稅、由誰計算稅額，以及怎麼四捨五入。
- **4.4 狀態。** 加值中心的狀態值，以及各自對應的 unified `InvoiceStatus`。
- **4.5 時限。** 期限與延遲：上傳時間、作廢期限、新開立的發票什麼時候可以作廢。
- **4.6 Capabilities。** `Capability::ALL` 的每個 flag 一列：API 是否支援、adapter 是否宣告，以及有什麼條件。
- **4.7 與 MIG 的差異。** 加值中心比 MIG 嚴格、寬鬆，或不一樣的地方。
- **4.8 Contract 與 live 測試。** 任何會影響 shared contract（`spec/support/shared_examples/invoice_provider.rb`）或 live spec 執行方式的事：測試環境、號碼格式、contract 沒有傳的輸入，以及在測試中無法執行的步驟。

### 5. 欄位參考

4.1 用到的 endpoint 的請求與回應欄位，以及它們的規則。「M」表示必填，「O」表示選填。條件寫在規則欄，例如「`Print` 為 `1` 時 M」。

### 6. 代碼

列舉值與錯誤代碼。錯誤代碼表的欄位依序是：代碼、意思、unified 錯誤類別、`Reason`、來源。還沒決定的類別就留空。

### 7. 待解問題

所有標為 unknown 的事項，集中成一份清單。

## 規格筆記的格式

規格（例如 MIG）不是 API。它的筆記包含：

1. **狀態與來源。** 和加值中心筆記相同。
2. **內容。** 訊息或資料。內容變長時，拆成多個檔案。
3. **對應到 unified API。** 規格告訴我們關於 unified model 的事。
4. **待解問題。**

## API 版本

同一家加值中心可能同時有多個 API 版本在使用。每個版本各有一份筆記，以版本命名，例如 `tradevan/defaultapi.md`。只要還有人在用舊版 API，新版的筆記就不會取代舊版的筆記。
