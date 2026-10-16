# MIG 4.1：存證訊息

[English](storage.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

存證訊息：F0401、F0501、F0701、G0401 和 G0501。B2C 交易使用這些訊息，B2B 交易也可以使用。來源和標記見 [README.zh-TW.md](README.zh-TW.md)。型別與代碼表見 [codes.zh-TW.md](codes.zh-TW.md)。

「M」表示必填，「O」表示選填。

## F0401：開立發票

表頭（`Invoice/Main`）`[mig 表 15-1, 15-3]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `InvoiceNumber` | M | `[A-Z]{2}\d{8}`（[codes](codes.zh-TW.md#發票號碼-invoicenumbertype)） |
| `InvoiceDate` | M | `yyyyMMdd`，UTC+8（[codes](codes.zh-TW.md#日期與時間-datetype-timetype)） |
| `InvoiceTime` | M | `xsd:time`，UTC+8 |
| `Seller` | M | 角色（[codes](codes.zh-TW.md#賣方與買方-roledescriptiontype)）。賣方的 `Address` 必填 |
| `Buyer` | M | 角色 |
| `BuyerRemark` | O | `1` 到 `4`（[codes](codes.zh-TW.md#買方註記-buyerremarkenum)） |
| `MainRemark` | O | 最多 200 |
| `CustomsClearanceMark` | O | `1` / `2`。零稅率時必填（[codes](codes.zh-TW.md#通關方式-customsclearancemarkenum)） |
| `Category` | O | 最多 2（沖帳別） |
| `RelateNumber` | O | 最多 20 |
| `InvoiceType` | M | `07` / `08`（[codes](codes.zh-TW.md#發票類別-invoicetypeenum)） |
| `GroupMark` | O | `*` 表示彙開 |
| `DonateMark` | M | `0` / `1`。為 `1` 時，`NPOBAN` 不可空白 |
| `CarrierType` | O | 6 字元（[codes](codes.zh-TW.md#載具類別-carriertypeenum)）。沒有載具時空白 |
| `CarrierId1` | O | 最多 400。載具顯碼 |
| `CarrierId2` | O | 最多 400。載具隱碼，也就是讀碼機讀到的值 |
| `PrintMark` | M | `Y` / `N` |
| `NPOBAN` | O | 最多 10。3 到 7 位數字的捐贈碼，或受捐贈者的統一編號 |
| `RandomNumber` | O | 4 位數字。買方是消費者時必填 |
| `BondedAreaConfirm` | O | `1` 到 `4` |
| `ZeroTaxRateReason` | O | `71` 到 `79`。零稅率時必填（[codes](codes.zh-TW.md#零稅率原因-zerotaxratereasonenum)） |
| `Reserved1`、`Reserved2` | O | 最多 20、最多 100 |

跨欄位規則 `[mig 表 15-3]`：

- `PrintMark` 為 `Y` 時：`CarrierType`、`CarrierId1` 和 `CarrierId2` 必須空白，`DonateMark` 必須是 `0`。
- `CarrierId1` 或 `CarrierId2` 不是空白時，`PrintMark` 必須是 `N`。
- 買方使用手機條碼時（發票上有統一編號也一樣），不論是否列印，`CarrierId1` 和 `CarrierId2` 都必填。
- `CarrierId1` 和 `CarrierId2` 的開頭和結尾不可以是空白，半形全形都不行。

品項（`Invoice/Details/ProductItem`），1 到 9999 筆 `[mig 表 15-5]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `Description` | M | 最多 500 |
| `Quantity` | M | 數值，20 位，小數點後最多 7 位 |
| `Unit` | O | 最多 6 |
| `UnitPrice` | M | 數值，20 位，小數點後最多 7 位 |
| `TaxType` | M | `1` 到 `4`。不可以是 `9` |
| `Amount` | M | 數值，20 位，小數點後最多 7 位 |
| `SequenceNumber` | M | 最多 4 |
| `Remark` | O | 最多 120。健康捐品項填 `健康捐` |
| `RelateNumber` | O | 最多 50。商品編號寫成 `{A...}`（國際條碼）或 `{Z...}`（其他） |

總計（`Invoice/Amount`）`[mig 表 15-6]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `SalesAmount` | M | 應稅銷售額合計。新台幣整數，沒有時填 `0`，不可為負數 |
| `FreeTaxSalesAmount` | M | 免稅銷售額合計。整數，沒有時填 `0` |
| `ZeroTaxSalesAmount` | M | 零稅率銷售額合計。整數，沒有時填 `0` |
| `TaxType` | M | `1`、`2`、`3`、`4` 或 `9`（[codes](codes.zh-TW.md#課稅別與稅率-taxtypeenum-taxrateenum)） |
| `TaxRate` | M | 見 [codes](codes.zh-TW.md#課稅別與稅率-taxtypeenum-taxrateenum) |
| `TaxAmount` | M | 整數，不可為負數 |
| `TotalAmount` | M | 新台幣整數，不可為負數 |
| `DiscountAmount` | O | 只是備註 |
| `OriginalCurrencyAmount` | O | 只是備註 |
| `ExchangeRate` | O | 只是備註。13 位，小數點後最多 5 位 |
| `Currency` | O | ISO 4217。境外電商必填 |

金額的填法 `[mig 表 15-6, 註 1, 註 2]`：

- 稅額四捨五入到元（營業稅法第 14 條）。
- 營業人買方的發票，銷售額和稅額分開列示。消費者的發票，列示含稅價（營業稅法第 32 條）。上傳的內容必須和開立的內容一致。

## F0501：作廢發票

所有欄位都在 `CancelInvoice` 下 `[mig 表 16-1, 16-2]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `CancelInvoiceNumber` | M | 發票號碼 |
| `InvoiceDate` | M | `yyyyMMdd` |
| `BuyerId` | M | BAN（[codes](codes.zh-TW.md#ban)）。消費者填 `0000000000` |
| `SellerId` | M | BAN |
| `CancelDate` | M | `yyyyMMdd` |
| `CancelTime` | M | `xsd:time` |
| `CancelReason` | M | 1 到 20 字元 |
| `ReturnTaxDocumentNumber` | O | 最多 60。專案作廢核准文號 |
| `Remark` | O | 最多 200 |
| `Reserved1`、`Reserved2` | O | 最多 20、最多 100 |

## F0701：註銷發票

所有欄位都在 `VoidInvoice` 下 `[mig 表 17-1, 17-2]`：`VoidInvoiceNumber`、`InvoiceDate`、`BuyerId`、`SellerId`、`VoidDate`、`VoidTime` 和 `VoidReason`（1 到 20 字元）都必填。`Remark`（最多 200）、`Reserved1` 和 `Reserved2` 選填。

## G0401：開立折讓

表頭（`Allowance/Main`）`[mig 表 18-1, 18-3]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `AllowanceNumber` | M | 最多 16。不可重複，跨年度也一樣（[codes](codes.zh-TW.md#折讓證明單號碼-allowancenumbertype)） |
| `AllowanceDate` | M | `yyyyMMdd` |
| `Seller` | M | 角色。`Address` 必填 |
| `Buyer` | M | 角色 |
| `AllowanceType` | M | V4.1 起固定為 `2` |
| `OriginalInvoiceSellerId` | O | BAN。只在賣方的統一編號變更，或賣方被合併時使用 |
| `OriginalInvoiceBuyerId` | O | BAN。同上，用於買方 |

品項（`Allowance/Details/ProductItem`），1 到 9999 筆 `[mig 表 18-5]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `OriginalInvoiceDate` | M | `yyyyMMdd` |
| `OriginalInvoiceNumber` | M | 發票號碼 |
| `OriginalSequenceNumber` | O | 最多 4。該品項在原發票上的 `SequenceNumber` |
| `OriginalDescription` | M | 最多 500 |
| `Quantity` | M | 數值，小數點後最多 7 位 |
| `Unit` | O | 最多 6 |
| `UnitPrice` | M | 數值，小數點後最多 7 位 |
| `Amount` | M | 未稅。新台幣整數 |
| `Tax` | M | 整數。境外電商填 `0` |
| `AllowanceSequenceNumber` | M | 最多 4 |
| `TaxType` | M | `1` 到 `4` |

總計（`Allowance/Amount`）`[mig 表 18-6]`：`TaxAmount`（整數，不可為負數）和 `TotalAmount`（未稅，整數，不可為負數）。境外電商在 `TotalAmount` 填含稅總額，`TaxAmount` 填 `0`。

## G0501：作廢折讓

所有欄位都在 `CancelAllowance` 下 `[mig 表 19-1, 19-2]`：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `CancelAllowanceNumber` | M | 折讓證明單號碼 |
| `AllowanceType` | M | `1` / `2` |
| `AllowanceDate` | M | `yyyyMMdd` |
| `BuyerId` | M | BAN |
| `SellerId` | M | BAN |
| `CancelDate` | M | `yyyyMMdd` |
| `CancelTime` | M | `xsd:time` |
| `CancelReason` | M | 1 到 20 字元 |
| `Remark` | O | 最多 200 |
