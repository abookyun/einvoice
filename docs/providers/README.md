# Provider references

English | [繁體中文](README.zh-TW.md)

These notes are for people who build or maintain an adapter. They are not user documentation.

Each provider publishes its API in its own way. Some publish full public docs. Some only send a PDF to customers. Some publish nothing. We read what the provider gives us, and then we write down the parts that adapter work needs, in one shape for every provider.

The provider docs belong to the provider. We link to them, and we do not copy their text into this repository. Each note is our own summary.

## The MOF standard

All providers send their invoices to the Ministry of Finance in the formats of the MIG. So the MIG is the reference when a provider's docs are unclear, or when two providers disagree. Read it first.

| Standard | Version | Note |
| --- | --- | --- |
| MIG 電子發票資料交換標準訊息建置指引 | 4.1 | [mof/mig-4.1/](mof/mig-4.1/README.md) |

The MOF also runs an open data API. `Einvoice::MOF::DonationCodes` uses it to check donation codes: [mof/ods-api.md](mof/ods-api.md).

## Providers

| Provider | API | Adapter in 2.x | Note |
| --- | --- | --- | --- |
| Amego 光貿 | 電子發票 API | in progress | [amego/api.md](amego/api.md) |
| ECPay 綠界 | B2C 電子發票 API | `Einvoice::ECPay::Provider` | [ecpay/b2c.md](ecpay/b2c.md) |
| ezPay 簡單行動支付 | 電子發票 API (EZP_INVI 1.2.2) | in progress | [ezpay/invoice.md](ezpay/invoice.md) |
| Tradevan 關貿 | DEFAULTAPI | in progress | [tradevan/defaultapi.md](tradevan/defaultapi.md) |

### Providers at a glance

Details and sources are in each note.

| | ECPay | Amego | ezPay | Tradevan DEFAULTAPI |
| --- | --- | --- | --- | --- |
| Verified | Adapter built. Stage runs recorded (2026-08) | Public test account runs (2026-10) | Docs only. Our crypto matches the manual's samples. No live run | 1.x code in production. No account today |
| Request | JSON, `Data` in AES-128-CBC | Form, JSON in `data`, MD5 `sign` | Form, query string in AES-256-CBC (hex) | Query param `v`, AES-128-CBC with zero padding, two keys |
| Test account | Public, shared | Public, shared | Own test shop | None. Hosts unknown |
| Void needs | Number, invoice date, reason (max 20) | Number. Reason optional | Number, reason (max 6 Chinese chars) | Number, order id (`saleIdentifier`) |
| Void timing | Right away | Queued. May not be done yet | Only after the next day's upload | Unknown |
| Allowance amounts | Tax included | Tax excluded, tax per item | Either | The header has all three: without tax, tax, with tax |
| Allowance number | ECPay assigns | Seller assigns | ezPay assigns | Unknown |
| Query by number needs | Invoice date | Nothing more (180 days) | Random code | Nothing more |

## The unified model

Section 4 of every note maps the provider onto these rules. The core types follow them.

**References.** Void, allowance and query take `invoice:`. It is an `InvoiceReference`, or a plain invoice number. Void allowance takes `allowance:`. It is an `AllowanceReference`, or a plain allowance number. The results of issue, query and allowance return a reference as `#reference`. A reference holds the facts about an existing document that providers ask for:

| Reference | Fields |
| --- | --- |
| `InvoiceReference` | `number`, `invoice_datetime`, `random_code`, `order_id`, `total_amount` |
| `AllowanceReference` | `allowance_number`, `allowance_date`, `invoice_number` |

When a provider needs a field that the caller did not give, the adapter may query the provider for it. If it cannot, it raises `ValidationError` and names the field. It never fills in a guess.

**Dates.** An input does not carry the time of the operation itself. The provider records that time. If a provider asks for it, the adapter sends the current time in UTC+8. Names and types follow the MIG:

| Field | Type | MIG |
| --- | --- | --- |
| `invoice_datetime` | `Time`, UTC+8 | `InvoiceDate` and `InvoiceTime` |
| `allowance_date` | `Date` | `AllowanceDate` |
| `cancel_datetime` | `Time`, UTC+8. `nil` when the provider does not return it | `CancelDate` and `CancelTime` |

**Amounts.** An invoice follows F0401. For a consumer, `sales_amount` includes tax and `tax_amount` is `0`. For a business buyer, `sales_amount` excludes tax and `tax_amount` holds the tax. An allowance follows G0401: its amounts exclude tax. If the caller gives `tax_amount` `0`, the core splits the tax out of the taxable items. It rounds half up and puts the remainder on the last taxable item. Only the core computes tax. Adapters use its result.

**Tax rate.** `tax_rate` is a decimal, for example `0.05`. The core accepts the MIG rates only: `0`, `0.01`, `0.02`, `0.05`, `0.15` and `0.25` `[mig 表 4-18]`. The default is `0.05` for taxable sales and `0` for zero-rated or tax-free sales. When a provider cannot send a rate, the adapter raises `UnsupportedError`.

**Input checks.** The core checks these before an adapter runs:

- `ubn` is 8 digits. A B2B invoice needs one. If the caller sets `category`, it must agree with `ubn`.
- Totals are integers and not negative. Item quantity, price and amount are numbers with at most 7 decimals.
- A mobile barcode is `/` and 7 characters. A citizen certificate is 2 letters and 14 digits.
- A void reason is 1 to 20 characters. A void allowance reason is optional. The core fills `作廢折讓` when it is missing.
- A donation and a carrier can both be set. The MIG allows it.

**Status.** `QueryInvoiceResult#status` is `nil` when the provider's status cannot be mapped to `InvoiceStatus`.

**Errors.** Every failure is an `Einvoice::Error`, never a plain Ruby error.

- Each provider has its own default class for an error code that we do not know. Section 6.4 gives it, with the evidence.
- HTTP 5xx and 429 are a `NetworkError`, so the caller can retry.
- `Reason::RETRY_LATER` means the provider says "not now, try later", for example a void before the invoice is uploaded.

**Capabilities.**

- `QUERY_BY_ORDER_ID` means the provider can find an invoice from data that the caller knows, without the invoice number. The caller passes an `InvoiceReference` with `order_id`, and `total_amount` if the provider needs it.
- `CARRIER_VALIDATION` means the adapter implements `Provider#validate_carrier`.

**Connection.** `base_url` must use https. Only localhost may use http.

## Sources and trust

Every fact in a note has a source tag. The tag tells you how much to trust the fact. Each note lists its tags at the top.

| Kind of source | Example tags | Trust |
| --- | --- | --- |
| Provider docs | `[doc]`, or one short tag per document, for example `[inv]` | documented: the provider says it, nobody checked it live |
| Our live runs and recorded responses | `[live]` | verified: we saw it. The note says when |
| Code that runs in production, or a production report | `[prod]` | verified in production |
| Our 2.x adapter code | `[code]` | what our adapter does. Not proof of what the API does |
| The 1.x client code | `[1x-code]` | what the old client does. It ran in production for years |
| The MOF standard | `[mig 表 x-y]` | the standard. See the MIG note |

Two more marks have no tag:

- **(inferred)**: we worked it out from other facts. The text says from which ones. It is a claim about the provider.
- **unknown**: we do not know. It goes into the open questions.

Section 4 and the class columns in 6.4 are not facts about the provider. They are the mapping that the adapter follows: which field to send, which error class to raise. Write them from the provider docs and the unified model, before the adapter. When an adapter has to differ, change the note in the same pull request.

`[doc]` always means the provider's own docs. Our own old summaries get a different tag.

When a live run shows that a provider doc is wrong, keep both. Write what the doc says, then what the API really does.

## Provider note layout

Each provider note uses these sections, in this order. A section can be short, but do not drop it.

### 1. Status and sources

- Which API, which version, and if the 2.x line has an adapter for it.
- One line on how far to trust the note: is there an adapter, and was anything verified live.
- Who owns the docs, with a link, and a line that says the note is our summary.
- The source table: tag, source, date, what it gives.
- How to check for updates: a change log page, a version number, or a file date.

### 2. Connection

Hosts, credentials, test accounts, signing or encryption, and the request and response envelopes. Give one real or documented example of a full request and a full response, with the payload shown both before and after encryption if that helps.

**Limits of the API.** Say what the API does not protect, so users know what to guard: for example no signature on responses, credentials in the URL, or a fixed IV.

**Official test vectors.** List every sample in the docs that gives both the inputs and the output of a signature, an encryption or a check code: the key, the input, and the expected result. Say which spec uses it. If the docs have none, say so. A test vector checks the wire format without a test account, so look through the appendices for one before you write the adapter.

### 3. Operations

The endpoints. Give details only for the endpoints that the five unified operations use. List the others in one table, one line each, so an adapter can reach them through `raw`.

### 4. Mapping to the unified API

This is the main section. It holds every decision an adapter must make. Use tables, not prose, where you can.

- **4.1 Operations.** One row per unified operation: the endpoint, the reference fields it needs, and anything else the caller must send in `provider_options`.
- **4.2 Fields.** One table per operation, for the request and for the result: unified field, provider field, rule or default. Say which unified fields are not sent, and which result fields the adapter fills itself. Dates and references follow [the unified model](#the-unified-model).
- **4.3 Amounts and tax.** How `AmountSummary` and item amounts map to the provider totals, for invoices and allowances. Say if amounts include tax, who computes the tax, and how rounding works.
- **4.4 Status.** Provider status values and the unified `InvoiceStatus` for each.
- **4.5 Timing.** Deadlines and delays: upload time, void deadline, when a new invoice can be voided.
- **4.6 Capabilities.** One row for each flag in `Capability::ALL`: does the API support it, does the adapter declare it, and under what conditions.
- **4.7 Against the MIG.** Where the provider is stricter or looser than the MIG, or differs from it.
- **4.8 Contract and live tests.** Anything that changes how the shared contract (`spec/support/shared_examples/invoice_provider.rb`) or a live spec runs against this provider: the sandbox, number formats, inputs the contract does not send, and steps that cannot run in a test.

### 5. Field reference

Request and response fields for the endpoints in 4.1, with their rules. "M" means required, "O" means optional. Put conditions in the rule, for example "M when `Print` is `1`".

### 6. Codes

Enum values and error codes. Error code tables have these columns: code, meaning, unified error class, `Reason`, source. Leave the class empty when we have not decided.

### 7. Open questions

Everything marked unknown, in one list.

## Standard note layout

A standard, such as the MIG, is not an API. Its note has:

1. **Status and sources.** As for a provider note.
2. **Content.** The messages or data, split into files when the note grows long.
3. **Mapping to the unified API.** What the standard tells us about the unified model.
4. **Open questions.**

## API versions

A provider can have more than one API version in use at the same time. Each version gets its own note, named after the version, for example `tradevan/defaultapi.md`. A newer version does not replace the older note while people still use the older API.
