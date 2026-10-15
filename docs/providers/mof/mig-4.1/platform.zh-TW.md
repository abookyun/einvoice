# MIG 4.1：平台檔案與回應

[English](platform.md) | 繁體中文

> 本文譯自英文版。兩者不一致時，以英文版為準。

財政部平台回傳的檔案：E0502、E0503 和 E0504，以及平台回應 ProcessResult 和 SummaryResult。來源和標記見 [README.zh-TW.md](README.zh-TW.md)。型別與代碼表見 [codes.zh-TW.md](codes.zh-TW.md)。

「M」表示必填，「O」表示選填。

## E0502：進項存證發票

買方或代為處理的加值中心，下載賣方開給它的發票（進項存證發票）`[mig 第貳拾參章, 表 23-1, 23-2]`。

結構是 F0401 加上下列變更：

- `Main` 加上 `CurrentStatus`，也就是發票在平台上的狀態（[codes](codes.zh-TW.md#發票狀態-currentstatus)）。
- `Main` 用 `SellerId`、`SellerName`、`BuyerId` 和 `BuyerName`，取代完整的 `Seller` 和 `Buyer` 角色。
- `Details` 和 `Amount` 改成選填。
- 另外有三個選填區塊，顯示這張發票後來發生了什麼事：

| 區塊 | 什麼時候有資料 | 欄位 |
| --- | --- | --- |
| `Cancel` | 發票已作廢 | `CancelDate`、`CancelTime`、`CancelReason`、`ReturnTaxDocumentNumber`、`CancelRemark`、`Reserved1`、`Reserved2` |
| `Reject` | 買方已退回 | `RejectDate`、`RejectTime`、`RejectReason`、`RejectRemark`、`Reserved1`、`Reserved2` |
| `Void` | 發票已註銷 | `VoidDate`、`VoidTime`、`VoidReason`（最多 20）、`VoidRemark`（最多 200）、`Reserved1`、`Reserved2` |

## E0503：進項存證折讓單

買方下載賣方開給它的折讓 `[mig 第貳拾肆章, 表 24-1, 24-3]`。結構是 G0401 加上下列變更：

- `Main` 加上 `CurrentStatus`（[codes](codes.zh-TW.md#折讓狀態-currentstatus)）。
- `Main` 用 `SellerId`、`SellerName`、`BuyerId` 和 `BuyerName`，取代完整的角色。
- `Details` 和 `Amount` 維持必填。
- 兩個選填區塊：折讓作廢時的 `Cancel`（`CancelDate`、`CancelTime`、`CancelReason`、`CancelRemark`），以及折讓註銷時的 `Void`（`VoidDate`、`VoidTime`、`VoidReason`、`VoidRemark`）。沒有 `Reject` 區塊。

## E0504：中獎清冊

營業人或代為處理的加值中心，下載自己開立的發票中，統一發票兌獎中獎的清單（中獎清冊）`[mig 第貳拾伍章, 表 25-1, 25-3, 25-5]`。

表頭（`Award/Main`），全部必填：

| 欄位 | 規則 |
| --- | --- |
| `HeadBan` | 總機構 BAN |
| `YearMonth` | 期別 |
| `AwardListType` | `A` 會員載具、`Y` 紙本列印、`Z` 批次轉檔、`X` 開獎前已歸戶的會員載具 |
| `TotalRecordCnt` | 筆數 |
| `TotalPrizeAmount` | 獎金總額 |
| `RecAwardBegin`、`RecAwardEnd` | 領獎期間，民國 `YYYMMDD` |

品項（`Award/Details/PrizeInvoice`），1 到 9999 筆：

| 欄位 | M/O | 規則 |
| --- | --- | --- |
| `InvTrack` | M | 字軌，2 字元 |
| `InvoiceNumber` | M | 發票號碼 |
| `InvoiceDate` | M | `yyyyMMdd` |
| `InvoiceTime` | O | `xsd:time` |
| `Seller` | M | 角色 |
| `BuyerId` | M | BAN |
| `TotalAmount` | M | 發票總額 |
| `CarrierType`、`CarrierTypeName`、`CarrierId1`、`CarrierId2` | O | 載具資料 |
| `RandomNumber` | O | V4.1（2025-10-29）起改為選填 |
| `PrizeType` | M | 1 字元。MIG 沒有列出可能的值 |
| `PrizeAmount` | M | 獎金 |
| `DepositMark` | M | `Y` / `N`：是否匯入銀行帳戶 |
| `RedeemDataType` | M | 領獎方式。`A` 會員載具、`B` 其他載具、`C` 和 `D` 公用事業會員載具、`E` 電子支付帳戶、`F` 退回信用卡或簽帳卡、`X` 已捐贈、`Y` 無載具的紙本發票 |
| `PrizeDataSource` | M | `10` 存證、`40` B2B 交換 |
| `PrintType` | M | `T7` 一般稅額發票、`T8` 特種稅額發票 |

## ProcessResult

平台對上傳的回應 `[mig 第貳拾陸章, 表 26-1 to 26-6]`。

| 部分 | 欄位 |
| --- | --- |
| `RoutingInfo` | `From`、`FromVAC`、`To`、`ToVAC`：發送方和接收方的 BAN，以及它們的路由代碼 |
| `MessageInfo` | `Id`、`Size`、`MessageType`（例如 `F0401`）、`Service`（`E` 交換、`S` 存證）、`Action`（`B2B`、`B2C`、`B2S`） |
| `Result/Info` | 1 到 10000 筆結果。每筆有必填的 `Code`、選填的 `Description`，以及選填的 `Parameter0` 到 `Parameter4` |

MIG 沒有列出結果代碼。

## SummaryResult

前一天所有上傳的每日彙總 `[mig 第貳拾柒章, 表 27-1 to 27-5]`。包含和上面相同的 `RoutingInfo`，以及 1 到 5000 筆 `Message` 組成的 `DetailList`。每筆有一個 `Info`（欄位和 `MessageInfo` 相同）和一個 `ResultType`。

`ResultType` 包含 `Total`、`Good` 和 `Failed`。每一項都有 `Count` 和一份發票清單，清單中每張發票有 `ReferenceNumber` 和日期 `[mig 表 4-26 to 4-30]`。
