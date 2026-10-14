# ezPay 簡單行動支付: 電子發票 API

## 1. Status and sources

ezPay (簡單行動支付股份有限公司) runs the ezPay 電子發票加值服務平台. The 2.x line has no adapter for it yet. Nothing here is verified against the live API.

ezPay publishes its manuals as PDFs on a public download page: <https://inv.ezpay.com.tw/Invoice_index/download>. The PDFs say ezPay holds the copyright, so this note is our summary only.

| Tag | Source | Version and date | What it gives |
| --- | --- | --- | --- |
| `[inv]` | 電子發票技術串接手冊 標準版, `dw_files/info_api/EZP_INVI_1_2_2.pdf`, 72 pages | EZP_INVI_1.2.2, 2024-04-22 | Issue, void, allowance, allowance void, query |
| `[ces]` | 電子發票技術串接手冊 境外電商版, `EZP_CES_1_0_0.pdf`, 65 pages | EZP_CES_1.0.0, 2021-01-26 | Cross-border sellers |
| `[track]` | 電子發票字軌管理 技術串接手冊, `EZP__Track__1_0_0.pdf`, 38 pages | EZP_Track_1.0.0, 2018-10 | Track (字軌) management |
| `[bdv]` | 手機條碼與捐贈碼驗證 技術串接手冊, `BDV_1_0_0.pdf`, 24 pages | EZP_BDV_1.0.0, 2021-03-03 | Mobile barcode and donation code checks |

All four were downloaded on 2026-10-14. The `[inv]` manual has had no change since April 2024, and its last real field changes are from 2021.

## 2. Connection

### 2.1 Hosts and credentials

| Environment | Host |
| --- | --- |
| Test | `https://cinv.ezpay.com.tw` |
| Production | `https://inv.ezpay.com.tw` |

There are no shared test credentials. A developer signs up on the test platform, opens a test shop, gets its `HashKey` and `HashIV`, and adds test track numbers under 管理設定 > 發票字軌號碼設定 `[inv 三]`. The test and production shops are separate.

A shop has a `MerchantID_` (商店代號, max 15), a `HashKey` and a `HashIV`. AES-256 needs a 32-byte key and a 16-byte IV, as in the manual's examples. The track API uses the member id `CompanyID_` instead of `MerchantID_` `[track 四]`.

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
| `RespondType` | `JSON` or `String` |
| `Version` | Fixed per API: `1.5` for issue, `1.3` for allowance and query, `1.0` for the others |
| `TimeStamp` | Unix time |

In `CarrierNum`, encode the value with `rawurlencode()` first, so no data is lost `[inv 四]`.

### 2.3 Response

With `RespondType` `JSON`:

```json
{ "Status": "SUCCESS", "Message": "...", "Result": "<a JSON string>" }
```

`Status` is `SUCCESS` or an error code (6.4). `Result` is itself a JSON string. With `String`, the same fields come as a query string that ends with `EndStr` `##` `[inv 四]`.

**Issue is idempotent.** If the same `PostData_` comes again with exactly the same data, ezPay answers `SUCCESS` with the original `Result` `[inv 四(二)]`.

### 2.4 Check codes

Issue, void, allowance and query results carry a `CheckCode`, so the caller can check that ezPay sent them `[inv 附件二]`:

1. Take `InvoiceTransNo`, `MerchantID`, `MerchantOrderNo`, `RandomNum` and `TotalAmt` from the result.
2. Sort them by name and join as a query string.
3. Put `HashIV=...&` before it and `&HashKey=...` after it.
4. SHA-256, upper case hex.

The validation APIs use `CheckValue` instead: SHA-256 of `HashKey=...&<Result>&HashIV=...`, upper case `[bdv 附件三]`.

## 3. Operations

| Group | Endpoint | Purpose | Source |
| --- | --- | --- | --- |
| Issue | `/Api/invoice_issue` | Issue now, hold for a trigger, or schedule | `[inv 四]` |
| | `/Api/invoice_touch_issue` | Issue a held or scheduled invoice now | `[inv 四(三)]` |
| Void | `/Api/invoice_invalid` | Void an invoice | `[inv 五]` |
| Allowance | `/Api/allowance_issue` | Issue an allowance, confirmed now or later | `[inv 六]` |
| | `/Api/allowance_touch_issue` | Confirm (`C`) or cancel (`D`) a pending allowance | `[inv 六(三)]` |
| | `/Api/allowanceInvalid` | Void a confirmed allowance | `[inv 七]` |
| Query | `/Api/invoice_search` | One invoice, as data, as an ezPay web page, or as a URL | `[inv 八]` |
| Cross-border | `/Api/crossBorderInvoiceIssue`, `/Api/crossBorderAllowanceIssue`, `/Api/crossBorderInvoiceSearch` | The same for cross-border sellers | `[ces]` |
| Tracks | `/Api_number_management/createNumber`, `manageNumber`, `searchNumber` | Add, change and list tracks | `[track]` |
| Checks | `/Api_inv_application/checkBarCode`, `checkLoveCode` | Is a mobile barcode or donation code registered | `[bdv]` |

### Timing

- ezPay uploads the day's issues, voids and allowances to the MOF from 01:00 the next day. From 06:00 it updates the upload status from the MOF reply `[inv 三]`.
- An invoice can only be voided **after** it is uploaded (`LIB10009`) `[inv 九]`. So an invoice issued today cannot be voided today.
- Before the 14th of an odd month, invoices of the two months before can still be voided. On 13 July, May and June invoices can be voided `[inv 一]`.
- An invoice with an allowance cannot be voided (`LIB10007`).
- A pending allowance stays in ezPay and is not uploaded until it is confirmed. It is uploaded the day after the confirm `[inv 一]`.

## 4. Mapping to the unified API

| Unified | ezPay | Note |
| --- | --- | --- |
| `issue` | `invoice_issue`, `Status` `1` | |
| `void` | `invoice_invalid` | Number and reason only. Not before upload |
| `allowance` | `allowance_issue`, `Status` `1` | ezPay assigns the allowance number |
| `void_allowance` | `allowanceInvalid` | Number and reason only |
| `query` by number | `invoice_search`, `SearchType` `0` | Also needs the **random code** |
| `query` by order id | `invoice_search`, `SearchType` `1` | Also needs the **total amount** |

### Against the MIG and the unified model

- **Query needs a second key.** By number, `RandomNum` is required. By order id, `TotalAmt` is required. `QueryInvoiceInput` has neither, so they must come in `provider_options`.
- **Voids need no date.** `invoice_invalid` and `allowanceInvalid` take only the number and a reason. ezPay fills the dates from its records (inferred), as MIG F0501 and G0501 need them.
- **The void reason is short.** `InvalidReason` is at most 6 Chinese characters or 20 English ones `[inv 五, 七]`. The MIG allows 20 characters of any kind. A Chinese reason of 7 to 20 characters passes the unified rules but fails here.
- **Item fields are much smaller than the MIG.** `ItemName` is max 30, `ItemUnit` max 2 Chinese or 6 English characters, and `ItemCount` and `ItemPrice` are **integers** `[inv 四]`. The MIG allows 500 chars and 7 decimals.
- **Item prices change meaning with the buyer.** For `Category` `B2B`, `ItemPrice` and `ItemAmt` exclude tax. For `B2C`, they include tax `[inv 四]`.
- **`TaxRate` is a percent.** Send `5`, not `0.05` `[inv 四]`. The MIG and the other providers use `0.05`.
- **Mixed tax is B2C only.** `TaxType` `9` only works with `Category` `B2C` `[inv 四]`.
- **An allowance on a mixed invoice is split.** One allowance covers one tax type (`TaxTypeForMixed`). A mixed invoice needs one allowance per tax type `[inv 六]`.
- **Allowance prices may include tax.** If they do, `ItemTaxAmt` must be `0`, and the buyer cannot deduct that tax `[inv 六]`. The MIG wants amounts without tax and a tax per item.
- **The allowance number is longer than the MIG's.** ezPay returns an `AllowanceNo` of up to 20 characters (25 in `allowanceInvalid`). MIG `AllowanceNumber` is max 16. How ezPay maps one to the other is unknown.
- **ezPay checks little.** It only checks `ItemAmt = ItemCount × ItemPrice`, `TotalAmt = Amt + TaxAmt` for invoices, and `TotalAmt = items + item tax` for allowances. The rest is up to the caller `[inv 三]`.

### Status

`invoice_search` returns `[inv 八(二)]`:

| Field | Values |
| --- | --- |
| `InvoiceStatus` | `1` issued, `2` voided |
| `UploadStatus` | `0` not uploaded, `1` uploaded, `2` uploading, `3` failed, `4` timed out |

There is no allowance status and no cancelled status in the query.

## 5. Field reference

### 5.1 `invoice_issue`

`[inv 四(一)]`. "Req" means required.

| Field | Rule |
| --- | --- |
| `RespondType`, `Version` (`1.5`), `TimeStamp` | Req |
| `TransNum` | ezPay payment transaction number, only for shops that also use ezPay payments |
| `MerchantOrderNo` | Req, max 20. Letters, digits and `_`. Unique in the shop |
| `Status` | Req. `1` issue now, `0` hold for a trigger, `3` schedule |
| `CreateStatusTime` | `YYYY-MM-DD`. Only for `Status` `3` |
| `Category` | Req. `B2B` or `B2C` |
| `BuyerName` | Req. B2B: company name, max 60, or the 統一編號 when it does not fit. B2C: name or an id the shop uses, max 30 |
| `BuyerUBN` | 8 digits. Req for B2B |
| `BuyerAddress` | max 100 |
| `BuyerEmail` | max 50. ezPay sends the invoice notice here. Req for the ezPay member carrier |
| `CarrierType` | B2C only. `0` mobile barcode, `1` citizen certificate, `2` ezPay member carrier. Empty for none. Must be empty when `LoveCode` is set |
| `CarrierNum` | max 50. Req with `CarrierType`. See 6.2 |
| `LoveCode` | 3 to 7 digits. B2C only. Must be empty when `CarrierType` is set |
| `PrintFlag` | Req. `Y` / `N`. Must be `Y` for B2B, and for B2C with no carrier and no donation |
| `KioskPrintFlag` | `1`: a winning invoice can be printed at a FamiPort kiosk. Only with `CarrierType` `2` |
| `TaxType` | Req. `1` taxable, `2` zero rated, `3` tax free, `9` mixed (B2C only) |
| `TaxRate` | Req. A percent: `5` for normal tax, the special rate for special tax (for example `18`), `0` for zero rated and tax free |
| `CustomsClearance` | `1` / `2`. Req for zero rated |
| `Amt` | Req. Sales total without tax. For mixed tax, `AmtSales + AmtZero + AmtFree` |
| `AmtSales`, `AmtZero`, `AmtFree` | Mixed tax only. Taxable (without tax), zero rated and tax free sales |
| `TaxAmt` | Req. Tax |
| `TotalAmt` | Req. Total with tax. `Amt + TaxAmt` |
| `ItemName` | Req, max 30 each. Separate items with `\|` |
| `ItemCount` | Req, integer. Separate items with `\|` |
| `ItemUnit` | Req, max 2 Chinese or 6 English characters. Separate items with `\|` |
| `ItemPrice` | Req, integer. B2B without tax, B2C with tax. Separate items with `\|` |
| `ItemAmt` | Req, integer. `ItemCount × ItemPrice`. Separate items with `\|` |
| `ItemTaxType` | Mixed tax only. `1`, `2`, `3`. Separate items with `\|` |
| `Comment` | max 200 |

The manual has no field for the zero tax rate reason (MIG `ZeroTaxRateReason`), because it was last changed before MIG 4.0.

Result: `InvoiceTransNo` (ezPay's issue number), `MerchantOrderNo`, `TotalAmt`, `InvoiceNumber` (only when issued now), `RandomNum`, `CreateTime` (`yyyy-MM-dd HH:mm:ss`), `CheckCode`, and for printed invoices `BarCode`, `QRcodeL`, `QRcodeR`.

### 5.2 `invoice_touch_issue`

`InvoiceTransNo`, `MerchantOrderNo` and `TotalAmt` from the held invoice, all required. Works for held (`Status` `0`) and scheduled (`Status` `3`) invoices `[inv 四(三)]`.

### 5.3 `invoice_invalid`

`InvoiceNumber` and `InvalidReason` (max 6 Chinese or 20 English), both required. Result: `InvoiceNumber`, `CreateTime`, `CheckCode` `[inv 五]`.

### 5.4 `allowance_issue`

`[inv 六(一)]`:

| Field | Rule |
| --- | --- |
| `Version` | `1.3` |
| `InvoiceNo` | Req. The invoice to credit |
| `MerchantOrderNo` | Req. The invoice's order id |
| `ItemName`, `ItemCount`, `ItemUnit`, `ItemPrice`, `ItemAmt` | Req. As in issue: separate items with `\|`. `ItemPrice` may be with or without tax |
| `TaxTypeForMixed` | For a mixed invoice: the tax type of this allowance, `1`, `2` or `3` |
| `ItemTaxAmt` | Req. `ItemAmt × rate` when prices exclude tax. `0` when they include tax |
| `TotalAmt` | Req. Allowance total |
| `BuyerEmail` | ezPay sends the allowance notice here |
| `Status` | Req. `1` confirm now, `0` wait for a confirm |

Result: `AllowanceNo`, `InvoiceNumber`, `MerchantOrderNo`, `AllowanceAmt`, `CheckCode`.

### 5.5 `allowanceInvalid`

`AllowanceNo` (max 25) and `InvalidReason` (max 6 Chinese or 20 English), both required. Result: `AllowanceNo`, `CreateTime`, `CheckCode` `[inv 七]`.

### 5.6 `invoice_search`

`[inv 八(一)]`:

| Field | Rule |
| --- | --- |
| `Version` | `1.3` |
| `SearchType` | `0` by number and random code (default), `1` by order id and total |
| `MerchantOrderNo`, `TotalAmt` | For `SearchType` `1` |
| `InvoiceNumber`, `RandomNum` | For `SearchType` `0` |
| `DisplayFlag` | Empty: return data. `1`: the caller form-posts and ezPay shows a web page. `2`: return a URL to that page |

Result fields: `MerchantOrderNo`, `InvoiceNumber`, `RandomNum`, `BuyerName`, `BuyerUBN`, `BuyerAddress`, `BuyerPhone`, `BuyerEmail`, `InvoiceType` (`07` / `08`), `Category`, `TaxType`, `TaxRate` (here as `0.05`), `Amt`, `AmtSales`, `AmtZero`, `AmtFree`, `TaxAmt`, `TotalAmt`, `CarrierType`, `CarrierNum`, `LoveCode`, `PrintFlag`, `KioskPrintFlag`, `CreateTime`, `InvoiceStatus`, `UploadStatus`, `CheckCode`, `BarCode`, `QRcodeL`, `QRcodeR` `[inv 八(二)]`. Items are not in the result.

### 5.7 Cross-border (`crossBorderInvoiceIssue`)

For cross-border sellers (營業稅法第 6 條第 4 款). The same flow, with `Currency` required, and `OriginalCurrencyAmount` (2 decimals) and `ExchangeRate` (5 decimals) as memo fields. Amounts may be in the foreign currency. `Comment` is max 71 `[ces 四]`.

## 6. Codes

### 6.1 Tax type

`1` taxable, `2` zero rated, `3` tax free, `9` mixed. The MIG codes, except that `4` (special rate) is not listed. Special tax probably uses `TaxType` `1` with the special `TaxRate`. We inferred this from the `TaxRate` note.

### 6.2 Carrier type

| ezPay | Meaning | `CarrierNum` |
| --- | --- | --- |
| `0` | Mobile barcode (`3J0002`) | `/` and 7 of `0-9`, `A-Z`, `+`, `-`, `.` |
| `1` | Citizen certificate (`CQ0001`) | 2 capital letters and 14 digits |
| `2` | ezPay member carrier | Any id the shop picks for the buyer (email, phone, member id). ezPay builds the carrier from the shop's 統一編號 and this id |

ezPay's codes are its own. They are not the MIG codes, and not ECPay's.

### 6.3 Status

See section 4.

### 6.4 Error codes

`[inv 九]`:

| Code | Meaning |
| --- | --- |
| `KEY10002` | Cannot decrypt the data |
| `KEY10004` | Data incomplete |
| `KEY10006` | Shop has not applied for e-invoicing |
| `KEY10007` | Page stayed open more than 30 minutes |
| `KEY10010`, `KEY10011`, `KEY10013` | Shop id, `PostData_` or data empty |
| `KEY10012` | Data transfer error |
| `KEY10014` | Timeout |
| `KEY10015` | Invoice amount format wrong |
| `INV10003`, `INV10004` | Item data wrong, or item total wrong |
| `INV10006` | Tax rate format wrong |
| `INV10012` | Amount and tax type do not match |
| `INV10013` | Fields missing or wrong |
| `INV10014` | Order id format wrong |
| `INV10015`, `INV10016` | No sales amount, or no tax |
| `INV10017` | This `Version` does not support mixed tax |
| `INV10019` | Data has control characters |
| `INV10020`, `INV10021` | Suspended, or stopped |
| `INV20006` | Invoice not found |
| `INV70001` | Field format wrong |
| `INV70002` | An invoice that failed to upload cannot be voided |
| `INV90005` | No contract, or contract expired |
| `INV90006` | No invoices left to issue |
| `NOR10001` | Network error |
| `LIB10003` | Duplicate order id |
| `LIB10005` | Already voided |
| `LIB10007` | Has an allowance, cannot void |
| `LIB10008` | Past the void deadline |
| `LIB10009` | Not uploaded yet, cannot void |
| `IAI10001` to `IAI10006` | Allowance void errors: missing parameter, query failed, update failed, wrong parameter, insert failed, stopped |

## 7. Open questions

1. The manual was last changed before ezPay moved to MIG 4.0. How does ezPay fill MIG fields it does not take, such as `ZeroTaxRateReason`?
2. How does ezPay keep its 20-character `AllowanceNo` inside the MIG's 16?
3. Is special tax really `TaxType` `1` with a special `TaxRate`?
4. Can a query return the items? `invoice_search` does not list them.
5. None of this is verified live. It needs a test shop on `cinv.ezpay.com.tw`.
