# ECPay 綠界: B2C 電子發票 API

## 1. Status and sources

This is ECPay's B2C invoice API, the AES JSON API under `/B2CInvoice/`. The 2.x line has an adapter for it: `Einvoice::ECPay::Provider`.

The B2C API also issues invoices to a business buyer: send a 統一編號 in `CustomerIdentifier`. ECPay's home page says a seller does not need the separate B2B API for that `[doc 7809]`. The B2B API is not covered here.

| Tag | Source | Date | What it gives |
| --- | --- | --- | --- |
| `[doc]` | ECPay B2C電子發票API技術文件, <https://developers.ecpay.com.tw/7809/>. One page per endpoint. We read all 44 pages on 2026-10-14. | Home page changed 2026-03-12, issue page 2026-05-20 | Everything below that has no other tag. |
| `[live]` | Our live specs (`spec/einvoice/ecpay/live_spec.rb`) and the VCR cassettes they recorded (`spec/fixtures/vcr_cassettes/ecpay/`) | 2026-08-15, stage | Real responses and error codes. |
| `[code]` | The 2.x adapter (`lib/einvoice/ecpay/`) | 2026-08 | What the adapter does today. Its comments name some codes as checked live, but no cassette records them. |

`[doc 7896]` means the page `https://developers.ecpay.com.tw/7896/`. Page numbers are listed in section 3.

ECPay keeps its full error code list in the merchant back office, not in the public docs `[doc 7954]`. So the error codes in 6.4 come from single pages and from `[live]`.

## 2. Connection

### 2.1 Hosts and credentials

| Environment | Host |
| --- | --- |
| Test (stage) | `https://einvoice-stage.ecpay.com.tw` |
| Production | `https://einvoice.ecpay.com.tw` |

A merchant has a `MerchantID` (特店編號), a `HashKey` and a `HashIV` `[doc 7849]`. In production they are in the back office under 系統設定 → 系統介接設定 → 介接資訊.

ECPay publishes shared test credentials `[doc 7849]`:

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
- `Data` is the business payload: JSON, then URL encode, then AES. It must also carry `MerchantID`.
- The docs list no `Revision` in `RqHeader`. See 7.

### 2.3 Encryption

`[doc 7958]`:

- AES-128-CBC with PKCS7 padding, using the merchant's `HashKey` and `HashIV`.
- Encrypt: JSON → URL encode → AES → Base64.
- Decrypt: Base64 → AES → URL decode → JSON.
- The URL encoding may use upper or lower case hex. The cipher text differs, and both decode to the same JSON. The page gives a test vector for each.

Only the server callback of the online allowance uses `CheckMacValue` `[doc 38242, 15391]`. It is an MD5 hash of the sorted, URL encoded parameters, with `HashKey` and `HashIV` around them.

### 2.4 Response

```json
{ "MerchantID": "2000132", "RpHeader": { "Timestamp": 1525169058 }, "TransCode": 1, "TransMsg": "", "Data": "<encrypted>" }
```

There are two result layers:

1. `TransCode` is the transport result. `1` means ECPay read the envelope.
2. After decrypting `Data`: `RtnCode` is the business result. `1` means success, with a few exceptions (6.4).

HTTP status codes also matter `[doc 7854]`:

- **403**: too many calls. Wait 30 minutes before you call again.
- **500**: bad data format, a `MerchantID` that does not match the key and IV, or an encryption error. A wrong key gives `TransCode` 110 with HTTP 500 `[live]`.

### 2.5 Callbacks

Two endpoints call back to the merchant: delayed issue (`NotifyURL`) and online allowance (`ReturnURL`). The merchant answers `1|OK` `[doc 15369, 15391]`. Stage sends no `NotifyURL` callback. Delayed issue callbacks come from `postgate.ecpay.com.tw` (stage: `postgate-stage.ecpay.com.tw`).

## 3. Operations

| Group | Endpoint | Purpose | Page |
| --- | --- | --- | --- |
| Issue | `/B2CInvoice/Issue` | Issue an invoice now (一般開立) | 7896 |
| | `/B2CInvoice/DelayIssue` | Hold an invoice: issue after N days, or when triggered | 15369 |
| | `/B2CInvoice/EditDelayIssue` | Change a held invoice | 47979 |
| | `/B2CInvoice/TriggerIssue` | Trigger a held invoice | 15371 |
| | `/B2CInvoice/CancelDelayIssue` | Cancel a held invoice | 15382 |
| Allowance | `/B2CInvoice/Allowance` | Issue a paper allowance (紙本開立) | 7901 |
| | `/B2CInvoice/AllowanceByCollegiate` | Online allowance: the buyer confirms by email (線上開立) | 15391 |
| Void | `/B2CInvoice/Invalid` | Void an invoice | 7906 |
| | `/B2CInvoice/AllowanceInvalid` | Void an allowance | 7911 |
| | `/B2CInvoice/AllowanceInvalidByCollegiate` | Cancel an online allowance before the buyer confirms | 7913 |
| | `/B2CInvoice/VoidWithReIssue` | Cancel and reissue with the same number (註銷重開) | 7918 |
| Query | `/B2CInvoice/GetIssue` | One invoice, by order id or by number and date | 7923 |
| | `/B2CInvoice/GetIssueList` | Invoices in a date range, paged | 17229 |
| | `/B2CInvoice/GetAllowanceList` | Allowances, by number or by invoice | 7928 |
| | `/B2CInvoice/GetInvalid` | One voided invoice | 7933 |
| | `/B2CInvoice/GetAllowanceInvalid` | One voided allowance | 7943 |
| Checks | `/B2CInvoice/CheckBarcode` | Is a mobile barcode registered | 7886 |
| | `/B2CInvoice/CheckLoveCode` | Is a donation code registered, and its name | 7891 |
| | `/B2CInvoice/GetCompanyNameByTaxID` | Check a 統一編號 and get the company name | 32089 |
| Notice | `/B2CInvoice/InvoiceNotify` | Send an invoice notice by email or SMS | 7938 |
| Print | `/B2CInvoice/InvoicePrint` | Get a printable invoice page | 7949 |
| Numbers | `/B2CInvoice/GetGovInvoiceWordSetting` | MOF number ranges for a year | 7859 |
| | `/B2CInvoice/AddInvoiceWordSetting` | Add a track and range | 7870 |
| | `/B2CInvoice/UpdateInvoiceWordStatus` | Enable, pause or stop a track | 7875 |
| | `/B2CInvoice/GetInvoiceWordSetting` | List the merchant's tracks | 7881 |
| Settings | `/B2CInvoice/GetInvoiceNotifySetting`, `InvoiceNotifySetting` | Notice settings | 63356, 64067 |
| | `/B2CInvoice/GetRemainNotifySetting`, `RemainNotifySetting` | Low number warning | 64079, 64088 |
| | `/B2CInvoice/QueryBlankInvoiceList`, `BlankInvAutoUploadSetting`, `DownLoadBlankInvList` | Unused numbers (E0402) | 64106, 64122, 64133 |

The settings endpoints were added on 2026-06-23 `[doc 36050]`.

Page 49890 is an older copy of the issue page ("一般開立發票 - MIG 4.0", changed 2025-01-22). It lacks the newer fields. Use 7896.

## 4. Mapping to the unified API

| Unified | ECPay | Note |
| --- | --- | --- |
| `issue` | `Issue` | |
| `void` | `Invalid` | Needs the invoice date |
| `allowance` | `Allowance` | Needs the invoice date. Amounts include tax |
| `void_allowance` | `AllowanceInvalid` | No allowance date needed |
| `query` by order id | `GetIssue` with `RelateNumber` | |
| `query` by number | `GetIssue` with `InvoiceNo` and `InvoiceDate` | Needs the invoice date |

### Against the MIG

- **B2B goes through storage (F0401), not exchange (inferred).** The B2C API accepts a 統一編號 with a carrier, and allows mixed tax. MIG A0101 allows neither. So ECPay must upload these invoices as F0401. This answers the MIG note's open question 4 for ECPay.
- **Allowance amounts include tax.** `AllowanceAmount` and `ItemAmount` include tax `[doc 7901]`. MIG G0401 wants amounts without tax and a tax per item. ECPay does the split. Its query returns both: `IA_Total_Amount` (tax excluded) and `IA_Total_Tax_Amount` (tax included), plus `ItemRateAmt` per item `[doc 7928]`.
- **Voiding an allowance needs no allowance date.** MIG G0501 requires it, so ECPay must fill it from its own records `[doc 7911]`.
- **Voiding and querying by number need the invoice date.** As MIG F0501 does `[doc 7906, 7923]`. This is why the adapter asks for `provider_options: { invoice_date: }`.
- **Up to 999 items** `[doc 7896]`. The MIG allows 9999.
- **Reasons are 1 to 20 chars** for voids and allowance voids `[doc 7906, 7911]`, as in the MIG. The allowance reason (`Reason` in `Allowance`) is up to 50 chars.

### Status

`GetIssue` reports status in three fields `[doc 7923]`:

| Field | Values |
| --- | --- |
| `IIS_Issue_Status` | `1` issued, `0` cancelled (註銷) |
| `IIS_Invalid_Status` | `1` voided, `0` not voided |
| `IIS_Remain_Allowance_Amt` | Amount still open for allowance |

`IIS_Upload_Status` (`1` uploaded) and `IIS_Turnkey_Status` (`C` the MOF accepted it, `E` the upload failed) show the upload to the MOF.

### Timing

- Voids, allowances and allowance voids are uploaded to the MOF the next day `[doc 7906, 7901, 7911]`. Issued invoices are uploaded within 48 hours `[doc 7809]`.
- After 23:59:59 on the 13th of an odd month, invoices and allowances of the two months before cannot be voided. On 14 March, January and February invoices are closed `[doc 7906, 7911]`.
- A cancel-and-reissue (註銷重開) must finish before the 13th of the month after the period `[doc 7918]`.
- A paper allowance (`Allowance`) still needs the buyer's signature on paper. The seller mails it and keeps it. The online allowance (`AllowanceByCollegiate`) replaces the signature with an email link, valid 72 hours `[doc 7901, 15391]`.

## 5. Field reference

### 5.1 `Issue`

`Data` fields `[doc 7896]`. "Req" means required.

| Field | Rule |
| --- | --- |
| `MerchantID` | Req, max 10 |
| `RelateNumber` | Req, max 50. Unique. No special symbols. Case does not matter (`abc` = `ABC`) |
| `ChannelPartner` | `1` Shopee. Other values are ignored |
| `CustomerID` | max 20. Letters, digits, `_` |
| `ProductServiceID` | 1 to 10 letters or digits. Only used when the merchant has 「B2C系統多組字軌」 on |
| `CustomerIdentifier` | 8 digits. The buyer's 統一編號 |
| `CustomerName` | max 60. Req when `Print` is `1`. Use the company name when there is a 統一編號 |
| `CustomerAddr` | max 100. Req when `Print` is `1` |
| `CustomerPhone` | max 20, digits. Req when `CustomerEmail` is empty |
| `CustomerEmail` | max 80, one address. Req when `CustomerPhone` is empty |
| `ClearanceMark` | `1` / `2`. Req when `TaxType` is `2` or `9` |
| `Print` | Req. `0` / `1`. This only marks that the merchant prints the invoice. ECPay does not print or mail it |
| `Donation` | Req. `0` / `1` |
| `LoveCode` | 3 to 7 digits, may start with `0`. Req when `Donation` is `1` |
| `CarrierType` | Empty, `1` ECPay carrier, `2` citizen certificate, `3` mobile barcode, `4` EasyCard, `5` iPASS |
| `CarrierNum` | max 64. See below |
| `CarrierNum2` | max 64. Req for `4` and `5`: the card's visible code. Leave empty for `1` to `3` |
| `TaxType` | Req. `1` taxable, `2` zero rated, `3` tax free, `4` special rate, `9` mixed (needs approval). With `InvType` `07`: `1`, `2`, `3` or `9`. With `08`: `3` or `4` |
| `ZeroTaxRateReason` | `71` to `79`. From 2026-01-01, req when `TaxType` is `2` or `9`, unless set in the back office |
| `SpecialTaxType` | `0` for `TaxType` `1`, `2`, `9`. `8` for `3`. `1` to `8` for `4` |
| `SalesAmount` | Req. Integer, tax included, TWD only, up to 12 digits |
| `TaxAmount` | Integer, up to 11 digits. Optional: ECPay computes it if missing. If given, it may differ from ECPay's result by at most 1. `0` for special tax |
| `InvoiceRemark` | max 200. `\r\n`, `\r` or `\n` breaks the line |
| `Items` | 1 to 999 items |
| `InvType` | Req. `07` general, `08` special |
| `vat` | `1` prices include tax (default), `0` prices exclude tax |

`CarrierNum` by `CarrierType`:

| Type | `CarrierNum` |
| --- | --- |
| empty | empty |
| `1` | empty. ECPay builds the carrier from the email or phone, email first |
| `2` | 16 chars: 2 capital letters and 14 digits |
| `3` | 8 chars: `/` and 7 of `0-9`, `A-Z`, `+`, `-`, `.` |
| `4`, `5` | Req. The card's hidden code. Not checked |

Item fields:

| Field | Rule |
| --- | --- |
| `ItemSeq` | 1 to 999 |
| `ItemName` | Req, max 500 |
| `ItemCount` | Req. 8 digits, up to 7 after the point |
| `ItemWord` | Req, max 6. The unit |
| `ItemPrice` | Req. 10 digits, up to 7 after the point. Tax included or not, as `vat` says |
| `ItemTaxType` | `1`, `2`, `3`. Req when `TaxType` is `9`, ignored otherwise |
| `ItemAmount` | Req. Tax included. 12 digits, up to 7 after the point |
| `ItemRemark` | max 120 |

Rules across fields `[doc 7896]`:

- The sum of `ItemAmount`, rounded, must equal `SalesAmount`. With `vat` `0` and `TaxType` `1`, `ItemPrice × ItemCount × 1.05 = ItemAmount`.
- Mixed tax (`9`) allows taxable with tax free, or taxable with zero rated. Not tax free with zero rated.
- ECPay computes tax as `round(SalesAmount / 1.05 × 0.05)`. For mixed tax it uses the sum of the taxable items.
- Donated (`Donation` `1`): `Print` must be `0`, and `CustomerIdentifier` must be empty. A carrier is allowed: it means the buyer donated the invoice later.
- With a 統一編號: `Donation` must be `0`. No carrier means `Print` `1`. Carrier `1` or `2` means `Print` `0`. Carrier `3` allows either.
- With a 統一編號 and `Print` `1`, the only carrier allowed is `3`.

Response `Data`: `RtnCode`, `RtnMsg`, `InvoiceNo`, `InvoiceDate` (`yyyy-MM-dd HH:mm:ss` or `yyyy/MM/dd HH:mm:ss`), `RandomNumber`.

### 5.2 `Invalid` (void an invoice)

`InvoiceNo` (10), `InvoiceDate` (`yyyy-MM-dd` or `yyyy/MM/dd`) and `Reason` (max 20) are required. The response has `InvoiceNo` `[doc 7906]`.

An invoice with an allowance cannot be voided until every allowance on it is voided.

### 5.3 `Allowance` (paper allowance)

`[doc 7901]`:

| Field | Rule |
| --- | --- |
| `InvoiceNo` | Req, 10 |
| `InvoiceDate` | Req, `yyyy-MM-dd` or `yyyy/MM/dd` |
| `AllowanceNotify` | Req. `S` SMS, `E` email, `A` both, `N` none |
| `CustomerName` | max 60 |
| `NotifyMail` | max 100. Several addresses split by `;`. Req for `E` |
| `NotifyPhone` | max 20, digits. Req for `S` |
| `AllowanceAmount` | Req. Integer, tax included, more than 0. At most the invoice total, or what is left after earlier allowances |
| `Reason` | max 50 |
| `Items` | `ItemSeq`, `ItemName`, `ItemCount`, `ItemWord`, `ItemPrice` and `ItemAmount` are req. `ItemTaxType` is req for mixed tax |

- `ItemAmount` includes tax. It may differ from `ItemPrice × ItemCount` by at most 1.
- The sum of `ItemAmount` must equal `AllowanceAmount`.
- ECPay suggests whole numbers, because the MOF wants whole numbers in the allowance.

Response: `IA_Allow_No` (16), `IA_Invoice_No`, `IA_Date` (`yyyy-MM-dd HH:mm:ss`), `IA_Remain_Allowance_Amt`.

`AllowanceByCollegiate` takes the same fields, with `AllowanceNotify` fixed to `E`, and a `ReturnURL` for the callback. The allowance exists only after the buyer clicks the link `[doc 15391]`.

### 5.4 `AllowanceInvalid` (void an allowance)

`InvoiceNo` (10), `AllowanceNo` (16) and `Reason` (max 20) are required. The response has `IA_Invoice_No` `[doc 7911]`.

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
| `IIS_Sales_Amount` | Invoice amount |
| `IIS_Create_Date` | Issue time, `yyyy-MM-dd HH:mm:ss` |
| `IIS_Random_Number` | Random code |
| `IIS_Carrier_Type`, `IIS_Carrier_Num` | Carrier. For cards (`4`, `5`), the visible code only |
| `IIS_Love_Code` | Donation code |
| `IIS_Print_Flag` | `1` / `0` |
| `IIS_Award_Flag`, `IIS_Award_Type` | Lottery result |
| `Items` | `ItemSeq`, `ItemName`, `ItemCount`, `ItemWord`, `ItemPrice` (tax included), `ItemTaxType`, `ItemAmount` (tax included), `ItemRemark` |

Status fields are in section 4. `IIS_Check_Number` is no longer used.

## 6. Codes

### 6.1 Tax type

| Unified | ECPay `TaxType` | MIG |
| --- | --- | --- |
| `TAXABLE` | `1` | `1` |
| `ZERO_RATED` | `2` | `2` |
| `TAX_FREE` | `3` | `3` |
| `SPECIAL` | `4` | `4` |
| mixed | `9` | `9` |

The codes are the MIG codes.

### 6.2 Carrier type

| ECPay | Meaning | MIG `CarrierType` |
| --- | --- | --- |
| `1` | ECPay member carrier | ECPay's own code |
| `2` | Citizen certificate | `CQ0001` |
| `3` | Mobile barcode | `3J0002` |
| `4` | EasyCard (悠遊卡), since 2025-04-17 | card carrier code |
| `5` | iPASS (一卡通), since 2025-04-17 | card carrier code |

The unified `CarrierType` has no value for `4` or `5`.

### 6.3 Special tax type (`SpecialTaxType`)

`1` 25% (bars with hostesses), `2` 15% (night clubs), `3` 2% (core income of banks and insurers), `4` 1% (reinsurance), `5` 5% (other income of banks and insurers), `6` and `7` 5% (bank and insurance core income, after and before 2014-07), `8` tax free or not output tax `[doc 7896]`.

### 6.4 Result codes

`TransCode` (transport):

| Code | Meaning | Source |
| --- | --- | --- |
| `1` | Envelope accepted | `[doc]` |
| `104` | Timestamp more than 10 minutes off | `[code]` |
| `110` | `Data` cannot be decrypted (wrong key or IV). HTTP 500 | `[live]` |

`RtnCode` (business):

| Code | Meaning | Source |
| --- | --- | --- |
| `1` | Success | `[doc]` |
| `4000003` | Held invoice triggered, will issue after `DelayDay` days | `[doc 15371]` |
| `4000004` | Held invoice triggered and issued | `[doc 15371]` |
| `1600003` | Invoice not found (無發票號碼資料) | `[live]` |
| `2000039` | Allowance not found (查無折讓單資料) | `[live]` |
| `2000042` | Voided invoice cannot get an allowance | `[live]` |
| `2000063` | Allowance already voided | `[code]` |
| `5000007` | Clearance mark missing for zero rate | `[code]` |
| `5000015` | B2C carrier invoice must not print | `[code]` |
| `5000022` | `SalesAmount` does not match the items | `[live]` |
| `5000028` | Non-printed B2B invoice needs a carrier | `[code]` |
| `5070350`, `1500047` | No usable track or number. Check the track is added and enabled, and not used up | `[doc 7954]` |
| `5070357` | Duplicate `RelateNumber` | `[live]` |
| `5070450` | Invoice has an allowance, cannot void | `[code]` |
| `5070453` | Invoice already voided | `[live]` |
| `9000001` | The MOF API failed (maintenance). Try later | `[doc 7886]` |
| `1200125` | 統一編號 check digit wrong. Stop issuing | `[doc 32089]` |
| `2027000` | 統一編號 not 8 digits. Stop issuing | `[doc 32089]` |
| `7` | 統一編號 not in public data. Issuing may continue | `[doc 32089]` |

For `GetCompanyNameByTaxID`, `RtnCode` `1` means a company name was found. If ECPay finds no name, the number may still be right. Some welfare committees, government bodies and hospitals are not in public data `[doc 32089]`.

## 7. Open questions

These are places where the docs and the 2.x adapter `[code]` do not agree, or where we have not checked yet.

1. **`RqHeader.Revision`.** The adapter sends `Revision: "3.0.0"`, and its comment says the docs mark it as required. The current docs do not list `Revision` at all `[doc 7896]`. The comment should change, and maybe the field should go.
2. **Cancelled invoices.** `IIS_Issue_Status` `0` means cancelled (註銷). The adapter's status check reads only `IIS_Invalid_Status` and the remaining allowance, so a cancelled invoice reads as issued.
3. **Tax on B2C queries.** `IIS_Tax_Amount` is `0` for B2C. The adapter builds `AmountSummary` as `sales = total - tax`, so a taxable B2C invoice reports a tax of `0`.
4. **`TaxAmount` on issue.** The adapter does not send `TaxAmount`, so ECPay computes it, and the unified `amount.tax_amount` is not used. Should the adapter send it?
5. **Clearance mark with mixed tax.** The docs require `ClearanceMark` for any `TaxType` `9`. The adapter requires it only when a zero rated item is in the mix, which it says it checked live (`5000007`). Which is right for taxable plus tax free?
6. **Zero tax rate reason.** From 2026-01-01 it is required for `TaxType` `2` and `9`. The adapter only passes it through `provider_options` and does not check it.
7. **Card carriers.** EasyCard and iPASS (`4`, `5`) have no unified `CarrierType`.
8. **The B2B API.** ECPay also has a B2B invoice API. Is it the MIG exchange flow? Do we need it?
