# MIG 4.1: platform files and replies

English | [繁體中文](platform.zh-TW.md)

The files that the MOF platform sends back: E0502, E0503 and E0504, and the replies ProcessResult and SummaryResult. Sources and tags are in [README.md](README.md). Types and code lists are in [codes.md](codes.md).

"M" means required, "O" means optional.

## E0502: purchase invoices

A buyer, or a value-added center for it, downloads the invoices that sellers issued to it (進項存證發票) `[mig 第貳拾參章, 表 23-1, 23-2]`.

The structure is F0401 with these changes:

- `Main` adds `CurrentStatus`, the invoice status on the platform ([codes](codes.md#invoice-status-currentstatus)).
- `Main` has `SellerId`, `SellerName`, `BuyerId` and `BuyerName` instead of the full `Seller` and `Buyer` roles.
- `Details` and `Amount` are optional.
- Three optional blocks show what happened to the invoice:

| Block | When it has data | Fields |
| --- | --- | --- |
| `Cancel` | The invoice is voided (作廢) | `CancelDate`, `CancelTime`, `CancelReason`, `ReturnTaxDocumentNumber`, `CancelRemark`, `Reserved1`, `Reserved2` |
| `Reject` | The buyer rejected it (退回) | `RejectDate`, `RejectTime`, `RejectReason`, `RejectRemark`, `Reserved1`, `Reserved2` |
| `Void` | The invoice record is cancelled (註銷) | `VoidDate`, `VoidTime`, `VoidReason` (max 20), `VoidRemark` (max 200), `Reserved1`, `Reserved2` |

## E0503: purchase allowances

A buyer downloads the allowances that sellers issued to it `[mig 第貳拾肆章, 表 24-1, 24-3]`. The structure is G0401 with these changes:

- `Main` adds `CurrentStatus` ([codes](codes.md#allowance-status-currentstatus)).
- `Main` has `SellerId`, `SellerName`, `BuyerId` and `BuyerName` instead of the full roles.
- `Details` and `Amount` stay required.
- Two optional blocks: `Cancel` (`CancelDate`, `CancelTime`, `CancelReason`, `CancelRemark`) when the allowance is voided, and `Void` (`VoidDate`, `VoidTime`, `VoidReason`, `VoidRemark`) when its record is cancelled. There is no `Reject` block.

## E0504: prize list

A business, or a value-added center for it, downloads the list of its invoices that won the invoice lottery (中獎清冊) `[mig 第貳拾伍章, 表 25-1, 25-3, 25-5]`.

Header (`Award/Main`), all required:

| Field | Rule |
| --- | --- |
| `HeadBan` | Head office BAN |
| `YearMonth` | Period |
| `AwardListType` | `A` member carrier, `Y` printed on paper, `Z` batch transfer, `X` member carrier linked before the draw |
| `TotalRecordCnt` | Number of items |
| `TotalPrizeAmount` | Total prize money |
| `RecAwardBegin`, `RecAwardEnd` | Claim period, `YYYMMDD` in the ROC calendar (民國) |

Items (`Award/Details/PrizeInvoice`), 1 to 9999:

| Field | M/O | Rule |
| --- | --- | --- |
| `InvTrack` | M | Track, 2 chars |
| `InvoiceNumber` | M | Invoice number |
| `InvoiceDate` | M | `yyyyMMdd` |
| `InvoiceTime` | O | `xsd:time` |
| `Seller` | M | Role |
| `BuyerId` | M | BAN |
| `TotalAmount` | M | Invoice total |
| `CarrierType`, `CarrierTypeName`, `CarrierId1`, `CarrierId2` | O | Carrier details |
| `RandomNumber` | O | Optional since V4.1 (2025-10-29) |
| `PrizeType` | M | 1 char. The MIG does not list the values |
| `PrizeAmount` | M | Prize money |
| `DepositMark` | M | `Y` / `N`: paid to a bank account |
| `RedeemDataType` | M | How the prize is claimed. `A` member carrier, `B` other carrier, `C` and `D` utility member carriers, `E` e-payment account, `F` back to the credit or debit card, `X` donated, `Y` paper invoice with no carrier |
| `PrizeDataSource` | M | `10` storage, `40` B2B exchange |
| `PrintType` | M | `T7` general tax invoice, `T8` special tax invoice |

## ProcessResult

The platform's reply to an upload `[mig 第貳拾陸章, 表 26-1 to 26-6]`.

| Part | Fields |
| --- | --- |
| `RoutingInfo` | `From`, `FromVAC`, `To`, `ToVAC`: the sender and receiver BANs and their routing codes |
| `MessageInfo` | `Id`, `Size`, `MessageType` (for example `F0401`), `Service` (`E` exchange, `S` storage), `Action` (`B2B`, `B2C`, `B2S`) |
| `Result/Info` | 1 to 10000 results. Each has a required `Code`, an optional `Description`, and optional `Parameter0` to `Parameter4` |

The MIG does not list the result codes.

## SummaryResult

A daily summary of the uploads from the day before `[mig 第貳拾柒章, 表 27-1 to 27-5]`. `RoutingInfo` as above, and a `DetailList` of 1 to 5000 `Message` entries. Each entry has an `Info` (the same fields as `MessageInfo`) and a `ResultType`.

`ResultType` has `Total`, `Good` and `Failed`. Each one has a `Count` and a list of invoices, each with a `ReferenceNumber` and a date `[mig 表 4-26 to 4-30]`.
