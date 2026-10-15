# MOF 財政部: MIG 4.1

English | [繁體中文](README.zh-TW.md)

## 1. Status and sources

The MIG (電子發票資料交換標準訊息建置指引, Message Implementation Guideline) is the Ministry of Finance's standard for e-invoice data. Every value-added center (加值中心) uploads invoices to the MOF platform in these message formats. So when a provider's docs are unclear, or two providers disagree, the MIG is the reference.

The MIG defines messages, not an API. A provider's API is its own design, but the data it sends to the MOF must fit these messages. So a provider rule that is stricter than the MIG may be the provider's own choice. A provider rule that is looser than the MIG means the provider fixes the data before upload, or rejects it later.

| Tag | Source | Date | What it gives |
| --- | --- | --- | --- |
| `[mig]` | 電子發票資料交換標準訊息建置指引 V4.1, 財政部財政資訊中心. [PDF](https://www.einvoice.nat.gov.tw/static/ptl/ein_upload/download/5340.pdf), 212 pages. We got it on 2026-10-14. | 2025-10-29 | All messages, fields, rules and code lists. |

References name the MIG table (表), for example `[mig 表 15-3]`. Table numbers are easier to find than page numbers, because the page numbers printed in the PDF do not match the PDF page index.

Everything in these notes is **documented**. The MIG is the standard itself, so there is nothing to verify it against.

### Files

| File | Content |
| --- | --- |
| README.md | This page: sources, changes, the message list, the mapping to the unified API, open questions |
| [codes.md](codes.md) | Shared types and code lists (MIG 第肆章) |
| [storage.md](storage.md) | Storage messages F0401, F0501, F0701, G0401, G0501 |
| [exchange.md](exchange.md) | B2B exchange messages A0101 to A0302, B0101 to B0202 |
| [numbering.md](numbering.md) | Number range messages E0401, E0402, E0501 |
| [platform.md](platform.md) | Platform files E0502, E0503, E0504, and the replies ProcessResult and SummaryResult |

### Recent changes that matter for adapters

- **V4.0 (2024-05-30).** The F/G messages replaced the old A0401, C0401, A0501, C0501, B0401, D0401, B0501 and D0501. F0401 dropped `CheckNumber`. Carrier IDs grew to 400 chars. Item `TaxType` was added. `NPOBAN` became a 10-char string.
- **V4.1 (2024-12-13).** The seller now issues and voids every allowance (統一發票使用辦法第 20 條之 1). `AllowanceType` is required and fixed to `2` in G0401. Amounts must not be negative.
- **V4.1 (2025-09-03, 2025-10-29).** Small fixes: more non-negative rules, and `RandomNumber` is optional in E0504.

## 2. Connection

Not in scope. The MIG defines the message content. The transport (Turnkey, or a value-added center) is defined elsewhere, and providers hide it behind their own APIs.

## 3. Operations

The MIG has 21 messages `[mig 表 3-1]`. B2B trades can use exchange (交換) or storage (存證) messages. B2C trades, and invoices on a carrier, use storage messages.

| Group | Messages | Use | Note |
| --- | --- | --- | --- |
| Storage | F0401, F0501, F0701, G0401, G0501 | B2C and B2B | [storage.md](storage.md) |
| Exchange | A0101, A0102, A0201, A0202, A0301, A0302, B0101, B0102, B0201, B0202 | B2B only | [exchange.md](exchange.md) |
| Number ranges | E0401, E0402, E0501 | all | [numbering.md](numbering.md) |
| Platform files | E0502, E0503, E0504 | all | [platform.md](platform.md) |
| Replies | ProcessResult, SummaryResult | all | [platform.md](platform.md) |

## 4. Mapping to the unified API

| Unified | MIG message | Note |
| --- | --- | --- |
| `issue` | F0401, or A0101 for B2B exchange | |
| `void` | F0501, or A0201 | Needs the invoice date (see below) |
| `allowance` | G0401, or B0101 | Needs each original invoice's date (see below) |
| `void_allowance` | G0501, or B0201 | Needs the allowance date |
| `query` | none | Queries are a provider feature. The MIG has no query message |

### What the MIG tells us about the unified API

These are the points where the MIG settles a question for us, or where our model and the MIG differ.

- **Voiding needs the invoice date.** F0501 requires `InvoiceDate` `[mig 表 16-2]`. A provider that does not ask for it must look it up or guess it. `VoidInvoiceInput` and `AllowanceInput` already have a `date` field, but the core does not say what it means: the operation date, or the invoice date. The ECPay adapter uses it as the invoice date. #36 discusses an explicit `invoice_date`.
- **An allowance needs each original invoice's number and date.** Every G0401 item requires `OriginalInvoiceNumber` and `OriginalInvoiceDate` `[mig 表 18-5]`.
- **Voiding an allowance needs the allowance date.** G0501 requires `AllowanceDate` `[mig 表 19-2]`. `VoidAllowanceInput` does not have it.
- **The void reason is required.** F0501 `CancelReason` and G0501 `CancelReason` are 1 to 20 chars `[mig 表 16-2, 19-2]`. `VoidAllowanceInput.reason` is optional, so an adapter must fill a default.
- **Allowance amounts exclude tax.** G0401 item `Amount` and total `TotalAmount` are tax-excluded. Each item also needs its own integer `Tax` `[mig 表 18-5, 18-6]`.
- **The random code is required for B2C.** F0401 `RandomNumber` is 4 digits. It is required when the buyer is a consumer, and optional for a business buyer `[mig 表 15-3]`.
- **Foreign currency is a memo only.** `Currency`, `OriginalCurrencyAmount` and `ExchangeRate` are optional notes. The legal amounts stay in TWD integers `[mig 表 15-6]`. This matches the unified `FOREIGN_CURRENCY` design. Cross-border sellers (境外電商) are the exception: they may list amounts in a foreign currency.
- **Mixed tax is header-level only.** The header `TaxType` can be `9` (mixed), but an item cannot `[mig 表 15-5, 4-12]`.
- **B2B exchange has states that the unified API does not have.** In exchange, an invoice is agreed only after the buyer confirms it (A0102), and the buyer can reject it (A0301). `InvoiceStatus` has no state for "waiting for the buyer" or "rejected". This matters only for a provider that sends B2B invoices through exchange (see 5, question 4). Details are in [exchange.md](exchange.md).
- **A B2B invoice through exchange cannot carry a carrier or mixed tax.** A0101 has no carrier fields, and its `TaxType` must not be `9`. F0401 allows both for a business buyer. So the `B2B` and `MIXED_TAX` capabilities can depend on which message a provider uses.
- **The MOF has its own invoice status list.** E0502 reports one of seven statuses: issued, voided or rejected, each confirmed or not, and cancelled ([codes](codes.md#invoice-status-currentstatus)). The unified `InvoiceStatus` has `issued`, `voided` and `allowance`. `allowance` is not an MOF invoice status: the MOF tracks an allowance as its own document with its own status. When a provider reports a status, check it against this list first.
- **F0701 is not a fix-up tool.** The MIG warns that F0701 must not be used to correct an invoice. Errors in an invoice need a void and a new invoice. Returns and discounts need an allowance `[mig F0701 訊息功能]`. The unified API has no operation for F0701, and should not get one without care.

## 5. Open questions

1. Item `Quantity`, `UnitPrice` and `Amount` allow 7 digits after the point, but the totals must be TWD integers. How do providers round item amounts? Each provider note should say.
2. The MIG says nothing about upload deadlines or the time a void is still allowed. Those rules live in other MOF documents. Which ones should we track?
3. The F0401 notes on `CarrierId1` and `CarrierId2` say two things that do not fit together. If `PrintMark` is `Y`, both must be blank. But if the buyer uses a mobile barcode, both are required "printed or not" `[mig 表 15-3]`. Which rule wins when a mobile barcode invoice is printed?
4. Do B2B invoices from our providers go through the exchange messages, or always through F0401? Each provider note should say. The answer decides if the points about exchange in 4 apply.
