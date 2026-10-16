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
| Amego 光貿 | 電子發票 API | none yet | [amego/api.md](amego/api.md) |
| ECPay 綠界 | B2C 電子發票 API | `Einvoice::ECPay::Provider` | [ecpay/b2c.md](ecpay/b2c.md) |
| ezPay 簡單行動支付 | 電子發票 API (EZP_INVI 1.2.2) | none yet | [ezpay/invoice.md](ezpay/invoice.md) |
| Tradevan 關貿 | DEFAULTAPI | none yet | [tradevan/defaultapi.md](tradevan/defaultapi.md) |


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

Some notes also mark sections as a **proposal**. A proposal is not a fact about the provider. It is our plan for an adapter that does not exist yet: which field to send, which error class to raise. Change it freely when the adapter is built.

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

### 3. Operations

The endpoints. Give details only for the endpoints that the five unified operations use. List the others in one table, one line each, so an adapter can reach them through `raw`.

### 4. Mapping to the unified API

This is the main section. It holds every decision an adapter must make. Use tables, not prose, where you can.

- **4.1 Operations.** One row per unified operation: the endpoint, and what the caller must send in `provider_options`.
- **4.2 Fields.** One table per operation, for the request and for the result: unified field, provider field, rule or default. Say which unified fields are not sent, and which result fields the adapter fills itself.
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
