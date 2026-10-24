# ECPay 綠界: B2C 電子發票 API

English | [繁體中文](b2c.zh-TW.md)

## 1. Status and sources

> **Trust:** the 2.x line has an adapter for this API. The five operations were run against the stage API and recorded (2026-08-15). Facts with only a `[doc]` tag were not run.

This is ECPay's B2C invoice API, the AES JSON API under `/B2CInvoice/`. The 2.x line has an adapter for it: `Einvoice::ECPay::Provider` (`lib/einvoice/ecpay/`).

The docs belong to 綠界科技 ECPay and are published at <https://developers.ecpay.com.tw/7809/>. This note is our summary.

The B2C API also issues invoices to a business buyer: send a 統一編號 in `CustomerIdentifier`. ECPay's home page says a seller does not need the separate B2B API for that `[doc 7809]`. The B2B API is not covered here.

| Tag | Source | Date | What it gives |
| --- | --- | --- | --- |
| `[doc]` | ECPay B2C電子發票API技術文件, <https://developers.ecpay.com.tw/7809/>. One page per endpoint. We read all 44 pages on 2026-10-14. | Home page changed 2026-03-12, issue page 2026-05-20 | Everything below that has no other tag. |
| `[live]` | Our live specs (`spec/einvoice/ecpay/live_spec.rb`) and the VCR cassettes they recorded (`spec/fixtures/vcr_cassettes/ecpay/`) | 2026-08-15, stage | Real requests, responses and error codes. |
| `[code]` | The 2.x adapter (`lib/einvoice/ecpay/`) | 2026-08 | What the adapter does today. Its comments name some codes as checked live, but no cassette records them. |
| `[fixture]` | Wire and error fixtures of another SDK for the same API. A copy is in `spec/fixtures/shared/ecpay/`, with its source. We read them on 2026-10-28. | Transport errors run live on stage 2026-08-15, by that SDK's authors | Error codes and messages that its authors saw live. |

`[doc 7896]` means the page `https://developers.ecpay.com.tw/7896/`. Page numbers are listed in section 3.

ECPay keeps its full error code list in the merchant back office, not in the public docs `[doc 7954]`. So the error codes in 6.4 come from single pages and from `[live]`.

**Updates.** ECPay lists its changes on the 更新歷程 page, <https://developers.ecpay.com.tw/36050/>. Each endpoint page also shows the date it last changed.

## 2. Connection

### 2.1 Hosts and credentials

| Environment | Host |
| --- | --- |
| Test (stage) | `https://einvoice-stage.ecpay.com.tw` |
| Production | `https://einvoice.ecpay.com.tw` |

A merchant has a `MerchantID` (特店編號), a `HashKey` and a `HashIV` `[doc 7849]`. In production they are in the back office under 系統設定 → 系統介接設定 → 介接資訊.

ECPay publishes shared test credentials `[doc 7849]`. The adapter has them as `Einvoice::ECPay::SANDBOX`.

| Account | MerchantID | HashKey | HashIV |
| --- | --- | --- | --- |
| Merchant | `2000132` | `ejCk326UnaZWKisg` | `q9jcZX8Ib9LM8wYk` |
| Platform | `3085340` (PlatformID) | `HwiqPsywG1hLQNuN` | `YqITWD4TyKacYXpn` |

The stage MOF platform often fails. So stage marks every invoice as uploaded and never sends it to the MOF `[doc 7849]`. Stage also sends no email or SMS `[doc 7938, 15391]`.

A platform merchant (平台商) sends its `PlatformID` and a sub-merchant's `MerchantID`. Normal merchants leave `PlatformID` empty.

### 2.2 Request

Every endpoint is `POST`, `Content-Type: application/json`, over TLS 1.2 on port 443 `[doc 7854]`.

```json
{ "MerchantID": "2000132", "RqHeader": { "Timestamp": 1525168923 }, "Data": "<encrypted>" }
```

- `Timestamp` is a Unix time. ECPay accepts it for 10 minutes. Keep the server clock in sync `[doc 7896]`.
- `Data` is the business payload, encrypted (2.3). It must also carry `MerchantID`.
- The docs list no `Revision` in `RqHeader`. The adapter sends `"Revision": "3.0.0"`, and the response echoes it `[live]`. See 7.
- Leave out empty optional fields instead of sending `null`. The adapter drops `nil` values at the top level `[code]`.

### 2.3 Encryption

`[doc 7958]`:

- AES-128-CBC with PKCS7 padding, using the merchant's `HashKey` and `HashIV`. Both must be 16 bytes.
- Encrypt: JSON → URL encode → AES → Base64.
- Decrypt: Base64 → AES → URL decode → JSON.
- The URL encoding may use upper or lower case hex. The cipher text differs, and both decode to the same JSON. The page gives a test vector for each.

The URL encoding is PHP `urlencode`, and this is where implementations go wrong `[code]`:

- A space becomes `+`, not `%20`.
- Only `a-z`, `A-Z`, `0-9`, `-`, `_` and `.` stay as they are. Every other byte becomes `%XX`, `~` and `!*'()` too. Ruby's `CGI.escape` leaves `~` alone, so it does not match.
- Encode the UTF-8 bytes, so Chinese text survives.

**Official test vectors** `[doc 7958]`. MerchantID `2000132`, HashKey `ejCk326UnaZWKisg`, HashIV `q9jcZX8Ib9LM8wYk`, and the JSON `{"Name":"Test","ID":"A123456789"}`:

| URL encoding | Encoded | Cipher text |
| --- | --- | --- |
| Upper case hex | `%7B%22Name%22%3A%22Test%22%2C%22ID%22%3A%22A123456789%22%7D` | `uvI4yrErM37XNQkXGAgRgJAgHn2t72jahaMZzYhWL1HmvH4WV18VJDP2i9pTbC+tby5nxVExLLFyAkbjbS2Dvg==` |
| Lower case hex | `%7b%22Name%22%3a%22Test%22%2c%22ID%22%3a%22A123456789%22%7d` | `ZD/z07UvdmL3aYz0tsVo+bFXF5VldNcns6ezyfea777KOmLiizrUNDYe+v1bh2QTT4AySf1NICgXxWXB6f7c6A==` |

PHP `urlencode` gives upper case hex, so encryption must give the first value. Decryption must accept both. The vectors use no space, `~` or Chinese, so they do not test the rules above. The crypto spec covers those with extra vectors of its own.

**Limits of the API.** The response has no signature. `Data` is AES-CBC without a MAC, and `TransCode` and `RtnCode` are outside any check. The fixed `HashIV` means the same request always gives the same cipher text. So the integrity of a response depends on TLS only.

Only the server callback of the online allowance uses `CheckMacValue` `[doc 38242, 15391]`. It is an MD5 hash of the sorted, URL encoded parameters, with `HashKey` and `HashIV` around them.

### 2.4 Response

```json
{ "PlatformID": 0, "MerchantID": 2000132,
  "RpHeader": { "Timestamp": 1786807739, "RqID": "c62778a1-…", "Revision": "3.0.0" },
  "TransCode": 1, "TransMsg": "Success", "Data": "<encrypted>" }
```

There are two result layers, and the adapter checks both:

1. `TransCode` is the transport result. `1` means ECPay read the envelope.
2. After decrypting `Data`: `RtnCode` is the business result. `1` means success, with a few exceptions (6.4).

HTTP status codes also matter `[doc 7854]`:

- **403**: too many calls. Wait 30 minutes before you call again. The adapter raises `NetworkError` with `Reason::RATE_LIMITED`, so the caller can retry later.
- **500**: bad data format, a `MerchantID` that does not match the key and IV, or an encryption error. A wrong key gives `TransCode` 110 with HTTP 500, and `Data` is empty `[live]`.

### 2.5 Example

An issue call on stage, with `Data` shown decrypted `[live]` (`issue.yml`).

Request `Data`:

```json
{ "MerchantID": "2000132", "RelateNumber": "RBVCR20260815issue",
  "CustomerID": "", "CustomerIdentifier": "", "CustomerName": "", "CustomerAddr": "",
  "CustomerPhone": "", "CustomerEmail": "test@example.com",
  "Print": "0", "Donation": "0", "LoveCode": "", "CarrierType": "1", "CarrierNum": "",
  "TaxType": "1", "SalesAmount": 100, "InvoiceRemark": "",
  "Items": [{ "ItemSeq": 1, "ItemName": "整合測試商品", "ItemCount": 2, "ItemWord": "式",
              "ItemPrice": 50, "ItemTaxType": "1", "ItemAmount": 100 }],
  "InvType": "07", "vat": "1" }
```

Response `Data`:

```json
{ "RtnCode": 1, "RtnMsg": "開立發票成功", "InvoiceNo": "LA25008597",
  "InvoiceDate": "2026-08-15 23:28:58", "RandomNumber": "6049" }
```

Section 5 has an example for each of the other operations.

### 2.6 Callbacks

Two endpoints call back to the merchant: delayed issue (`NotifyURL`) and online allowance (`ReturnURL`). The merchant answers `1|OK` `[doc 15369, 15391]`. Stage sends no `NotifyURL` callback. Delayed issue callbacks come from `postgate.ecpay.com.tw` (stage: `postgate-stage.ecpay.com.tw`). The adapter does not handle callbacks.

## 3. Operations

The five unified operations use these endpoints. Section 5 has their fields.

| Endpoint | Purpose | Page |
| --- | --- | --- |
| `/B2CInvoice/Issue` | Issue an invoice now (一般開立) | 7896 |
| `/B2CInvoice/Invalid` | Void an invoice | 7906 |
| `/B2CInvoice/Allowance` | Issue a paper allowance (紙本開立) | 7901 |
| `/B2CInvoice/AllowanceInvalid` | Void an allowance | 7911 |
| `/B2CInvoice/GetIssue` | One invoice, by order id or by number and date | 7923 |

The adapter also maps two checks: `/B2CInvoice/CheckBarcode` (is a mobile barcode registered, page 7886) and `/B2CInvoice/CheckLoveCode` (is a donation code registered, and its name, page 7891).

Other endpoints. An adapter can reach them through `Provider#raw`:

| Endpoint | Purpose | Page |
| --- | --- | --- |
| `DelayIssue`, `EditDelayIssue`, `TriggerIssue`, `CancelDelayIssue` | Hold an invoice, change it, trigger it, cancel it | 15369, 47979, 15371, 15382 |
| `AllowanceByCollegiate`, `AllowanceInvalidByCollegiate` | Online allowance: the buyer confirms by email. Cancel it before the confirm | 15391, 7913 |
| `VoidWithReIssue` | Cancel and reissue with the same number (註銷重開) | 7918 |
| `GetIssueList`, `GetAllowanceList`, `GetInvalid`, `GetAllowanceInvalid` | List invoices or allowances, read one void | 17229, 7928, 7933, 7943 |
| `GetCompanyNameByTaxID` | Check a 統一編號 and get the company name | 32089 |
| `InvoiceNotify`, `InvoicePrint` | Send a notice, get a printable page | 7938, 7949 |
| `GetGovInvoiceWordSetting`, `AddInvoiceWordSetting`, `UpdateInvoiceWordStatus`, `GetInvoiceWordSetting` | Number ranges and tracks | 7859, 7870, 7875, 7881 |
| `GetInvoiceNotifySetting`, `InvoiceNotifySetting`, `GetRemainNotifySetting`, `RemainNotifySetting` | Notice and low number settings (added 2026-06-23) | 63356, 64067, 64079, 64088 |
| `QueryBlankInvoiceList`, `BlankInvAutoUploadSetting`, `DownLoadBlankInvList` | Unused numbers (E0402) | 64106, 64122, 64133 |

All paths start with `/B2CInvoice/`. Page 49890 is an older copy of the issue page ("一般開立發票 - MIG 4.0", changed 2025-01-22). It lacks the newer fields. Use 7896.

## 4. Mapping to the unified API

### 4.1 Operations

| Unified | Endpoint | Reference fields | `provider_options` |
| --- | --- | --- | --- |
| `issue` | `Issue` | | `customer_id`, `clearance_mark`, `zero_tax_rate_reason`, `special_tax_type`, `data` (merges any raw `Issue` field) |
| `void` | `Invalid` | `invoice_datetime` | |
| `allowance` | `Allowance` | `invoice_datetime` | `allowance_notify`, `notify_mail`, `notify_phone`, `customer_name`, `reason` |
| `void_allowance` | `AllowanceInvalid` | `invoice_number` of the allowance reference | |
| `query` | `GetIssue` | `order_id`, or `number` with `invoice_datetime` | |

All `provider_options` keys are strings or symbols.

**Missing invoice date.** `void`, `allowance` and a query by number need the invoice date. If the reference has no `invoice_datetime` but has `order_id`, the adapter queries `GetIssue` by `RelateNumber` first and takes `IIS_Create_Date`. Otherwise it raises `ValidationError` for `invoice_datetime`. A plain invoice number is not enough.

**Missing invoice number on void allowance.** `AllowanceInvalid` needs `InvoiceNo`. A plain allowance number has none, so it raises `ValidationError` for `invoice_number`.

### 4.2 Fields

#### `issue`

| Unified | ECPay | Rule or default |
| --- | --- | --- |
| `order_id` | `RelateNumber` | Max 50 |
| `buyer.ubn` | `CustomerIdentifier` | B2B only. Empty for B2C |
| `buyer.name`, `.address`, `.phone`, `.email` | `CustomerName`, `CustomerAddr`, `CustomerPhone`, `CustomerEmail` | Empty string when missing. A printed invoice (`Print` `1`) needs the name and the address `[doc 7896]` |
| `carrier.type` | `CarrierType` | `MEMBER` `1`, `CITIZEN_CERTIFICATE` `2`, `MOBILE_BARCODE` `3` |
| `carrier.code` | `CarrierNum` | Empty for `MEMBER`. ECPay builds the carrier from the email or phone |
| `donation.npoban` | `LoveCode` | And `Donation` `1`. A carrier can be sent with it (4.7) |
| (derived) | `Print` | `0` with a carrier or a donation, else `1` |
| `tax_type`, `items[].tax_type` | `TaxType` | `9` when the items have different tax types, else the code (6.1) |
| `tax_type` | `InvType` | `08` for `SPECIAL`, else `07` |
| `price_mode` | `vat` | `TAX_EXCLUSIVE` `0`, else `1` |
| `amount.total_amount` | `SalesAmount` | See 4.3 |
| `tax_rate` | (none) | ECPay fixes the rate by `TaxType`. A taxable invoice with a rate other than `0.05` raises `UnsupportedError`. `SPECIAL` uses `special_tax_type` |
| `provider_options[:clearance_mark]` | `ClearanceMark` | Required when a zero rated item is present |
| `provider_options[:zero_tax_rate_reason]` | `ZeroTaxRateReason` | `71` to `79`. Passed through. ECPay requires it for `TaxType` `2` and `9` from 2026-01-01, unless it is set in the back office, so the adapter cannot check it |
| `remark` | `InvoiceRemark` | |
| `items[]` | `Items` | See below |
| `currency` | (none) | Not TWD: `UnsupportedError` |
| `amount.sales_amount`, `amount.tax_amount`, `exchange_rate` | (none) | Not sent |

Items:

| Unified | ECPay | Rule or default |
| --- | --- | --- |
| (index) | `ItemSeq` | 1, 2, 3, … |
| `description` | `ItemName` | |
| `quantity` | `ItemCount` | |
| `unit` | `ItemWord` | `式` when missing |
| `unit_price` | `ItemPrice` | |
| `tax_type` | `ItemTaxType` | The item's type, else the invoice's, else taxable |
| `amount` | `ItemAmount` | |
| `remark` | `ItemRemark` | Only when given |

Result:

| Unified | From |
| --- | --- |
| `invoice_number` | `InvoiceNo` |
| `invoice_datetime` | `InvoiceDate` (date and time), UTC+8 |
| `random_code` | `RandomNumber` |
| `order_id`, `total_amount` | The input |
| `status` | `ISSUED` |
| `reference` | Built from the fields above |

#### `void`

| Unified | ECPay | Rule or default |
| --- | --- | --- |
| `invoice` | `InvoiceNo` | |
| `invoice.invoice_datetime` | `InvoiceDate` | `yyyy-MM-dd` in UTC+8. See 4.1 when it is missing |
| `reason` | `Reason` | Max 20 |

Result: `invoice_number` from the input, `status` `VOIDED`, `cancel_datetime` `nil`. The response has no void time.

#### `allowance`

| Unified | ECPay | Rule or default |
| --- | --- | --- |
| `invoice` | `InvoiceNo` | |
| `invoice.invoice_datetime` | `InvoiceDate` | The original invoice date, `yyyy-MM-dd` in UTC+8 |
| `provider_options[:allowance_notify]` | `AllowanceNotify` | `N` (no notice) when missing |
| `provider_options[:customer_name]`, `[:notify_mail]`, `[:notify_phone]`, `[:reason]` | `CustomerName`, `NotifyMail`, `NotifyPhone`, `Reason` | Sent only when given |
| `amount.total_amount` | `AllowanceAmount` | Tax included. See 4.3 |
| `items[]` | `Items` | As for `issue`. `ItemAmount` is the item amount plus its tax (4.3) |
| `allowance_id` | (none) | Not sent. ECPay assigns the allowance number |

Result:

| Unified | From |
| --- | --- |
| `allowance_number` | `IA_Allow_No` (16 digits) |
| `invoice_number` | `IA_Invoice_No`, else the input |
| `allowance_date` | The date part of `IA_Date`, UTC+8 |
| `total_amount` | The input |
| `reference` | `allowance_number`, `allowance_date`, `invoice_number` |

#### `void_allowance`

| Unified | ECPay | Rule or default |
| --- | --- | --- |
| `allowance.invoice_number` | `InvoiceNo` | See 4.1 when it is missing |
| `allowance` | `AllowanceNo` | |
| `reason` | `Reason` | Max 20. The core fills `作廢折讓` when it is missing |

Result: `allowance_number` from the input, `cancel_datetime` `nil`.

#### `query`

| Unified | ECPay | Rule or default |
| --- | --- | --- |
| `invoice.order_id` | `RelateNumber` | Used when present |
| `invoice.number` | `InvoiceNo` | Only without an order id |
| `invoice.invoice_datetime` | `InvoiceDate` | With `InvoiceNo` only. Required with it |

Result:

| Unified | From |
| --- | --- |
| `invoice_number` | `IIS_Number` |
| `invoice_datetime` | `IIS_Create_Date`, UTC+8 |
| `random_code` | `IIS_Random_Number` |
| `order_id` | `IIS_Relate_Number` |
| `status` | See 4.4 |
| `amount` | See 4.3 |
| `buyer` | `IIS_Customer_Name`, `_Addr`, `_Phone`, `_Email`, and `IIS_Identifier` as `ubn`. `0000000000` and empty strings become `nil` |
| `items` | `Items`: `ItemName`, `ItemCount`, `ItemPrice`, `ItemAmount`, `ItemWord`, `ItemTaxType`, `ItemRemark`. Whole numbers stay integers |
| `reference` | Built from the fields above, with `IIS_Sales_Amount` as `total_amount` |

### 4.3 Amounts and tax

The unified rules are in [the unified model](../README.md#the-unified-model).

**Issue.**

- The adapter sends `amount.total_amount` as `SalesAmount`, for both B2C and B2B. It is the amount with tax included `[doc 7896]`. `sales_amount` and `tax_amount` are not sent. ECPay computes the tax: `round(SalesAmount / 1.05 × 0.05)`. For mixed tax, it uses the sum of the taxable items `[doc 7896]`.
- With `vat` `1`, `SalesAmount` must equal the rounded sum of `ItemAmount`, or ECPay returns `5000022` `[live]`. The adapter checks this before the call.
- With `vat` `0`, ECPay computes the total itself.
- Item amounts may have up to 7 digits after the point. Only the sum is rounded `[doc 7896]`.

**Allowance.**

- After the core, each allowance item has an amount without tax and its own tax (G0401). ECPay wants amounts with tax `[doc 7901]`. So `ItemAmount` is the item amount plus its tax, and `AllowanceAmount` is `amount.total_amount`.
- `ItemAmount` may differ from `ItemPrice × ItemCount` by at most 1. The sum of `ItemAmount` must equal `AllowanceAmount`. The adapter checks this before the call.
- ECPay splits out the tax again for the MOF (4.7).

**Query.**

- `IIS_Sales_Amount` is the total with tax. `IIS_Tax_Amount` is only filled for B2B. For B2C it is `0` `[doc 7923]` `[live]`.
- The result is `total = IIS_Sales_Amount`, `tax = IIS_Tax_Amount`, `sales = total - tax`. A B2C invoice reads back as `tax 0`, as F0401 shows it to a consumer.

### 4.4 Status

`GetIssue` reports status in three fields `[doc 7923]`. The adapter reads them in this order:

| ECPay | Unified `InvoiceStatus` |
| --- | --- |
| `IIS_Issue_Status` `0` (cancelled, 註銷) | `nil` |
| `IIS_Invalid_Status` `1` | `VOIDED` |
| `IIS_Remain_Allowance_Amt` below `IIS_Sales_Amount` (and sales above 0) | `ALLOWANCE` |
| otherwise | `ISSUED` |

Seen live `[live]`: a voided invoice has `IIS_Invalid_Status` `1` and `IIS_Remain_Allowance_Amt` `0`. After an allowance of 50 on a total of 100, `IIS_Remain_Allowance_Amt` is `50`.

`IIS_Upload_Status` (`1` uploaded) and `IIS_Turnkey_Status` (`C` the MOF accepted it, `E` the upload failed) show the upload to the MOF. The adapter does not read them.

### 4.5 Timing

- Voids, allowances and allowance voids are uploaded to the MOF the next day `[doc 7906, 7901, 7911]`. Issued invoices are uploaded within 48 hours `[doc 7809]`.
- An invoice can be voided right after it is issued `[live]`. An allowance can be voided right after it is issued `[live]`.
- After 23:59:59 on the 13th of an odd month, invoices and allowances of the two months before cannot be voided. On 14 March, January and February invoices are closed `[doc 7906, 7911]`.
- A cancel-and-reissue (註銷重開) must finish before the 13th of the month after the period `[doc 7918]`.
- A paper allowance (`Allowance`) still needs the buyer's signature on paper. The seller mails it and keeps it. The online allowance (`AllowanceByCollegiate`) replaces the signature with an email link, valid 72 hours `[doc 7901, 15391]`.

### 4.6 Capabilities

| Capability | API | Adapter | Note |
| --- | --- | --- | --- |
| `ISSUE`, `VOID`, `ALLOWANCE`, `VOID_ALLOWANCE`, `QUERY` | yes | yes | |
| `B2B` | yes | yes | Through the B2C API with a 統一編號 |
| `MIXED_TAX` | yes | yes | `TaxType` `9` needs approval from ECPay `[doc 7896]`. The adapter sends `9` when the items differ |
| `QUERY_BY_ORDER_ID` | yes | yes | `RelateNumber` |
| `SCHEDULED_ISSUE` | yes | no | `DelayIssue` exists. The adapter does not map it |
| `CARRIER_VALIDATION` | yes | yes | `validate_carrier` calls `CheckBarcode` for a mobile barcode |
| `FOREIGN_CURRENCY` | no | no | The B2C API has no currency field |

### 4.7 Against the MIG

- **B2B goes through storage (F0401), not exchange (inferred).** The B2C API accepts a 統一編號 with a carrier, and allows mixed tax. MIG A0101 allows neither. So ECPay must upload these invoices as F0401. This answers the MIG note's open question 4 for ECPay.
- **A donated invoice can carry a carrier** `[doc 7896]`. It means the buyer donated it later. The MIG allows it too.
- **Allowance amounts include tax.** `AllowanceAmount` and `ItemAmount` include tax `[doc 7901]`. MIG G0401 wants amounts without tax and a tax per item. ECPay does the split. Its allowance query returns both: `IA_Total_Amount` (tax excluded) and `IA_Total_Tax_Amount` (tax included), plus `ItemRateAmt` per item `[doc 7928]`.
- **Voiding an allowance needs no allowance date.** MIG G0501 requires it, so ECPay must fill it from its own records `[doc 7911]`.
- **Voiding and querying by number need the invoice date,** as MIG F0501 does `[doc 7906, 7923]`.
- **Up to 999 items** `[doc 7896]`. The MIG allows 9999.
- **Reasons are 1 to 20 chars** for voids and allowance voids `[doc 7906, 7911]`, as in the MIG. The allowance reason (`Reason` in `Allowance`) is up to 50 chars.

### 4.8 Contract and live tests

- **Offline contract.** `spec/einvoice/ecpay/provider_spec.rb` runs the shared contract against `spec/support/fake_ecpay.rb`. The fake speaks the real envelope, encryption and `RtnCode`s.
- **Unknown numbers.** ECPay checks the format first, so the contract gets `unknown_invoice_number: "ZZ00000000"` and `unknown_allowance_number: "9999999999999999"`.
- **References.** The contract passes the reference from `issue` to the next steps, so `invoice_datetime` is always there.
- **Shared fixtures.** Another SDK publishes wire fixtures for this API. The spec runs a copy of them from `spec/fixtures/shared/ecpay/`. Cases where the unified model differs on purpose are skipped, with the reason.
- **Live specs.** `spec/einvoice/ecpay/live_spec.rb` runs against stage with `ECPAY_LIVE=1`. The stage account is shared with every other developer, so each run builds a unique order id (`RB` + time + a random number).
- **Recorded specs.** `spec/einvoice/ecpay/recorded_spec.rb` replays the cassettes in `spec/fixtures/vcr_cassettes/ecpay/`.
- **What stage cannot test.** Stage does not upload to the MOF, and sends no email, SMS or `NotifyURL` callback `[doc 7849, 15369]`. So upload status, notices and callbacks cannot be checked there.

## 5. Field reference

### 5.1 `Issue`

`Data` fields `[doc 7896]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `MerchantID` | M | max 10 |
| `RelateNumber` | M | max 50. Unique. No special symbols. Case does not matter (`abc` = `ABC`) |
| `ChannelPartner` | O | `1` Shopee. Other values are ignored |
| `CustomerID` | O | max 20. Letters, digits, `_` |
| `ProductServiceID` | O | 1 to 10 letters or digits. Only used when the merchant has 「B2C系統多組字軌」 on |
| `CustomerIdentifier` | O | 8 digits. The buyer's 統一編號 |
| `CustomerName` | O | max 60. M when `Print` is `1`. Use the company name when there is a 統一編號 |
| `CustomerAddr` | O | max 100. M when `Print` is `1` |
| `CustomerPhone` | O | max 20, digits. M when `CustomerEmail` is empty |
| `CustomerEmail` | O | max 80, one address. M when `CustomerPhone` is empty |
| `ClearanceMark` | O | `1` / `2`. M when `TaxType` is `2` or `9` |
| `Print` | M | `0` / `1`. This only marks that the merchant prints the invoice. ECPay does not print or mail it |
| `Donation` | M | `0` / `1` |
| `LoveCode` | O | 3 to 7 digits, may start with `0`. M when `Donation` is `1` |
| `CarrierType` | O | Empty, `1` ECPay carrier, `2` citizen certificate, `3` mobile barcode, `4` EasyCard, `5` iPASS |
| `CarrierNum` | O | max 64. See below |
| `CarrierNum2` | O | max 64. M for `4` and `5`: the card's visible code. Leave empty for `1` to `3` |
| `TaxType` | M | `1` taxable, `2` zero rated, `3` tax free, `4` special rate, `9` mixed (needs approval). With `InvType` `07`: `1`, `2`, `3` or `9`. With `08`: `3` or `4` |
| `ZeroTaxRateReason` | O | `71` to `79`. From 2026-01-01, M when `TaxType` is `2` or `9`, unless set in the back office |
| `SpecialTaxType` | O | `0` for `TaxType` `1`, `2`, `9`. `8` for `3`. `1` to `8` for `4` (6.3) |
| `SalesAmount` | M | Integer, tax included, TWD only, up to 12 digits |
| `TaxAmount` | O | Integer, up to 11 digits. ECPay computes it if missing. If given, it may differ from ECPay's result by at most 1. `0` for special tax |
| `InvoiceRemark` | O | max 200. `\r\n`, `\r` or `\n` breaks the line |
| `Items` | M | 1 to 999 items |
| `InvType` | M | `07` general, `08` special |
| `vat` | O | `1` prices include tax (default), `0` prices exclude tax |

`CarrierNum` by `CarrierType`:

| Type | `CarrierNum` |
| --- | --- |
| empty | empty |
| `1` | empty. ECPay builds the carrier from the email or phone, email first |
| `2` | 16 chars: 2 capital letters and 14 digits |
| `3` | 8 chars: `/` and 7 of `0-9`, `A-Z`, `+`, `-`, `.` |
| `4`, `5` | M. The card's hidden code. Not checked |

Item fields:

| Field | M/O | Rule |
| --- | --- | --- |
| `ItemSeq` | O | 1 to 999 |
| `ItemName` | M | max 500 |
| `ItemCount` | M | 8 digits, up to 7 after the point |
| `ItemWord` | M | max 6. The unit |
| `ItemPrice` | M | 10 digits, up to 7 after the point. Tax included or not, as `vat` says |
| `ItemTaxType` | O | `1`, `2`, `3`. M when `TaxType` is `9`, ignored otherwise |
| `ItemAmount` | M | Tax included. 12 digits, up to 7 after the point |
| `ItemRemark` | O | max 120 |

Rules across fields `[doc 7896]`:

- The sum of `ItemAmount`, rounded, must equal `SalesAmount`. With `vat` `0` and `TaxType` `1`, `ItemPrice × ItemCount × 1.05 = ItemAmount`.
- Mixed tax (`9`) allows taxable with tax free, or taxable with zero rated. Not tax free with zero rated.
- Donated (`Donation` `1`): `Print` must be `0`, and `CustomerIdentifier` must be empty. A carrier is allowed: it means the buyer donated the invoice later.
- With a 統一編號: `Donation` must be `0`. No carrier means `Print` `1`. Carrier `1` or `2` means `Print` `0`. Carrier `3` allows either.
- With a 統一編號 and `Print` `1`, the only carrier allowed is `3`.

The docs and the API do not always agree. The adapter's checks follow what stage really did `[live]`:

- A B2C invoice with a carrier must not print (`5000015`).
- A B2B invoice that does not print needs a carrier (`5000028`).
- A zero rated invoice needs `ClearanceMark` (`5000007`). The adapter asks for it only when a zero rated item is present, also with `TaxType` `9` (see 7).

Response `Data`: `RtnCode`, `RtnMsg`, `InvoiceNo`, `InvoiceDate` (`yyyy-MM-dd HH:mm:ss` or `yyyy/MM/dd HH:mm:ss`), `RandomNumber`. Example in 2.5.

### 5.2 `Invalid` (void an invoice)

`InvoiceNo` (10), `InvoiceDate` (`yyyy-MM-dd` or `yyyy/MM/dd`) and `Reason` (max 20) are M. The response has `InvoiceNo` `[doc 7906]`.

An invoice with an allowance cannot be voided until every allowance on it is voided.

Example `[live]` (`void.yml`):

```json
{ "MerchantID": "2000132", "InvoiceNo": "LA25008598", "InvoiceDate": "2026-08-15", "Reason": "整合測試作廢" }
{ "RtnCode": 1, "RtnMsg": "作廢發票成功", "InvoiceNo": "LA25008598" }
```

### 5.3 `Allowance` (paper allowance)

`[doc 7901]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `InvoiceNo` | M | 10 |
| `InvoiceDate` | M | `yyyy-MM-dd` or `yyyy/MM/dd` |
| `AllowanceNotify` | M | `S` SMS, `E` email, `A` both, `N` none |
| `CustomerName` | O | max 60 |
| `NotifyMail` | O | max 100. Several addresses split by `;`. M for `E` |
| `NotifyPhone` | O | max 20, digits. M for `S` |
| `AllowanceAmount` | M | Integer, tax included, more than 0. At most the invoice total, or what is left after earlier allowances |
| `Reason` | O | max 50 |
| `Items` | M | `ItemSeq`, `ItemName`, `ItemCount`, `ItemWord`, `ItemPrice` and `ItemAmount` are M. `ItemTaxType` is M for mixed tax |

- `ItemAmount` includes tax. It may differ from `ItemPrice × ItemCount` by at most 1.
- The sum of `ItemAmount` must equal `AllowanceAmount`.
- ECPay suggests whole numbers, because the MOF wants whole numbers in the allowance.

Response: `IA_Allow_No` (16), `IA_Invoice_No`, `IA_Date` (`yyyy-MM-dd HH:mm:ss`), `IA_Remain_Allowance_Amt`.

Example `[live]` (`allowance.yml`):

```json
{ "MerchantID": "2000132", "InvoiceNo": "LA25008600", "InvoiceDate": "2026-08-15",
  "AllowanceNotify": "N", "AllowanceAmount": 50,
  "Items": [{ "ItemSeq": 1, "ItemName": "整合測試商品", "ItemCount": 1, "ItemWord": "式",
              "ItemPrice": 50, "ItemTaxType": "1", "ItemAmount": 50 }] }
{ "RtnCode": 1, "RtnMsg": "折讓單資料新增成功", "IA_Allow_No": "2026081523293352",
  "IA_Invoice_No": "LA25008600", "IA_Date": "2026-08-15 23:29:03", "IA_Remain_Allowance_Amt": 50 }
```

`AllowanceByCollegiate` takes the same fields, with `AllowanceNotify` fixed to `E`, and a `ReturnURL` for the callback. The allowance exists only after the buyer clicks the link `[doc 15391]`.

### 5.4 `AllowanceInvalid` (void an allowance)

`InvoiceNo` (10), `AllowanceNo` (16) and `Reason` (max 20) are M. The response has `IA_Invoice_No` `[doc 7911]`.

Example `[live]` (`allowance.yml`). The success message reads like an error, so match messages only when `RtnCode` is not `1`:

```json
{ "MerchantID": "2000132", "InvoiceNo": "LA25008600", "AllowanceNo": "2026081523293352", "Reason": "作廢折讓" }
{ "RtnCode": 1, "RtnMsg": "該折讓單已作廢", "IA_Invoice_No": "LA25008600" }
```

### 5.5 `GetIssue` (query)

Request: `RelateNumber`, or `InvoiceNo` with `InvoiceDate` `[doc 7923]`.

Response fields that the unified model uses:

| Field | Meaning |
| --- | --- |
| `IIS_Number` | Invoice number |
| `IIS_Relate_Number` | Order id |
| `IIS_Identifier` | Buyer 統一編號. `0000000000` when there is none |
| `IIS_Customer_Name`, `IIS_Customer_Addr`, `IIS_Customer_Phone`, `IIS_Customer_Email` | Buyer |
| `IIS_Category` | `B2B` with a 統一編號, `B2C` without |
| `IIS_Type` | `07` / `08` |
| `IIS_Tax_Type` | `1`, `2`, `3`, `4`, `9` |
| `IIS_Tax_Rate` | Rate, 2 decimals |
| `IIS_Tax_Amount` | Tax. **Only for a B2B invoice.** For B2C it is `0`, because the tax is inside the amount |
| `IIS_Sales_Amount` | Invoice amount, tax included |
| `IIS_Create_Date` | Issue time, `yyyy-MM-dd HH:mm:ss` |
| `IIS_Random_Number` | Random code |
| `IIS_Issue_Status`, `IIS_Invalid_Status`, `IIS_Remain_Allowance_Amt` | Status (4.4) |
| `IIS_Upload_Status`, `IIS_Turnkey_Status` | Upload to the MOF (4.4) |
| `IIS_Carrier_Type`, `IIS_Carrier_Num` | Carrier. For cards (`4`, `5`), the visible code only |
| `IIS_Love_Code` | Donation code |
| `IIS_Print_Flag` | `1` / `0` |
| `IIS_Award_Flag`, `IIS_Award_Type` | Lottery result |
| `Items` | `ItemSeq`, `ItemName`, `ItemCount`, `ItemWord`, `ItemPrice` (tax included), `ItemTaxType`, `ItemAmount` (tax included), `ItemRemark` |

`IIS_Check_Number` is no longer used `[doc 7923]`. Stage still returns `"P"` in it `[live]`.

Example `[live]` (`void.yml`, after the void; some fields left out):

```json
{ "MerchantID": "2000132", "RelateNumber": "RBVCR20260815void" }
{ "IIS_Number": "LA25008598", "IIS_Relate_Number": "RBVCR20260815void", "IIS_Identifier": "0000000000",
  "IIS_Customer_Email": "test@example.com", "IIS_Type": "07", "IIS_Category": "B2C",
  "IIS_Tax_Type": "1", "IIS_Tax_Rate": 0.05, "IIS_Tax_Amount": 0, "IIS_Sales_Amount": 100,
  "IIS_Carrier_Type": "1", "IIS_Create_Date": "2026-08-15 23:28:59",
  "IIS_Issue_Status": "1", "IIS_Invalid_Status": "1", "IIS_Upload_Status": "1", "IIS_Turnkey_Status": "C",
  "IIS_Remain_Allowance_Amt": 0, "IIS_Print_Flag": "0", "IIS_Random_Number": "1457",
  "RtnCode": 1, "RtnMsg": "查詢成功" }
```

`RtnCode` and `RtnMsg` come at the end of the query response, after `Items` `[live]`.

## 6. Codes

### 6.1 Tax type

| Unified | ECPay `TaxType` | MIG |
| --- | --- | --- |
| `TAXABLE` | `1` | `1` |
| `ZERO_RATED` | `2` | `2` |
| `TAX_FREE` | `3` | `3` |
| `SPECIAL` | `4` | `4` |
| (mixed, derived) | `9` | `9` |

The codes are the MIG codes.

### 6.2 Carrier type

| Unified | ECPay | Meaning | MIG `CarrierType` |
| --- | --- | --- | --- |
| `MEMBER` | `1` | ECPay member carrier | ECPay's own code |
| `CITIZEN_CERTIFICATE` | `2` | Citizen certificate | `CQ0001` |
| `MOBILE_BARCODE` | `3` | Mobile barcode | `3J0002` |
| (none) | `4` | EasyCard (悠遊卡), since 2025-04-17 | card carrier code |
| (none) | `5` | iPASS (一卡通), since 2025-04-17 | card carrier code |

### 6.3 Special tax type (`SpecialTaxType`)

`1` 25%, `2` 15%, `3` 2%, `4` 1%, `5` 5%, `6` and `7` 5%, `8` tax free or not output tax. Page 7896 lists the trade for each `[doc 7896]`. The adapter passes it through `provider_options[:special_tax_type]`.

### 6.4 Result codes

The adapter first looks up the code in a table, then matches the message. The same condition can come back under different codes on different endpoints, so the message match matters. Run it only when the code is not a success.

`TransCode` (transport):

| Code | Meaning | Unified error | `Reason` | Source |
| --- | --- | --- | --- | --- |
| `1` | Envelope accepted | | | `[doc]` |
| `104` | Timestamp more than 10 minutes off. HTTP 500 | `AuthError` | `STALE_TIMESTAMP` | `[fixture]` |
| `110` | `Data` cannot be decrypted (wrong key or IV). HTTP 500 | `AuthError` | `CREDENTIALS_INVALID` | `[live]` |
| `111` | `Data` is empty. HTTP 500 | `ProviderError` | | `[fixture]` |
| `115` | B2C or B2B not enabled for the merchant (B2C/B2B功能尚未開通). HTTP 500 | `AuthError` | `NOT_ENROLLED` | `[fixture]` |
| other | | `ProviderError` | | |

`RtnCode` (business):

| Code | Meaning | Unified error | `Reason` | Source |
| --- | --- | --- | --- | --- |
| `1` | Success | | | `[doc]` |
| `4000003` | Held invoice triggered, will issue after `DelayDay` days. Success for `TriggerIssue` | | | `[doc 15371]` |
| `4000004` | Held invoice triggered and issued. Success for `TriggerIssue` | | | `[doc 15371]` |
| `2` | `GetIssue`: invoice not found (查無發票資料) | `NotFoundError` (by message) | | `[live]` |
| `1600003` | Invoice not found (無發票號碼資料) | `NotFoundError` | | `[code]` |
| `2000039` | Allowance not found (查無折讓單資料) | `NotFoundError` | | `[live]` |
| `2000042` | Voided invoice cannot get an allowance | `ConflictError` | `ALLOWANCE_BLOCKED_BY_VOID` | `[live]` |
| `2000063` | Allowance already voided | `ConflictError` | `ALREADY_VOIDED` | `[fixture]` |
| `4000001` | Transaction number not found (不存在此交易單號) | `NotFoundError` | | `[fixture]` |
| `1100040` | Track used up (發票字軌已用完) | `NumberExhaustedError` | | `[fixture]` |
| `5070250` | An online allowance already agreed cannot be cancelled | `ConflictError` | | `[fixture]` |
| `5000007` | Clearance mark missing for zero rate | `ValidationError` | | `[code]` |
| `5000015` | B2C carrier invoice must not print | `ValidationError` | | `[code]` |
| `5000022` | `SalesAmount` does not match the items | `ValidationError` | | `[live]` |
| `5000028` | Non-printed B2B invoice needs a carrier | `ValidationError` | | `[code]` |
| `5070350`, `1500047` | No usable track or number. Check the track is added and enabled, and not used up | `NumberExhaustedError` (by message) | | `[doc 7954]` |
| `5070357` | Duplicate `RelateNumber` | `ConflictError` | `DUPLICATE_ORDER` | `[live]` |
| `5070450` | Invoice has an allowance, cannot void | `ConflictError` | `VOID_BLOCKED_BY_ALLOWANCE` | `[live]` |
| `5070453` | Invoice already voided | `ConflictError` | `ALREADY_VOIDED` | `[live]` |
| `9000001` | The MOF API failed (maintenance). Try later | `NetworkError` | | `[doc 7886]` |
| `1200125` | 統一編號 check digit wrong. Stop issuing | | | `[doc 32089]` |
| `2027000` | 統一編號 not 8 digits. Stop issuing | | | `[doc 32089]` |
| `7` | 統一編號 not in public data. Issuing may continue | | | `[doc 32089]` |

For `GetCompanyNameByTaxID`, `RtnCode` `1` means a company name was found. If ECPay finds no name, the number may still be right. Some welfare committees, government bodies and hospitals are not in public data `[doc 32089]`.

Message matching, for codes not in the table `[code]`:

| Message contains | Unified error | `Reason` |
| --- | --- | --- |
| 財政部 … 失敗 or 維護, 呼叫 … API失敗 | `NetworkError` | |
| 金鑰, 簽章, 未授權 | `AuthError` | `CREDENTIALS_INVALID` |
| 特店 … 不存在, 平台商 … 不存在 | `AuthError` | `NOT_ENROLLED` |
| 字軌 … 用罄 / 用完 / 不足 / 已滿 | `NumberExhaustedError` | |
| 作廢 … 不能 | `ConflictError` | `ALLOWANCE_BLOCKED_BY_VOID` |
| 已作廢, 已被作廢 | `ConflictError` | `ALREADY_VOIDED` |
| 已折讓, 折讓過 | `ConflictError` | `VOID_BLOCKED_BY_ALLOWANCE` |
| 重複, 重覆 | `ConflictError` | `DUPLICATE_ORDER` |
| 已開立, 已存在, 同意 | `ConflictError` | |
| 查無, 查不到, 無 … 資料, 不存在 | `NotFoundError` | |
| 系統錯誤 / 異常 / 忙碌, 請稍後 | `ProviderError` | `RATE_LIMITED` |
| anything else | `ValidationError` | |

**Default class.** An unknown business code is a `ValidationError`. On stage, the codes outside the table were nearly all field errors `[live]`, and the shared fixtures pin the same default `[fixture]`.

ECPay writes both 重複 and 重覆, and both 已作廢 and 已被作廢. Match both forms.

## 7. Open questions

1. **`RqHeader.Revision`.** The adapter sends `Revision: "3.0.0"`, and its comment says the docs mark it as required. The current docs do not list `Revision` at all `[doc 7896]`. Stage accepts a request without it `[code]`. The comment should change, and maybe the field should go.
2. **Clearance mark with mixed tax.** The docs require `ClearanceMark` for any `TaxType` `9`. The adapter requires it only when a zero rated item is in the mix, which it says it checked live (`5000007`). Which is right for taxable plus tax free?
3. **Card carriers.** EasyCard and iPASS (`4`, `5`) have no unified `CarrierType`.
4. **The B2B API.** ECPay also has a B2B invoice API. Is it the MIG exchange flow? Do we need it?
5. **The body of a 403.** What does ECPay send? The adapter does not need it, but a sample would make the fake more real.
