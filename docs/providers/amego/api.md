# Amego 光貿: 電子發票 API

English | [繁體中文](api.zh-TW.md)

## 1. Status and sources

> **Trust:** an adapter is in progress. Its live spec passed on the public test account on 2026-10-22, and the facts it saw are marked `[live]`. Section 4 and the class columns in 6.4 are the mapping the adapter follows. The live spec did not check every row.

This is Amego's JSON API at `https://invoice-api.amego.tw`. The 2.x adapter will be `Einvoice::Amego::Provider`. Facts marked `[live]` were seen on the public test account.

The docs belong to 光貿科技 Amego and are published at <https://invoice.amego.tw/api_doc/>. This note is our summary.

The API follows the MIG closely. Its endpoints are named after MIG messages (`f0401`, `f0501`, `g0401`, `g0501`), and most fields carry MIG names.

| Tag | Source | Date | What it gives |
| --- | --- | --- | --- |
| `[doc]` | Amego API docs, <https://invoice.amego.tw/api_doc/>. An apiDoc site. We read the data bundle (`main.bundle.js?2026093003`) on 2026-10-14. | Generated 2026-09-30, doc version 1.0.0 | All endpoints, fields, examples, and the basic rules. |
| `[live]` | Our live spec (`spec/einvoice/amego/live_spec.rb`) on the public test account, 2026-10-22. | 2026-10-22 | What Amego really accepted and answered. |
| `[info]` | Amego help pages. The docs link to them: <https://invoice.amego.tw/info_detail?mid=70> (issue modes), `mid=71` (error codes), `mid=73` (member carrier rules), `mid=74` (checks). Read on 2026-10-14. | | Error codes and format rules. |

**Updates.** The docs site has no change log. The bundle URL carries a build number (`main.bundle.js?2026093003`). A new number means the docs were rebuilt.

## 2. Connection

### 2.1 Host and credentials

One host for test and production: `https://invoice-api.amego.tw`. The credentials pick the environment, not the URL `[doc]`.

A seller has its 統一編號 and an App Key from Amego support. The shared test account `[doc]`:

| Item | Value |
| --- | --- |
| 統一編號 | `12345678` |
| App Key | `sHeq7t8G1wiQvhAuIM27` |
| Back office | <https://invoice.amego.tw/>, `test@amego.tw` / `12345678` |

The test environment sends no email. To get a test email, open the invoice in the test back office and press 「補發發票開立通知」 `[doc]`.

### 2.2 Request

Every API is `POST` with `Content-Type: application/x-www-form-urlencoded`. Do not send `application/json` `[doc]`.

| Field | Type | Rule |
| --- | --- | --- |
| `invoice` | String | The seller's 統一編號 |
| `data` | String | The API payload as a JSON string, URL encoded |
| `time` | Number | Unix time. Must be within ±60 seconds of the server clock |
| `sign` | String | `md5(data + time + AppKey)`, where `data` is the JSON string before URL encoding |

Amego URL decodes the POST data once on its side. `/json/time` returns the server time, to fix clock drift.

Some APIs take an array in `data`, for example `f0501`, `g0401` and `g0501`. Others take one object, for example `f0401` `[info 71: codes 23, 3040112]`.

There is no encryption. The `sign` only proves that the caller knows the App Key.

**Limits of the API.** The payload is plain JSON, so only TLS protects the buyer's data. The `sign` is MD5, and the response has no signature at all. Test and production share one host, and only the credentials pick the account. An app that ships the shared test account by mistake issues test invoices, with no error.

### 2.3 Response

JSON, with `code` and `msg` on every response. `code` `0` means success. Other codes are errors (6.4) `[doc]`.

Where the result sits depends on the endpoint `[doc]`:

| Endpoint | Result |
| --- | --- |
| `f0401` | At the top level, next to `code` and `msg`: `invoice_number`, `invoice_time`, … Only on success |
| `f0501`, `g0401`, `g0501` | Nothing besides `code` and `msg` |
| `invoice_query`, `allowance_query`, lists, `f0401_custom` | In `data` |

The array endpoints return one `code` for the whole call. The docs do not say what happens when one entry of several fails. Error messages name the entry ("第n筆"), so an adapter should send one entry per call (see 7).

### 2.4 MIG 4.0 paths

From 2025-01-01 Amego uses MIG 4.0. The old paths still work `[doc]`:

| Old | New |
| --- | --- |
| `/json/c0401` | `/json/f0401` |
| `/json/c0501` | `/json/f0501` |
| `/json/d0401` | `/json/g0401` |
| `/json/d0501` | `/json/g0501` |
| `/json/c0401_custom` | `/json/f0401_custom` |

### 2.5 Example

From the docs `[doc]`. A B2C invoice that prints, with a discount line.

Form fields:

```
invoice=12345678
data=<the JSON below, URL encoded>
time=1729000000
sign=md5(<the JSON below> + "1729000000" + AppKey)
```

`data`:

```json
{ "OrderId": "A20200817101021", "BuyerIdentifier": "0000000000", "BuyerName": "客人",
  "BuyerAddress": "", "BuyerTelephoneNumber": "", "BuyerEmailAddress": "", "MainRemark": "",
  "CarrierType": "", "CarrierId1": "", "CarrierId2": "", "NPOBAN": "",
  "ProductItem": [
    { "Description": "測試商品1", "Quantity": "1", "UnitPrice": "170", "Amount": "170", "Remark": "", "TaxType": "1" },
    { "Description": "會員折抵", "Quantity": "1", "UnitPrice": "-2", "Amount": "-2", "Remark": "", "TaxType": "1" } ],
  "SalesAmount": "168", "FreeTaxSalesAmount": "0", "ZeroTaxSalesAmount": "0",
  "TaxType": "1", "TaxRate": "0.05", "TaxAmount": "0", "TotalAmount": "168" }
```

The docs give no full response for `f0401`. By the field list, it is:

```json
{ "code": 0, "msg": "", "invoice_number": "…", "invoice_time": 1729000000,
  "random_number": "…", "barcode": "…", "qrcode_left": "…", "qrcode_right": "…" }
```

A failure: `{ "code": 3040171, "msg": "…" }`. A query that finds nothing: `{ "code": 71, "msg": "查無資料" }`.

### 2.6 Official test vectors

The example page <https://invoice.amego.tw/api_doc/example> has one sample with a known result. Its Python code says the `sign` is `f53a336934b2af0589b845638d1495cc` `[doc]`. The inputs:

- `data`: a B2B invoice (`OrderId` `A20200817105934`, `BuyerIdentifier` `28080623`, two items), as Python's `json.dumps(indent=0)` writes it. That is a newline after each `{`, `[` and item, and `\uXXXX` for each non-ASCII character.
- `time`: `1628136135`, from a comment in the sample.
- App Key: the public test key.

Amego signs the string as it was sent. The JSON layout is part of the input, and any valid JSON layout works. The client spec checks this sample (`spec/einvoice/amego/client_spec.rb`). The docs have no other sample with a result.

## 3. Operations

The five unified operations use these endpoints. Section 5 has their fields.

| Endpoint | Purpose |
| --- | --- |
| `/json/f0401` | Issue an invoice. Amego picks the number (自動配號) |
| `/json/f0501` | Void invoices (array) |
| `/json/g0401` | Issue allowances (array) |
| `/json/g0501` | Void allowances (array) |
| `/json/invoice_query` | One invoice, by order id or number, within 180 days |

Other endpoints. An adapter can reach them through a `raw` method:

| Endpoint | Purpose |
| --- | --- |
| `/json/invoice_status`, `/json/allowance_status` | Upload status of invoices or allowances (array) |
| `/json/invoice_list`, `/json/allowance_list` | Invoices or allowances in a date range, paged |
| `/json/allowance_query` | One allowance |
| `/json/invoice_file`, `/json/invoice_print`, `/json/allowance_file`, `/json/allowance_print` | File and thermal printer data |
| `/json/invoice_modify` | Change an issued invoice (see below) |
| `/json/lottery_status`, `/json/lottery_type` | Winning invoices for a period, prize codes |
| `/json/barcode` | Is a mobile barcode registered |
| `/json/ban_query` | Company name for a 統一編號 |
| `/json/track_all`, `/json/track_get`, `/json/track_status` | Tracks: list, take a range (API 配號 only), status |
| `/json/f0401_custom` | Issue with the seller's own number, date, time and random code |
| `/json/time` | Server time |

There are two ways to number invoices `[info 70]`:

- **自動配號**: the seller sends the invoice, and Amego returns the number, date and random code. Use `f0401`.
- **API 配號**: the seller takes a range with `track_get`, and sends its own number, date, time and random code with `f0401_custom`. This suits a POS that prints offline.

A track is set to one mode in the back office (發票作業 > 發票字軌列表). An adapter for the unified API uses 自動配號.

`invoice_modify` changes an invoice that `f0401` issued. It works only within 180 days, after the upload, and not for a printed B2C invoice, a special tax invoice, or an invoice with an allowance `[info 71: codes 43 to 50]`. The docs do not say which MIG message it sends.

## 4. Mapping to the unified API

### 4.1 Operations

| Unified | Endpoint | Reference fields | `provider_options` |
| --- | --- | --- | --- |
| `issue` | `f0401` | | `track_api_code`, `customs_clearance_mark`, `zero_tax_rate_reason`, `brand_name`, `detail_amount_round`, `tax_adjustment` |
| `void` | `f0501` | `number` | |
| `allowance` | `g0401` | `number`, `invoice_datetime` | `buyer_identifier`, `buyer_name` |
| `void_allowance` | `g0501` | `allowance_number` | |
| `query` | `invoice_query` | `order_id`, or `number` | |

Each call sends one entry, also to the array endpoints (2.3).

**Allowance data from a query.** `g0401` needs the original invoice date and its buyer (`BuyerIdentifier`, `BuyerName`). A reference has the date but no buyer. So the adapter calls `invoice_query` first, and takes the buyer, and the date if the reference has none. When `provider_options` gives `buyer_identifier` and `buyer_name`, and the reference has `invoice_datetime`, the adapter skips the query. The query only works within 180 days. After that, the caller must give all three, or the adapter raises `ValidationError`.

### 4.2 Fields

#### `issue`

| Unified | Amego | Rule or default |
| --- | --- | --- |
| `order_id` | `OrderId` | Max 40 |
| `buyer.ubn` | `BuyerIdentifier` | `0000000000` for B2C |
| `buyer.name` | `BuyerName` | M. For B2C without a name, send `消費者`. For B2B without a name, send the 統一編號. Never `0` to `0000` |
| `buyer.address`, `.phone`, `.email` | `BuyerAddress`, `BuyerTelephoneNumber`, `BuyerEmailAddress` | Amego sends the invoice notice to the email |
| `carrier` (`MOBILE_BARCODE`) | `CarrierType` `3J0002`, `CarrierId1` = `CarrierId2` = `code` | |
| `carrier` (`CITIZEN_CERTIFICATE`) | `CarrierType` `CQ0001`, both ids = `code` | |
| `carrier` (`MEMBER`) | `CarrierType` `amego`, both ids = `code` | Without a `code`, use the buyer's email, else `a` + the buyer's mobile number (6.2). Neither: `ValidationError` |
| `donation.npoban` | `NPOBAN` | A carrier can be sent with it |
| `remark` | `MainRemark` | Max 200 |
| `tax_type`, `items[].tax_type` | `TaxType` | `9` when items have different tax types, else the code (6.1). `SPECIAL`: `UnsupportedError` |
| `tax_rate` | `TaxRate` | As a decimal string, for example `0.05`. Only `0` and `0.05`. Any other rate: `UnsupportedError` |
| `price_mode` | `DetailVat` | `TAX_EXCLUSIVE` `0`, else `1`. `0` only for B2B: B2C with `TAX_EXCLUSIVE` is a `ValidationError` |
| `amount` | `SalesAmount`, `FreeTaxSalesAmount`, `ZeroTaxSalesAmount`, `TaxAmount`, `TotalAmount` | Computed from the items. See 4.3 |
| `provider_options[:customs_clearance_mark]` | `CustomsClearanceMark` | `1` or `2`. Required when a zero rated item is present |
| `provider_options[:zero_tax_rate_reason]` | `ZeroTaxRateReason` | `71` to `79`. Required when a zero rated item is present |
| `items[]` | `ProductItem` | `description` → `Description` (max 256), `quantity` → `Quantity`, `unit` → `Unit`, `unit_price` → `UnitPrice`, `amount` → `Amount`, `remark` → `Remark`, `tax_type` → `TaxType` (the item's, else the invoice's) |
| `currency` | (none) | Not TWD: `UnsupportedError` (see 7) |
| `category` | (none) | Decides B2B, as in the core |
| `exchange_rate` | (none) | Not sent |

Result:

| Unified | From |
| --- | --- |
| `invoice_number` | `invoice_number` |
| `invoice_datetime` | `invoice_time` (Unix time), UTC+8 |
| `random_code` | `random_number` |
| `order_id`, `total_amount` | The input |
| `status` | `ISSUED` |
| `reference` | Built from the fields above |

#### `void`

| Unified | Amego | Rule or default |
| --- | --- | --- |
| `invoice.number` | `[0].CancelInvoiceNumber` | |
| `reason` | `[0].CancelReason` | Max 20 |

Result: `invoice_number` from the input, `status` `VOIDED`, `cancel_datetime` `nil`. The response has only `code` and `msg`.

The void is asynchronous. `code` `0` means Amego accepted the void into its queue, not that the void is done. A query right after the void can still report `ISSUED` (4.4).

#### `allowance`

| Unified | Amego | Rule or default |
| --- | --- | --- |
| `allowance_id` | `AllowanceNumber` | Max 16. Must be unique in the account |
| (now) | `AllowanceDate` | Today in UTC+8, `Ymd`. Amego requires it, and it is the date of this allowance |
| (fixed) | `AllowanceType` | `2` |
| `provider_options[:buyer_identifier]`, `[:buyer_name]`, else the query | `BuyerIdentifier`, `BuyerName` | Must match the original invoice |
| `invoice.number` | `ProductItem[].OriginalInvoiceNumber` | |
| `invoice.invoice_datetime`, else the query | `ProductItem[].OriginalInvoiceDate` | `Ymd` in UTC+8 |
| `items[]` | `ProductItem[]` | `description` → `OriginalDescription`, `quantity` → `Quantity`, `unit_price` → `UnitPrice`, `amount` → `Amount`, plus the item's `Tax` and `TaxType`. Amounts exclude tax. See 4.3 |
| `amount` | `TaxAmount`, `TotalAmount` | See 4.3 |

Result:

| Unified | From |
| --- | --- |
| `allowance_number` | The input `allowance_id`. The response has only `code` and `msg` |
| `invoice_number` | The input |
| `allowance_date` | The `AllowanceDate` the adapter sent |
| `total_amount` | The input |
| `reference` | `allowance_number`, `allowance_date`, `invoice_number` |

#### `void_allowance`

| Unified | Amego | Rule or default |
| --- | --- | --- |
| `allowance.allowance_number` | `[0].CancelAllowanceNumber` | |
| `reason` | (none) | Not sent. `g0501` has no reason field |

Result: `allowance_number` from the input, `cancel_datetime` `nil`.

#### `query`

| Unified | Amego | Rule or default |
| --- | --- | --- |
| `invoice.order_id` | `{ "type": "order", "order_id": … }` | Used when present |
| `invoice.number` | `{ "type": "invoice", "invoice_number": … }` | |

Result:

| Unified | From |
| --- | --- |
| `invoice_number` | `invoice_number` |
| `invoice_datetime` | `invoice_date` (`YYYYMMDD`) and `invoice_time` (`HH:mm:ss`), UTC+8 |
| `random_code` | `random_number` |
| `order_id` | `order_id` |
| `status` | See 4.4 |
| `amount` | See 4.3 |
| `buyer` | `buyer_name`, `buyer_identifier` (`0000000000` becomes `nil`), `buyer_address`, `buyer_telephone_number`, `buyer_email_address` |
| `items` | `product_item[]`: `description`, `quantity`, `unit_price`, `amount`, `unit`, `tax_type`, `remark` |
| `reference` | Built from the fields above |

### 4.3 Amounts and tax

The unified rules are in [the unified model](../README.md#the-unified-model).

**Issue.** Amego wants all MIG totals, and gives the formula `[doc]`. With prices that include tax (`DetailVat` `1`):

```
SalesAmount        = round(sum of Amount where TaxType = 1)
FreeTaxSalesAmount = round(sum of Amount where TaxType = 3)
ZeroTaxSalesAmount = round(sum of Amount where TaxType = 2)
B2C:  TaxAmount = 0
B2B:  TaxAmount = SalesAmount - round(SalesAmount / 1.05)
      SalesAmount = SalesAmount - TaxAmount
TotalAmount = SalesAmount + FreeTaxSalesAmount + ZeroTaxSalesAmount + TaxAmount
```

With prices that exclude tax (`DetailVat` `0`, B2B only), `TaxAmount = round(SalesAmount × 0.05)`, and the rest is the same.

The adapter computes these totals from the items with the core's tax helper. Then it checks that `TotalAmount` equals `amount.total_amount`, and for B2B that `TaxAmount` equals `amount.tax_amount`. If they differ, it raises `ValidationError` before the call. For B2C the formula gives `tax 0`, as F0401 does.

Item amounts keep 7 decimals unless `DetailAmountRound` is `1` `[doc]`.

**Allowance.** Amounts exclude tax, and each item has its own integer `Tax` `[doc]`. This is the shape that the core gives (G0401). The adapter sends each item's amount and tax as they are. `TotalAmount` is the sum without tax, and `TaxAmount` is the sum of the item taxes. A 99 split into 94 and a tax of 5 was accepted `[live]`.

**Query.** `total_amount` is the total. `tax_amount` is only split out for B2B, as on issue. The result is `total = total_amount`, `tax = tax_amount`, `sales = total - tax`.

### 4.4 Status

`invoice_query` reports two things `[doc]`:

- `invoice_type`: the last MIG message for the invoice. It uses the **pre-4.0 names**: `C0401` issued, `C0501` voided, `C0701` cancelled, `A0401` and `A0501` for B2B storage, and `A0101` to `A0302` for B2B exchange.
- `invoice_status`: the upload status (6.3).

`wait` lists changes still in the queue, for example a void that is not processed yet. `allowance` lists the invoice's allowances, each with its own type and status (added 2024-10-24).

Mapping (inferred):

| `invoice_type` | Unified `InvoiceStatus` |
| --- | --- |
| `C0401`, `A0401`, `A0101`, `A0102` | `ALLOWANCE` when `allowance` has an entry that is not voided (`D0401` / `G0401`, not `D0501` / `G0501`), else `ISSUED` |
| `C0501`, `A0501`, `A0201`, `A0202` | `VOIDED` |
| `C0701` (cancelled) | `nil` |
| `A0301`, `A0302` (rejected) | `nil` |

A void in `wait` is not done yet. The invoice is still `ISSUED` until `invoice_type` changes.

### 4.5 Timing

- Queries work within 180 days of the invoice. After that, code `51` `[doc]`.
- A void, issue or cancel waits in a queue. While one is queued, a void returns `3050131`, and a void of an invoice that is still being issued returns `3050121` `[info 71]`. Both mean "try later" (6.4).
- There is a time limit for voids (`3050126`, `4050135`), but the docs do not give it (see 7).
- `invoice_modify` works within 180 days, and only after the upload `[info 71]`.

### 4.6 Capabilities

| Capability | API | Adapter | Note |
| --- | --- | --- | --- |
| `ISSUE`, `VOID`, `ALLOWANCE`, `VOID_ALLOWANCE`, `QUERY` | yes | yes | |
| `B2B` | yes | yes | A 統一編號 in `BuyerIdentifier` |
| `MIXED_TAX` | yes | yes | `TaxType` `9` |
| `QUERY_BY_ORDER_ID` | yes | yes | `invoice_query` with `type: order` |
| `SCHEDULED_ISSUE` | no | no | No such endpoint |
| `CARRIER_VALIDATION` | yes | yes | `validate_carrier` calls `barcode` for a mobile barcode. `9000113` means not registered. Donation codes go through `Einvoice::MOF::DonationCodes` |
| `FOREIGN_CURRENCY` | unknown | no | `f0401` has no currency fields. `f0401_custom` has them (see 7) |

### 4.7 Against the MIG

- **Totals are the MIG totals.** `f0401` takes `SalesAmount`, `FreeTaxSalesAmount`, `ZeroTaxSalesAmount`, `TaxType`, `TaxRate`, `TaxAmount` and `TotalAmount`, all required, as in F0401.
- **Allowances are MIG G0401.** The seller assigns `AllowanceNumber` (max 16, unique). `AllowanceDate` is required. Amounts exclude tax, and each item has its own `Tax`. Each item needs `OriginalInvoiceNumber` and `OriginalInvoiceDate`.
- **Voids need less than the MIG.** `f0501` takes only the number and an optional reason. `g0501` takes only the allowance number. Amego must fill the dates and the reason from its records, because F0501 and G0501 require them (inferred).
- **`AllowanceType` must be `2`.** Since 2025-01-01 Amego rejects `1` `[info 71: code 4040145]`.
- **One invoice per allowance.** An allowance can only credit one invoice `[info 71: codes 4040132, 4040133]`. The MIG allows items from several invoices. The unified model also credits one invoice.
- **`Description` is max 256** `[doc]`. The MIG allows 500.
- **B2B is storage (inferred).** `f0401` takes a 統一編號 together with carrier fields and mixed tax, which A0101 does not allow. The query can still report exchange types (A0101 to A0302), so some invoices in Amego may come from exchange.

### 4.8 Contract and live tests

- **Shared test account.** Every developer uses the account `12345678`. A live spec must build unique order ids and unique allowance numbers. The contract uses fixed allowance ids (`AL_1`, `AL_AV`), which can collide on the live account.
- **Unknown numbers.** Use a well-formed invoice number, for example `unknown_invoice_number: "ZZ00000000"`. Allowance numbers are free text up to 16 chars, so the default `NOPE00000000` fits.
- **Void right after issue.** The contract voids an invoice it has just issued. Amego may answer `3050121` (still being issued) or `3050131` (queued) `[info 71]`. On 2026-10-22 a void right after the issue worked at once, and a second void raised `ConflictError` `[live]`. The live spec still retries on `RETRY_LATER`. The fake ignores the queue.
- **Allowance.** The reference from `issue` gives the invoice date. The adapter still queries for the buyer, so the fake must answer `invoice_query`.
- **A fake.** A fake needs the form envelope, the `sign` check, and the response shapes in 2.3.

## 5. Field reference

### 5.1 `f0401`

`data` is one object `[doc]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `OrderId` | M | max 40, unique |
| `TrackApiCode` | O | Pick a track by its API code (set in the back office). Without it, Amego uses the track order in the back office |
| `BuyerIdentifier` | M | 統一編號, or `0000000000` for a consumer |
| `BuyerName` | M | For a consumer, any name (客人, 消費者). For a business, the company name, or the 統一編號 if the name cannot be given. Not `0`, `00`, `000` or `0000` |
| `BuyerAddress`, `BuyerTelephoneNumber` | O | |
| `BuyerEmailAddress` | O | Amego sends the invoice notice here. Leave empty to send nothing |
| `MainRemark` | O | max 200 |
| `CarrierType` | O | `3J0002` mobile barcode, `CQ0001` citizen certificate, `amego` Amego member carrier, or the seller's own member carrier code |
| `CarrierId1`, `CarrierId2` | O | Visible and hidden code. See 6.2 |
| `NPOBAN` | O | Donation code |
| `ProductItem` | M | up to 9999 items |
| `SalesAmount` | M | Taxable sales total |
| `FreeTaxSalesAmount` | M | Tax free sales total |
| `ZeroTaxSalesAmount` | M | Zero rated sales total |
| `TaxType` | M | `1`, `2`, `3`, `4`, `9` |
| `TaxRate` | M | `0.05` for 5% |
| `TaxAmount` | M | Only a B2B invoice splits out the tax. B2C always sends `0` |
| `TotalAmount` | M | |
| `CustomsClearanceMark` | O | `1` / `2`. M for zero rated |
| `ZeroTaxRateReason` | O | `71` to `79`. M for zero rated |
| `BrandName` | O | Brand name |
| `DetailVat` | O | `1` item prices include tax (default), `0` exclude tax. `0` is only allowed for B2B |
| `DetailAmountRound` | O | `0` keep 7 decimals in item amounts (default), `1` round each to an integer |
| `TaxAdjustment` | O | `1` lowers the tax by 1. Only for B2B with `DetailVat` `0`, when `SalesAmount` ends in 10, 30, 50, 70 or 90 |
| `PrinterType`, `PrinterLang`, `PrintDetail` | O | Thermal printer output |

Item fields:

| Field | M/O | Rule |
| --- | --- | --- |
| `Description` | M | max 256 |
| `Quantity` | M | up to 7 decimals |
| `Unit` | O | max 6 |
| `UnitPrice` | M | up to 7 decimals. Tax included unless `DetailVat` is `0` |
| `Amount` | M | up to 7 decimals |
| `Remark` | O | max 120 |
| `TaxType` | M | `1`, `2`, `3` |

Response (top level, success only): `invoice_number`, `invoice_time` (Unix time), `random_number`, `barcode`, `qrcode_left`, `qrcode_right`, and `base64_data` for a printer. A zero amount invoice returns empty QR codes and no `base64_data`.

### 5.2 `f0501`

`data` is an array of `{ CancelInvoiceNumber, CancelReason }`. `CancelReason` is O, max 20 `[doc]`. The response has only `code` and `msg`.

```json
[{ "CancelInvoiceNumber": "AB00001111", "CancelReason": "作廢原因" }]
```

### 5.3 `g0401`

`data` is an array of allowances `[doc]`:

| Field | M/O | Rule |
| --- | --- | --- |
| `AllowanceNumber` | M | max 16, unique |
| `AllowanceDate` | M | `Ymd` |
| `AllowanceType` | M | `2` |
| `BuyerIdentifier` | M | Must match the original invoice. `0000000000` for a consumer |
| `BuyerName` | M | |
| `BuyerAddress`, `BuyerTelephoneNumber`, `BuyerEmailAddress` | O | |
| `ProductItem` | M | up to 9999 |
| `TaxAmount` | M | |
| `TotalAmount` | M | Tax excluded |

Items: `OriginalInvoiceNumber`, `OriginalInvoiceDate` (`Ymd`), `OriginalDescription` (max 256), `Quantity`, `UnitPrice` (tax excluded), `Amount` (tax excluded), `Tax` (integer) and `TaxType` are all M.

The allowance total, alone or with other allowances on the same invoice, must not exceed the invoice total `[info 71: codes 4040171, 4040173]`.

The response has only `code` and `msg`. Example from the docs, for two machines at 2180 each without tax:

```json
[{ "AllowanceNumber": "3821061800001", "AllowanceDate": "20210618", "AllowanceType": "2",
   "BuyerIdentifier": "0000000000", "BuyerName": "蕭XX",
   "ProductItem": [{ "OriginalInvoiceDate": 20210520, "OriginalInvoiceNumber": "NW93016392",
                     "OriginalDescription": "超聲波清洗機", "Quantity": 2, "UnitPrice": "2180",
                     "Amount": "4360", "Tax": 218, "TaxType": 1 }],
   "TaxAmount": "218", "TotalAmount": "4360" }]
```

### 5.4 `g0501`

`data` is an array of `{ CancelAllowanceNumber }` `[doc]`. The response has only `code` and `msg`.

### 5.5 `invoice_query`

Request: `{ "type": "order", "order_id": … }` or `{ "type": "invoice", "invoice_number": … }` `[doc]`.

Response `data`:

| Field | Meaning |
| --- | --- |
| `invoice_number`, `invoice_date` (`YYYYMMDD`), `invoice_time` (`HH:mm:ss`) | Invoice |
| `invoice_type`, `invoice_status` | See 4.4 and 6.3 |
| `order_id` | Order id |
| `buyer_identifier`, `buyer_name`, `buyer_zip`, `buyer_address`, `buyer_telephone_number`, `buyer_email_address` | Buyer |
| `sales_amount`, `free_tax_sales_amount`, `zero_tax_sales_amount`, `tax_type`, `tax_rate`, `tax_amount`, `total_amount` | MIG totals |
| `print_mark`, `random_number`, `main_remark`, `customs_clearance_mark` (`0` when not zero rated) | |
| `carrier_type`, `carrier_id1`, `carrier_id2`, `npoban` | |
| `cancel_date` | Void time, Unix time |
| `invoice_lottery` | Prize code (see `lottery_type`) |
| `detail_vat`, `detail_amount_round`, `create_date` | |
| `product_item` | `tax_type`, `description`, `unit_price`, `quantity`, `unit`, `amount`, `remark` |
| `wait` | Queued changes: `invoice_type`, `create_date` |
| `allowance` | `invoice_type`, `invoice_status`, `allowance_type`, `allowance_number`, `allowance_date`, `tax_amount`, `total_amount` |

Example from the docs (one item, with a queued void):

```json
{ "code": 0, "msg": "", "data": {
  "invoice_number": "AA12301393", "invoice_type": "C0401", "invoice_status": 31,
  "invoice_date": "20221201", "invoice_time": "09:56:38",
  "buyer_identifier": "0000000000", "buyer_name": "客人",
  "sales_amount": 100, "free_tax_sales_amount": 0, "zero_tax_sales_amount": 0,
  "tax_type": 1, "tax_rate": "0.05", "tax_amount": 0, "total_amount": 100,
  "print_mark": "Y", "random_number": "2729", "order_id": "P202212010001",
  "detail_vat": 1, "detail_amount_round": 0, "create_date": 1669859798,
  "product_item": [{ "tax_type": 1, "description": "紅利儲值", "unit_price": 100, "quantity": 1,
                     "unit": "", "amount": 100, "remark": "" }],
  "wait": [{ "invoice_type": "C0501", "create_date": 1670486981 }] } }
```

## 6. Codes

### 6.1 Tax type

The MIG codes: `1` taxable, `2` zero rated, `3` tax free, `4` special rate, `9` mixed.

| Unified | Amego |
| --- | --- |
| `TAXABLE` | `1` |
| `ZERO_RATED` | `2` |
| `TAX_FREE` | `3` |
| `SPECIAL` | `4` (header only. Items take `1` to `3`) |
| (mixed, derived) | `9` |

### 6.2 Carrier type

| Unified | `CarrierType` | `CarrierId1` and `CarrierId2` | Rule |
| --- | --- | --- | --- |
| `MOBILE_BARCODE` | `3J0002` | Mobile barcode | `^\/[0-9A-Z\+\-\.]{7}$` `[info 74]` |
| `CITIZEN_CERTIFICATE` | `CQ0001` | Citizen certificate | `^TP[0-9]{14}$` `[info 74]` |
| `MEMBER` | `amego` | `a` + mobile number | `^a09[0-9]{8}$` `[info 73]` |
| `MEMBER` | `amego` | Email | An email address |
| (none) | `amego` | Shopee account | `^shopee_[A-Za-z0-9_\.]{5,30}$` |
| (none) | `amego` | Ruten account | `^ruten_[a-z0-9_\-]{4,24}$` |
| (none) | `amego` | Yahoo auction id | `^yahoo_[Yy][0-9]{10}$` |
| (none) | `amego` | 8591 buyer id | `^8591_\d{5,7}$` |

The visible and hidden codes must match `[info 71: codes 3040131, 3040133]`. An email in the carrier does not trigger a notice email `[doc]`.

### 6.3 Upload status

`1` waiting, `2` uploading, `3` uploaded, `31` processing, `32` done and waiting for confirm, `91` error, `99` done. `-1` with type `NOT_FOUND` means no such invoice `[doc]`.

### 6.4 Error codes

`[info 71]`. The unified error and `Reason` columns are the mapping. Code `15` and `71` were seen live. An unknown invoice in a query or a void, and an unknown allowance in a void, all gave `NotFoundError` `[live]`.

**Default class.** A code outside the tables is a `ProviderError`. Amego's code list is complete for the common codes, and its field errors have their own ranges, so an unknown code is more likely a server problem than a bad field.

Common codes:

| Code | Meaning | Unified error | `Reason` |
| --- | --- | --- | --- |
| `0` | Success | | |
| `10` | System maintenance | `ProviderError` | |
| `11`, `12` | `invoice` (統一編號) empty or wrong | `AuthError` | `CREDENTIALS_INVALID` |
| `13` | Status not active | `AuthError` | `NOT_ENROLLED` |
| `14` | IP not allowed | `AuthError` | `IP_BLOCKED` |
| `15` | `time` out of range | `ValidationError` | `STALE_TIMESTAMP` |
| `16` | Signature wrong | `AuthError` | `CREDENTIALS_INVALID` |
| `17` | Data empty | `ValidationError` | |
| `18` | Database connection failed | `ProviderError` | |
| `19` | Company suspended | `AuthError` | `ACCOUNT_SUSPENDED` |
| `20` | `data` is not JSON | `ValidationError` | |
| `21` | Too many users, try later | `ProviderError` | `RATE_LIMITED` |
| `22` | API access not applied for | `AuthError` | `NOT_ENROLLED` |
| `23` | This API takes an array | `ValidationError` | |
| `51` | Past the 180-day query limit | `ProviderError` | |
| `71` | Not found | `NotFoundError` | |
| `99` | Other error, with a message | `ProviderError` | |

`f0401` codes are `3040xxx`. The other `30401xx` codes are field format errors: `ValidationError`.

| Code | Meaning | Unified error | `Reason` |
| --- | --- | --- | --- |
| `3040111` | No numbers left in the track (字軌不足) | `NumberExhaustedError` | |
| `3040131`, `3040133` | Carrier visible and hidden codes differ | `ValidationError` | |
| `3040132` | Carrier does not exist | `ValidationError` | `CARRIER_NOT_REGISTERED` |
| `3040136`, `3040137` | Donation code wrong format, or does not exist | `ValidationError` | |
| `3040162` | Tax excluded prices are only for B2B | `ValidationError` | |
| `3040171` | Duplicate `OrderId` (also during a cancel and reissue) | `ConflictError` | `DUPLICATE_ORDER` |
| `3040172` to `3040178` | An amount or total does not add up | `ValidationError` | |
| `3040179` | Clearance mark missing for zero rate | `ValidationError` | |
| `3040191` | Cannot get the next number | `NumberExhaustedError` | |

`f0501` codes:

| Code | Meaning | Unified error | `Reason` |
| --- | --- | --- | --- |
| `3050111` | Invoice number wrong | `ValidationError` | |
| `3050113` | Reason longer than 20 | `ValidationError` | |
| `3050121` | Invoice is still being issued | `ConflictError` | `RETRY_LATER` |
| `3050122` | Already voided | `ConflictError` | `ALREADY_VOIDED` |
| `3050123` | Already cancelled | `ConflictError` | |
| `3050125` | Invoice does not exist | `NotFoundError` | |
| `3050126` | Past the time limit for changes | `ConflictError` | `PAST_DEADLINE` |
| `3050131` | Waiting for a queued issue, void or cancel | `ConflictError` | `RETRY_LATER` |
| `3050141` | Invoice has an allowance | `ConflictError` | `VOID_BLOCKED_BY_ALLOWANCE` |

`g0401` codes are `4040xxx`:

| Code | Meaning | Unified error | `Reason` |
| --- | --- | --- | --- |
| `4040145` | `AllowanceType` `1` not allowed | `ValidationError` | |
| `4040151` | Wrong original invoice date | `ValidationError` | |
| `4040153` | Original invoice voided | `ConflictError` | `ALLOWANCE_BLOCKED_BY_VOID` |
| `4040154` | Original invoice cancelled | `ConflictError` | |
| `4040156` | Original invoice does not exist | `NotFoundError` | |
| `4040157` | Buyer 統一編號 differs from the invoice | `ValidationError` | |
| `4040161` | Allowance number already used | `ConflictError` | `DUPLICATE_ALLOWANCE` |
| `4040171`, `4040173` | Allowance more than the invoice total | `ValidationError` | |

`g0501` codes:

| Code | Meaning | Unified error | `Reason` |
| --- | --- | --- | --- |
| `4050132` | Already voided | `ConflictError` | `ALREADY_VOIDED` |
| `4050134` | Allowance does not exist | `NotFoundError` | |
| `4050135` | Past the time limit | `ConflictError` | `PAST_DEADLINE` |
| `4050141` | Waiting for a queued change | `ConflictError` | `RETRY_LATER` |

`barcode` codes: `9000111` empty, `9000112` wrong format, `9000113` does not exist. For a carrier check, `9000113` means "not registered", not an error.

## 7. Open questions

1. Which MIG message does `invoice_modify` send? A change after upload sounds like F0701 and a new F0401. The MIG warns against that for content errors.
2. How long can an invoice be voided? Code `3050126` says there is a limit, but the docs do not give it.
3. `f0401` has no `Currency` or `ExchangeRate`, but `f0401_custom` has both. Does `f0401` accept them anyway?
4. The query lists the item `remark` as max 40, the issue API as max 120. Which is right?
5. Amego's citizen certificate rule is `^TP[0-9]{14}$`. ECPay's is "2 capital letters and 14 digits", and the core checks that. The MIG gives no format. Does Amego reject other letters?
6. When an array call has several entries and one fails, do the others succeed? Until we know, send one entry per call.
7. The live spec checked the main paths only. It did not check zero rate, mixed tax, carriers or a decimal quantity.
8. A space in the payload works when sent as `%20`, and the `sign` over the raw JSON still passes `[live]`. We did not test `+`, so we do not know which PHP decoder Amego uses.
