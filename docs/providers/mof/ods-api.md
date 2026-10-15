# MOF 財政部: 電子發票開放資料 API

English | [繁體中文](ods-api.zh-TW.md)

## 1. Status and sources

This is the MOF's open data API for e-invoice datasets. It is not an invoice provider, but the 2.x line uses one of its endpoints: `Einvoice::MOF::DonationCodes` (`lib/einvoice/mof/donation_codes.rb`) reads the donation code list from it.

The API and its data belong to 財政部財政資訊中心. The API is described in a public OpenAPI file. This note is our summary.

| Tag | Source | Date | What it gives |
| --- | --- | --- | --- |
| `[doc]` | 電子發票開放資料Open API服務, OpenAPI 3.0.1, <https://www.einvoice.nat.gov.tw/portal/ods/openapi.json>. We read it on 2026-10-14. | version `v1` | All endpoints, parameters and response fields. |
| `[live]` | Our live spec (`spec/einvoice/mof/live_spec.rb`) and the cassettes it recorded (`spec/fixtures/vcr_cassettes/mof/`) | 2026-08-17 | Real requests and responses. |
| `[code]` | `Einvoice::MOF::DonationCodes` | 2026-08 | What the client does. |

The donation code list is also data.gov.tw dataset 31868 (受捐贈機關或團體捐贈碼清單), under the 政府資料開放授權條款－第1版. The 1.x line bundles a copy of it and credits the source in its README.

**Updates.** The OpenAPI file has `info.version`. Check it, and the parameters of the endpoints we use.

## 2. Connection

- Host: `https://dataset.einvoice.nat.gov.tw/ods/portal/` `[doc]`. There is no test host.
- Every endpoint is `GET` with query parameters, and returns a JSON array.
- At most 100 rows by default. `limit` takes up to 500, and `offset` skips rows. Use both to page `[doc]`.
- The OpenAPI file declares two security schemes: an `api_key` header and OAuth2. The endpoint answers without them today `[live]`. The client turns HTTP 401 or 403 into an `AuthError`, in case this changes `[code]`.

## 3. Operations

The client uses one endpoint:

| Endpoint | Purpose |
| --- | --- |
| `/api/v1/DonateCodeList` | Dataset 31868: donation codes (受捐贈機關或團體捐贈碼清單) |

The other 27 endpoints are statistics: invoice counts, carrier counts, donations, prizes and spending by area. One more lists businesses that use e-invoices (`InvoiceBusinessList`, dataset 31869). None of them matter for an adapter.

## 4. Mapping to the unified API

`DonationCodes` is not one of the five operations. It checks a 愛心碼 without a provider, so it works with any value-added center `[code]`.

| Method | Request | Note |
| --- | --- | --- |
| `lookup(code)` | `?donateCode=<code>` | The code must be 3 to 7 digits. An empty array means "not registered" |
| `exist?(code)` | the same | |
| `for_ubn(ubn)` | `?donateBan=<ubn>` | One 統一編號 can hold more than one code |
| `all` | `?limit=500&offset=…` | About 2,000 rows, so about five requests |

The result is `DonationCode`: `code` ← `donateCode`, `name` ← `donateNm`, `short_name` ← `donateShortNm`, `ubn` ← `donateBan`, `city` ← `hsnNm`.

Providers with their own donation code check: ECPay (`CheckLoveCode`) and ezPay (`checkLoveCode`). Amego and Tradevan DEFAULTAPI have none, so `DonationCodes` fills that gap.

## 5. Field reference

### 5.1 `DonateCodeList`

Parameters `[doc]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `donateBan` | O | 統一編號 of the organisation |
| `limit` | O | 1 to 500 |
| `offset` | O | Rows to skip |

`donateCode` is not in the OpenAPI file, but the endpoint filters by it `[live]`.

Response: an array. Each row has `[doc]`:

| Field | Meaning |
| --- | --- |
| `seq` | Row number |
| `donateNm` | Organisation name |
| `donateCode` | Donation code. The OpenAPI file describes it wrongly, as 捐贈碼捐贈數量 |
| `donateShortNm` | Short name |
| `donateBan` | 統一編號 |
| `hsnNm` | City or county |

Example `[live]` (`lookup.yml`):

```
GET /ods/portal/api/v1/DonateCodeList?donateCode=2718
```

```json
[{ "donateBan": "92000392", "donateNm": "社團法人台北市喜願協會", "donateCode": "2718",
   "donateShortNm": "喜願協會", "hsnNm": "臺北市", "seq": 1 }]
```

A code that does not exist returns `[]` with HTTP 200 `[live]`.

## 6. Codes

| HTTP | Meaning | Unified error | `Reason` |
| --- | --- | --- | --- |
| `200` | OK. An empty array means no match | | |
| `401`, `403` | The endpoint now needs credentials | `AuthError` | `CREDENTIALS_INVALID` |
| other | | `ProviderError` | |
| no answer | | `NetworkError` | |

`[code]`.

## 7. Open questions

1. Will the `donateCode` filter stay? It works, but the OpenAPI file does not list it.
2. Will the endpoint start to require the `api_key` header that the OpenAPI file declares?
