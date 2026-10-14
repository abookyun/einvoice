# MIG 4.1: storage messages

The storage (存證) messages: F0401, F0501, F0701, G0401 and G0501. B2C trades use them, and B2B trades may use them. Sources and tags are in [README.md](README.md). Types and code lists are in [codes.md](codes.md).

"M" means required, "O" means optional.

## F0401: issue an invoice

Header (`Invoice/Main`) `[mig 表 15-1, 15-3]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `InvoiceNumber` | M | `[A-Z]{2}\d{8}` ([codes](codes.md#invoice-number-invoicenumbertype)) |
| `InvoiceDate` | M | `yyyyMMdd`, UTC+8 ([codes](codes.md#date-and-time-datetype-timetype)) |
| `InvoiceTime` | M | `xsd:time`, UTC+8 |
| `Seller` | M | Role ([codes](codes.md#seller-and-buyer-roledescriptiontype)). `Address` is required for the seller |
| `Buyer` | M | Role |
| `BuyerRemark` | O | `1` to `4` ([codes](codes.md#buyer-remark-buyerremarkenum)) |
| `MainRemark` | O | max 200 |
| `CustomsClearanceMark` | O | `1` / `2`. Required for zero rated ([codes](codes.md#customs-clearance-customsclearancemarkenum)) |
| `Category` | O | max 2 (沖帳別) |
| `RelateNumber` | O | max 20 |
| `InvoiceType` | M | `07` / `08` ([codes](codes.md#invoice-type-invoicetypeenum)) |
| `GroupMark` | O | `*` means a grouped invoice (彙開) |
| `DonateMark` | M | `0` / `1`. If `1`, `NPOBAN` must not be blank |
| `CarrierType` | O | 6 chars ([codes](codes.md#carrier-type-carriertypeenum)). Blank when there is no carrier |
| `CarrierId1` | O | max 400. The visible code (顯碼) |
| `CarrierId2` | O | max 400. The hidden code (隱碼) that the barcode reader reads |
| `PrintMark` | M | `Y` / `N` |
| `NPOBAN` | O | max 10. A 3 to 7 digit donation code, or the recipient's 統一編號 |
| `RandomNumber` | O | 4 digits. Required when the buyer is a consumer |
| `BondedAreaConfirm` | O | `1` to `4` |
| `ZeroTaxRateReason` | O | `71` to `79`. Required for zero rated ([codes](codes.md#zero-tax-rate-reason-zerotaxratereasonenum)) |
| `Reserved1`, `Reserved2` | O | max 20, max 100 |

Rules across fields `[mig 表 15-3]`:

- If `PrintMark` is `Y`: `CarrierType`, `CarrierId1` and `CarrierId2` must be blank, and `DonateMark` must be `0`.
- If `CarrierId1` or `CarrierId2` is not blank, `PrintMark` must be `N`.
- A buyer who uses a mobile barcode (also with a 統一編號 on the invoice) needs `CarrierId1` and `CarrierId2`, printed or not.
- `CarrierId1` and `CarrierId2` must not start or end with a space, half-width or full-width.

Items (`Invoice/Details/ProductItem`), 1 to 9999 `[mig 表 15-5]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `Description` | M | max 500 |
| `Quantity` | M | decimal, 20 digits, up to 7 after the point |
| `Unit` | O | max 6 |
| `UnitPrice` | M | decimal, 20 digits, up to 7 after the point |
| `TaxType` | M | `1` to `4`. Not `9` |
| `Amount` | M | decimal, 20 digits, up to 7 after the point |
| `SequenceNumber` | M | max 4 |
| `Remark` | O | max 120. Write `健康捐` for a health tax item |
| `RelateNumber` | O | max 50. A product code is written as `{A...}` (international) or `{Z...}` (other) |

Totals (`Invoice/Amount`) `[mig 表 15-6]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `SalesAmount` | M | Taxable sales total. Integer in TWD, `0` if none, not negative |
| `FreeTaxSalesAmount` | M | Tax free sales total. Integer, `0` if none |
| `ZeroTaxSalesAmount` | M | Zero rated sales total. Integer, `0` if none |
| `TaxType` | M | `1`, `2`, `3`, `4` or `9` ([codes](codes.md#tax-type-and-tax-rate-taxtypeenum-taxrateenum)) |
| `TaxRate` | M | See [codes](codes.md#tax-type-and-tax-rate-taxtypeenum-taxrateenum) |
| `TaxAmount` | M | Integer, not negative |
| `TotalAmount` | M | Integer in TWD, not negative |
| `DiscountAmount` | O | Memo only |
| `OriginalCurrencyAmount` | O | Memo only |
| `ExchangeRate` | O | Memo only. 13 digits, up to 5 after the point |
| `Currency` | O | ISO 4217. Required for cross-border sellers |

How to fill the amounts `[mig 表 15-6, 註 1, 註 2]`:

- Tax is rounded half up to a whole dollar (營業稅法第 14 條).
- For a business buyer, the invoice shows sales and tax separately. For a consumer, it shows the price with tax included (營業稅法第 32 條). The upload must match what was issued.

## F0501: void an invoice

All fields under `CancelInvoice` `[mig 表 16-1, 16-2]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `CancelInvoiceNumber` | M | Invoice number |
| `InvoiceDate` | M | `yyyyMMdd` |
| `BuyerId` | M | BAN ([codes](codes.md#ban)). `0000000000` for a consumer |
| `SellerId` | M | BAN |
| `CancelDate` | M | `yyyyMMdd` |
| `CancelTime` | M | `xsd:time` |
| `CancelReason` | M | 1 to 20 chars |
| `ReturnTaxDocumentNumber` | O | max 60. 專案作廢核准文號 |
| `Remark` | O | max 200 |
| `Reserved1`, `Reserved2` | O | max 20, max 100 |

## F0701: cancel an invoice record

All fields under `VoidInvoice` `[mig 表 17-1, 17-2]`: `VoidInvoiceNumber`, `InvoiceDate`, `BuyerId`, `SellerId`, `VoidDate`, `VoidTime` and `VoidReason` (1 to 20 chars) are required. `Remark` (max 200), `Reserved1` and `Reserved2` are optional.

## G0401: issue an allowance

Header (`Allowance/Main`) `[mig 表 18-1, 18-3]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `AllowanceNumber` | M | max 16. Must be unique, also across years ([codes](codes.md#allowance-number-allowancenumbertype)) |
| `AllowanceDate` | M | `yyyyMMdd` |
| `Seller` | M | Role. `Address` is required |
| `Buyer` | M | Role |
| `AllowanceType` | M | Fixed to `2` since V4.1 |
| `OriginalInvoiceSellerId` | O | BAN. Only when the seller's 統一編號 changed, or the seller merged into another company |
| `OriginalInvoiceBuyerId` | O | BAN. The same, for the buyer |

Items (`Allowance/Details/ProductItem`), 1 to 9999 `[mig 表 18-5]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `OriginalInvoiceDate` | M | `yyyyMMdd` |
| `OriginalInvoiceNumber` | M | Invoice number |
| `OriginalSequenceNumber` | O | max 4. The item's `SequenceNumber` on the original invoice |
| `OriginalDescription` | M | max 500 |
| `Quantity` | M | decimal, up to 7 after the point |
| `Unit` | O | max 6 |
| `UnitPrice` | M | decimal, up to 7 after the point |
| `Amount` | M | Tax excluded. Integer in TWD |
| `Tax` | M | Integer. `0` for cross-border sellers |
| `AllowanceSequenceNumber` | M | max 4 |
| `TaxType` | M | `1` to `4` |

Totals (`Allowance/Amount`) `[mig 表 18-6]`: `TaxAmount` (integer, not negative) and `TotalAmount` (tax excluded, integer, not negative). Cross-border sellers put the tax-included total in `TotalAmount` and `0` in `TaxAmount`.

## G0501: void an allowance

All fields under `CancelAllowance` `[mig 表 19-1, 19-2]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `CancelAllowanceNumber` | M | Allowance number |
| `AllowanceType` | M | `1` / `2` |
| `AllowanceDate` | M | `yyyyMMdd` |
| `BuyerId` | M | BAN |
| `SellerId` | M | BAN |
| `CancelDate` | M | `yyyyMMdd` |
| `CancelTime` | M | `xsd:time` |
| `CancelReason` | M | 1 to 20 chars |
| `Remark` | O | max 200 |
