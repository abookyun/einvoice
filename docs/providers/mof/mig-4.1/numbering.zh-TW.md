# MIG 4.1：字軌配號訊息

[English](numbering.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

關於發票字軌配號的訊息：E0401、E0402 和 E0501。來源和標記見 [README.zh-TW.md](README.zh-TW.md)。型別與代碼表見 [codes.zh-TW.md](codes.zh-TW.md)。

「M」表示必填，「O」表示選填。

## 號碼怎麼配發

財政部每兩個月一期，配發一組發票號碼區間給每家營業人。每個區間有兩個英文字母的字軌（例如 `AB`），以及起訖號碼。號碼以本為單位，每本 50 號。

- 營業人以 E0501 下載配發的區間。
- 總機構和分支機構共用區間時，總機構以 E0401 上傳分配結果。
- 下一期 10 日以前，營業人以 E0402 上傳沒有使用的號碼。

營業人可以委託加值中心代為收發這些訊息。替商家管理號碼的加值中心（例如提供「字軌設定」API 的），就是在這些訊息之上運作。

## E0401：分支機構配號

總機構上傳如何把一個區間分配給各分支機構 `[mig 第貳拾章, 表 20-1, 20-3, 20-5]`。總機構自己保留的號碼屬於總機構，所以也要上傳，`BranchBan` 填總機構自己的 BAN。

如果平台再次收到 `Main` 中的同一個區間，會刪除該區間先前所有的分支機構資料，改用新的資料。

表頭（`BranchTrack/Main`）：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `HeadBan` | M | 總機構 BAN |
| `BranchBan` | M | 分支機構 BAN。總機構保留的部分填總機構 BAN |
| `InvoiceType` | M | `07` / `08` |
| `YearMonth` | M | 期別（[codes](codes.zh-TW.md#發票期別-yearmonth)） |
| `InvoiceTrack` | M | 兩個大寫英文字母 |
| `InvoiceBeginNo` | M | 8 位數字，結尾是 `00` 或 `50`。必須和財政部配發的區間相符 |
| `InvoiceEndNo` | M | 8 位數字，結尾是 `49` 或 `99`。必須和財政部配發的區間相符 |

品項（`BranchTrack/Details/BranchTrackItem`），1 到 25000 筆：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `InvoiceBeginNo` | M | 8 位數字 |
| `InvoiceEndNo` | M | 8 位數字 |
| `InvoiceBooklet` | M | 本數 |

## E0402：空白未使用字軌

營業人或代為處理的加值中心，在下一期 10 日以前，透過 Turnkey 上傳沒有使用的號碼 `[mig 第貳拾壹章, 表 21-1, 21-3, 21-5]`。

上傳規則：

- 同一次上傳中的區間不可以重疊。如果重疊，平台會拒絕整次上傳。
- 新上傳的區間如果和平台已有的區間重疊，平台會刪除舊區間，保留新區間。沒有重疊的區間會保留。
- 要修正上傳錯誤的區間：先上傳一個同時涵蓋錯誤區間和正確區間的區間，再上傳正確的區間。或者在財政部網站上刪除錯誤的區間。

表頭（`BranchTrackBlank/Main`）：`HeadBan`、`BranchBan`、`InvoiceType`、`YearMonth` 和 `InvoiceTrack`，全部必填，規則和 E0401 相同。

品項（`BranchTrackBlank/Details/BranchTrackBlankItem`），1 到 10000 筆：`InvoiceBeginNo` 和 `InvoiceEndNo`，各 8 位數字，都必填。

## E0501：配號檔

營業人或代為處理的加值中心，下載財政部配發的區間 `[mig 第貳拾貳章, 表 22-1]`。`InvoiceAssignNo` 下的欄位全部必填：

| 欄位 | 規則 |
| --- | --- |
| `Ban` | 營業人 BAN |
| `InvoiceType` | `07` / `08` |
| `YearMonth` | 期別 |
| `InvoiceTrack` | 兩個大寫英文字母 |
| `InvoiceBeginNo` | 8 位數字 |
| `InvoiceEndNo` | 8 位數字 |
| `InvoiceBooklet` | 本數 |
