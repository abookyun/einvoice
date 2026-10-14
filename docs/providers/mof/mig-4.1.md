# MOF 財政部: MIG 4.1

## 1. Status and sources

The MIG (電子發票資料交換標準訊息建置指引, Message Implementation Guideline) is the Ministry of Finance's standard for e-invoice data. Every value-added center (加值中心) uploads invoices to the MOF platform in these message formats. So when a provider's docs are unclear, or two providers disagree, the MIG is the reference.

The MIG defines messages, not an API. A provider's API is its own design, but the data it sends to the MOF must fit these messages. So a provider rule that is stricter than the MIG may be the provider's own choice. A provider rule that is looser than the MIG means the provider fixes the data before upload, or rejects it later.

| Tag | Source | Date | What it gives |
| --- | --- | --- | --- |
| `[mig]` | 電子發票資料交換標準訊息建置指引 V4.1, 財政部財政資訊中心. [PDF](https://www.einvoice.nat.gov.tw/static/ptl/ein_upload/download/5340.pdf), 212 pages. We got it on 2026-10-14. | 2025-10-29 | All messages, fields, rules and code lists. |

References below name the MIG table (表), for example `[mig 表 15-3]`. Table numbers are easier to find than page numbers, because the page numbers printed in the PDF do not match the PDF page index.

Everything in this note is **documented**. The MIG is the standard itself, so there is nothing to verify it against.

### Recent changes that matter for adapters

- **V4.0 (2024-05-30).** The F/G messages replaced the old A0401, C0401, A0501, C0501, B0401, D0401, B0501 and D0501. F0401 dropped `CheckNumber`. Carrier IDs grew to 400 chars. Item `TaxType` was added. `NPOBAN` became a 10-char string.
- **V4.1 (2024-12-13).** The seller now issues and voids every allowance (統一發票使用辦法第 20 條之 1). `AllowanceType` is required and fixed to `2` in G0401. Amounts must not be negative.
- **V4.1 (2025-09-03, 2025-10-29).** Small fixes: more non-negative rules, and `RandomNumber` is optional in E0504.

## 2. Connection

Not in scope. The MIG defines the message content. The transport (Turnkey, or a value-added center) is defined elsewhere, and providers hide it behind their own APIs.

## 3. Operations

The MIG has 21 messages `[mig 表 3-1]`. B2B trades can use exchange (交換) or storage (存證) messages. B2C trades, and invoices on a carrier, use storage messages. The storage messages are the ones that B2C providers send for us:

| Message | Name | Sender | Note |
| --- | --- | --- | --- |
| F0401 | 平台存證開立發票 | seller | Issue an invoice |
| F0501 | 平台存證作廢發票 | seller | Void an invoice |
| F0701 | 平台存證註銷發票 | seller | Cancel an invoice record. Not a correction tool, see 4 |
| G0401 | 平台存證開立折讓證明單 | seller | Issue an allowance |
| G0501 | 平台存證作廢折讓證明單 | seller (buyer, before V4.0) | Void an allowance |

The other messages are B2B exchange (A01–A03, B01–B02), number allocation (E04, E0501) and platform files (E0502–E0504). This note does not cover them yet.

## 4. Mapping to the unified API

| Unified | MIG message | Note |
| --- | --- | --- |
| `issue` | F0401 | |
| `void` | F0501 | Needs the invoice date (see below) |
| `allowance` | G0401 | Needs each original invoice's date (see below) |
| `void_allowance` | G0501 | Needs the allowance date |
| `query` | none | Queries are a provider feature. The MIG has no query message |

### What the MIG tells us about the unified API

These are the points where the MIG settles a question for us, or where our model and the MIG differ.

- **Voiding needs the invoice date.** F0501 requires `InvoiceDate` `[mig 表 16-2]`. A provider that does not ask for it must look it up or guess it. This supports adding `invoice_date` to `VoidInvoiceInput` (#36).
- **An allowance needs each original invoice's number and date.** Every G0401 item requires `OriginalInvoiceNumber` and `OriginalInvoiceDate` `[mig 表 18-5]`.
- **Voiding an allowance needs the allowance date.** G0501 requires `AllowanceDate` `[mig 表 19-2]`. `VoidAllowanceInput` does not have it.
- **The void reason is required.** F0501 `CancelReason` and G0501 `CancelReason` are 1 to 20 chars `[mig 表 16-2, 19-2]`. `VoidAllowanceInput.reason` is optional, so an adapter must fill a default.
- **Allowance amounts exclude tax.** G0401 item `Amount` and total `TotalAmount` are tax-excluded. Each item also needs its own integer `Tax` `[mig 表 18-5, 18-6]`.
- **The random code is required for B2C.** F0401 `RandomNumber` is 4 digits. It is required when the buyer is a consumer, and optional for a business buyer `[mig 表 15-3]`.
- **Foreign currency is a memo only.** `Currency`, `OriginalCurrencyAmount` and `ExchangeRate` are optional notes. The legal amounts stay in TWD integers `[mig 表 15-6]`. This matches the unified `FOREIGN_CURRENCY` design. Cross-border sellers (境外電商) are the exception: they may list amounts in a foreign currency.
- **Mixed tax is header-level only.** The header `TaxType` can be `9` (mixed), but an item cannot `[mig 表 15-5, 4-12]`.
- **F0701 is not a fix-up tool.** The MIG warns that F0701 must not be used to correct an invoice. Errors in an invoice need a void and a new invoice. Returns and discounts need an allowance `[mig F0701 訊息功能]`. The unified API has no operation for F0701, and should not get one without care.

## 5. Field reference

### 5.1 F0401: issue an invoice

Header (`Invoice/Main`) `[mig 表 15-1, 15-3]`. "M" means required, "O" means optional.

| Field | M/O | Rule |
| --- | --- | --- |
| `InvoiceNumber` | M | `[A-Z]{2}\d{8}` (6.1) |
| `InvoiceDate` | M | `yyyyMMdd`, UTC+8 (6.2) |
| `InvoiceTime` | M | `xsd:time`, UTC+8 |
| `Seller` | M | Role (5.6). `Address` is required for the seller |
| `Buyer` | M | Role (5.6) |
| `BuyerRemark` | O | `1` to `4` (6.9) |
| `MainRemark` | O | max 200 |
| `CustomsClearanceMark` | O | `1` / `2`. Required for zero rated (6.8) |
| `Category` | O | max 2 (沖帳別) |
| `RelateNumber` | O | max 20 |
| `InvoiceType` | M | `07` / `08` (6.3) |
| `GroupMark` | O | `*` means a grouped invoice (彙開) |
| `DonateMark` | M | `0` / `1`. If `1`, `NPOBAN` must not be blank |
| `CarrierType` | O | 6 chars (6.5). Blank when there is no carrier |
| `CarrierId1` | O | max 400. The visible code (顯碼) |
| `CarrierId2` | O | max 400. The hidden code (隱碼) that the barcode reader reads |
| `PrintMark` | M | `Y` / `N` |
| `NPOBAN` | O | max 10. A 3 to 7 digit donation code, or the recipient's 統一編號 |
| `RandomNumber` | O | 4 digits. Required when the buyer is a consumer |
| `BondedAreaConfirm` | O | `1` to `4` |
| `ZeroTaxRateReason` | O | `71` to `79`. Required for zero rated (6.7) |
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
| `TaxType` | M | `1`, `2`, `3`, `4` or `9` |
| `TaxRate` | M | See 6.6 |
| `TaxAmount` | M | Integer, not negative |
| `TotalAmount` | M | Integer in TWD, not negative |
| `DiscountAmount` | O | Memo only |
| `OriginalCurrencyAmount` | O | Memo only |
| `ExchangeRate` | O | Memo only. 13 digits, up to 5 after the point |
| `Currency` | O | ISO 4217. Required for cross-border sellers |

How to fill the amounts `[mig 表 15-6, 註 1, 註 2]`:

- Tax is rounded half up to a whole dollar (營業稅法第 14 條).
- For a business buyer, the invoice shows sales and tax separately. For a consumer, it shows the price with tax included (營業稅法第 32 條). The upload must match what was issued.

### 5.2 F0501: void an invoice

All fields under `CancelInvoice` `[mig 表 16-1, 16-2]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `CancelInvoiceNumber` | M | Invoice number (6.1) |
| `InvoiceDate` | M | `yyyyMMdd` |
| `BuyerId` | M | BAN (6.10). `0000000000` for a consumer |
| `SellerId` | M | BAN |
| `CancelDate` | M | `yyyyMMdd` |
| `CancelTime` | M | `xsd:time` |
| `CancelReason` | M | 1 to 20 chars |
| `ReturnTaxDocumentNumber` | O | max 60. 專案作廢核准文號 |
| `Remark` | O | max 200 |
| `Reserved1`, `Reserved2` | O | max 20, max 100 |

### 5.3 F0701: cancel an invoice record

All fields under `VoidInvoice` `[mig 表 17-1, 17-2]`: `VoidInvoiceNumber`, `InvoiceDate`, `BuyerId`, `SellerId`, `VoidDate`, `VoidTime` and `VoidReason` (1 to 20 chars) are required. `Remark` (max 200), `Reserved1` and `Reserved2` are optional.

### 5.4 G0401: issue an allowance

Header (`Allowance/Main`) `[mig 表 18-1, 18-3]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `AllowanceNumber` | M | max 16. Must be unique, also across years (6.4) |
| `AllowanceDate` | M | `yyyyMMdd` |
| `Seller` | M | Role (5.6). `Address` is required |
| `Buyer` | M | Role (5.6) |
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

### 5.5 G0501: void an allowance

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

### 5.6 Seller and buyer (`RoleDescriptionType`)

`[mig 表 4-2]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `Identifier` | M | BAN. For a consumer buyer, ten `0` |
| `Name` | M | 1 to 60 chars. See below |
| `Address` | O | max 100. Required for the seller in F0401 and G0401 |
| `PersonInCharge` | O | max 30 |
| `TelephoneNumber` | O | max 26 |
| `FacsimileNumber` | O | max 26 |
| `EmailAddress` | O | max 400 |
| `CustomerNumber` | O | max 20 |
| `RoleRemark` | O | 40 |

`Name` for the buyer:

- Business buyer: the company name. If the law lets the buyer skip the name, use the buyer's 統一編號.
- Consumer: a personal ID code (個人識別碼) that lets the consumer check the invoice on the MOF platform. It must not be `0`, `00`, `000` or `0000`. Use one of these:
  1. The consumer's name.
  2. If the invoice is printed, or stored on a carrier that is not a member carrier: the same value as the random code.
  3. If the invoice is stored on a member carrier: a value the seller designs, for example the last four chars of the carrier or the first four chars of the member's email.

## 6. Codes

### 6.1 Invoice number (`InvoiceNumberType`)

10 chars, `[A-Z]{2}\d{8}`. Example `QQ12345678` `[mig 表 4-10]`.

### 6.2 Date and time (`DateType`, `TimeType`)

Date is `yyyyMMdd` in the western calendar, for example `20240101`. Time is `xsd:time`. Both are in UTC+8. The platform ignores any time zone in the data `[mig 表 4-15, 4-16]`.

### 6.3 Invoice type (`InvoiceTypeEnum`)

| Code | Meaning |
| --- | --- |
| `07` | General tax (一般稅額計算) |
| `08` | Special tax (特種稅額計算) |

### 6.4 Allowance number (`AllowanceNumberType`)

1 to 16 chars. The seller's system assigns it. The platform rejects a number that was used before, also in an earlier year `[mig 表 4-5]`.

### 6.5 Carrier type (`CarrierTypeEnum`)

6 chars `[mig 表 4-13, 15-3]`:

| Code | Meaning |
| --- | --- |
| `3J0002` | Mobile barcode (手機條碼) |
| `CQ0001` | Citizen certificate (自然人憑證條碼) |
| `5G0001` | Cross-border email carrier (跨境電商電子郵件載具) |
| other | A code the MOF platform gives to a seller or center. Char 1 is the trade, char 2 is the carrier class, chars 3 to 6 are a serial number |

### 6.6 Tax type and tax rate (`TaxTypeEnum`, `TaxRateEnum`)

Tax type `[mig 表 4-12]`:

| Code | Meaning |
| --- | --- |
| `1` | Taxable (應稅) |
| `2` | Zero rated (零稅率) |
| `3` | Tax free (免稅) |
| `4` | Taxable, special rate (應稅, 特種稅率) |
| `9` | Mixed taxable with tax free or zero rated. F0401 header only |

Tax rate `[mig 表 4-18]`: one of `0`, `0.01`, `0.02`, `0.05`, `0.15`, `0.25`. A 5% rate is `0.05`.

### 6.7 Zero tax rate reason (`ZeroTaxRateReasonEnum`)

`71` to `79`, one per paragraph of 營業稅法第 7 條 `[mig 表 4-19]`. `71` is export of goods (外銷貨物). Required when the tax type is zero rated.

### 6.8 Customs clearance (`CustomsClearanceMarkEnum`)

| Code | Meaning |
| --- | --- |
| `1` | Export not through customs (非經海關出口) |
| `2` | Export through customs (經海關出口) |

Required for zero rated invoices `[mig 表 4-9]`.

### 6.9 Buyer remark (`BuyerRemarkEnum`)

`1` deductible purchases and expenses, `2` deductible fixed assets, `3` non-deductible purchases and expenses, `4` non-deductible fixed assets `[mig 表 4-8]`.

### 6.10 BAN

8 to 10 digits, digits only (since V4.1). A business buyer or seller uses its 統一編號. A consumer buyer uses `0000000000` `[mig 表 4-7]`.

### 6.11 Donation (`DonateMarkEnum`)

`0` not donated, `1` donated `[mig 表 4-11]`. A seller must accept a donation code that the buyer gives at the time of sale. Cross-border sellers (營業稅法第 6 條第 4 款) are the exception.

## 7. Open questions

1. Item `Quantity`, `UnitPrice` and `Amount` allow 7 digits after the point, but the totals must be TWD integers. How do providers round item amounts? Each provider note should say.
2. The MIG says nothing about upload deadlines or the time a void is still allowed. Those rules live in other MOF documents. Which ones should we track?
3. The F0401 notes on `CarrierId1` and `CarrierId2` say two things that do not fit together. If `PrintMark` is `Y`, both must be blank. But if the buyer uses a mobile barcode, both are required "printed or not" `[mig 表 15-3]`. Which rule wins when a mobile barcode invoice is printed?
4. The B2B exchange messages (A01–A03, B01–B02) are not covered. Do we need them for the `B2B` capability, or do B2B invoices from our providers always go through F0401?
