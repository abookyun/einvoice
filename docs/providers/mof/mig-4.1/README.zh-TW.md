# 財政部 MOF：MIG 4.1

[English](README.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

## 1. 狀態與來源

MIG（電子發票資料交換標準訊息建置指引，Message Implementation Guideline）是財政部的電子發票資料標準。每一家加值中心都用這些訊息格式，把發票上傳到財政部平台。所以當某一家的文件寫得不清楚，或兩家的說法不一致時，以 MIG 為準。

MIG 定義的是訊息，不是 API。加值中心的 API 是各家自己的設計，但它送到財政部的資料必須符合這些訊息。所以：

- 加值中心的規則如果比 MIG 嚴格，可能只是該家自己的選擇。
- 加值中心的規則如果比 MIG 寬鬆，代表該家會在上傳前自己補正資料，或之後才拒絕。

| 標記 | 來源 | 日期 | 提供的內容 |
| --- | --- | --- | --- |
| `[mig]` | 電子發票資料交換標準訊息建置指引 V4.1，財政部財政資訊中心。[PDF](https://www.einvoice.nat.gov.tw/static/ptl/ein_upload/download/5340.pdf)，212 頁。2026-10-14 取得。 | 2025-10-29 | 所有訊息、欄位、規則與代碼表。 |

引用時寫 MIG 的表格編號（表），例如 `[mig 表 15-3]`。表格編號比頁碼容易找，因為 PDF 上印的頁碼和 PDF 實際的頁數對不上。

這些筆記的內容都是 **documented**。MIG 就是規格本身，沒有別的東西可以拿來驗證它。

### 檔案

| 檔案 | 內容 |
| --- | --- |
| README.zh-TW.md | 本頁：來源、版本變更、訊息總表、對應到 unified API、待解問題 |
| [codes.zh-TW.md](codes.zh-TW.md) | 共通型別與代碼表（MIG 第肆章） |
| [storage.zh-TW.md](storage.zh-TW.md) | 存證訊息 F0401、F0501、F0701、G0401、G0501 |
| [exchange.zh-TW.md](exchange.zh-TW.md) | B2B 交換訊息 A0101 到 A0302、B0101 到 B0202 |
| [numbering.zh-TW.md](numbering.zh-TW.md) | 字軌配號訊息 E0401、E0402、E0501 |
| [platform.zh-TW.md](platform.zh-TW.md) | 平台檔案 E0502、E0503、E0504，以及平台回應 ProcessResult 和 SummaryResult |

### 對 adapter 有影響的近期變更

- **V4.0（2024-05-30）。**
  - F/G 訊息取代了舊的 A0401、C0401、A0501、C0501、B0401、D0401、B0501 和 D0501。
  - F0401 拿掉了 `CheckNumber`。
  - 載具號碼長度增加到 400 字元。
  - 新增品項層級的 `TaxType`。
  - `NPOBAN` 改成 10 字元的字串。
- **V4.1（2024-12-13）。** 所有折讓一律由賣方開立和作廢（統一發票使用辦法第 20 條之 1）。G0401 的 `AllowanceType` 改成必填，而且固定為 `2`。金額不可以是負數。
- **V4.1（2025-09-03、2025-10-29）。** 小幅修正：更多不可為負數的規則，以及 E0504 的 `RandomNumber` 改成選填。

## 2. 連線

不在本筆記範圍內。MIG 定義的是訊息內容。傳輸方式（Turnkey 或加值中心）定義在別的地方，而各家加值中心都把它包在自己的 API 後面。

## 3. 操作

MIG 共有 21 種訊息 `[mig 表 3-1]`。B2B 交易可以用交換訊息或存證訊息。B2C 交易，以及存在載具裡的發票，用存證訊息。

| 類別 | 訊息 | 適用 | 筆記 |
| --- | --- | --- | --- |
| 存證 | F0401、F0501、F0701、G0401、G0501 | B2C 和 B2B | [storage.zh-TW.md](storage.zh-TW.md) |
| 交換 | A0101、A0102、A0201、A0202、A0301、A0302、B0101、B0102、B0201、B0202 | 只限 B2B | [exchange.zh-TW.md](exchange.zh-TW.md) |
| 字軌配號 | E0401、E0402、E0501 | 全部 | [numbering.zh-TW.md](numbering.zh-TW.md) |
| 平台檔案 | E0502、E0503、E0504 | 全部 | [platform.zh-TW.md](platform.zh-TW.md) |
| 平台回應 | ProcessResult、SummaryResult | 全部 | [platform.zh-TW.md](platform.zh-TW.md) |

## 4. 對應到 unified API

| Unified | MIG 訊息 | 說明 |
| --- | --- | --- |
| `issue` | F0401，B2B 交換用 A0101 | |
| `void` | F0501 或 A0201 | 需要發票日期，來自 `InvoiceReference` |
| `allowance` | G0401 或 B0101 | 需要每張原發票的日期，來自 `InvoiceReference` |
| `void_allowance` | G0501 或 B0201 | 需要折讓日期，來自 `AllowanceReference` |
| `query` | 無 | 查詢是加值中心提供的功能。MIG 沒有查詢訊息 |

### MIG 對 unified API 的影響

下面列出 MIG 替我們回答的問題，以及我們的 model 和 MIG 不一樣的地方。從這些問題得出的規則，寫在 [unified model](../../README.zh-TW.md#unified-model)。

- **作廢需要發票日期。** F0501 的 `InvoiceDate` 是必填 `[mig 表 16-2]`。unified model 把它放在 `InvoiceReference#invoice_datetime`。Input 沒有 `date` 欄位：作廢的時間是 `CancelDate` 和 `CancelTime`，由加值中心記錄。
- **折讓需要每張原發票的號碼和日期。** G0401 的每個品項都必填 `OriginalInvoiceNumber` 和 `OriginalInvoiceDate` `[mig 表 18-5]`。兩者都來自 `InvoiceReference`。unified 的折讓只針對一張發票，跨多張發票的折讓不在 model 的範圍內。
- **作廢折讓需要折讓日期。** G0501 的 `AllowanceDate` 是必填 `[mig 表 19-2]`。它來自 `AllowanceReference#allowance_date`，型別是 `Date`，因為 G0401 沒有折讓時間。
- **作廢原因是必填。** F0501 和 G0501 的 `CancelReason` 都是 1 到 20 字元 `[mig 表 16-2, 19-2]`。core 要求作廢一定要有原因。作廢折讓時，呼叫端沒有給原因，core 就補上 `作廢折讓`。
- **折讓金額不含稅。** G0401 品項的 `Amount` 和總計 `TotalAmount` 都是未稅金額。每個品項另外需要自己的整數 `Tax` `[mig 表 18-5, 18-6]`。呼叫端給的 `tax_amount` 是 `0` 時，由 core 拆出稅額。
- **B2C 必須有隨機碼。** F0401 的 `RandomNumber` 是 4 位數字。買方是消費者時必填，買方是營業人時選填 `[mig 表 15-3]`。
- **外幣只是備註。** `Currency`、`OriginalCurrencyAmount` 和 `ExchangeRate` 都是選填的備註。法定金額一律是新台幣整數 `[mig 表 15-6]`。這和 unified 的 `FOREIGN_CURRENCY` 設計一致。境外電商是例外：他們可以用外幣列示金額。
- **混合稅率只能用在表頭。** 表頭的 `TaxType` 可以是 `9`（混合），品項不行 `[mig 表 15-5, 4-12]`。
- **B2B 交換有 unified API 沒有的狀態。** 在交換流程中，發票要等買方用 A0102 確認後，才算雙方合意。買方也可以用 A0301 退回。`InvoiceStatus` 沒有「等待買方確認」或「已退回」的狀態。只有透過交換訊息處理 B2B 發票的加值中心才會碰到（見第 5 節第 4 題）。細節見 [exchange.zh-TW.md](exchange.zh-TW.md)。
- **透過交換流程的 B2B 發票，不能帶載具，也不能用混合稅率。** A0101 沒有載具欄位，`TaxType` 也不可以是 `9`。F0401 對營業人買方則兩者都允許。所以 `B2B` 和 `MIXED_TAX` 這兩個 capability，可能取決於加值中心用哪一種訊息。
- **財政部有自己的發票狀態清單。** E0502 回報 7 種狀態之一：開立、作廢、退回，各自分成已確認和未確認，再加上已註銷（[codes](codes.zh-TW.md#發票狀態-currentstatus)）。unified 的 `InvoiceStatus` 有 `issued`、`voided` 和 `allowance`。`allowance` 不是財政部的發票狀態：財政部把折讓當成獨立的文件，有自己的狀態。加值中心回報狀態時，先拿這份清單對照。
- **F0701 不是用來修正發票的工具。** MIG 明確警告，不可以用 F0701 更正發票。發票內容有誤，要作廢後重開。退貨和折價要開折讓 `[mig F0701 訊息功能]`。unified API 沒有對應 F0701 的操作，未來如果要加，也要非常小心。

## 5. 待解問題

1. 品項的 `Quantity`、`UnitPrice` 和 `Amount` 允許小數點後 7 位，但總計必須是新台幣整數。各家加值中心怎麼處理品項金額的四捨五入？每份加值中心筆記都應該寫清楚。
2. MIG 沒有寫上傳期限，也沒有寫作廢的期限。這些規定在財政部的其他文件裡。我們應該追蹤哪些文件？
3. F0401 對 `CarrierId1` 和 `CarrierId2` 的說明有兩條規則互相衝突。`PrintMark` 為 `Y` 時，兩者都必須空白。但買方使用手機條碼時，「不論是否列印」兩者都是必填 `[mig 表 15-3]`。手機條碼的發票被列印時，以哪一條為準？
4. 我們的加值中心，B2B 發票是走交換訊息，還是一律走 F0401？每份加值中心筆記都應該寫清楚。這個答案決定第 4 節中關於交換流程的幾點是否適用。
