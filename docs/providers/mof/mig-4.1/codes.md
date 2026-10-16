# MIG 4.1: shared types and codes

English | [繁體中文](codes.zh-TW.md)

The types and code lists that all MIG messages use (MIG 第肆章). Sources and tags are in [README.md](README.md).

## Seller and buyer (`RoleDescriptionType`)

`[mig 表 4-2]`. "M" means required, "O" means optional.

| Field | M/O | Rule |
| --- | --- | --- |
| `Identifier` | M | BAN. For a consumer buyer, ten `0` |
| `Name` | M | 1 to 60 chars. See below |
| `Address` | O | max 100. Required for the seller in F0401 and G0401 |
| `PersonInCharge` | O | max 30 |
| `TelephoneNumber` | O | max 26 |
| `FacsimileNumber` | O | max 26 |
| `EmailAddress` | O | max 400 |
| `CustomerNumber` | O | max 20 |
| `RoleRemark` | O | 40 |

`Name` for the buyer:

- Business buyer: the company name. If the law lets the buyer skip the name, use the buyer's 統一編號.
- Consumer: a personal ID code (個人識別碼) that lets the consumer check the invoice on the MOF platform. It must not be `0`, `00`, `000` or `0000`. Use one of these:
  1. The consumer's name.
  2. If the invoice is printed, or stored on a carrier that is not a member carrier: the same value as the random code.
  3. If the invoice is stored on a member carrier: a value the seller designs, for example the last four chars of the carrier or the first four chars of the member's email.

## Invoice number (`InvoiceNumberType`)

10 chars, `[A-Z]{2}\d{8}`. Example `QQ12345678` `[mig 表 4-10]`.

## Date and time (`DateType`, `TimeType`)

Date is `yyyyMMdd` in the western calendar, for example `20240101`. Time is `xsd:time`. Both are in UTC+8. The platform ignores any time zone in the data `[mig 表 4-15, 4-16]`.

## Invoice type (`InvoiceTypeEnum`)

| Code | Meaning |
| --- | --- |
| `07` | General tax (一般稅額計算) |
| `08` | Special tax (特種稅額計算) |

## Allowance number (`AllowanceNumberType`)

1 to 16 chars. The seller's system assigns it. The platform rejects a number that was used before, also in an earlier year `[mig 表 4-5]`.

## Allowance type (`AllowanceTypeEnum`)

| Code | Meaning |
| --- | --- |
| `1` | The buyer issues (or voids) the allowance |
| `2` | The seller issues (or voids) the allowance notice |

Since V4.1 the seller issues and voids every allowance, so new allowances use `2` `[mig 表 4-6]`.

## Carrier type (`CarrierTypeEnum`)

6 chars `[mig 表 4-13, 15-3]`:

| Code | Meaning |
| --- | --- |
| `3J0002` | Mobile barcode (手機條碼) |
| `CQ0001` | Citizen certificate (自然人憑證條碼) |
| `5G0001` | Cross-border email carrier (跨境電商電子郵件載具) |
| other | A code the MOF platform gives to a seller or center. Char 1 is the trade, char 2 is the carrier class, chars 3 to 6 are a serial number |

## Tax type and tax rate (`TaxTypeEnum`, `TaxRateEnum`)

Tax type `[mig 表 4-12]`:

| Code | Meaning |
| --- | --- |
| `1` | Taxable (應稅) |
| `2` | Zero rated (零稅率) |
| `3` | Tax free (免稅) |
| `4` | Taxable, special rate (應稅, 特種稅率) |
| `9` | Mixed taxable with tax free or zero rated. F0401 header only |

Tax rate `[mig 表 4-18]`: one of `0`, `0.01`, `0.02`, `0.05`, `0.15`, `0.25`. A 5% rate is `0.05`.

## Zero tax rate reason (`ZeroTaxRateReasonEnum`)

`71` to `79`, one per paragraph of 營業稅法第 7 條 `[mig 表 4-19]`. `71` is export of goods (外銷貨物). Required when the tax type is zero rated.

## Customs clearance (`CustomsClearanceMarkEnum`)

| Code | Meaning |
| --- | --- |
| `1` | Export not through customs (非經海關出口) |
| `2` | Export through customs (經海關出口) |

Required for zero rated invoices `[mig 表 4-9]`.

## Bonded area (`BondedAreaEnum`)

The buyer's mark for a zero rate sale to a bonded area, an ocean fishing business or a free trade zone. `1` to `4`, where `4` is "other" `[mig 表 4-17]`.

## Buyer remark (`BuyerRemarkEnum`)

`1` deductible purchases and expenses, `2` deductible fixed assets, `3` non-deductible purchases and expenses, `4` non-deductible fixed assets `[mig 表 4-8]`.

## BAN

8 to 10 digits, digits only (since V4.1). A business buyer or seller uses its 統一編號. A consumer buyer uses `0000000000` `[mig 表 4-7]`.

## Donation (`DonateMarkEnum`)

`0` not donated, `1` donated `[mig 表 4-11]`. A seller must accept a donation code that the buyer gives at the time of sale. Cross-border sellers (營業稅法第 6 條第 4 款) are the exception.

## Invoice period (`YearMonth`)

5 digits: the ROC year (民國) and the even month that ends the two-month period. `11102` is January and February of ROC 111 (2022). The month is always `02`, `04`, `06`, `08`, `10` or `12` `[mig 表 20-3]`.

## Invoice status (`CurrentStatus`)

The status of an invoice on the MOF platform, as E0502 reports it `[mig 表 23-2]`:

| Code | Meaning |
| --- | --- |
| `1` | Issued, not confirmed (開立未確認) |
| `2` | Issued, confirmed (開立已確認) |
| `3` | Voided, not confirmed (作廢未確認) |
| `4` | Voided, confirmed (作廢已確認) |
| `5` | Rejected, not confirmed (退回未確認) |
| `6` | Rejected, confirmed (退回已確認) |
| `7` | Record cancelled (已註銷) |

"Confirmed" is the other side's confirm message in B2B exchange (see [exchange.md](exchange.md)).

## Allowance status (`CurrentStatus`)

The status of an allowance on the MOF platform, as E0503 reports it `[mig 表 24-3]`:

| Code | Meaning |
| --- | --- |
| `1` | Issued, not confirmed (折讓未確認) |
| `2` | Issued, confirmed (折讓已確認) |
| `3` | Voided, not confirmed (作廢未確認) |
| `4` | Voided, confirmed (作廢已確認) |
| `7` | Record cancelled (已註銷) |

## Currency (`CurrencyCodeEnum`)

ISO 4217 codes `[mig 表 4-14]`.
