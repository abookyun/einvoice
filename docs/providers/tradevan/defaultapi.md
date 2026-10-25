# Tradevan 關貿: DEFAULTAPI

English | [繁體中文](defaultapi.zh-TW.md)

## 1. Status and sources

> **Trust:** no public docs and no account. The API runs in production through the 1.x client (`[prod]`). An experimental 2.x adapter is in progress. It can only be tested against our fake, and nothing here was run against the live API in 2026. Section 4 and 6.4 are the mapping the adapter follows.

This is the API that the 1.x client wraps. All paths start with `/DEFAULTAPI/`. The 2.x adapter will be `Einvoice::Tradevan::DefaultAPI::Provider`, marked experimental.

The API document belongs to 關貿網路 Tradevan. Tradevan does not publish it, and it declined to send us a newer version. So there is no public link. We built this note from what the 1.x line has, and from one production report. Nobody in this project has a Tradevan account today, so nothing here is verified against the live API in 2026.

Tradevan has newer API versions. This note covers only DEFAULTAPI.

| Tag | Source | Date | What it gives |
| --- | --- | --- | --- |
| `[summary]` | Our summary of Tradevan's API document. We wrote it for 1.x. It is no longer in the repository, so see `docs/Tradevan E-Invoice APIs.md` at [v1.5.0](https://github.com/abookyun/einvoice/blob/v1.5.0/docs/Tradevan%20E-Invoice%20APIs.md). | last changed 2016-05-03 | Encryption, envelopes, the list of endpoints, GET parameters. No `issueData` or `voidData` fields. No responses. |
| `[readme]` | Examples in the 1.x README ([v1.5.0](https://github.com/abookyun/einvoice/blob/v1.5.0/README.md)) | 2016-04-26 | Requests and responses for issue, cancel, two searches and mark info. They look like real responses, but the personal data in them is fake. Nobody saved the raw responses. |
| `[rules]` | The 1.x validators: `IssueData`, `IssueItem`, `VoidData` and `issue_data_validator.rb` ([v1.5.0](https://github.com/abookyun/einvoice/tree/v1.5.0/lib/einvoice/tradevan)) | 2016 | The only source for `issueData` and `voidData` fields and their rules. |
| `[1x-code]` | The 1.x provider, connection and response decoder | 2016, still in production use | How the client really builds requests and reads responses. Where `[1x-code]` and `[summary]` disagree, `[1x-code]` has run in production. |
| `[prod]` | PR [#38](https://github.com/abookyun/einvoice/pull/38), from a production user | 2026-09 | The API still works in 2026. Issue, void, allowance and void allowance are in use. The API rejects unknown fields (see 2.4). |
| `[readme-2026]` | Allowance examples in the 1.x README, from 2026 ([199b803](https://github.com/abookyun/einvoice/commit/199b803)) | 2026-08 | Requests only. They were written from `[rules]`, not from real traffic. |
| `[rfc]` | The 2.0 RFC, issue [#31](https://github.com/abookyun/einvoice/issues/31) | 2026-08 | How its author read the 1.x API, for example `qty` |

The 1.x specs are not a source. Their responses are hand-written stubs from 2026.

The MOF standard is in [../mof/mig-4.1/](../mof/mig-4.1/README.md). References to it use `[mig]`. Our DEFAULTAPI sources are from 2016, years before MIG 4.0 (2024). Tradevan must map DEFAULTAPI fields to the new messages, and we do not know how.

**Updates.** There is no public source to watch. A newer document would come from Tradevan or from a user with an account.

## 2. Connection

### 2.1 Credentials

Tradevan gives each merchant four values `[summary]`:

| Value | Use |
| --- | --- |
| `acnt` | Account name. Sent inside the outer encrypted JSON. |
| `acntp` | Account password. Sent inside the outer encrypted JSON. |
| `key1` | AES key for each parameter value, and for responses `[1x-code]`. |
| `key2` | AES key for the outer JSON. |

The merchant also has a `companyUn` (統一編號, 8 chars) and an `orgId` (5 chars). Most requests carry them.

Hosts: unknown. The 1.x client takes the endpoint from its configuration and does not ship a default.

### 2.2 Encryption

Both keys use the same cipher `[summary]` `[1x-code]`:

- AES-128-CBC. The IV is the key itself.
- No PKCS padding. Pad the plain text with `\0` bytes to a multiple of 16 bytes. If the text is empty, pad it to 16 bytes. If the length is already a multiple of 16, add nothing.
- Base64 (strict) on the cipher text.

**Official test vectors.** None. Tradevan publishes no document, so there is no sample with a known result. `crypto_spec.rb` uses vectors made with the 1.x code instead. They prove that 2.x matches 1.x, not that either matches Tradevan.

### 2.3 Request

All endpoints take one parameter, `v`. It goes in the URL query string, also for the POST endpoints `[1x-code]`. The 1.x client sends `Accept: application/json; charset=utf-8`.

Build `v` like this `[summary]` `[1x-code]`:

1. For each API parameter: if the value is a Hash, turn it into JSON. Otherwise use `to_s`. Encrypt it with `key1`.
2. Build a JSON object: `{ "acnt": ..., "acntp": ..., <name>: <encrypted value>, ... }`. `acnt` and `acntp` are plain here. They are not encrypted with `key1`.
3. Encrypt that JSON with `key2`. The result is `v`.

### 2.4 Response

The body is JSON `[summary]`:

```json
{ "Success": "Y", "Message": "<text>" }
```

| `Success` | Meaning | `Message` |
| --- | --- | --- |
| `Y` | OK | Encrypted JSON |
| `N` | Failure | Encrypted JSON |
| `E` | Error | Plain text |

To read an encrypted `Message`: Base64 decode, decrypt, strip the trailing `\0` bytes, parse JSON.

`[summary]` says to decrypt with `key2`. `[1x-code]` decrypts with `key1`, and that code runs in production. Follow `[1x-code]`. The 1.x specs use the same value for both keys, so they cannot tell the two apart.

`Success` is only the outer result. The inner JSON has its own status field, for example `issueStatus` or `voidStatus` `[readme]`. A full check reads both.

Tradevan rejects the whole request when `issueData` or `voidData` has a field outside its schema `[prod]`. So never pass unknown keys through.

**Limits of the API.** The account, the password and every parameter travel in the URL query string, also for POST. Proxies and servers often log full URLs, so mask `v` in logs. The cipher uses the key as the IV and has no MAC, so the same data always gives the same `v`, and nothing checks that a response is intact. `Success` sits outside the encryption. Only TLS protects the request and the response.

### 2.5 Example

An issue call from the 1.x README `[readme]`, shown before encryption. `issueData`:

```json
{ "companyUn": "12345678", "orgId": "ABCDE", "type": "I",
  "saleIdentifier": "12345678_ABCDE_53b2a44e4b3c", "transactionNumber": "53b2a44e4b3c",
  "transactionDate": "20160425", "transactionTime": "12:34:56", "total": "20000",
  "paperPrintMode": "0", "invoiceAlarmMode": "4", "donate": "N",
  "carrierType": "3J0002", "carrierId": "TP03000001234567", "carrierIdHidden": "TP03000001234567",
  "receiverName": "John Appleseed", "receiverEmail": "john@gmail.com",
  "itemList": [{ "saleIdentifier": "12345678_ABCDE_53b2a44e4b3c", "serialNumber": "0001",
                 "productName": "Coffee Latte", "qty": "4000", "price": "5",
                 "itemTotal": "20000", "taxType": "T", "tax": "952" }] }
```

Decrypted `Message`:

```json
{ "saleIdentifier": "12345678_ABCDE_53b2a44e4b3c", "issueStatus": "Y", "failReason": "",
  "invoiceNumber": "GX38551078", "checkNumber": "4229",
  "invoiceDate": "20160425", "invoiceTime": "12:34:58",
  "texclusiveAmount": "19048", "oexclusiveAmount": "0", "zexclusiveAmount": "0",
  "tax": "952", "inclusiveAmount": "20000", "mainRemark": "", "invoiceType": "",
  "invoiceStatus": "V", "allowanceNumber": "", "allowanceDate": "",
  "allowanceExclusiveAmount": "", "allowanceTax": "", "allowanceTotalAmount": "0",
  "allowanceStatus": "" }
```

The example's `carrierId` has the citizen certificate format, but its `carrierType` is the mobile barcode code. The example data is fake, so do not copy this pair.

## 3. Operations

The five unified operations use these endpoints. Section 5 has their fields.

| Endpoint | Method | Purpose | Sources |
| --- | --- | --- | --- |
| `post/issue` | POST | Issue an invoice or an allowance. One endpoint, five types (see 5.1). | `[summary]` `[rules]` `[readme]` `[prod]` |
| `post/cancel` | POST | Void an invoice or an allowance. | `[summary]` `[rules]` `[readme]` `[prod]` |
| `get/searchInvoiceDetail` | GET | One invoice by number, with its items. | `[summary]` `[readme]` |
| `get/searchInvoiceInfoByTransactionnumber` | GET | One invoice by the merchant's transaction number. | `[1x-code]` only. Not in `[summary]`. |

Other endpoints. An adapter can offer them through a `raw` method:

| Endpoint | Method | Purpose | Sources |
| --- | --- | --- | --- |
| `get/searchInvoiceByMemberId` | GET | Invoices by member ID, carrier or `sellTargetCode`, in a date range. | `[summary]` `[readme]` |
| `get/getInvoiceContent` | GET | Invoice content by number or by `sellTargetCode`. | `[summary]`. No response example. |
| `get/sendCardInfotoCust` | GET | Carrier and prize notice to a customer (載具歸戶／中獎通知). | `[summary]`. No response example. |
| `get/getInvoiceMarkInfo` | GET | Invoice number ranges for a period (字軌配號). | `[summary]` `[readme]` |
| `get/getDonateUnitList` | GET | Donation codes (愛心碼). Overlaps with `Einvoice::MOF::DonationCodes`. | `[summary]`. No response example. |

`post/issue` types `R`, `G` and `H` (issue for an existing invoice or allowance) have no unified operation either.

## 4. Mapping to the unified API

### 4.1 Operations

| Unified | Endpoint | Reference fields | `provider_options` |
| --- | --- | --- | --- |
| `issue` | `post/issue`, type `I` | | |
| `void` | `post/cancel`, type `I` | `number`, `order_id` | `sale_identifier` |
| `allowance` | `post/issue`, type `A` | `number`, `order_id`, `invoice_datetime` | `sale_identifier` |
| `void_allowance` | `post/cancel`, type `A` | `allowance_number` | |
| `query` | `get/searchInvoiceDetail` | `number` | |

Constructor settings: `acnt`, `acntp`, `key1`, `key2`, `base_url` (no default, see 2.1), `company_un`, `org_id`, `paper_print_mode`, `invoice_alarm_mode`, `invoice_paper_returned`, `allowance_paper_returned`, and `member_carrier_type` (the merchant's own carrier code).

**The sale identifier.** Void and allowance need the original invoice's `saleIdentifier`. The adapter takes it in this order:

1. `provider_options[:sale_identifier]`. Use it for invoices that the 1.x client issued, because their identifiers can have any suffix.
2. The prefix and the reference's `order_id`, as `issue` builds it (4.2).
3. A `searchInvoiceDetail` query by number. Its response has `saleIdentifier` and `invoiceDate` `[readme]`.

The allowance takes the invoice date from the reference, or from the same query. With no number to query, the adapter raises `ValidationError`.

`get/searchInvoiceInfoByTransactionnumber` finds an invoice by order id, but its response is unknown. The adapter does not map it. Reach it through `raw`.

### 4.2 Fields

#### `issue`

| Unified | Tradevan | Rule or default |
| --- | --- | --- |
| (constructor) | `companyUn`, `orgId` | |
| (fixed) | `type` | `I` |
| `order_id` | `transactionNumber` | Max 50 |
| `order_id` | `saleIdentifier` | `"#{companyUn}_#{orgId}_#{order_id}"`, max 100. The prefix is a rule `[rules]`. The rest is our choice, so `void` can rebuild it from the order id |
| (now) | `transactionDate`, `transactionTime` | The current time in UTC+8, `yyyyMMdd` and `HH:MM:SS`. Tradevan requires them, and they are the time of this issue |
| `amount.total_amount` | `total` | Must equal the sum of `itemTotal` `[rules]` |
| (constructor) | `paperPrintMode`, `invoiceAlarmMode`, `invoicePaperReturned` | The meaning of the values is unknown (see 7). Require them in the constructor. Do not guess a default |
| `buyer.ubn` | `buyerUn` | B2B only |
| `buyer.name` | `buyerTitle` (B2B, max 60), `receiverName` (max 30) | A B2B name over 30 characters is cut for `receiverName` only |
| `buyer.address` | `receiverAddrRoad` | |
| `buyer.email` | `receiverEmail` | |
| `buyer.phone` | `receiverMobile` | Max 15 |
| `donation.npoban` | `donate` `Y`, `donationUnit` | Else `donate` `N`. A B2B invoice without a carrier leaves `donate` out, because `donate` `N` makes a carrier required |
| `carrier.type` | `carrierType` | `MOBILE_BARCODE` `3J0002`, `CITIZEN_CERTIFICATE` `CQ0001`, `MEMBER` the constructor's `member_carrier_type`. Sent with a donation too: the schema allows both (5.1) |
| `carrier.code` | `carrierId`, `carrierIdHidden` | Both the same. A `MEMBER` carrier without a code uses the buyer's email, then phone |
| `tax_type`, `items[].tax_type` | `itemList[].taxType` | Items with different tax types: `UnsupportedError`, because `MIXED_TAX` is not declared (4.6). `SPECIAL`: `UnsupportedError` (6.1) |
| `tax_rate` | (none) | Not sent. A taxable invoice with a rate other than `0.05`: `UnsupportedError` |
| `items[]` | `itemList` | See below |
| `remark` | (none) | `mainRemark` exists only for type `G`. Dropped |
| `price_mode` `TAX_EXCLUSIVE` | (none) | `itemTotal` includes tax, so this is a `ValidationError` |
| `currency` | (none) | Not TWD: `UnsupportedError` |

Items:

| Unified | Tradevan | Rule |
| --- | --- | --- |
| (header) | `saleIdentifier` | The same as the header |
| (index) | `serialNumber` | 4 digits: `0001`, `0002`, … |
| `description` | `productName` | Max 300 |
| `quantity` | `qty` | Written without a trailing `.0`. See 7, question 4 |
| `unit_price` | `price` | |
| `amount` | `itemTotal` | Tax included |
| `tax_type` | `taxType` | `T`, `Z`, `O` (6.1) |

Result:

| Unified | From |
| --- | --- |
| `invoice_number` | `invoiceNumber` |
| `invoice_datetime` | `invoiceDate` and `invoiceTime`, UTC+8 |
| `random_code` | `checkNumber` |
| `order_id`, `total_amount` | The input |
| `status` | `ISSUED`. Do not read `invoiceStatus` (6.3) |
| `reference` | Built from the fields above |

#### `void`

| Unified | Tradevan | Rule or default |
| --- | --- | --- |
| (fixed) | `type` | `I` |
| `invoice.number` | `invoiceNumber` | |
| see 4.1 | `saleIdentifier` | M |
| (constructor) | `invoicePaperReturned` | |
| `reason` | (none) | No field. Dropped |

Result: `invoice_number` from the input, `status` `VOIDED` after `voidStatus` `Y`, `cancel_datetime` `nil`.

#### `allowance`

| Unified | Tradevan | Rule or default |
| --- | --- | --- |
| (fixed) | `type` | `A` |
| `allowance_id` | `transactionNumber`, `allowanceIdentifier` | The identifier with the same prefix as `saleIdentifier` |
| (now) | `transactionDate` | Today in UTC+8 |
| `amount` | `allowanceExclusiveAmount`, `allowanceTax`, `allowanceInclusiveAmount` | See 4.3 |
| (constructor) | `allowancePaperReturned`, `invoicePaperReturned`, `paperPrintMode`, `invoiceAlarmMode` | |
| see 4.1 | `itemList[].saleIdentifier` | The original invoice's identifier `[readme-2026]` |
| `invoice.number` | `itemList[].invoiceNumber` | |
| `invoice.invoice_datetime`, else the query | `itemList[].invoiceDate` | M. `yyyyMMdd` in UTC+8 |
| `items[]` | `itemList[]` | As for issue. `itemExclude` is the item amount without tax, `tax` its tax, and `itemTotal` the two together (4.3) |

Result: no source shows the type `A` response. The adapter reads `allowanceNumber`, as the type `I` response has that field. If it is empty, the adapter raises `ProviderError` with the raw response. `allowance_date` is `allowanceDate` when the response has it, else today in UTC+8.

#### `void_allowance`

| Unified | Tradevan | Rule or default |
| --- | --- | --- |
| (fixed) | `type` | `A` |
| (constructor) | `companyUn`, `allowancePaperReturned` | |
| `allowance.allowance_number` | `allowanceNumber` | 16 chars |
| `reason` | (none) | Not sent |

Result: `allowance_number` from the input, `cancel_datetime` `nil`.

#### `query`

| Unified | Tradevan | Rule or default |
| --- | --- | --- |
| `invoice.number` | `searchInvoiceDetail`: `invoiceNumber` | A reference without a number: `UnsupportedError`, because `QUERY_BY_ORDER_ID` is not declared |

Result, from `searchInvoiceDetail` `[readme]`:

| Unified | From |
| --- | --- |
| `invoice_number` | `invoiceNumber` |
| `invoice_datetime` | `invoiceDate`, `invoiceTime` |
| `random_code` | `checkNumber` |
| `order_id` | `saleIdentifier` without the prefix |
| `status` | See 4.4 |
| `amount` | `sales = exclusiveAmount`, `tax = tax`, `total = total` |
| `buyer` | `receiverName`, `receiverAddr`, `receiverPhone`. No email or 統一編號 in the response |
| `items` | `detailList[]`: `productName`, `qty`, `price`, `total`, `taxType` |
| `reference` | Built from the fields above |

### 4.3 Amounts and tax

The unified rules are in [the unified model](../README.md#the-unified-model).

**Issue.**

- Amounts sit on each item: `itemTotal` (tax included) and an optional `tax` `[rules]`.
- The header `total` must equal the sum of `itemTotal` `[rules]`. Amounts are compared as decimals, not as integers.
- In `[readme]`, `itemTotal` 20000 and `tax` 952. The response gives `texclusiveAmount` 19048, `tax` 952, `inclusiveAmount` 20000. So Tradevan splits the tax: `20000 / 1.05 = 19047.6`, rounded to 19048.
- The adapter sends `itemTotal` with tax, and leaves the item `tax` out. Tradevan computes the split.
- B2B uses the same fields. The unified B2B amount has the tax apart, so `total` is `amount.total_amount`, and `itemTotal` is each item's amount with its tax.

**Allowance.**

- The header has `allowanceExclusiveAmount`, `allowanceTax` and `allowanceInclusiveAmount` `[rules]`. Each item has `itemExclude` (tax excluded), `tax` and `itemTotal`.
- After the core, each item has an amount without tax and its own tax (G0401). The adapter sends them as `itemExclude` and `tax`, and their sum as `itemTotal`.
- The header takes `sales_amount`, `tax_amount` and `total_amount`.

**Query.** `exclusiveAmount`, `tax` and `total` map directly.

### 4.4 Status

| Tradevan | Unified `InvoiceStatus` |
| --- | --- |
| `hasAllowance` `Y` | `ALLOWANCE` |
| `status` `I` / `V` | `nil`. The meaning is unknown (6.3) |

`status` decides between `ISSUED` and `VOIDED`, but we do not know which code means what. A wrong guess reports a voided invoice as issued. So the adapter declares `QUERY` but does not guess: `status` is `nil` unless `hasAllowance` is `Y`. The raw code stays in `raw["status"]`.

### 4.5 Timing

Unknown. The sources say nothing about upload times or void deadlines. The MOF rules still apply (see the MIG note).

### 4.6 Capabilities

| Capability | API | Adapter | Note |
| --- | --- | --- | --- |
| `ISSUE`, `VOID`, `VOID_ALLOWANCE` | yes | yes | In production use `[prod]` |
| `ALLOWANCE` | yes | yes | In production use `[prod]`, but the response is unknown |
| `QUERY` | yes | yes | The status codes are unknown, so `status` is often `nil` |
| `B2B` | yes | yes | `buyerUn` |
| `MIXED_TAX` | unknown | no | Items have their own `taxType`, so it may work (inferred). Until it is verified, mixed items raise `UnsupportedError` |
| `QUERY_BY_ORDER_ID` | unknown | no | `searchInvoiceInfoByTransactionnumber` exists, but its response is unknown |
| `SCHEDULED_ISSUE` | no | no | |
| `CARRIER_VALIDATION` | no | no | No barcode check. `Einvoice::MOF::DonationCodes` covers donation codes |
| `FOREIGN_CURRENCY` | no | no | No currency field |

### 4.7 Against the MIG

- **Tax types are letters.** `T`, `Z`, `O` stand for MIG `1`, `2`, `3` (inferred). There is no letter for MIG `4` or `9` (6.1).
- **Carrier types are the MIG codes** (6.2).
- **`checkNumber` on type `G`.** MIG 4.0 dropped `CheckNumber` from F0401 `[mig]`. We do not know what Tradevan does with it today.
- **No zero rated details.** `issueData` has no fields for `CustomsClearanceMark` or `ZeroTaxRateReason`, which F0401 requires for zero rated invoices `[mig 表 15-3]`. Tradevan must fill them, or zero rated invoices do not work through this API.
- **No void reason.** `voidData` has no reason. MIG F0501 requires `CancelReason`, so Tradevan fills it (inferred).
- **No void date.** `voidData` has no invoice date. Tradevan finds it from `saleIdentifier` and `invoiceNumber` (inferred).
- **Allowances carry the invoice date per item,** as MIG G0401 does.

### 4.8 Contract and live tests

- **No live tests.** We have no account and no host.
- **A fake only.** `spec/support/fake_tradevan.rb` follows the 1.x code and the `[readme]` examples. It uses two different keys, so a mix-up of `key1` and `key2` shows. It rejects keys outside the schema, as `[prod]` reports. Its failure texts are our guesses (6.4), so a passing contract proves only that the guesses are classified the same way. The fake must not use the adapter's own rule checks, or a wrong rule passes on both sides.
- **References.** The contract passes the reference from `issue` to the next steps. It has `order_id` and `invoice_datetime`, so void and allowance work.
- **Unknown allowance number.** The adapter checks that an allowance number has 16 characters before the call. So the contract gets a 16-character `unknown_allowance_number` (`ABCDE20260101999`).
- **Encryption.** `crypto_spec.rb` compares the cipher text byte for byte with output from the 1.x code. Tradevan publishes no test vectors.
- **Query status.** The contract checks the status after a void, and accepts `nil`, so it can pass while the status codes stay unknown.

## 5. Field reference

### 5.1 `post/issue`: `issueData`

One parameter, `issueData`, a JSON object `[summary]`. All values are strings `[readme]`.

`type` picks the operation. `[summary]` lists four purposes, and `[rules]` has five codes. The match below is inferred from which fields each type requires.

| `type` | Purpose (inferred) | Requires |
| --- | --- | --- |
| `I` | Issue a new invoice | `saleIdentifier`, `transactionTime`, `total` |
| `R` | Issue for an existing invoice | as `I`, plus `invoiceNumber` |
| `G` | Issue for an existing invoice, with its full header | as `R`. Allows `checkNumber`, `invoiceDate`, amounts |
| `A` | Issue a new allowance | `allowanceIdentifier`, allowance amounts |
| `H` | Issue for an existing allowance | as `A`, plus `saleIdentifier`, `invoiceNumber`, `allowanceNumber`, `allowanceDate` |

Header fields `[rules]`:

| Field | M/O | Rule | Types |
| --- | --- | --- | --- |
| `companyUn` | M | 8 chars | all |
| `orgId` | M | 5 chars | all |
| `orgUn` | O | 8 chars | all |
| `type` | M | `I` `R` `G` `H` `A` | all |
| `transactionNumber` | M | max 50 | all |
| `transactionDate` | M | `yyyyMMdd` | all |
| `transactionTime` | M | `HH:MM:SS` | I R G |
| `transactionSource`, `transactionTarget` | O | max 50 | all |
| `saleIdentifier` | M | max 100, starts with `{companyUn}_{orgId}_` | I R G H |
| `allowanceIdentifier` | M | max 100, same prefix | A H |
| `invoiceNumber` | M | 10 chars | R G H |
| `allowanceNumber` | M | 16 chars, starts with `orgId` | H |
| `allowanceDate` | M | `yyyyMMdd` | H |
| `allowaDeclaration` | O | 6 digits (example `201803`) | A |
| `total` | M | max 20, equals the sum of item `itemTotal` | I R G |
| `allowanceExclusiveAmount` | M | max 20 | A H |
| `allowanceTax` | M | max 8 | A H |
| `allowanceInclusiveAmount` | M | max 20 | A H |
| `allowancePaperReturned` | M | `Y` / `N` | A H |
| `paperPrintMode` | M | `0` to `4` | all |
| `invoiceAlarmMode` | M | `0` to `6` | all |
| `invoicePaperReturned` | O | `Y` / `N`. M for `A`, and when `buyerUn` is blank and `paperPrintMode` is not `0` | all |
| `donate` | O | 1 char (`Y` / `N`). M when type is I R G, `buyerUn` is blank and `paperPrintMode` is `0` | I R G |
| `donationUnit` | O | max 10. M when `donate` is `Y` | I R G |
| `carrierType` | O | 6 chars. M when `paperPrintMode` is `0`, `donate` is `N` and type is not `A` | all but A |
| `carrierId`, `carrierIdHidden` | O | max 64. M when `paperPrintMode` is `0` and `donate` is `N` | I R G |
| `buyerUn` | O | 8 chars | not A H |
| `buyerTitle` | O | max 60 | not A H |
| `receiverName` | O | max 30 | I R G A |
| `receiverAddrZip` | O | max 6 | I R G A |
| `receiverAddrRoad` | O | max 100 | I R G A |
| `receiverEmail` | O | max 80 | I R G A |
| `receiverMobile` | O | max 15 | I R G A |
| `idViewId` | O | max 10 | all |
| `memberId` | O | max 50 | all |
| `tax` | O | max 20 | I G |
| `checkNumber` | O | 4 chars | G |
| `invoiceDate` | O | 8 chars | G |
| `invoiceTime` | O | 8 chars | G |
| `texclusiveAmount`, `oeclusiveAmount`, `zexclusiveAmount` | O | max 20 | G |
| `mainRemark` | O | max 300 | G |
| `invoiceType` | O | `07` / `08` | G |
| `itemList` | M | array, see below | all |

`paperPrintMode` and `invoiceAlarmMode`: the meaning of each value is unknown. `[readme]` uses `0` and `4`.

`itemList` items `[rules]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `saleIdentifier` | M | max 100. Same as the header (for `A`, the original invoice's `saleIdentifier` `[readme-2026]`) |
| `serialNumber` | M | 4 digits (`0001`) |
| `productName` | M | max 300 |
| `qty` | M | max 20 |
| `price` | M | max 20 |
| `itemTotal` | M | max 20 |
| `taxType` | M | `T` / `O` / `Z` |
| `tax` | O | max 20 |
| `itemExclude` | O | max 20. M for `A` and `H` |
| `invoiceNumber` | O | 10 chars. M for `A` and `H` |
| `invoiceDate` | O | 8 digits. M for `A` and `H` |
| `invoiceTime` | O | `HH:MM:SS` |
| `productCode` | O | max 30 |
| `description` | O | max 300 |

`donationUnit` in 1.x is also checked against a bundled list of donation codes. That is a client rule, not an API rule.

### 5.2 `post/issue`: response

Type `I`, success `[readme]` (full example in 2.5):

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

One parameter, `voidData`, a JSON object `[summary]` `[rules]`:

| Field | M/O | Rule | Types |
| --- | --- | --- | --- |
| `type` | M | `C` / `I` / `A` | all |
| `saleIdentifier` | M | max 100 | C I |
| `invoiceNumber` | M | 10 chars | C I |
| `invoicePaperReturned` | M | `Y` / `N` | C I |
| `companyUn` | M | 8 chars | A |
| `allowanceNumber` | M | 16 chars | A |
| `allowancePaperReturned` | M | `Y` / `N` | A |

`I` voids an invoice `[readme]`. `A` voids an allowance `[readme-2026]`. `C` takes the same fields as `I`, and its meaning is unknown.

Response for type `I` `[readme]`:

```json
{ "saleIdentifier": "12345678_ABCDE_53b2a44e4b3c", "voidStatus": "Y", "failReason": "",
  "type": "I", "invoiceNumber": "GX38551078", "allowanceNumber": "" }
```

### 5.4 GET endpoints

Parameters `[summary]`, except where marked:

| Endpoint | Parameters |
| --- | --- |
| `searchInvoiceDetail` | `invoiceNumber` (M) |
| `searchInvoiceInfoByTransactionnumber` | `companyUn`, `orgId`, `transactionNumber` `[1x-code]` |
| `searchInvoiceByMemberId` | `companyUn` (M); one of `memberId`, `carrierId`, `sellTargetCode`; O `invoiceStartDate`, `invoiceEndDate` (`yyyyMMdd`) |
| `getInvoiceContent` | `invoiceNumber` or `sellTargetCode`; O `invoiceStartDate`, `invoiceEndDate` (`yyyyMMdd`) |
| `sendCardInfotoCust` | `companyUn`, `sellTargetCode` (M); `receiverEmail` or `receiverMobile`; O `invoiceStartYM`, `invoiceEndYM` (`yyyyMM`) |
| `getInvoiceMarkInfo` | `companyUn`, `orgId`, `uniFiedNumber`, `bookType`, `period` (`yyyymm`), all M |
| `getDonateUnitList` | `companyUn` (M) |

`searchInvoiceDetail` response, one object `[readme]`:

`saleIdentifier`, `invoiceNumber`, `checkNumber`, `invoiceDate`, `invoiceTime`, `exclusiveAmount`, `tax`, `total`, `status`, `hasAllowance` (`Y` / `N`), `sellerName`, `sellerUN`, `sellerAddr`, `sellerTel`, `receiverName`, `receiverAddr`, `receiverPhone`, `paper` (`Y` / `N`), `win` (`Y` / `N`), `donate` (`Y` / `N`), `carrierType`, and `detailList`. Each `detailList` item has `saleIdentifier`, `serialNumber`, `productName`, `qty`, `price`, `total`, `taxType`.

`searchInvoiceByMemberId` response, an array `[readme]`: the same header fields as `searchInvoiceDetail`, without `receiverPhone` and `detailList`, plus `carrierId`.

`getInvoiceMarkInfo` response, an array `[readme]`: `unifiedNumber`, `bookNumber`, `bookType`, `period`, `duration`, `mark` (字軌, e.g. `GX`), `start`, `end`.

## 6. Codes

### 6.1 Tax type (`taxType`)

No source lists these codes. We inferred them from the type `G` amount fields: `texclusiveAmount`, `oeclusiveAmount` and `zexclusiveAmount`.

| Unified | Tradevan | Meaning | MIG |
| --- | --- | --- | --- |
| `TAXABLE` | `T` | Taxable (應稅) | `1` |
| `ZERO_RATED` | `Z` | Zero rated (零稅率) | `2` |
| `TAX_FREE` | `O` | Tax free (免稅) | `3` |
| `SPECIAL` | (none) | | `4` |

All three letters are inferred. The MIG also has `9` (mixed, header only) `[mig 表 4-12]`. DEFAULTAPI has no header tax type.

### 6.2 Carrier type (`carrierType`)

| Unified | Code | Meaning | Status |
| --- | --- | --- | --- |
| `MOBILE_BARCODE` | `3J0002` | Mobile barcode (手機條碼) | MIG code `[mig 表 4-13]`, used in `[readme]` |
| `CITIZEN_CERTIFICATE` | `CQ0001` | Citizen certificate (自然人憑證) | MIG code `[mig 表 4-13]`, used in `[readme]` |
| `MEMBER` | merchant code | Member carrier | The MIG says the MOF platform gives each seller or center its own 6-char code `[mig 表 15-3]`. The 1.x factories use `1K0001` |

`carrierType` is the MIG field as it is, so DEFAULTAPI passes it to the MOF without change (inferred).

### 6.3 Status

| Field | Values seen | Meaning |
| --- | --- | --- |
| `invoiceStatus` (issue response) | `V` | unknown |
| `status` (search responses) | `I`, `V` | unknown |
| `issueStatus`, `voidStatus` | `Y` | `Y` is success. `N` is failure. This comes from the 1.x spec stubs. Nobody has seen it in a real response |

The MOF's own status list (E0502 `CurrentStatus`) uses the digits `1` to `7` `[mig 表 23-2]`. So `I` and `V` are Tradevan's own codes, and the MIG cannot tell us what they mean.

### 6.4 Errors

There is no error code list. A failure has `Success` `N` or `E`, and a free-text `failReason` or `Message`. The only failure text on record is `duplicated`, from a 1.x spec stub, not from a real response.

The classification. Everything in it is a guess until real failure texts are known:

| Case | Unified error | `Reason` |
| --- | --- | --- |
| HTTP or JSON failure | `NetworkError` / `ProviderError` | |
| `Success` `E`, the text mentions the account, password or key | `AuthError` | `CREDENTIALS_INVALID` |
| `Success` `E`, other text | `ProviderError` | |
| `failReason` `duplicated`, or contains 重複 / 重覆 | `ConflictError` | `DUPLICATE_ORDER` |
| Text contains 已作廢 / 已被作廢 | `ConflictError` | `ALREADY_VOIDED` |
| Text contains 查無 / 不存在 / not found | `NotFoundError` | |
| anything else | `ProviderError` | |

**Default class.** The fallback is `ProviderError`, not `ValidationError`. With so few samples, an unknown failure is more likely a provider problem than bad input.

## 7. Open questions

1. What do the status codes `V` and `I` mean? An adapter that guesses wrong can report a voided invoice as issued.
2. What does the type `A` issue response look like? Does it return an allowance number?
3. What failure texts does Tradevan send? Without them, errors cannot map to `NotFoundError` or `ConflictError`.
4. Is `qty` scaled? In `[readme]` an item has `qty` 4000, `price` 5 and `itemTotal` 20000, so `qty × price = itemTotal`. In `[readme-2026]` an item has `qty` 1000, `price` 100 and `itemTotal` 100, so `qty` looks like units × 1000. `[rfc]` also calls `qty` "a ×1000 integer". The sources do not agree, and a 1.x user who moves to 2.x needs the answer.
5. What are the test and production hosts?
6. Which key decrypts the response, `key1` (`[1x-code]`) or `key2` (`[summary]`)?
7. What is the difference between cancel types `C` and `I`? Between issue types `R` and `G`?
8. What do the values of `paperPrintMode` and `invoiceAlarmMode` mean? What is `sellTargetCode`?
9. Which version of Tradevan's document did `[summary]` summarize? It was not recorded.
10. How does Tradevan fill the MIG zero rated fields and the void reason, which DEFAULTAPI does not send?
