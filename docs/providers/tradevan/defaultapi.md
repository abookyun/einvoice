# Tradevan 關貿: DEFAULTAPI

## 1. Status and sources

This is the API that the 1.x client wraps. All paths start with `/DEFAULTAPI/`.

Tradevan does not publish its API docs. It also declined to send us a newer version. So this note is built from what the 1.x line has, and from one production report. Nobody in this project has a Tradevan account today, so nothing here is verified against the live API in 2026.

Tradevan has newer API versions. This note covers only DEFAULTAPI.

| Tag | Source | Date | What it gives |
| --- | --- | --- | --- |
| `[doc]` | Our summary of Tradevan's API document. We wrote it for 1.x. It is no longer in the repository, so see `docs/Tradevan E-Invoice APIs.md` at [v1.5.0](https://github.com/abookyun/einvoice/blob/v1.5.0/docs/Tradevan%20E-Invoice%20APIs.md). | last changed 2016-05-03 | Encryption, envelopes, the list of endpoints, GET parameters. No `issueData` or `voidData` fields. No responses. |
| `[readme]` | Examples in the 1.x README ([v1.5.0](https://github.com/abookyun/einvoice/blob/v1.5.0/README.md)) | 2016-04-26 | Requests and responses for issue, cancel, two searches and mark info. They look like real responses, but the personal data in them is fake. Nobody saved the raw responses. |
| `[rules]` | The 1.x validators: `IssueData`, `IssueItem`, `VoidData` and `issue_data_validator.rb` ([v1.5.0](https://github.com/abookyun/einvoice/tree/v1.5.0/lib/einvoice/tradevan)) | 2016 | The only source for `issueData` and `voidData` fields and their rules. |
| `[code]` | The 1.x provider, connection and response decoder | 2016, still in production use | How the client really builds requests and reads responses. Where `[code]` and `[doc]` disagree, `[code]` has run in production. |
| `[prod]` | PR [#38](https://github.com/abookyun/einvoice/pull/38), from a production user | 2026-09 | The API still works in 2026. Issue, void, allowance and void allowance are in use. The API rejects unknown fields (see 2.4). |
| `[readme-2026]` | Allowance examples added to the 1.x README ([199b803](https://github.com/abookyun/einvoice/commit/199b803)) | 2026-08 | Requests only. They were written from `[rules]`, not from real traffic. |

The 1.x specs are not a source. Their responses are hand-written stubs from 2026.

The MOF standard is in [../mof/mig-4.1/](../mof/mig-4.1/README.md). References to it use `[mig]`. Our DEFAULTAPI sources are from 2016, years before MIG 4.0 (2024). Tradevan must map DEFAULTAPI fields to the new messages, and we do not know how.

## 2. Connection

### 2.1 Credentials

Tradevan gives each merchant four values `[doc]`:

| Value | Use |
| --- | --- |
| `acnt` | Account name. Sent inside the outer encrypted JSON. |
| `acntp` | Account password. Sent inside the outer encrypted JSON. |
| `key1` | AES key for each parameter value, and for responses `[code]`. |
| `key2` | AES key for the outer JSON. |

The merchant also has a `companyUn` (統一編號, 8 chars) and an `orgId` (5 chars). Most requests carry them.

Hosts: unknown. The 1.x client takes the endpoint from its configuration and does not ship a default.

### 2.2 Encryption

Both keys use the same cipher `[doc]` `[code]`:

- AES-128-CBC. The IV is the key itself.
- No PKCS padding. Pad the plain text with `\0` bytes to a multiple of 16 bytes. If the text is empty, pad it to 16 bytes. If the length is already a multiple of 16, add nothing.
- Base64 (strict) on the cipher text.

### 2.3 Request

All endpoints take one parameter, `v`. It goes in the URL query string, also for the POST endpoints `[code]`. The 1.x client sends `Accept: application/json; charset=utf-8`.

Build `v` like this `[doc]` `[code]`:

1. For each API parameter: if the value is a Hash, turn it into JSON. Otherwise use `to_s`. Encrypt it with `key1`.
2. Build a JSON object: `{ "acnt": ..., "acntp": ..., <name>: <encrypted value>, ... }`. `acnt` and `acntp` are plain here. They are not encrypted with `key1`.
3. Encrypt that JSON with `key2`. The result is `v`.

### 2.4 Response

The body is JSON `[doc]`:

```json
{ "Success": "Y", "Message": "<text>" }
```

| `Success` | Meaning | `Message` |
| --- | --- | --- |
| `Y` | OK | Encrypted JSON |
| `N` | Failure | Encrypted JSON |
| `E` | Error | Plain text |

To read an encrypted `Message`: Base64 decode, decrypt, strip the trailing `\0` bytes, parse JSON.

`[doc]` says to decrypt with `key2`. `[code]` decrypts with `key1`, and that code runs in production. Follow `[code]`. The 1.x specs use the same value for both keys, so they cannot tell the two apart.

`Success` is only the outer result. The inner JSON has its own status field, for example `issueStatus` or `voidStatus` `[readme]`. A full check reads both.

Tradevan rejects the whole request when `issueData` or `voidData` has a field outside its schema `[prod]`. So never pass unknown keys through.

## 3. Operations

| Endpoint | Method | Purpose | Sources |
| --- | --- | --- | --- |
| `post/issue` | POST | Issue an invoice or an allowance. One endpoint, five types (see 5.1). | `[doc]` `[rules]` `[readme]` `[prod]` |
| `post/cancel` | POST | Void an invoice or an allowance. | `[doc]` `[rules]` `[readme]` `[prod]` |
| `get/searchInvoiceDetail` | GET | One invoice by number, with its items. | `[doc]` `[readme]` |
| `get/searchInvoiceInfoByTransactionnumber` | GET | One invoice by the merchant's transaction number. | `[code]` only. Not in `[doc]`. |
| `get/searchInvoiceByMemberId` | GET | Invoices by member ID, carrier or `sellTargetCode`, in a date range. | `[doc]` `[readme]` |
| `get/getInvoiceContent` | GET | Invoice content by number or by `sellTargetCode`. | `[doc]`. No response example. |
| `get/sendCardInfotoCust` | GET | Carrier and prize notice to a customer (載具歸戶／中獎通知). | `[doc]`. No response example. |
| `get/getInvoiceMarkInfo` | GET | Invoice number ranges for a period (字軌配號). | `[doc]` `[readme]` |
| `get/getDonateUnitList` | GET | Donation codes (愛心碼). | `[doc]`. No response example. |

## 4. Mapping to the unified API

| Unified | Tradevan | Status |
| --- | --- | --- |
| `issue` | `post/issue`, type `I` | Can map. See notes. |
| `void` | `post/cancel`, type `I` | Can map. Needs a core decision. |
| `allowance` | `post/issue`, type `A` | Can map the request. Needs a core decision. The response is unknown. |
| `void_allowance` | `post/cancel`, type `A` | Can map. |
| `query` by number | `get/searchInvoiceDetail` | Can map, except `status`. |
| `query` by order id | `get/searchInvoiceInfoByTransactionnumber` | Can map the request. The response is unknown. |

### `issue`

- Merchant settings, not per call: `companyUn`, `orgId`, and the defaults for `paperPrintMode`, `invoiceAlarmMode` and `invoicePaperReturned`.
- `saleIdentifier` must start with `{companyUn}_{orgId}_` `[rules]`. In `[readme]` the rest of it is the `transactionNumber`. In the 1.x factories it is not. So this is our choice, not an API rule.
- `transactionNumber` is the order id (max 50).
- Amounts sit on each item: `itemTotal` (tax included), `tax`, and `itemExclude` (tax excluded). The header `total` must equal the sum of the `itemTotal` values `[rules]`. The unified `InvoiceItem` has only `amount`, so the adapter has to split the tax per item.
- Tax types: `T` taxable, `Z` zero rated, `O` tax free (see 6.1). The unified `SPECIAL` has no code.
- Carrier types are 6 chars: `3J0002` mobile barcode, `CQ0001` citizen certificate `[readme]`. A member carrier uses a code the merchant gets from Tradevan (the 1.x factories use `1K0001`).
- The response has `invoiceNumber`, `checkNumber` (the random code), `invoiceDate` and `invoiceTime` `[readme]`. That covers `IssueInvoiceResult`.

### `void`

- Needs `saleIdentifier` as well as `invoiceNumber` `[rules]`. `VoidInvoiceInput` has only `invoice_number`. **Core decision:** carry the order id, or ask for it in `provider_options`.
- No reason field. The unified `reason` is dropped.
- `invoicePaperReturned` (Y/N) is required.

### `allowance`

- Every item needs the original `invoiceNumber` and `invoiceDate` `[rules]`. **Core decision:** this is the same `invoice_date` question as in #36.
- `allowanceIdentifier` follows the same prefix rule as `saleIdentifier`.
- The response is not known. We do not know if Tradevan returns an allowance number for type `A`. The issue response has empty `allowance*` fields `[readme]`, so type `A` may use the same response shape (inferred).

### `void_allowance`

- `companyUn`, `allowanceNumber` (16 chars), `allowancePaperReturned` `[rules]`. Nothing is missing.

### `query`

- `searchInvoiceDetail` returns amounts, buyer, items and status `[readme]`. All of `QueryInvoiceResult` maps, except `status`: the meaning of the status codes is unknown (see 6.3).

### Outside the unified API

Types `R`, `G` and `H`, and the other five GET endpoints, have no unified operation. An adapter can offer them as provider-specific methods. `getDonateUnitList` overlaps with `Einvoice::MOF::DonationCodes`.

## 5. Field reference

### 5.1 `post/issue`: `issueData`

One parameter, `issueData`, a JSON object `[doc]`. All values are strings `[readme]`.

`type` picks the operation. `[doc]` lists four purposes, and `[rules]` has five codes. The match below is inferred from which fields each type requires.

| `type` | Purpose (inferred) | Requires |
| --- | --- | --- |
| `I` | Issue a new invoice | `saleIdentifier`, `transactionTime`, `total` |
| `R` | Issue for an existing invoice | as `I`, plus `invoiceNumber` |
| `G` | Issue for an existing invoice, with its full header | as `R`. Allows `checkNumber`, `invoiceDate`, amounts |
| `A` | Issue a new allowance | `allowanceIdentifier`, allowance amounts |
| `H` | Issue for an existing allowance | as `A`, plus `saleIdentifier`, `invoiceNumber`, `allowanceNumber`, `allowanceDate` |

Header fields `[rules]`. "Req" means required, "opt" means optional.

| Field | Rule | Types |
| --- | --- | --- |
| `companyUn` | req, 8 chars | all |
| `orgId` | req, 5 chars | all |
| `orgUn` | opt, 8 chars | all |
| `type` | req, `I` `R` `G` `H` `A` | all |
| `transactionNumber` | req, max 50 | all |
| `transactionDate` | req, `yyyyMMdd` | all |
| `transactionTime` | req, `HH:MM:SS` | I R G |
| `transactionSource`, `transactionTarget` | opt, max 50 | all |
| `saleIdentifier` | req, max 100, starts with `{companyUn}_{orgId}_` | I R G H |
| `allowanceIdentifier` | req, max 100, same prefix | A H |
| `invoiceNumber` | req, 10 chars | R G H |
| `allowanceNumber` | req, 16 chars, starts with `orgId` | H |
| `allowanceDate` | req, `yyyyMMdd` | H |
| `allowaDeclaration` | opt, 6 digits (example `201803`) | A |
| `total` | req, max 20, equals the sum of item `itemTotal` | I R G |
| `allowanceExclusiveAmount` | req, max 20 | A H |
| `allowanceTax` | req, max 8 | A H |
| `allowanceInclusiveAmount` | req, max 20 | A H |
| `allowancePaperReturned` | req, `Y` / `N` | A H |
| `paperPrintMode` | req, `0` to `4` | all |
| `invoiceAlarmMode` | req, `0` to `6` | all |
| `invoicePaperReturned` | `Y` / `N`. Req for `A`, and when `buyerUn` is blank and `paperPrintMode` is not `0` | all |
| `donate` | req when type is I R G, `buyerUn` is blank and `paperPrintMode` is `0`. 1 char (`Y` / `N`) | I R G |
| `donationUnit` | req when `donate` is `Y`, max 10 | I R G |
| `carrierType` | req when `paperPrintMode` is `0`, `donate` is `N` and type is not `A`. 6 chars | all but A |
| `carrierId`, `carrierIdHidden` | req when `paperPrintMode` is `0` and `donate` is `N`. Max 64 | I R G |
| `buyerUn` | opt, 8 chars | not A H |
| `buyerTitle` | opt, max 60 | not A H |
| `receiverName` | opt, max 30 | I R G A |
| `receiverAddrZip` | opt, max 6 | I R G A |
| `receiverAddrRoad` | opt, max 100 | I R G A |
| `receiverEmail` | opt, max 80 | I R G A |
| `receiverMobile` | opt, max 15 | I R G A |
| `idViewId` | opt, max 10 | all |
| `memberId` | opt, max 50 | all |
| `tax` | opt, max 20 | I G |
| `checkNumber` | opt, 4 chars. MIG 4.0 dropped `CheckNumber` from F0401 `[mig]` | G |
| `invoiceDate` | opt, 8 chars | G |
| `invoiceTime` | opt, 8 chars | G |
| `texclusiveAmount`, `oeclusiveAmount`, `zexclusiveAmount` | opt, max 20 | G |
| `mainRemark` | opt, max 300 | G |
| `invoiceType` | opt, `07` / `08` | G |
| `itemList` | req, array, see below | all |

`paperPrintMode` and `invoiceAlarmMode`: the meaning of each value is unknown. `[readme]` uses `0` and `4`.

`itemList` items `[rules]`:

| Field | Rule |
| --- | --- |
| `saleIdentifier` | req, max 100. Same as the header (for `A`, the original invoice's `saleIdentifier` `[readme-2026]`) |
| `serialNumber` | req, 4 digits (`0001`) |
| `productName` | req, max 300 |
| `qty` | req, max 20 |
| `price` | req, max 20 |
| `itemTotal` | max 20. Every item must have it |
| `taxType` | `T` / `O` / `Z`. Every item must have it |
| `tax` | opt, max 20 |
| `itemExclude` | max 20. Every item must have it for `A` and `H` |
| `invoiceNumber` | 10 chars. Every item must have it for `A` and `H` |
| `invoiceDate` | 8 digits. Every item must have it for `A` and `H` |
| `invoiceTime` | opt, `HH:MM:SS` |
| `productCode` | opt, max 30 |
| `description` | opt, max 300 |

`donationUnit` in 1.x is also checked against a bundled list of donation codes. That is a client rule, not an API rule.

### 5.2 `post/issue`: response

Type `I`, success `[readme]`:

| Field | Example | Note |
| --- | --- | --- |
| `saleIdentifier` | `12345678_ABCDE_53b2a44e4b3c` | Echoed |
| `issueStatus` | `Y` | Inner result |
| `failReason` | `""` | Present even on success |
| `invoiceNumber` | `GX38551078` | |
| `checkNumber` | `4229` | Random code (隨機碼) |
| `invoiceDate` | `20160425` | |
| `invoiceTime` | `12:34:58` | |
| `texclusiveAmount` | `19048` | Taxable sales, tax excluded |
| `oexclusiveAmount` | `0` | Tax free sales. Note the spelling: the request field for type `G` is `oeclusiveAmount` |
| `zexclusiveAmount` | `0` | Zero rated sales |
| `tax` | `952` | |
| `inclusiveAmount` | `20000` | |
| `mainRemark`, `invoiceType` | `""` | |
| `invoiceStatus` | `V` | Meaning unknown (6.3) |
| `allowanceNumber`, `allowanceDate`, `allowanceExclusiveAmount`, `allowanceTax`, `allowanceStatus` | `""` | Empty for type `I` |
| `allowanceTotalAmount` | `0` | |

Other types: no example.

### 5.3 `post/cancel`: `voidData`

One parameter, `voidData`, a JSON object `[doc]` `[rules]`:

| Field | Rule | Types |
| --- | --- | --- |
| `type` | req, `C` / `I` / `A` | all |
| `saleIdentifier` | req, max 100 | C I |
| `invoiceNumber` | req, 10 chars | C I |
| `invoicePaperReturned` | req, `Y` / `N` | C I |
| `companyUn` | req, 8 chars | A |
| `allowanceNumber` | req, 16 chars | A |
| `allowancePaperReturned` | req, `Y` / `N` | A |

`I` voids an invoice `[readme]`. `A` voids an allowance `[readme-2026]`. `C` takes the same fields as `I`, and its meaning is unknown.

Response for type `I` `[readme]`: `saleIdentifier`, `voidStatus` (`Y`), `failReason`, `type`, `invoiceNumber`, `allowanceNumber` (empty).

### 5.4 GET endpoints

Parameters `[doc]`, except where marked:

| Endpoint | Parameters |
| --- | --- |
| `searchInvoiceDetail` | `invoiceNumber` (req) |
| `searchInvoiceInfoByTransactionnumber` | `companyUn`, `orgId`, `transactionNumber` `[code]` |
| `searchInvoiceByMemberId` | `companyUn` (req); one of `memberId`, `carrierId`, `sellTargetCode`; opt `invoiceStartDate`, `invoiceEndDate` (`yyyyMMdd`) |
| `getInvoiceContent` | `invoiceNumber` or `sellTargetCode`; opt `invoiceStartDate`, `invoiceEndDate` (`yyyyMMdd`) |
| `sendCardInfotoCust` | `companyUn`, `sellTargetCode` (req); `receiverEmail` or `receiverMobile`; opt `invoiceStartYM`, `invoiceEndYM` (`yyyyMM`) |
| `getInvoiceMarkInfo` | `companyUn`, `orgId`, `uniFiedNumber`, `bookType`, `period` (`yyyymm`), all req |
| `getDonateUnitList` | `companyUn` (req) |

`searchInvoiceDetail` response, one object `[readme]`:

`saleIdentifier`, `invoiceNumber`, `checkNumber`, `invoiceDate`, `invoiceTime`, `exclusiveAmount`, `tax`, `total`, `status`, `hasAllowance` (`Y` / `N`), `sellerName`, `sellerUN`, `sellerAddr`, `sellerTel`, `receiverName`, `receiverAddr`, `receiverPhone`, `paper` (`Y` / `N`), `win` (`Y` / `N`), `donate` (`Y` / `N`), `carrierType`, and `detailList`. Each `detailList` item has `saleIdentifier`, `serialNumber`, `productName`, `qty`, `price`, `total`, `taxType`.

`searchInvoiceByMemberId` response, an array `[readme]`: the same header fields as `searchInvoiceDetail`, without `receiverPhone` and `detailList`, plus `carrierId`.

`getInvoiceMarkInfo` response, an array `[readme]`: `unifiedNumber`, `bookNumber`, `bookType`, `period`, `duration`, `mark` (字軌, e.g. `GX`), `start`, `end`.

## 6. Codes

### 6.1 Tax type (`taxType`)

No source lists these codes. We inferred them from the type `G` amount fields: `texclusiveAmount`, `oeclusiveAmount` and `zexclusiveAmount`.

| Code | Meaning | Status |
| --- | --- | --- |
| `T` | Taxable (應稅). MIG `1` | inferred |
| `Z` | Zero rated (零稅率). MIG `2` | inferred |
| `O` | Tax free (免稅). MIG `3` | inferred |

The MIG also has `4` (special rate) and `9` (mixed, header only) `[mig 表 4-12]`. DEFAULTAPI has no letter for either.

### 6.2 Carrier type (`carrierType`)

| Code | Meaning | Status |
| --- | --- | --- |
| `3J0002` | Mobile barcode (手機條碼) | MIG code `[mig 表 4-13]`, used in `[readme]` |
| `CQ0001` | Citizen certificate (自然人憑證) | MIG code `[mig 表 4-13]`, used in `[readme]` |
| merchant code | Member carrier | The MIG says the MOF platform gives each seller or center its own 6-char code `[mig 表 15-3]`. The 1.x factories use `1K0001` |

`carrierType` is the MIG field as it is, so DEFAULTAPI passes it to the MOF without change (inferred).

### 6.3 Status

| Field | Values seen | Meaning |
| --- | --- | --- |
| `invoiceStatus` (issue response) | `V` | unknown |
| `status` (search responses) | `I`, `V` | unknown |
| `issueStatus`, `voidStatus` | `Y` | `Y` is success. `N` is failure (from the 1.x spec stubs, not seen in a real response) |

The MOF's own status list (E0502 `CurrentStatus`) uses the digits `1` to `7` `[mig 表 23-2]`. So `I` and `V` are Tradevan's own codes, and the MIG cannot tell us what they mean.

### 6.4 Errors

There is no error code list. A failure has `Success` `N` or `E`, and a free-text `failReason` or `Message`. No real failure text is on record.

## 7. Open questions

1. What do the status codes `V` and `I` mean? An adapter that guesses wrong can report a voided invoice as issued.
2. What does the type `A` issue response look like? Does it return an allowance number?
3. What failure texts does Tradevan send? Without them, errors cannot map to `NotFoundError` or `ConflictError`.
4. Is `qty` scaled? In `[readme]` an item has `qty` 4000, `price` 5 and `itemTotal` 20000, so `qty × price = itemTotal`. In `[readme-2026]` an item has `qty` 1000, `price` 100 and `itemTotal` 100, so `qty` looks like units × 1000. The two do not agree.
5. What are the test and production hosts?
6. Which key decrypts the response, `key1` (`[code]`) or `key2` (`[doc]`)?
7. What is the difference between cancel types `C` and `I`? Between issue types `R` and `G`?
8. What do the values of `paperPrintMode` and `invoiceAlarmMode` mean? What is `sellTargetCode`?
9. Which version of Tradevan's document did `[doc]` summarize? It was not recorded.
