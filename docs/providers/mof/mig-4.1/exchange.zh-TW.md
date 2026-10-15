# MIG 4.1：交換訊息

[English](exchange.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

交換訊息：A0101 到 A0302，以及 B0101 到 B0202。只有 B2B 交易使用。來源和標記見 [README.zh-TW.md](README.zh-TW.md)。型別與代碼表見 [codes.zh-TW.md](codes.zh-TW.md)。存證訊息見 [storage.zh-TW.md](storage.zh-TW.md)。

「M」表示必填，「O」表示選填。

## 交換流程怎麼運作

存證訊息由賣方送到財政部平台，到此就結束了。交換訊息則是透過平台，從一方營業人送到另一方，對方再回覆一個確認訊息。收到確認之後，雙方才算交換合意 `[mig 第伍章 to 第壹拾肆章, 訊息功能]`。

| 動作 | 訊息 | 發送 → 接收 | 確認 | 發送 → 接收 |
| --- | --- | --- | --- | --- |
| 開立發票 | A0101 | 賣方 → 買方 | A0102 | 買方 → 賣方 |
| 作廢發票 | A0201 | 賣方 → 買方 | A0202 | 買方 → 賣方 |
| 退回發票（退回／拒收） | A0301 | 買方 → 賣方 | A0302 | 賣方 → 買方 |
| 開立折讓 | B0101 | 賣方 → 買方 | B0102 | 買方 → 賣方 |
| 作廢折讓 | B0201 | 賣方 → 買方 | B0202 | 買方 → 賣方 |

V4.0 以前，買方可以開立折讓，再用 B0201 作廢。V4.1 起，所有折讓一律由賣方開立和作廢 `[mig 表 4-6]`。

發票內容有誤時（例如數量、單價或品名），買方用 A0301 退回 `[mig 第壹拾參章]`。存證訊息沒有這個步驟。

## A0101：開立發票

A0101 的結構和 F0401 相同，差別如下 `[mig 表 5-1, 5-3, 5-5, 5-6]`：

- **沒有載具、列印和捐贈的資料。** A0101 沒有 `CarrierType`、`CarrierId1`、`CarrierId2`、`PrintMark`、`NPOBAN`、`RandomNumber` 和 `BondedAreaConfirm`。`DonateMark` 仍然必填。
- **保稅區註記由買方提供。** `BondedAreaConfirm` 在買方的確認訊息 A0102 裡，不在 A0101 裡。
- **不能用混合稅率。** 表頭的 `TaxType` 不可以是 `9`。
- **只有一個銷售額合計。** `Invoice/Amount` 只有 `SalesAmount`，沒有 `FreeTaxSalesAmount` 和 `ZeroTaxSalesAmount`。
- **總計都是整數。** `SalesAmount`、`TaxAmount`、`TotalAmount` 和 `DiscountAmount` 都不允許小數，四捨五入。營業人買方的 `SalesAmount` 不含稅。
- **`Description` 和 `SequenceNumber` 至少要 1 個字元。**

其他表頭欄位和 F0401 相同：`InvoiceNumber`、`InvoiceDate`、`InvoiceTime`、`Seller`、`Buyer`、`BuyerRemark`、`MainRemark`、`CustomsClearanceMark`、`Category`、`RelateNumber`、`InvoiceType`、`GroupMark`、`ZeroTaxRateReason`、`Reserved1` 和 `Reserved2`。品項和備註欄位（`OriginalCurrencyAmount`、`ExchangeRate`、`Currency`）也相同。

總計（`Invoice/Amount`）`[mig 表 5-6]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `SalesAmount` | M | 整數，不可為負數。營業人買方時不含稅 |
| `TaxType` | M | `1` 到 `4`。不可以是 `9` |
| `TaxRate` | M | 見 [codes](codes.zh-TW.md#課稅別與稅率-taxtypeenum-taxrateenum) |
| `TaxAmount` | M | 整數，不可為負數 |
| `TotalAmount` | M | 整數，不可為負數 |
| `DiscountAmount` | O | 整數。只是備註 |
| `OriginalCurrencyAmount` | O | 只是備註 |
| `ExchangeRate` | O | 只是備註 |
| `Currency` | O | 只是備註 |

## A0102：確認發票

由買方發送，欄位在 `InvoiceConfirm` 下 `[mig 表 6-1, 6-2]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `InvoiceNumber` | M | 發票號碼 |
| `InvoiceDate` | M | `yyyyMMdd` |
| `BuyerId` | M | BAN |
| `SellerId` | M | BAN |
| `ReceiveDate` | M | `yyyyMMdd` |
| `ReceiveTime` | M | `xsd:time` |
| `BuyerRemark` | O | `1` 到 `4`（[codes](codes.zh-TW.md#買方註記-buyerremarkenum)） |
| `Remark` | O | 最多 200 |
| `BondedAreaConfirm` | O | `1` 到 `4`（[codes](codes.zh-TW.md#保稅區-bondedareaenum)） |

## A0201：作廢發票

欄位和 F0501 相同（[storage](storage.zh-TW.md#f0501作廢發票)），在 `CancelInvoice` 下 `[mig 表 9-1, 9-2]`。這裡的 `InvoiceDate` 也是必填。

## A0202：確認作廢

由買方發送，欄位在 `CancelInvoiceConfirm` 下 `[mig 表 10-1, 10-2]`：`CancelInvoiceNumber`、`InvoiceDate`、`BuyerId`、`SellerId`、`CancelDate` 和 `CancelTime` 必填。`Remark`（最多 200）選填。

## A0301：退回發票

由買方發送，欄位在 `RejectInvoice` 下 `[mig 表 13-1, 13-2]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `RejectInvoiceNumber` | M | 發票號碼 |
| `InvoiceDate` | M | `yyyyMMdd` |
| `BuyerId` | M | BAN |
| `SellerId` | M | BAN |
| `RejectDate` | M | `yyyyMMdd` |
| `RejectTime` | M | `xsd:time` |
| `RejectReason` | M | 最多 20 |
| `Remark` | O | 最多 200 |
| `Reserved1`、`Reserved2` | O | 最多 20、最多 100 |

## A0302：確認退回

由賣方發送，欄位在 `RejectInvoiceConfirm` 下 `[mig 表 14-1, 14-2]`：`RejectInvoiceNumber`、`InvoiceDate`、`BuyerId`、`SellerId`、`RejectDate` 和 `RejectTime` 必填。`Remark`（最多 200）選填。

## B0101：開立折讓

結構和 G0401 相同（[storage](storage.zh-TW.md#g0401開立折讓)），差別如下 `[mig 表 7-1, 7-3, 7-5, 7-6]`：

- `Seller` 和 `Buyer` 可以帶 `RoleRemark`。G0401 沒有 `RoleRemark`。
- 沒有境外電商的規則。品項的 `Amount` 和 `Tax`，以及總計的 `TaxAmount` 和 `TotalAmount` 都是整數，四捨五入。
- `AllowanceType` 必填，並固定為 `2`，和 G0401 相同。

## B0102：確認折讓

由買方發送，欄位在 `AllowanceConfirm` 下 `[mig 表 8-1]`：`AllowanceNumber`、`AllowanceDate`、`BuyerId`、`SellerId`、`ReceiveDate`、`ReceiveTime` 和 `AllowanceType` 必填。`Remark`（最多 200）選填。

## B0201：作廢折讓

欄位和 G0501 相同（[storage](storage.zh-TW.md#g0501作廢折讓)），在 `CancelAllowance` 下 `[mig 表 11-1, 11-2]`。這裡的 `AllowanceDate` 也是必填。

## B0202：確認作廢折讓

由另一方發送，欄位在 `CancelAllowanceConfirm` 下 `[mig 表 12-1, 12-2]`：`CancelAllowanceNumber`、`AllowanceDate`、`BuyerId`、`SellerId`、`AllowanceType`、`CancelDate` 和 `CancelTime` 必填。`Remark`（最多 200）選填。
