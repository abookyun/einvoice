# ezPay 簡單行動支付: 電子發票 API

English | [繁體中文](invoice.zh-TW.md)

## 1. Status and sources

> **Trust:** manuals only. There is no adapter and no live run. Sections 4.2 and 6.4 are proposals.

ezPay (簡單行動支付股份有限公司) runs the ezPay 電子發票加值服務平台. The 2.x line has no adapter for it yet. Nothing here is verified against the live API. So sections 4.2 and 6.4 are **proposals**: what an adapter should do, based on the manuals.

The manuals belong to 簡單行動支付 ezPay, and the PDFs say ezPay holds the copyright. They are published on a public download page: <https://inv.ezpay.com.tw/Invoice_index/download>. This note is our summary.

| Tag | Source | Version and date | What it gives |
| --- | --- | --- | --- |
| `[inv]` | 電子發票技術串接手冊 標準版, <https://inv.ezpay.com.tw/dw_files/info_api/EZP_INVI_1_2_2.pdf>, 72 pages | EZP_INVI_1.2.2, 2024-04-22 | Issue, void, allowance, allowance void, query |
| `[ces]` | 電子發票技術串接手冊 境外電商版, <https://inv.ezpay.com.tw/dw_files/info_api/EZP_CES_1_0_0.pdf>, 65 pages | EZP_CES_1.0.0, 2021-01-26 | Cross-border sellers |
| `[track]` | 電子發票字軌管理 技術串接手冊, <https://inv.ezpay.com.tw/dw_files/info_api/EZP__Track__1_0_0.pdf>, 38 pages | EZP_Track_1.0.0, 2018-10 | Track (字軌) management |
| `[bdv]` | 手機條碼與捐贈碼驗證 技術串接手冊, <https://inv.ezpay.com.tw/dw_files/info_api/BDV_1_0_0.pdf>, 24 pages | EZP_BDV_1.0.0, 2021-03-03 | Mobile barcode and donation code checks |

All four were downloaded on 2026-10-14. The `[inv]` manual has had no change since April 2024, and its last real field changes are from 2021.

**Updates.** The download page lists each manual with its version and date. A new version also gets a new file name, for example `EZP_INVI_1_2_2.pdf`.

## 2. Connection

### 2.1 Hosts and credentials

| Environment | Host |
| --- | --- |
| Test | `https://cinv.ezpay.com.tw` |
| Production | `https://inv.ezpay.com.tw` |

There are no shared test credentials. A developer signs up on the test platform, opens a test shop, gets its `HashKey` and `HashIV`, and adds test track numbers under 管理設定 > 發票字軌號碼設定 `[inv 三]`. The test and production shops are separate.

A shop has a `MerchantID_` (商店代號, max 15), a `HashKey` and a `HashIV`. AES-256 needs a 32-byte key and a 16-byte IV, as in the manual's examples. The check APIs use the same host and shop `[bdv]`. The track API uses the member id `CompanyID_` instead of `MerchantID_` `[track 四]`.

### 2.2 Request

Every API is a standard form POST in UTF-8, with two fields `[inv 三, 四]`:

| Field | Rule |
| --- | --- |
| `MerchantID_` | The shop id. Note the trailing `_` |
| `PostData_` | The encrypted payload. Note the trailing `_` |

The payload is **not JSON**. It is a URL query string of the fields, as PHP `http_build_query` builds it. Then `[inv 附件一]`:

1. Pad the query string with PKCS#7 to a multiple of **32 bytes**.
2. Encrypt with AES-256-CBC, key `HashKey`, IV `HashIV`, no further padding.
3. Hex encode, lower case. That is `PostData_`.

Every payload carries:

| Field | Rule |
| --- | --- |
| `RespondType` | `JSON` or `String`. An adapter should use `JSON` |
| `Version` | Fixed per API: `1.5` for issue, `1.3` for allowance and query, `1.0` for the others |
| `TimeStamp` | Unix time |

In `CarrierNum`, encode the value with `rawurlencode()` first, so no data is lost `[inv 四]`.

### 2.3 Response

With `RespondType` `JSON`:

```json
{ "Status": "SUCCESS", "Message": "...", "Result": "<a JSON string>" }
```

- `Status` is `SUCCESS` or an error code (6.4).
- `Result` is itself a JSON string, so parse it a second time. In the query result, `ItemDetail` is a JSON string inside that, so parse it a third time `[inv 八(二)]`.
- With `String`, the same fields come as a query string that ends with `EndStr` `##` `[inv 四]`.

**Issue is idempotent.** If the same `PostData_` comes again with exactly the same data, ezPay answers `SUCCESS` with the original `Result` `[inv 四(二)]`.

### 2.4 Check codes

Issue and query results carry a `CheckCode`, so the caller can check that ezPay sent them `[inv 附件二]`:

1. Take `InvoiceTransNo`, `MerchantID`, `MerchantOrderNo`, `RandomNum` and `TotalAmt` from the result.
2. Sort them by name and join as a query string.
3. Put `HashIV=...&` before it and `&HashKey=...` after it.
4. SHA-256, upper case hex.

Void and allowance results also carry a `CheckCode`, but they do not have these five fields. The manual gives no other rule, so these cannot be checked (see 7).

The check APIs use `CheckValue` instead: SHA-256 of `HashKey=...&<Result>&HashIV=...`, upper case `[bdv 附件三]`.

### 2.5 Example

The issue response example from the manual `[inv 四(二)]`, with `Result` parsed:

```json
{ "Status": "SUCCESS", "Message": "電子發票開立成功",
  "Result": { "CheckCode": "00E108DF7DE8756AF003312206DA77A4C37AE33990EA04A944C414113D512228",
              "MerchantID": "3502275", "MerchantOrderNo": "201511031758110280",
              "InvoiceNumber": "DS12223139", "TotalAmt": 348,
              "InvoiceTransNo": "15110317583641325", "RandomNum": "4253",
              "CreateTime": "2015-11-03 17:58:36", "BarCode": "10412DS122231394253",
              "QRcodeL": "…", "QRcodeR": "…" } }
```

The request side is a query string before encryption, for example (B2C, one item, a mobile barcode):

```
RespondType=JSON&Version=1.5&TimeStamp=1729000000&MerchantOrderNo=ORDER_1&Status=1
&Category=B2C&BuyerName=消費者&PrintFlag=N&CarrierType=0&CarrierNum=%2FABC1234
&TaxType=1&TaxRate=5&Amt=95&TaxAmt=5&TotalAmt=100
&ItemName=商品一&ItemCount=1&ItemUnit=個&ItemPrice=100&ItemAmt=100
```

This request is ours, built from the field rules. It is not from the manual.

## 3. Operations

The five unified operations use these endpoints. Section 5 has their fields.

| Endpoint | Purpose | Source |
| --- | --- | --- |
| `/Api/invoice_issue` | Issue now, hold for a trigger, or schedule | `[inv 四]` |
| `/Api/invoice_invalid` | Void an invoice | `[inv 五]` |
| `/Api/allowance_issue` | Issue an allowance, confirmed now or later | `[inv 六]` |
| `/Api/allowanceInvalid` | Void a confirmed allowance | `[inv 七]` |
| `/Api/invoice_search` | One invoice, as data, as an ezPay web page, or as a URL | `[inv 八]` |

Other endpoints. An adapter can reach them through a `raw` method:

| Endpoint | Purpose | Source |
| --- | --- | --- |
| `/Api/invoice_touch_issue` | Issue a held or scheduled invoice now | `[inv 四(三)]` |
| `/Api/allowance_touch_issue` | Confirm (`C`) or cancel (`D`) a pending allowance | `[inv 六(三)]` |
| `/Api/crossBorderInvoiceIssue`, `/Api/crossBorderAllowanceIssue`, `/Api/crossBorderInvoiceSearch` | The same for cross-border sellers | `[ces]` |
| `/Api_number_management/createNumber`, `manageNumber`, `searchNumber` | Add, change and list tracks | `[track]` |
| `/Api_inv_application/checkBarCode`, `checkLoveCode` | Is a mobile barcode or donation code registered | `[bdv]` |

## 4. Mapping to the unified API

### 4.1 Operations

| Unified | Endpoint | `provider_options` (proposed) | Note |
| --- | --- | --- | --- |
| `issue` | `invoice_issue`, `Status` `1` | `customs_clearance` | |
| `void` | `invoice_invalid` | none | Not before the upload, the next day |
| `allowance` | `allowance_issue`, `Status` `1` | `order_id` (M), `tax_type_for_mixed`, `buyer_email` | ezPay assigns the allowance number |
| `void_allowance` | `allowanceInvalid` | none | |
| `query` | `invoice_search` | `random_code` (by number), `total_amount` (by order id) | A second key is always needed |

### 4.2 Fields

All rows are proposals.

#### `issue`

| Unified | ezPay | Rule or default |
| --- | --- | --- |
| `order_id` | `MerchantOrderNo` | Max **20**, letters, digits and `_`. Check it locally. Other providers allow longer ids |
| `category` (or the buyer's 統一編號) | `Category` | `B2B` / `B2C` |
| `buyer.name` | `BuyerName` | M. B2C without a name: `消費者`. B2B: the company name, max 60 |
| `buyer.ubn` | `BuyerUBN` | B2B only |
| `buyer.address` | `BuyerAddress` | |
| `buyer.email` | `BuyerEmail` | Max 50. M for the ezPay member carrier |
| `buyer.phone` | (none) | No field on issue. Dropped |
| `carrier.type` | `CarrierType` | `MOBILE_BARCODE` `0`, `CITIZEN_CERTIFICATE` `1`, `MEMBER` `2`. B2C only |
| `carrier.code` | `CarrierNum` | `rawurlencode` first. For `MEMBER` without a code, use the buyer's email |
| `donation.npoban` | `LoveCode` | B2C only. Not with a carrier |
| (derived) | `PrintFlag` | `Y` for B2B, and for B2C with no carrier and no donation. Else `N` |
| `tax_type`, `items[].tax_type` | `TaxType` | `9` when items differ (B2C only, else `ValidationError`). `SPECIAL`: see 6.1 |
| `tax_rate` | `TaxRate` | A percent: `tax_rate × 100`, `5` when missing. `0` for zero rated and tax free |
| `amount` | `Amt`, `TaxAmt`, `TotalAmt` | See 4.3 |
| `items[]` | `ItemName`, `ItemCount`, `ItemUnit`, `ItemPrice`, `ItemAmt`, `ItemTaxType` | Each field is one string, items separated by `\|`. See below |
| `price_mode` | (none) | ezPay fixes it by `Category`: B2B prices exclude tax, B2C prices include tax. A different `price_mode` is a `ValidationError` |
| `remark` | `Comment` | Max 200 |
| `currency` | (none) | Not TWD: `UnsupportedError`. The cross-border API is separate |
| `date`, `exchange_rate` | (none) | Not sent |

Items, each joined with `|`:

| Unified | ezPay | Rule |
| --- | --- | --- |
| `description` | `ItemName` | Max **30**. Longer: `ValidationError` |
| `quantity` | `ItemCount` | **Integer**. A decimal: `ValidationError` |
| `unit` | `ItemUnit` | M. Max 2 Chinese or 6 English characters. `個` when missing |
| `unit_price` | `ItemPrice` | **Integer** |
| `amount` | `ItemAmt` | Integer. Must be `ItemCount × ItemPrice` |
| `tax_type` | `ItemTaxType` | Mixed tax only |
| `remark` | (none) | No field. Dropped |

Result:

| Unified | From |
| --- | --- |
| `invoice_number` | `InvoiceNumber` |
| `invoice_date` | `CreateTime`, UTC+8 |
| `random_code` | `RandomNum` |
| `order_id` | `MerchantOrderNo` |
| `total_amount` | `TotalAmt` |
| `status` | `ISSUED` |

Check `CheckCode` first (2.4).

#### `void`

| Unified | ezPay | Rule or default |
| --- | --- | --- |
| `invoice_number` | `InvoiceNumber` | |
| `reason` | `InvalidReason` | Max **6 Chinese** or 20 English characters. Check it locally |
| `date` | (none) | Not needed |

Result: `invoice_number` from `InvoiceNumber`, `status` `VOIDED`.

#### `allowance`

| Unified | ezPay | Rule or default |
| --- | --- | --- |
| `invoice_number` | `InvoiceNo` | |
| `provider_options[:order_id]` | `MerchantOrderNo` | M. The original invoice's order id. `AllowanceInput` does not have it, and a query cannot find it without the random code |
| `items[]` | `ItemName`, `ItemCount`, `ItemUnit`, `ItemPrice`, `ItemAmt` | As for issue |
| (computed) | `ItemTaxAmt` | See 4.3 |
| `amount.total_amount` | `TotalAmt` | See 4.3 |
| `provider_options[:tax_type_for_mixed]` | `TaxTypeForMixed` | M for a mixed invoice |
| `provider_options[:buyer_email]` | `BuyerEmail` | ezPay sends the notice here |
| (fixed) | `Status` | `1`: confirm now |
| `allowance_id`, `date` | (none) | Not sent. ezPay assigns the number and the date |

Result:

| Unified | From |
| --- | --- |
| `allowance_number` | `AllowanceNo` |
| `invoice_number` | `InvoiceNumber` |
| `allowance_date` | `nil`. The result has no date |
| `total_amount` | `AllowanceAmt` |

#### `void_allowance`

| Unified | ezPay | Rule or default |
| --- | --- | --- |
| `allowance_number` | `AllowanceNo` | Max 25 |
| `reason` | `InvalidReason` | `作廢折讓` when missing. Max 6 Chinese characters |
| `invoice_number` | (none) | Not sent |

Result: `allowance_number` from `AllowanceNo`.

#### `query`

| Unified | ezPay | Rule or default |
| --- | --- | --- |
| `invoice_number` + `provider_options[:random_code]` | `SearchType` `0`, `InvoiceNumber`, `RandomNum` | |
| `order_id` + `provider_options[:total_amount]` | `SearchType` `1`, `MerchantOrderNo`, `TotalAmt` | |
| neither key | | `ValidationError` |

Result:

| Unified | From |
| --- | --- |
| `invoice_number` | `InvoiceNumber` |
| `invoice_date` | `CreateTime`, UTC+8 |
| `random_code` | `RandomNum` |
| `order_id` | `MerchantOrderNo` |
| `status` | See 4.4 |
| `amount` | `sales = Amt`, `tax = TaxAmt`, `total = TotalAmt` |
| `buyer` | `BuyerName`, `BuyerUBN`, `BuyerAddress`, `BuyerPhone`, `BuyerEmail` |
| `items` | `ItemDetail` (a JSON string): `ItemName`, `ItemCount`, `ItemWord` (unit), `ItemPrice`, `ItemAmount`, `ItemTaxType` |

### 4.3 Amounts and tax

The unified `AmountSummary` must satisfy `sales + tax = total`. The shared contract issues a taxable B2C invoice as `sales 100, tax 0, total 100`.

**Issue.** ezPay always splits out the tax, also for B2C `[inv 四]`:

- `Amt` is the sales total **without** tax. For mixed tax, `Amt = AmtSales + AmtZero + AmtFree`.
- `TaxAmt` is the tax. `TotalAmt = Amt + TaxAmt`.
- Item prices exclude tax for B2B, and include tax for B2C. So for B2C, the item total and `TotalAmt` include tax, but `Amt` does not.
- ezPay only checks `ItemAmt = ItemCount × ItemPrice` and `TotalAmt = Amt + TaxAmt`. The rest is up to the caller `[inv 三]`.

Proposal: when the unified amount has `tax 0` for a taxable invoice (the contract's B2C shape), compute `TaxAmt = total - round(total / 1.05)` and `Amt = total - TaxAmt`. Otherwise send `sales_amount`, `tax_amount` and `total_amount` as they are.

The query shows the same split for B2C: `Amt 1333`, `TaxAmt 67`, `TotalAmt 1400` `[inv 八(二)]`.

**Allowance.**

- Item prices may include tax or not `[inv 六]`. If they include tax, `ItemTaxAmt` must be `0`, and the buyer cannot deduct that tax.
- If they exclude tax, `ItemTaxAmt = ItemAmt × rate`.
- `TotalAmt` is the sum of the items plus the item tax.

Proposal: for B2C, send prices with tax and `ItemTaxAmt` `0`. The buyer of a B2C invoice does not deduct tax. For B2B, send prices without tax and the item tax.

**Integers.** Item counts and prices are integers. The unified model allows decimals, so check before the call.

### 4.4 Status

`invoice_search` returns `[inv 八(二)]`:

| ezPay | Unified `InvoiceStatus` |
| --- | --- |
| `InvoiceStatus` `1` | `ISSUED` |
| `InvoiceStatus` `2` | `VOIDED` |

The query has no allowance data and no cancelled status. So an adapter cannot report `ALLOWANCE` from a query.

`UploadStatus` shows the upload to the MOF: `0` not uploaded, `1` uploaded, `2` uploading, `3` failed, `4` timed out.

### 4.5 Timing

- ezPay uploads the day's issues, voids and allowances to the MOF from 01:00 the next day. From 06:00 it updates the upload status from the MOF reply `[inv 三]`.
- An invoice can only be voided **after** it is uploaded (`LIB10009`) `[inv 九]`. So an invoice issued today cannot be voided today.
- An invoice whose upload failed cannot be voided (`INV70002`).
- Before the 14th of an odd month, invoices of the two months before can still be voided. On 13 July, May and June invoices can be voided `[inv 一]`.
- An invoice with an allowance cannot be voided (`LIB10007`).
- A pending allowance (`Status` `0`) stays in ezPay and is not uploaded until it is confirmed. It is uploaded the day after the confirm `[inv 一]`.

### 4.6 Capabilities

| Capability | API | Note |
| --- | --- | --- |
| `ISSUE`, `VOID`, `ALLOWANCE`, `VOID_ALLOWANCE` | yes | Voids only from the next day |
| `QUERY` | partly | Needs the random code with the number |
| `B2B` | yes | `Category` `B2B` |
| `MIXED_TAX` | partly | B2C only |
| `QUERY_BY_ORDER_ID` | partly | Needs the total with the order id |
| `SCHEDULED_ISSUE` | yes | `Status` `3` with `CreateStatusTime` |
| `CARRIER_VALIDATION` | yes | `checkBarCode`, `checkLoveCode` |
| `FOREIGN_CURRENCY` | no | Only in the separate cross-border API |

A capability is yes or no. For "partly", the adapter must decide: declare it and document the extra key, or leave it out.

### 4.7 Against the MIG

- **Voids need no date.** `invoice_invalid` and `allowanceInvalid` take only the number and a reason. ezPay fills the dates from its records (inferred), because MIG F0501 and G0501 need them.
- **The void reason is short.** `InvalidReason` is at most 6 Chinese characters or 20 English ones `[inv 五, 七]`. The MIG allows 20 characters of any kind. A Chinese reason of 7 to 20 characters passes the unified rules but fails here.
- **Item fields are much smaller than the MIG.** `ItemName` is max 30, `ItemUnit` max 2 Chinese or 6 English characters, and `ItemCount` and `ItemPrice` are **integers** `[inv 四]`. The MIG allows 500 chars and 7 decimals.
- **`TaxRate` is a percent.** Send `5`, not `0.05` `[inv 四]`. The query returns `0.05` `[inv 八]`. The MIG and the other providers use `0.05`.
- **An allowance on a mixed invoice is split.** One allowance covers one tax type (`TaxTypeForMixed`). A mixed invoice needs one allowance per tax type `[inv 六]`.
- **Allowance prices may include tax.** MIG G0401 wants amounts without tax and a tax per item.
- **The allowance number is longer than the MIG's.** ezPay returns an `AllowanceNo` of up to 20 characters (25 in `allowanceInvalid`). MIG `AllowanceNumber` is max 16. The manual's example is 16 characters (`A151015111705007`).
- **No zero tax rate reason.** The manual was last changed before MIG 4.0 and has no field for `ZeroTaxRateReason`.

### 4.8 Contract and live tests

ezPay breaks several assumptions of the shared contract:

- **Query by number.** The contract sends only `invoice_number`. ezPay also needs the random code. The adapter cannot pass this test unless the contract sends `provider_options`, or the adapter keeps the random codes of the invoices it issued. Neither exists today.
- **Void right after issue.** The contract voids an invoice it has just issued. Live, ezPay refuses until the next day's upload (`LIB10009`). A fake can allow it. A live spec cannot test voids in one run.
- **Credit a voided invoice.** This test voids first, so it has the same problem live. ezPay has no documented code for "allowance on a voided invoice", so the expected `ConflictError` is unknown (see 7).
- **Unknown invoice.** The contract queries an unknown invoice with only `invoice_number`, and expects `NotFoundError`. Without a random code, the proposed adapter raises `ValidationError` before the call (4.2). So this test fails as well, for the same reason as the query by number.
- **Unknown allowance.** ezPay has no documented code for "allowance not found". `IAI10002` (query failed) is the closest (see 7).
- **Allowance needs the order id.** The contract does not send it. The adapter needs `provider_options[:order_id]`, or must remember the order ids of the invoices it issued.
- **Order ids.** Max 20 chars. The contract's ids (`ORDER_A`, …) fit. A live spec with long generated ids may not.
- **Test shop.** There is no shared account. Each developer opens a test shop on `cinv.ezpay.com.tw` and adds test tracks.

## 5. Field reference

### 5.1 `invoice_issue`

`[inv 四(一)]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `RespondType`, `Version` (`1.5`), `TimeStamp` | M | |
| `TransNum` | O | ezPay payment transaction number, only for shops that also use ezPay payments |
| `MerchantOrderNo` | M | max 20. Letters, digits and `_`. Unique in the shop |
| `Status` | M | `1` issue now, `0` hold for a trigger, `3` schedule |
| `CreateStatusTime` | O | `YYYY-MM-DD`. M for `Status` `3` |
| `Category` | M | `B2B` or `B2C` |
| `BuyerName` | M | B2B: company name, max 60, or the 統一編號 when it does not fit. B2C: name or an id the shop uses, max 30 |
| `BuyerUBN` | O | 8 digits. M for B2B |
| `BuyerAddress` | O | max 100 |
| `BuyerEmail` | O | max 50. ezPay sends the invoice notice here. M for the ezPay member carrier |
| `CarrierType` | O | B2C only. `0` mobile barcode, `1` citizen certificate, `2` ezPay member carrier. Empty for none. Must be empty when `LoveCode` is set |
| `CarrierNum` | O | max 50. M with `CarrierType`. See 6.2 |
| `LoveCode` | O | 3 to 7 digits. B2C only. Must be empty when `CarrierType` is set |
| `PrintFlag` | M | `Y` / `N`. Must be `Y` for B2B, and for B2C with no carrier and no donation |
| `KioskPrintFlag` | O | `1`: a winning invoice can be printed at a FamiPort kiosk. Only with `CarrierType` `2` |
| `TaxType` | M | `1` taxable, `2` zero rated, `3` tax free, `9` mixed (B2C only) |
| `TaxRate` | M | A percent: `5` for normal tax, the special rate for special tax (for example `18`), `0` for zero rated and tax free |
| `CustomsClearance` | O | `1` / `2`. M for zero rated |
| `Amt` | M | Sales total without tax. For mixed tax, `AmtSales + AmtZero + AmtFree` |
| `AmtSales`, `AmtZero`, `AmtFree` | O | Mixed tax only. Taxable (without tax), zero rated and tax free sales |
| `TaxAmt` | M | Tax |
| `TotalAmt` | M | Total with tax. `Amt + TaxAmt` |
| `ItemName` | M | max 30 each. Separate items with `\|` |
| `ItemCount` | M | integer. Separate items with `\|` |
| `ItemUnit` | M | max 2 Chinese or 6 English characters. Separate items with `\|` |
| `ItemPrice` | M | integer. B2B without tax, B2C with tax. Separate items with `\|` |
| `ItemAmt` | M | integer. `ItemCount × ItemPrice`. Separate items with `\|` |
| `ItemTaxType` | O | Mixed tax only. `1`, `2`, `3`. Separate items with `\|` |
| `Comment` | O | max 200 |

Result: `InvoiceTransNo` (ezPay's issue number), `MerchantID`, `MerchantOrderNo`, `TotalAmt`, `InvoiceNumber` (only when issued now), `RandomNum`, `CreateTime` (`yyyy-MM-dd HH:mm:ss`), `CheckCode`, and for printed invoices `BarCode`, `QRcodeL`, `QRcodeR`. Example in 2.5.

`invoice_touch_issue` takes `InvoiceTransNo`, `MerchantOrderNo` and `TotalAmt` from the held invoice, all M. It works for held (`Status` `0`) and scheduled (`Status` `3`) invoices `[inv 四(三)]`.

### 5.2 `invoice_invalid`

`InvoiceNumber` and `InvalidReason` (max 6 Chinese or 20 English), both M. Result: `MerchantID`, `InvoiceNumber`, `CreateTime`, `CheckCode` `[inv 五]`.

Example result from the manual, `Result` parsed:

```json
{ "CheckCode": "01DD7B45A33B9647536D81656C6B3E93B218802480B94EE0674D92D6BDB3204A",
  "MerchantID": "3459997", "InvoiceNumber": "OU00122220", "CreateTime": "2015-07-16 17:00:33" }
```

### 5.3 `allowance_issue`

`[inv 六(一)]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `Version` | M | `1.3` |
| `InvoiceNo` | M | The invoice to credit |
| `MerchantOrderNo` | M | The invoice's order id |
| `ItemName`, `ItemCount`, `ItemUnit`, `ItemPrice`, `ItemAmt` | M | As in issue, separated by `\|`. `ItemPrice` may be with or without tax |
| `TaxTypeForMixed` | O | M for a mixed invoice: the tax type of this allowance, `1`, `2` or `3` |
| `ItemTaxAmt` | M | `ItemAmt × rate` when prices exclude tax. `0` when they include tax |
| `TotalAmt` | M | Allowance total |
| `BuyerEmail` | O | ezPay sends the allowance notice here |
| `Status` | M | `1` confirm now, `0` wait for a confirm |

Result: `MerchantID`, `AllowanceNo`, `InvoiceNumber`, `MerchantOrderNo`, `AllowanceAmt`, `RemainAmt` (what is left of the invoice), `CheckCode`.

Example result from the manual, `Result` parsed:

```json
{ "MerchantID": "3622183", "AllowanceNo": "A151015111705007", "MerchantOrderNo": "202E19",
  "AllowanceAmt": "500", "RemainAmt": "0", "CheckCode": "F3BB07F4…" }
```

### 5.4 `allowanceInvalid`

`AllowanceNo` (max 25) and `InvalidReason` (max 6 Chinese or 20 English), both M. Result: `AllowanceNo`, `CreateTime`, `CheckCode` `[inv 七]`.

### 5.5 `invoice_search`

`[inv 八(一)]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `Version` | M | `1.3` |
| `SearchType` | O | `0` by number and random code (default), `1` by order id and total |
| `MerchantOrderNo`, `TotalAmt` | O | M for `SearchType` `1` |
| `InvoiceNumber`, `RandomNum` | O | M for `SearchType` `0` |
| `DisplayFlag` | O | Empty: return data. `1`: the caller form-posts and ezPay shows a web page. `2`: return a URL to that page |

Result fields `[inv 八(二)]`: `MerchantID`, `InvoiceTransNo`, `MerchantOrderNo`, `InvoiceNumber`, `RandomNum`, `BuyerName`, `BuyerUBN`, `BuyerAddress`, `BuyerPhone`, `BuyerEmail`, `InvoiceType` (`07` / `08`), `Category`, `TaxType`, `TaxRate` (here as `0.05`), `Amt`, `AmtSales`, `AmtZero`, `AmtFree` (mixed only), `TaxAmt`, `TotalAmt`, `CarrierType`, `CarrierNum`, `LoveCode`, `PrintFlag`, `KioskPrintFlag`, `CreateTime`, `ItemDetail`, `InvoiceStatus`, `UploadStatus`, `CheckCode`, `BarCode`, `QRcodeL`, `QRcodeR`.

`ItemDetail` is a JSON string of items: `ItemNum`, `ItemName`, `ItemCount`, `ItemWord` (unit), `ItemPrice`, `ItemAmount`, `ItemTaxType`. The manual's example also shows `ItemTaxRate`, `ItemRateAmt` and `ItemAmt`, all empty.

Example from the manual (some fields left out, `Result` and `ItemDetail` parsed):

```json
{ "MerchantID": "3757976", "InvoiceTransNo": "20020310232543048", "MerchantOrderNo": "1580696208",
  "InvoiceNumber": "BA00000007", "RandomNum": "4234", "InvoiceType": "07", "Category": "B2C",
  "TaxType": "1", "TaxRate": "0.05000", "Amt": "1333", "TaxAmt": "67", "TotalAmt": "1400",
  "PrintFlag": "Y", "CreateTime": "2020-02-03 10:23:25",
  "ItemDetail": [{ "ItemNum": "", "ItemName": "商品1", "ItemCount": 1, "ItemWord": "",
                   "ItemPrice": 100, "ItemAmount": 100 }, "…"] }
```

### 5.6 Cross-border (`crossBorderInvoiceIssue`)

For cross-border sellers (營業稅法第 6 條第 4 款). The same flow, with `Currency` required, and `OriginalCurrencyAmount` (2 decimals) and `ExchangeRate` (5 decimals) as memo fields. Amounts may be in the foreign currency. `Comment` is max 71 `[ces 四]`.

## 6. Codes

### 6.1 Tax type

| Unified | ezPay `TaxType` | MIG |
| --- | --- | --- |
| `TAXABLE` | `1` | `1` |
| `ZERO_RATED` | `2` | `2` |
| `TAX_FREE` | `3` | `3` |
| `SPECIAL` | `1` with the special `TaxRate` (inferred from the `TaxRate` note) | `4` |
| (mixed, derived) | `9` | `9` |

`4` (special rate) is not listed in the manual.

### 6.2 Carrier type

| Unified | ezPay | Meaning | `CarrierNum` |
| --- | --- | --- | --- |
| `MOBILE_BARCODE` | `0` | Mobile barcode (`3J0002`) | `/` and 7 of `0-9`, `A-Z`, `+`, `-`, `.` |
| `CITIZEN_CERTIFICATE` | `1` | Citizen certificate (`CQ0001`) | 2 capital letters and 14 digits |
| `MEMBER` | `2` | ezPay member carrier | Any id the shop picks for the buyer (email, phone, member id). ezPay builds the carrier from the shop's 統一編號 and this id |

ezPay's codes are its own. They are not the MIG codes, and not ECPay's.

### 6.3 Status

`InvoiceStatus`: `1` issued, `2` voided. `UploadStatus`: `0` not uploaded, `1` uploaded, `2` uploading, `3` failed, `4` timed out. See 4.4.

### 6.4 Error codes

`[inv 九]`. The unified error and `Reason` columns are proposals. A `CheckCode` that does not match is a `ProviderError`.

| Code | Meaning | Unified error | `Reason` |
| --- | --- | --- | --- |
| `KEY10002` | Cannot decrypt the data | `AuthError` | `CREDENTIALS_INVALID` |
| `KEY10004` | Data incomplete | `ValidationError` | |
| `KEY10006` | Shop has not applied for e-invoicing | `AuthError` | `NOT_ENROLLED` |
| `KEY10007` | Page stayed open more than 30 minutes | `ValidationError` | `STALE_TIMESTAMP` |
| `KEY10010`, `KEY10011`, `KEY10013` | Shop id, `PostData_` or data empty | `ValidationError` | |
| `KEY10012` | Data transfer error | `ProviderError` | |
| `KEY10014` | Timeout | `NetworkError` | |
| `KEY10015` | Invoice amount format wrong | `ValidationError` | |
| `INV10003`, `INV10004` | Item data wrong, or item total wrong | `ValidationError` | |
| `INV10006` | Tax rate format wrong | `ValidationError` | |
| `INV10012` | Amount and tax type do not match | `ValidationError` | |
| `INV10013` | Fields missing or wrong | `ValidationError` | |
| `INV10014` | Order id format wrong | `ValidationError` | |
| `INV10015`, `INV10016` | No sales amount, or no tax | `ValidationError` | |
| `INV10017` | This `Version` does not support mixed tax | `ValidationError` | |
| `INV10019` | Data has control characters | `ValidationError` | |
| `INV10020`, `INV10021` | Suspended, or stopped | `AuthError` | `ACCOUNT_SUSPENDED` |
| `INV20006` | Invoice not found | `NotFoundError` | |
| `INV70001` | Field format wrong | `ValidationError` | |
| `INV70002` | An invoice that failed to upload cannot be voided | `ConflictError` | |
| `INV90005` | No contract, or contract expired | `AuthError` | `CONTRACT_EXPIRED` |
| `INV90006` | No invoices left to issue | `NumberExhaustedError` | |
| `NOR10001` | Network error | `NetworkError` | |
| `LIB10003` | Duplicate order id | `ConflictError` | `DUPLICATE_ORDER` |
| `LIB10005` | Already voided | `ConflictError` | `ALREADY_VOIDED` |
| `LIB10007` | Has an allowance, cannot void | `ConflictError` | `VOID_BLOCKED_BY_ALLOWANCE` |
| `LIB10008` | Past the void deadline | `ConflictError` | `PAST_DEADLINE` |
| `LIB10009` | Not uploaded yet, cannot void | `ConflictError` | |
| `IAI10001` to `IAI10006` | Allowance void errors: missing parameter, query failed, update failed, wrong parameter, insert failed, stopped | `ProviderError` | |

The list has no code for these cases: an allowance on a voided invoice, an allowance that does not exist, or a duplicate allowance.

## 7. Open questions

1. The manual was last changed before ezPay moved to MIG 4.0. How does ezPay fill MIG fields it does not take, such as `ZeroTaxRateReason`?
2. How does ezPay keep its 20-character `AllowanceNo` inside the MIG's 16?
3. Is special tax really `TaxType` `1` with a special `TaxRate`?
4. How is the `CheckCode` of a void or allowance result built? It lacks the five fields of the documented rule.
5. Which codes come back for an allowance on a voided invoice, and for voiding an allowance that does not exist? The contract needs `ConflictError` and `NotFoundError` there.
6. **Contract:** query by number needs the random code, and an allowance needs the order id. Should the shared contract pass `provider_options`, or should adapters remember what they issued?
7. **Core:** what does a B2C `AmountSummary` with `tax 0` mean for a provider that always splits the tax (4.3)?
8. None of this is verified live. It needs a test shop on `cinv.ezpay.com.tw`.
