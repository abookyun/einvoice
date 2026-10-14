# Provider references

These notes are for people who build or maintain an adapter. They are not user documentation.

Each provider publishes its API in its own way. Some publish full public docs. Some only send a PDF to customers. Some publish nothing. We read what the provider gives us, and then we write down the parts that adapter work needs, in one shape for every provider.

## The MOF standard

All providers send their invoices to the Ministry of Finance in the formats of the MIG. So the MIG is the reference when a provider's docs are unclear, or when two providers disagree. Read it first.

| Standard | Version | Note |
| --- | --- | --- |
| MIG 電子發票資料交換標準訊息建置指引 | 4.1 | [mof/mig-4.1/](mof/mig-4.1/README.md) |

## Providers

| Provider | API | Adapter in 2.x | Note |
| --- | --- | --- | --- |
| ECPay 綠界 | B2C 電子發票 API | `Einvoice::ECPay::Provider` | [ecpay/b2c.md](ecpay/b2c.md) |
| Tradevan 關貿 | DEFAULTAPI | none yet | [tradevan/defaultapi.md](tradevan/defaultapi.md) |

## How to read a note

### Sources

Every fact in a note has a source tag. The tag tells you how much to trust the fact.

There are two kinds of sources:

- **Provider docs.** Documents that the provider published or sent to us. We record the title, the version, the date we got it, and where it came from. We do not copy the provider's text into this repository. We write our own summary instead.
- **Our own evidence.** Things we saw ourselves: live test runs, recorded responses, code that ran in production, and reports from users of this gem.

Each note lists its sources at the top and gives each one a short tag, for example `[doc]` or `[live]`. A fact with no provider doc behind it says so.

### Verification status

| Mark | Meaning |
| --- | --- |
| verified | Seen in a real response or a live run. The note says when. |
| documented | The provider docs say it. Nobody has checked it against the live API. |
| inferred | We worked it out from other facts. The note says from which ones. |
| unknown | We do not know. It is listed under "Open questions". |

When a live run shows that a provider doc is wrong, keep both. Write what the doc says, then what the API really does.

## Note layout

Each note uses these sections, in this order. A section can be short, but do not drop it.

1. **Status and sources.** Which API version, which sources, and how fresh they are.
2. **Connection.** Hosts, credentials, signing or encryption, the request envelope, the response envelope.
3. **Operations.** Every endpoint the provider offers, and what it does.
4. **Mapping to the unified API.** For each of `issue`, `void`, `allowance`, `void_allowance` and `query`: which endpoint it uses, how the fields map, and what is missing.
5. **Field reference.** Request and response fields, with their rules.
6. **Codes.** Enum values, status codes and error codes.
7. **Open questions.** Everything marked unknown, in one list.

## API versions

A provider can have more than one API version in use at the same time. Each version gets its own note, named after the version, for example `tradevan/defaultapi.md`. A newer version does not replace the older note while people still use the older API.
