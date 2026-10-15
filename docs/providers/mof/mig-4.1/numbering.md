# MIG 4.1: number range messages

English | [繁體中文](numbering.zh-TW.md)

The messages about invoice number ranges (字軌配號): E0401, E0402 and E0501. Sources and tags are in [README.md](README.md). Types and code lists are in [codes.md](codes.md).

"M" means required, "O" means optional.

## How numbers are given out

The MOF gives each business a set of invoice number ranges for each two-month period. A range has a two-letter track (字軌), for example `AB`, and a start and an end number. Numbers come in booklets (本) of 50.

- The business downloads its ranges as E0501.
- A head office that shares ranges with its branches uploads the split as E0401.
- Before the 10th of the next period, the business uploads the numbers it did not use as E0402.

A business can let a value-added center send or receive these messages for it. Providers that manage numbers for their merchants (for example a "字軌設定" API) work on top of these messages.

## E0401: branch number ranges

The head office uploads how it split a range among its branches `[mig 第貳拾章, 表 20-1, 20-3, 20-5]`. Numbers that the head office keeps belong to the head office, so it uploads those as well, with its own BAN as `BranchBan`.

If the platform gets the same range in `Main` again, it removes all earlier branch data for that range and keeps the new data.

Header (`BranchTrack/Main`):

| Field | M/O | Rule |
| --- | --- | --- |
| `HeadBan` | M | Head office BAN |
| `BranchBan` | M | Branch BAN. The head office BAN for the part it keeps |
| `InvoiceType` | M | `07` / `08` |
| `YearMonth` | M | Period ([codes](codes.md#invoice-period-yearmonth)) |
| `InvoiceTrack` | M | Two capital letters |
| `InvoiceBeginNo` | M | 8 digits, ends in `00` or `50`. Must match the MOF range |
| `InvoiceEndNo` | M | 8 digits, ends in `49` or `99`. Must match the MOF range |

Items (`BranchTrack/Details/BranchTrackItem`), 1 to 25000:

| Field | M/O | Rule |
| --- | --- | --- |
| `InvoiceBeginNo` | M | 8 digits |
| `InvoiceEndNo` | M | 8 digits |
| `InvoiceBooklet` | M | Number of booklets |

## E0402: unused numbers

The business, or a value-added center for it, uploads the numbers it did not use, through Turnkey, before the 10th of the next period `[mig 第貳拾壹章, 表 21-1, 21-3, 21-5]`.

Upload rules:

- Ranges inside one upload must not overlap. If they do, the platform rejects the whole upload.
- If a new upload overlaps a range the platform already has, the platform removes the old range and keeps the new one. Ranges that do not overlap stay.
- To move a wrong range, upload a range that covers both the wrong range and the right one, and then upload the right one. Or delete the wrong range on the MOF website.

Header (`BranchTrackBlank/Main`): `HeadBan`, `BranchBan`, `InvoiceType`, `YearMonth` and `InvoiceTrack`, all required, with the same rules as E0401.

Items (`BranchTrackBlank/Details/BranchTrackBlankItem`), 1 to 10000: `InvoiceBeginNo` and `InvoiceEndNo`, 8 digits each, both required.

## E0501: assigned number ranges

The business, or a value-added center for it, downloads the ranges that the MOF assigned `[mig 第貳拾貳章, 表 22-1]`. All fields under `InvoiceAssignNo` are required:

| Field | Rule |
| --- | --- |
| `Ban` | The business BAN |
| `InvoiceType` | `07` / `08` |
| `YearMonth` | Period |
| `InvoiceTrack` | Two capital letters |
| `InvoiceBeginNo` | 8 digits |
| `InvoiceEndNo` | 8 digits |
| `InvoiceBooklet` | Number of booklets |
