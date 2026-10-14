# Amego 光貿: 電子發票 API

## 1. Status and sources

This is Amego's JSON API at `https://invoice-api.amego.tw`. The 2.x line has no adapter for it yet. Nothing here is verified against the live API.

The API follows the MIG closely. Its endpoints are named after MIG messages (`f0401`, `f0501`, `g0401`, `g0501`), and most fields carry MIG names.

| Tag | Source | Date | What it gives |
| --- | --- | --- | --- |
| `[doc]` | Amego API docs, <https://invoice.amego.tw/api_doc/>. An apiDoc site. We read the data bundle (`main.bundle.js?2026093003`) on 2026-10-14. | Generated 2026-09-30, doc version 1.0.0 | All endpoints, fields, examples, and the basic rules. |
| `[info]` | Amego help pages. The docs link to them: <https://invoice.amego.tw/info_detail?mid=70> (issue modes), `mid=71` (error codes), `mid=73` (member carrier rules), `mid=74` (checks). Read on 2026-10-14. | | Error codes and format rules. |

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
| `sign` | String | `md5(data + time + AppKey)`, where `data` is the JSON string |

Amego URL decodes the POST data once on its side. `/json/time` returns the server time, to fix clock drift.

Some APIs take an array in `data`, for example `f0501` and `g0401`. Others take one object, for example `f0401` `[info 71: codes 23, 3040112]`.

### 2.3 Response

JSON. `code` `0` means success. Other codes are errors (6.4). `msg` has the message `[doc]`.

### 2.4 MIG 4.0 paths

From 2025-01-01 Amego uses MIG 4.0. The old paths still work `[doc]`:

| Old | New |
| --- | --- |
| `/json/c0401` | `/json/f0401` |
| `/json/c0501` | `/json/f0501` |
| `/json/d0401` | `/json/g0401` |
| `/json/d0501` | `/json/g0501` |
| `/json/c0401_custom` | `/json/f0401_custom` |

## 3. Operations

| Group | Endpoint | Purpose |
| --- | --- | --- |
| Invoice | `/json/f0401` | Issue an invoice. Amego picks the number (自動配號) |
| | `/json/f0501` | Void invoices (array) |
| | `/json/invoice_query` | One invoice, by order id or number, within 180 days |
| | `/json/invoice_status` | Upload status of invoices (array) |
| | `/json/invoice_list` | Invoices in a date range, paged (20 to 500 per page) |
| | `/json/invoice_file` | Download an invoice file |
| | `/json/invoice_print` | Print data for a thermal printer |
| | `/json/invoice_modify` | Change an issued invoice (see below) |
| Allowance | `/json/g0401` | Issue allowances (array) |
| | `/json/g0501` | Void allowances (array) |
| | `/json/allowance_query` | One allowance |
| | `/json/allowance_status` | Upload status of allowances (array) |
| | `/json/allowance_list` | Allowances in a date range |
| | `/json/allowance_file`, `/json/allowance_print` | File and print data |
| Lottery | `/json/lottery_status` | Winning invoices for a period |
| | `/json/lottery_type` | Prize codes |
| Other | `/json/barcode` | Is a mobile barcode registered |
| | `/json/ban_query` | Company name for a 統一編號 |
| | `/json/track_all` | All tracks for a period |
| | `/json/time` | Server time |
| Own numbers | `/json/track_get` | Take a number range (API 配號 tracks only) |
| | `/json/track_status` | Track status |
| | `/json/f0401_custom` | Issue with the seller's own number, date, time and random code |

There are two ways to number invoices `[info 70]`:

- **自動配號**: the seller sends the invoice, and Amego returns the number, date and random code. Use `f0401`.
- **API 配號**: the seller takes a range with `track_get`, and sends its own number, date, time and random code with `f0401_custom`. This suits a POS that prints offline.

A track is set to one mode in the back office (發票作業 > 發票字軌列表).

`invoice_modify` changes an invoice that `f0401` issued. It works only within 180 days, after the upload, and not for a printed B2C invoice, a special tax invoice, or an invoice with an allowance `[info 71: codes 43 to 50]`. The docs do not say which MIG message it sends.

## 4. Mapping to the unified API

| Unified | Amego | Note |
| --- | --- | --- |
| `issue` | `f0401` | The caller sends all MIG totals (see below) |
| `void` | `f0501` | Invoice number only. No invoice date needed |
| `allowance` | `g0401` | The seller picks the allowance number. Amounts exclude tax. Each item needs the original invoice date |
| `void_allowance` | `g0501` | Allowance number only |
| `query` by order id | `invoice_query`, `type: order` | Within 180 days |
| `query` by number | `invoice_query`, `type: invoice` | Within 180 days |

### Against the MIG

- **Totals are the MIG totals.** `f0401` takes `SalesAmount`, `FreeTaxSalesAmount`, `ZeroTaxSalesAmount`, `TaxType`, `TaxRate`, `TaxAmount` and `TotalAmount`, all required, as in F0401. The adapter must compute them.
- **Allowances are MIG G0401.** The seller assigns `AllowanceNumber` (max 16, unique). `AllowanceDate` is required. Amounts exclude tax, and each item has its own `Tax`. Each item needs `OriginalInvoiceNumber` and `OriginalInvoiceDate`. So the unified `allowance_id` can be the allowance number, and the adapter needs the original invoice date.
- **Voids need less than the MIG.** `f0501` takes only the number and an optional reason. `g0501` takes only the allowance number. Amego must fill the dates and the reason from its records, because F0501 and G0501 require them (inferred).
- **`AllowanceType` must be `2`.** Since 2025-01-01 Amego rejects `1` `[info 71: code 4040145]`.
- **One invoice per allowance.** An allowance can only credit one invoice `[info 71: codes 4040132, 4040133]`. The MIG allows items from several invoices.
- **`Description` is max 256** `[doc]`. The MIG allows 500.
- **B2B is storage (inferred).** `f0401` takes a 統一編號 together with carrier fields and mixed tax, which A0101 does not allow. The query can still report exchange types (A0101 to A0302), so some invoices in Amego may come from exchange.

### Status

`invoice_query` reports two things `[doc]`:

- `invoice_type`: the last MIG message for the invoice. It uses the **pre-4.0 names**: `C0401` issued, `C0501` voided, `C0701` cancelled, `A0401` and `A0501` for B2B storage, and `A0101` to `A0302` for B2B exchange.
- `invoice_status`: the upload status. `1` waiting, `2` uploading, `3` uploaded, `31` processing, `32` done and waiting for confirm, `91` error, `99` done.

`wait` lists changes still in the queue, for example a void that is not processed yet. `allowance` lists the invoice's allowances, each with its own type and status (added 2024-10-24).

So the unified status maps like this (inferred):

| `invoice_type` | Unified `InvoiceStatus` |
| --- | --- |
| `C0401`, `A0401`, `A0101`, `A0102` | `issued`, or `allowance` when `allowance` has an active entry |
| `C0501`, `A0501`, `A0201`, `A0202` | `voided` |
| `C0701` | cancelled: no unified status |
| `A0301`, `A0302` | rejected: no unified status |

## 5. Field reference

### 5.1 `f0401`

`data` is one object `[doc]`. "Req" means required.

| Field | Rule |
| --- | --- |
| `OrderId` | Req, max 40, unique |
| `TrackApiCode` | Pick a track by its API code (set in the back office). Without it, Amego uses the track order in the back office |
| `BuyerIdentifier` | Req. 統一編號, or `0000000000` for a consumer |
| `BuyerName` | Req. For a consumer, any name (客人, 消費者). For a business, the company name, or the 統一編號 if the name cannot be given. Not `0`, `00`, `000` or `0000` |
| `BuyerAddress`, `BuyerTelephoneNumber` | Optional |
| `BuyerEmailAddress` | Optional. Amego sends the invoice notice here. Leave empty to send nothing |
| `MainRemark` | max 200 |
| `CarrierType` | `3J0002` mobile barcode, `CQ0001` citizen certificate, `amego` Amego member carrier, or the seller's own member carrier code |
| `CarrierId1`, `CarrierId2` | Visible and hidden code. See 6.2 |
| `NPOBAN` | Donation code |
| `ProductItem` | Req, up to 9999 items |
| `SalesAmount` | Req. Taxable sales total |
| `FreeTaxSalesAmount` | Req. Tax free sales total |
| `ZeroTaxSalesAmount` | Req. Zero rated sales total |
| `TaxType` | Req. `1`, `2`, `3`, `4`, `9` |
| `TaxRate` | Req. `0.05` for 5% |
| `TaxAmount` | Req. Only a B2B invoice splits out the tax. B2C always sends `0` |
| `TotalAmount` | Req |
| `CustomsClearanceMark` | `1` / `2`. Req for zero rated |
| `ZeroTaxRateReason` | `71` to `79`. Req for zero rated |
| `BrandName` | Optional brand name |
| `DetailVat` | `1` item prices include tax (default), `0` exclude tax. `0` is only allowed for B2B |
| `DetailAmountRound` | `0` keep 7 decimals in item amounts (default), `1` round each to an integer |
| `TaxAdjustment` | `1` lowers the tax by 1. Only for B2B with `DetailVat` `0`, when `SalesAmount` ends in 10, 30, 50, 70 or 90 |
| `PrinterType`, `PrinterLang`, `PrintDetail` | Thermal printer output |

Item fields:

| Field | Rule |
| --- | --- |
| `Description` | Req, max 256 |
| `Quantity` | Req, up to 7 decimals |
| `Unit` | max 6 |
| `UnitPrice` | Req, up to 7 decimals. Tax included unless `DetailVat` is `0` |
| `Amount` | Req, up to 7 decimals |
| `Remark` | max 120 |
| `TaxType` | Req. `1`, `2`, `3` |

How to compute the totals `[doc]`. With prices that include tax (`DetailVat` `1`):

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

Response: `invoice_number`, `invoice_time` (Unix time), `random_number`, `barcode`, `qrcode_left`, `qrcode_right`, and `base64_data` for a printer.

### 5.2 `f0501`

`data` is an array of `{ CancelInvoiceNumber, CancelReason }`. `CancelReason` is optional, max 20 `[doc]`.

### 5.3 `g0401`

`data` is an array of allowances `[doc]`:

| Field | Rule |
| --- | --- |
| `AllowanceNumber` | Req, max 16, unique |
| `AllowanceDate` | Req, `Ymd` |
| `AllowanceType` | Req, `2` |
| `BuyerIdentifier` | Req. Must match the original invoice |
| `BuyerName` | Req |
| `BuyerAddress`, `BuyerTelephoneNumber`, `BuyerEmailAddress` | Optional |
| `ProductItem` | Req, up to 9999 |
| `TaxAmount` | Req |
| `TotalAmount` | Req, tax excluded |

Items: `OriginalInvoiceNumber`, `OriginalInvoiceDate` (`Ymd`), `OriginalDescription` (max 256), `Quantity`, `UnitPrice` (tax excluded), `Amount` (tax excluded), `Tax` (integer) and `TaxType` are all required.

The allowance total, alone or with other allowances on the same invoice, must not exceed the invoice total `[info 71: codes 4040171, 4040173]`.

### 5.4 `g0501`

`data` is an array of `{ CancelAllowanceNumber }` `[doc]`.

### 5.5 `invoice_query`

Request: `{ type: "order", order_id }` or `{ type: "invoice", invoice_number }` `[doc]`.

Response `data`:

| Field | Meaning |
| --- | --- |
| `invoice_number`, `invoice_date` (`YYYYMMDD`), `invoice_time` (`HH:mm:ss`) | Invoice |
| `invoice_type`, `invoice_status` | See 4 |
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

## 6. Codes

### 6.1 Tax type

The MIG codes: `1` taxable, `2` zero rated, `3` tax free, `4` special rate, `9` mixed.

### 6.2 Carrier type

| `CarrierType` | `CarrierId1` and `CarrierId2` | Rule |
| --- | --- | --- |
| `3J0002` | Mobile barcode | `^\/[0-9A-Z\+\-\.]{7}$` `[info 74]` |
| `CQ0001` | Citizen certificate | `^TP[0-9]{14}$` `[info 74]` |
| `amego` | `a` + mobile number | `^a09[0-9]{8}$` `[info 73]` |
| `amego` | Email | An email address |
| `amego` | Shopee account | `^shopee_[A-Za-z0-9_\.]{5,30}$` |
| `amego` | Ruten account | `^ruten_[a-z0-9_\-]{4,24}$` |
| `amego` | Yahoo auction id | `^yahoo_[Yy][0-9]{10}$` |
| `amego` | 8591 buyer id | `^8591_\d{5,7}$` |

The visible and hidden codes must match `[info 71: codes 3040131, 3040133]`. An email in the carrier does not trigger a notice email `[doc]`.

### 6.3 Upload status

`1` waiting, `2` uploading, `3` uploaded, `31` processing, `32` done and waiting for confirm, `91` error, `99` done. `-1` with type `NOT_FOUND` means no such invoice `[doc]`.

### 6.4 Error codes

`[info 71]`. Common codes:

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `10` | System maintenance |
| `11`, `12` | `invoice` (統一編號) empty or wrong |
| `13` | Status not active |
| `14` | IP not allowed |
| `15` | `time` out of range |
| `16` | Signature wrong |
| `17` | Data empty |
| `18` | Database connection failed |
| `19` | Company suspended |
| `20` | `data` is not JSON |
| `21` | Too many users, try later |
| `22` | API access not applied for |
| `23` | This API takes an array |

`f0401` codes are `3040xxx`. The ones an adapter needs to tell apart:

| Code | Meaning |
| --- | --- |
| `3040111` | No numbers left in the track (字軌不足) |
| `3040131`, `3040133` | Carrier visible and hidden codes differ |
| `3040132` | Carrier does not exist |
| `3040136`, `3040137` | Donation code wrong format, or does not exist |
| `3040162` | Tax excluded prices are only for B2B |
| `3040171` | Duplicate `OrderId` (also during a cancel and reissue) |
| `3040172` to `3040178` | An amount or total does not add up |
| `3040179` | Clearance mark missing for zero rate |
| `3040191` | Cannot get the next number |

The other `30401xx` codes are field format errors.

`f0501` codes:

| Code | Meaning |
| --- | --- |
| `3050111` | Invoice number wrong |
| `3050113` | Reason longer than 20 |
| `3050121` | Invoice is still being issued |
| `3050122` | Already voided |
| `3050123` | Already cancelled |
| `3050125` | Invoice does not exist |
| `3050126` | Past the time limit for changes |
| `3050131` | Waiting for a queued issue, void or cancel |
| `3050141` | Invoice has an allowance |

`g0401` codes are `4040xxx`. Important ones: `4040145` (`AllowanceType` `1` not allowed), `4040151` (wrong original invoice date), `4040153` (original invoice voided), `4040154` (original invoice cancelled), `4040156` (original invoice does not exist), `4040157` (buyer 統一編號 differs from the invoice), `4040161` (allowance number already used), `4040171`, `4040173` (allowance more than the invoice total).

`g0501` codes: `4050132` (already voided), `4050134` (allowance does not exist), `4050135` (past the time limit), `4050141` (waiting for a queued change).

Query codes: `51` (past the 180-day query limit), `71` (not found). `barcode` codes: `9000111` empty, `9000112` wrong format, `9000113` does not exist. Many other APIs return `99` with a message.

## 7. Open questions

1. Which MIG message does `invoice_modify` send? A change after upload sounds like F0701 and a new F0401. The MIG warns against that for content errors.
2. How long can an invoice be voided? Code `3050126` says there is a limit, but the docs do not give it.
3. `f0401` has no `Currency` or `ExchangeRate`, but `f0401_custom` has both. Does `f0401` accept them anyway?
4. The query lists the item `remark` as max 40, the issue API as max 120. Which is right?
5. Amego's citizen certificate rule is `^TP[0-9]{14}$`. ECPay's is "2 capital letters and 14 digits". The MIG gives no format. Which is right?
6. None of this is verified live. The public test account can do that.
