# MIG 4.1: exchange messages

English | [繁體中文](exchange.zh-TW.md)

The exchange (交換) messages: A0101 to A0302 and B0101 to B0202. Only B2B trades use them. Sources and tags are in [README.md](README.md). Types and code lists are in [codes.md](codes.md). The storage messages are in [storage.md](storage.md).

"M" means required, "O" means optional.

## How exchange works

A storage message goes from the seller to the MOF platform, and that is the end of it. An exchange message goes from one business to the other through the platform, and the other side answers with a confirm message. The two sides reach an exchange agreement (交換合意) only after the confirm `[mig 第伍章 to 第壹拾肆章, 訊息功能]`.

| Action | Message | From → to | Confirm | From → to |
| --- | --- | --- | --- | --- |
| Issue an invoice | A0101 | seller → buyer | A0102 | buyer → seller |
| Void an invoice | A0201 | seller → buyer | A0202 | buyer → seller |
| Reject an invoice (退回／拒收) | A0301 | buyer → seller | A0302 | seller → buyer |
| Issue an allowance | B0101 | seller → buyer | B0102 | buyer → seller |
| Void an allowance | B0201 | seller → buyer | B0202 | buyer → seller |

Before V4.0, a buyer could issue an allowance and then void it with B0201. Since V4.1 the seller issues and voids every allowance `[mig 表 4-6]`.

The buyer uses A0301 when the content of an invoice is wrong, for example the quantity, the price or the product name `[mig 第壹拾參章]`. Storage messages have no such step.

## A0101: issue an invoice

A0101 has the same structure as F0401, with these differences `[mig 表 5-1, 5-3, 5-5, 5-6]`:

- **No carrier, print or donation details.** A0101 has no `CarrierType`, `CarrierId1`, `CarrierId2`, `PrintMark`, `NPOBAN`, `RandomNumber` or `BondedAreaConfirm`. `DonateMark` is still required.
- **The buyer gives the bonded area mark.** `BondedAreaConfirm` is in the buyer's confirm, A0102, not in A0101.
- **No mixed tax.** The header `TaxType` must not be `9`.
- **One sales total.** `Invoice/Amount` has only `SalesAmount`. There is no `FreeTaxSalesAmount` or `ZeroTaxSalesAmount`.
- **Totals are whole numbers.** `SalesAmount`, `TaxAmount`, `TotalAmount` and `DiscountAmount` allow no digits after the point. Round half up. For a business buyer, `SalesAmount` excludes tax.
- **`Description` and `SequenceNumber` need at least 1 char.**

The other header fields are the same as F0401: `InvoiceNumber`, `InvoiceDate`, `InvoiceTime`, `Seller`, `Buyer`, `BuyerRemark`, `MainRemark`, `CustomsClearanceMark`, `Category`, `RelateNumber`, `InvoiceType`, `GroupMark`, `ZeroTaxRateReason`, `Reserved1` and `Reserved2`. Items and the memo fields (`OriginalCurrencyAmount`, `ExchangeRate`, `Currency`) are the same as well.

Totals (`Invoice/Amount`) `[mig 表 5-6]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `SalesAmount` | M | Integer, not negative. Tax excluded for a business buyer |
| `TaxType` | M | `1` to `4`. Not `9` |
| `TaxRate` | M | See [codes](codes.md#tax-type-and-tax-rate-taxtypeenum-taxrateenum) |
| `TaxAmount` | M | Integer, not negative |
| `TotalAmount` | M | Integer, not negative |
| `DiscountAmount` | O | Integer. Memo only |
| `OriginalCurrencyAmount` | O | Memo only |
| `ExchangeRate` | O | Memo only |
| `Currency` | O | Memo only |

## A0102: confirm an invoice

From the buyer, under `InvoiceConfirm` `[mig 表 6-1, 6-2]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `InvoiceNumber` | M | Invoice number |
| `InvoiceDate` | M | `yyyyMMdd` |
| `BuyerId` | M | BAN |
| `SellerId` | M | BAN |
| `ReceiveDate` | M | `yyyyMMdd` |
| `ReceiveTime` | M | `xsd:time` |
| `BuyerRemark` | O | `1` to `4` ([codes](codes.md#buyer-remark-buyerremarkenum)) |
| `Remark` | O | max 200 |
| `BondedAreaConfirm` | O | `1` to `4` ([codes](codes.md#bonded-area-bondedareaenum)) |

## A0201: void an invoice

The same fields as F0501 ([storage](storage.md#f0501-void-an-invoice)), under `CancelInvoice` `[mig 表 9-1, 9-2]`. `InvoiceDate` is required here too.

## A0202: confirm a void

From the buyer, under `CancelInvoiceConfirm` `[mig 表 10-1, 10-2]`: `CancelInvoiceNumber`, `InvoiceDate`, `BuyerId`, `SellerId`, `CancelDate` and `CancelTime` are required. `Remark` (max 200) is optional.

## A0301: reject an invoice

From the buyer, under `RejectInvoice` `[mig 表 13-1, 13-2]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `RejectInvoiceNumber` | M | Invoice number |
| `InvoiceDate` | M | `yyyyMMdd` |
| `BuyerId` | M | BAN |
| `SellerId` | M | BAN |
| `RejectDate` | M | `yyyyMMdd` |
| `RejectTime` | M | `xsd:time` |
| `RejectReason` | M | max 20 |
| `Remark` | O | max 200 |
| `Reserved1`, `Reserved2` | O | max 20, max 100 |

## A0302: confirm a rejection

From the seller, under `RejectInvoiceConfirm` `[mig 表 14-1, 14-2]`: `RejectInvoiceNumber`, `InvoiceDate`, `BuyerId`, `SellerId`, `RejectDate` and `RejectTime` are required. `Remark` (max 200) is optional.

## B0101: issue an allowance

The same structure as G0401 ([storage](storage.md#g0401-issue-an-allowance)), with these differences `[mig 表 7-1, 7-3, 7-5, 7-6]`:

- `Seller` and `Buyer` may carry `RoleRemark`. G0401 has no `RoleRemark`.
- There are no rules for cross-border sellers. Item `Amount` and `Tax`, and the totals `TaxAmount` and `TotalAmount`, are integers. Round half up.
- `AllowanceType` is required and fixed to `2`, as in G0401.

## B0102: confirm an allowance

From the buyer, under `AllowanceConfirm` `[mig 表 8-1]`: `AllowanceNumber`, `AllowanceDate`, `BuyerId`, `SellerId`, `ReceiveDate`, `ReceiveTime` and `AllowanceType` are required. `Remark` (max 200) is optional.

## B0201: void an allowance

The same fields as G0501 ([storage](storage.md#g0501-void-an-allowance)), under `CancelAllowance` `[mig 表 11-1, 11-2]`. `AllowanceDate` is required here too.

## B0202: confirm an allowance void

From the other side, under `CancelAllowanceConfirm` `[mig 表 12-1, 12-2]`: `CancelAllowanceNumber`, `AllowanceDate`, `BuyerId`, `SellerId`, `AllowanceType`, `CancelDate` and `CancelTime` are required. `Remark` (max 200) is optional.
