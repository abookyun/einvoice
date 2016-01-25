# Neweb Technologies Co., Ltd. 藍新科技電子發票 API 說明

## Overview

### Request

* 由商家申請後,由藍新提供正式主機與測試主機 `hostname` & `code`。
* Request URL："#{hostname} + #{action}"
* 傳送方式：(1) 以 Form Post 方式傳送 (2) UTF-8 編碼
* 參數:
	* `storecode`：商家代碼
	* `xmldata`：URLEncoded XML
	* `hash`：驗證碼 = MD5(urlencoded_xmldata + `code`)
* 範例（以 [httpie](https://github.com/jkbrzt/httpie) 為例）：

```shell
http --form POST ${HOSTNAME}/IN_PreInvoiceS.action storecode=${STORECODE} hash="d537a4807813c36816517b2a32994a35" xmldata="<InvoiceRoot><Invoice><InvoiceItem><Description>item1</Description><Quantity>1</Quantity><UnitPrice>10.0</UnitPrice><Amount>10.0</Amount><SequenceNumber>1</SequenceNumber></InvoiceItem><InvoiceItem><Description>item2</Description><Quantity>1</Quantity><UnitPrice>10.0</UnitPrice><Amount>10.0</Amount><SequenceNumber>2</SequenceNumber><Unit></Unit><Remark></Remark></InvoiceItem><DataNumber>12345</DataNumber><DataDate>2016/01/20</DataDate><SellerId>12345678</SellerId><BuyerName>name</BuyerName><BuyerId>0000000000</BuyerId><CustomsClearanceMark>1</CustomsClearanceMark><InvoiceType>07</InvoiceType><DonateMark>0</DonateMark><CarrierType></CarrierType><CarrierId1></CarrierId1><CarrierId2></CarrierId2><PrintMark>N</PrintMark><NPOBAN></NPOBAN><RandomNumber>AAAA</RandomNumber><SalesAmount>19</SalesAmount><FreeTaxSalesAmount>0</FreeTaxSalesAmount><ZeroTaxSalesAmount>0</ZeroTaxSalesAmount><TaxType>1</TaxType><TaxRate>0.05</TaxRate><TaxAmount>1</TaxAmount><TotalAmount>20</TotalAmount><Contact><Name>name</Name><Address>Taipei City</Address><TEL>0212341234</TEL><Email></Email></Contact></Invoice></InvoiceRoot>"
```

### Response

* 回應結構（各 APIs 略有不同）:
	* Result
		* statcode
		* statdesc
		* data
* 範例：

```xml
<Result>
  <statcode>0000</statcode>
  <statdesc></statdesc>
</Result>
```
* 一般性回應碼與訊息對照表：

statcode | statdesc
---------|---------
0000 | OK
6001 | 某 node 值不符合長度要求
6002 | 某 node 值不符合型別要求（只檢查數型態）
6003 | 某 node 值為必填，卻發生空值或是 node 不存在
7001 | Xmldata 參數為空
7002 | Hash 參數為空
7003 | StoreCode 參數為空
8001 | Hash 值不符合
9998 | xmldata 結構有誤
9999 | 系統異常

## Issue an new invoice

* Request：
    * Action：`IN_PreInvoiceS.action`
    * XmlData：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
InvoiceRoot | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;Invoice | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DataNumber | 單據號碼 | Y | 英數 | 20 | (SellerId & DataNumber) 需唯一
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DataDate | 單據日期 | Y | 英數 | 10 | 格式：`YYYY/MM/DD`
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SellerId | 賣方統一編號 | Y | 英數 | 10 | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BuyerName | 買方名稱 | Y | 英數 | 60 | * B2B:買方-營業人名稱。<br/>* B2C:買方-業者通知消費者之個人識別碼資料,共 4 位 ASCII 或 2 位全型中文。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BuyerId | 買方統一編號 | Y | 英數 | 10 | * B2B:買方-營業人統一編號(BAN)。<br/>* B2C:買方-填滿 10 位數 字的 "0"。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CustomsClearanceMark | 通關方式註記 | N | 數 | 1 | * '1': 非經海關出口<br/>* '2': 經海關出口(若為零稅率發票,此為必填欄位)
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceType | 發票類別 | Y | 英數 | 2 | * '01': 三聯式<br/>* '02': 二聯式<br/>* '03': 二聯式收銀機<br/>* '04': 特種稅額<br/>* '05': 電子計算機<br/>* '06': 三聯式收銀機<br/>* '07': 一般稅額計算之電子發票<br/>* '08': 特種稅額計算之電子發票<br/>* 電子發票僅適用第 7 項及 第 8 項
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DonateMark | 捐贈註記 | Y | 英數 | 1 | * '0':表示「非捐贈發票」<br/>* '1':表示為「捐贈發票」<br/>* 此部分資料須由消費者決定,網購業者可於網站畫面上新增欄位,讓消費者輸入資訊,範例請參考「電子發票網頁說明資訊.doc」,倘消費者於愛心碼欄位有輸入資訊,則此欄位值帶 '1',其餘皆帶 '0'。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CarrierType | 載具類別 | N | 英數 | 6 | 填入平台配發的載具類別號碼,編碼規則:AA0000,第一碼行業別(英文),第二碼載具類別(英數),後四碼載具類別(序號)若現金消費無使用載具,請免填。消費者使用手機條碼索取含買方統編發票,則不論是否已列印紙本皆為必填。手機條碼:3J0002 手機載具相關資訊請參考財政部網頁若需使用網優載具進行發票代管服務,則此欄空白,由 EIVO 系統自動帶出值
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CarrierId1 | 載具顯碼id | N | 英數 | 64 | 填入載具外顯碼號碼,卡片上載列之卡片號碼資訊。若紙本電子發票已列印註記為 Y,此欄位必須為空白;若此欄位非空 白,則紙本電子發票已列印註記必須為 N。消費者使用手機條碼索取含買方統編發票,則不論是否已列印紙本皆為必填。若消費者使用手機載具索取發票,則須將消費者填寫之手機載具資訊帶入此欄,範例請參考「電子發票網頁說明資訊.doc」若需使用網優載具進行發票代管服務,則此欄空白,由本系統自動帶出值
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CarrierId2 | 載具隱碼id | N | 英數 | 64 | 填入載具內碼號碼,營業人應載入讀取工具所讀取之原始資訊。若紙本電子發票已列印註記為 Y,此欄位必須為空白;若此欄位非空白,則紙本電子發票已列印註記必須為 N。消費者使用手機條碼索取含買方統編發票,則不論是否已列印紙本皆為必填。若消費者使用手機載具索取發票,則須將消費者填寫之手機載具資訊帶入此欄,範例請參考「電子發票網頁說明資訊.doc」若需使用網優載具進行發票代管服務,則此欄空白,由本系統自動帶出值
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PrintMark | 紙本電子發票已列印註記 | Y | 英 | 1 | * 'Y'/'N'<br/> * PrintMark 為 Y 時載具類別號碼,載具顯碼 ID, 載具隱碼 ID 必須為空白,捐贈註記必為 N。<br/>* 消費者使用手機條碼索取含買方統編發票,則不論是否已列印紙本,其載具類別號碼、載具顯碼 ID 和載具隱碼 ID 皆為必填。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NPOBAN | 發票捐贈對象統一 | N | 英數 | 10 | 受捐贈者統一編號 BAN 捐贈愛心碼請將愛心碼資料 3-7 碼「完整」填入。愛心碼申請方式請參考財政部網頁
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;RandomNumber | 發票防偽隨機碼 | N | 英數 | 4 | 交易當下隨機產生 4 位數值,少於 4 位者踢退;若為虛擬通路,則限填 "AAAA"
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceItem | - | - | - | - | 可重複
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Description | 品名 | Y | 英數 | 256 | - | - | - |
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Quantity | 數量 | Y | 數 | 17 | * 商品數量：整數 12 位,小數 4 位。<br/>* 整數部分第一位不能有零,小數為零時不顯示小數點,負號請接於整數第一位前 Ex:999999999999.9999 Ex:-2356
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Unit | 單位 | 選 | 英數 | 6 | 可為空白，商品單位, 除鋼鐵業外, 一般空白
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;UnitPrice | 單價 | Y | 數 | 17 | 商品單價 (未稅) 原幣報價，整數 12 位,小數 4 位。整數部分第一位不能有零,小數為零時不顯示小數點,負號請接於整數第一位前 Ex:999999999999.9999 Ex:-2356
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Amount | 金額 | Y | 數 | 17 | * 商品單價(未稅) * 數量：整數 12 位,小數 4 位。<br/>* 整數部分第一位不能有零,小數為零時不顯示小數點,負號請接於整數第一位前 Ex:999999999999.9999 Ex:-2356
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SequenceNumber | 明細排列序號 | Y | 英數 | 3 | 系統使用,不重複發票明細項目之排列序號, 第一筆商品標示 '1', 其餘接續編號
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Remark | 單一欄位備註 | N | 英數 | 40 | 可為空白,若為健康捐請於本項填寫"健康捐"
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SalesAmount | 應稅銷售額合計（新台幣） | Y | 數 | 12 | 整張發票應稅品銷售額合計 (未稅) 整數(小數點以下四捨五入),請注意銷售額合計不應為負數。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FreeTaxSalesAmount | 免稅銷售額合計（新台幣） | Y | 數 | 12 | 整張發票免稅品銷售額合計整數(小數點以下四捨五入),若無需求則填 0,請注意銷售額合計不應為負數。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ZeroTaxSalesAmount | 零稅率銷售額合計（新台幣） | Y | 數 | 12 | 整張發票零稅率品項銷售額合計整數(小數點以下四捨五入),若無需求則填 0,請注意銷售額合計不應為負數。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TaxType | 課稅別 | Y | 英數 | 1 | <br/>* '1':應稅<br/>* '2':零稅率<br/>* '3':免稅<br/>* '4':應稅(特種稅率)<br/>* '9':混合應稅與免稅或零稅率 (限收銀機發票無法分辨時使用)
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TaxRate | 稅率 | Y | 數 | 6 | 範例: 稅率為 5% 時本欄位值為 0.05
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TaxAmount | 營業稅額 | Y | 數 | 12 | 整數(小數點以下四捨五入),填寫方式參閱註 1,請注意此項稅額不應為負數
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TotalAmount | 總計 | Y | 數 | 12 | 整數 (應稅銷售額合計 + 免稅銷售額合計 + 零稅率銷售額合計 + 營業稅額 = 此總計欄位),整數部分第一位不能有零,請注意此項總額不應為負數
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Contact | 郵件聯絡人資訊 | - | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Name | 姓名 | Y | 英數 | 64 | 郵寄信封上收件人
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Address | 地址 | Y | 英數 | 128 | 郵寄信封上收件人地址
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TEL | 電話 | N | 英數 | 64 | 聯絡人電話,若啟動簡訊通知服務則為收取簡訊電話,則此欄位必填
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Email | email | N | 英數 | 512 | 聯絡人 Email,若啟動 Email 通知服務則此欄位必填,若須設定多筆 Email 則 以;符號間隔,例: aa@aa.net;bb@bb.net
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CustomerDefined | 針對有印花稅需求者 | - | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ProjectNo | 專案編號 | N | 英數 | 64 | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PurchaseNo | 採購案號 | N | 英數 | 64 | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;StampDutyFlag | 顯示印花稅圖章 | N | 數 | 1 | 0:不需要 1:需要

註一、營業稅額欄位之填寫方式,應依照加值型及非加值型營業稅法第三十二條規定:「營業人依第十四條規定計算之銷項稅額,買受人為營業人者,應與銷售額於統一發票上分別載明之;買受人為非營業人者,應與銷售額合計開立統一發票。」填寫。上傳整合服務平台的發票內容應與開立內容一致。

* Response：
    * 回應結構與訊息對照表：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
Result | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statcode | 錯誤代碼 | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statdesc | 錯誤描述 | Y | - | - | -

----

statcode | statdesc | description
:-------:|:---------|:-----------
7001 | SellerId 不符 | StoreCode 取得商店統一編號與 <SellerId/>是否相同或該 <SellerId/> 必須存在於該商家的分支統編中
7002 | 單據號碼重複 | 以 <SellerId/> And <DataNumber/> 為條件確認資料庫資料不可有重複。
7003 | B2C 模式 BuyerName 不符合 | 若 <BuyerId/> 值等於 10 位的 '0',則 <BuyerName/> 必須符合共 4 位 ASCII 或 2 位全型中文。
7004 | CustomsClearanceMark 資料不符 | <CustomsClearanceMark/>若有填寫,必須為 1 或 2
7005 | InvoiceType 資料不符 | <InvoiceType/>值必須為「01、02、03、04、05、06」其中一個
7006 | DonateMark 資料不符 | <DonateMark/>必須為 0 或 1
7007 | 捐贈發票 NPOBAN 資料不可為空 | <DonateMark/> 當值等於 '1' 時,則 <NPOBAN/> 不可為空值
7008 | PrintMark 為紙本電子發票已列印時, CarrierId1, CarrierId2, DonateMark 不符合要求 | <PrintMark/> 值=Y,則<CarrierId1/>載具顯碼 ID, <CarrierId2/> 載具隱碼 ID 必須為空白, <DonateMark/>捐贈註記必為 N
7009 | RandomNumber 資料長度不符 | <RandomNumber/> 若非為空值時,則長度不可小於四位。
7010 | SequenceNumber 不可重複 | <SequenceNumber/> 不可重複
7011 | SalesAmount 為負值 | <SalesAmount/> 不可為負數
7012 | FreeTaxSalesAmount 為負值 | <FreeTaxSalesAmount/> 不可為負數
7013 | ZeroTaxSalesAmount 為負值 | <ZeroTaxSalesAmount/> 不可為負數
7014 | TaxType 資料不符 | <TaxType/> 值限為「1、2、3、4、9」其中一項
7015 | TaxAmount 為負值 | <TaxAmount/> 不可為負數
7016 | TotalAmount 為負值 | <TotalAmount/> 不可為負數

## Issue an existed invoice

* Request：
    * Action：`IN_SellerInvoiceS.action`
    * XmlData：

Tag | Description | Required | Type | Length | Detail
----|-------------|----------|------|--------|-------
InvoiceRoot | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;Invoice | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceNumber | 發票號碼 | Y | 英數 | 10 | (SellerId & DataNumber) 需唯一
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceDate | 發票日期 | Y | 英數 | 8 | `YYYY/MM/DD` 西元年月日,平台僅接收 2006/12/06 後的所有發票
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceTime | 發票時間 | Y | 英數 | 8 | HH:MM:SS(24hr);[00-23]:[0 0-59]:[00-59] 範例:23:59:59
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SellerId | 賣方統一編號 | Y | 英數 | 10 | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BuyerName | 買方名稱 | Y | 英數 | 60 | * B2B:買方-營業人名稱。<br/>* B2C:買方-業者通知消費者之個人識別碼資料,共 4 位 ASCII 或 2 位全型中文。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BuyerId | 買方統一編號 | Y | 英數 | 10 | * B2B:買方-營業人統一編號(BAN)。<br/>* B2C:買方-填滿 10 位數 字的 "0"。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CustomsClearanceMark | 通關方式註記 | N | 數 | 1 | * '1': 非經海關出口<br/>* '2': 經海關出口(若為零稅率發票,此為必填欄位)
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceType | 發票類別 | Y | 英數 | 2 | * '01': 三聯式<br/>* '02': 二聯式<br/>* '03': 二聯式收銀機<br/>* '04': 特種稅額<br/>* '05': 電子計算機<br/>* '06': 三聯式收銀機<br/>* '07': 一般稅額計算之電子發票<br/>* '08': 特種稅額計算之電子發票<br/>* 電子發票僅適用第 7 項及 第 8 項
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DonateMark | 捐贈註記 | Y | 英數 | 1 | * '0':表示「非捐贈發票」<br/>* '1':表示為「捐贈發票」<br/>* 此部分資料須由消費者決定,網購業者可於網站畫面上新增欄位,讓消費者輸入資訊,範例請參考「電子發票網頁說明資訊.doc」,倘消費者於愛心碼欄位有輸入資訊,則此欄位值帶 '1',其餘皆帶 '0'。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CarrierType | 載具類別 | N | 英數 | 6 | 填入平台配發的載具類別號碼,編碼規則:AA0000,第一碼行業別(英文),第二碼載具類別(英數),後四碼載具類別(序號)若現金消費無使用載具,請免填。消費者使用手機條碼索取含買方統編發票,則不論是否已列印紙本皆為必填。手機條碼:3J0002 手機載具相關資訊請參考財政部網頁若需使用網優載具進行發票代管服務,則此欄空白,由 EIVO 系統自動帶出值
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CarrierId1 | 載具顯碼id | N | 英數 | 64 | 填入載具外顯碼號碼,卡片上載列之卡片號碼資訊。若紙本電子發票已列印註記為 Y,此欄位必須為空白;若此欄位非空 白,則紙本電子發票已列印註記必須為 N。消費者使用手機條碼索取含買方統編發票,則不論是否已列印紙本皆為必填。若消費者使用手機載具索取發票,則須將消費者填寫之手機載具資訊帶入此欄,範例請參考「電子發票網頁說明資訊.doc」若需使用網優載具進行發票代管服務,則此欄空白,由本系統自動帶出值
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CarrierId2 | 載具隱碼id | N | 英數 | 64 | 填入載具內碼號碼,營業人應載入讀取工具所讀取之原始資訊。若紙本電子發票已列印註記為 Y,此欄位必須為空白;若此欄位非空白,則紙本電子發票已列印註記必須為 N。消費者使用手機條碼索取含買方統編發票,則不論是否已列印紙本皆為必填。若消費者使用手機載具索取發票,則須將消費者填寫之手機載具資訊帶入此欄,範例請參考「電子發票網頁說明資訊.doc」若需使用網優載具進行發票代管服務,則此欄空白,由本系統自動帶出值
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PrintMark | 紙本電子發票已列印註記 | Y | 英 | 1 | * 'Y'/'N'<br/> * PrintMark 為 Y 時載具類別號碼,載具顯碼 ID, 載具隱碼 ID 必須為空白,捐贈註記必為 N。<br/>* 消費者使用手機條碼索取含買方統編發票,則不論是否已列印紙本,其載具類別號碼、載具顯碼 ID 和載具隱碼 ID 皆為必填。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NPOBAN | 發票捐贈對象統一 | N | 英數 | 10 | 受捐贈者統一編號 BAN 捐贈愛心碼請將愛心碼資料 3-7 碼「完整」填入。愛心碼申請方式請參考財政部網頁
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;RandomNumber | 發票防偽隨機碼 | N | 英數 | 4 | 交易當下隨機產生 4 位數值,少於 4 位者踢退;若為虛擬通路,則限填 "AAAA"
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceItem | - | - | - | - | 可重複
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Description | 品名 | Y | 英數 | 256 | - | - | - |
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Quantity | 數量 | Y | 數 | 17 | * 商品數量：整數 12 位,小數 4 位。<br/>* 整數部分第一位不能有零,小數為零時不顯示小數點,負號請接於整數第一位前 Ex:999999999999.9999 Ex:-2356
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Unit | 單位 | 選 | 英數 | 6 | 可為空白，商品單位, 除鋼鐵業外, 一般空白
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;UnitPrice | 單價 | Y | 數 | 17 | 商品單價 (未稅) 原幣報價，整數 12 位,小數 4 位。整數部分第一位不能有零,小數為零時不顯示小數點,負號請接於整數第一位前 Ex:999999999999.9999 Ex:-2356
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Amount | 金額 | Y | 數 | 17 | * 商品單價(未稅) * 數量：整數 12 位,小數 4 位。<br/>* 整數部分第一位不能有零,小數為零時不顯示小數點,負號請接於整數第一位前 Ex:999999999999.9999 Ex:-2356
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SequenceNumber | 明細排列序號 | Y | 英數 | 3 | 系統使用,不重複發票明細項目之排列序號, 第一筆商品標示 '1', 其餘接續編號
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Remark | 單一欄位備註 | N | 英數 | 40 | 可為空白,若為健康捐請於本項填寫"健康捐"
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SalesAmount | 應稅銷售額合計（新台幣） | Y | 數 | 12 | 整張發票應稅品銷售額合計 (未稅) 整數(小數點以下四捨五入),請注意銷售額合計不應為負數。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FreeTaxSalesAmount | 免稅銷售額合計（新台幣） | Y | 數 | 12 | 整張發票免稅品銷售額合計整數(小數點以下四捨五入),若無需求則填 0,請注意銷售額合計不應為負數。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ZeroTaxSalesAmount | 零稅率銷售額合計（新台幣） | Y | 數 | 12 | 整張發票零稅率品項銷售額合計整數(小數點以下四捨五入),若無需求則填 0,請注意銷售額合計不應為負數。
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TaxType | 課稅別 | Y | 英數 | 1 | <br/>* '1':應稅<br/>* '2':零稅率<br/>* '3':免稅<br/>* '4':應稅(特種稅率)<br/>* '9':混合應稅與免稅或零稅率 (限收銀機發票無法分辨時使用)
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TaxRate | 稅率 | Y | 數 | 6 | 範例: 稅率為 5% 時本欄位值為 0.05
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TaxAmount | 營業稅額 | Y | 數 | 12 | 整數(小數點以下四捨五入),填寫方式參閱註 1,請注意此項稅額不應為負數
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TotalAmount | 總計 | Y | 數 | 12 | 整數 (應稅銷售額合計 + 免稅銷售額合計 + 零稅率銷售額合計 + 營業稅額 = 此總計欄位),整數部分第一位不能有零,請注意此項總額不應為負數
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Contact | 郵件聯絡人資訊 | - | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Name | 姓名 | Y | 英數 | 64 | 郵寄信封上收件人
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Address | 地址 | Y | 英數 | 128 | 郵寄信封上收件人地址
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TEL | 電話 | N | 英數 | 64 | 聯絡人電話,若啟動簡訊通知服務則為收取簡訊電話,則此欄位必填
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Email | email | N | 英數 | 512 | 聯絡人 Email,若啟動 Email 通知服務則此欄位必填,若須設定多筆 Email 則 以;符號間隔,例: aa@aa.net;bb@bb.net
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CustomerDefined | 針對有印花稅需求者 | - | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ProjectNo | 專案編號 | N | 英數 | 64 | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PurchaseNo | 採購案號 | N | 英數 | 64 | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;StampDutyFlag | 顯示印花稅圖章 | N | 數 | 1 | 0:不需要 1:需要

註一、營業稅額欄位之填寫方式,應依照加值型及非加值型營業稅法第三十二條規定:「營業人依第十四條規定計算之銷項稅額,買受人為營業人者,應與銷售額於統一發票上分別載明之;買受人為非營業人者,應與銷售額合計開立統一發票。」填寫。上傳整合服務平台的發票內容應與開立內容一致。

* Response：
    * 回應結構與訊息對照表：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
Result | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statcode | 錯誤代碼 | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statdesc | 錯誤描述 | Y | - | - | -

----

statcode | statdesc | description
:-------:|:---------|:-----------
7001 | SellerId 不符 | StoreCode 取得商店統一編號與 <SellerId/>是否相同或該 <SellerId/> 必須存在於該商家的分支統編中
7002 | 發票號碼重複 | 以 <InvoiceNumber/> 為條件確認資料庫資料不可有重複。
7003 | B2C 模式 BuyerName 不符合 | 若 <BuyerId/> 值等於 10 位的 '0',則 <BuyerName/> 必須符合共 4 位 ASCII 或 2 位全型中文。
7004 | CustomsClearanceMark 資料不符 | <CustomsClearanceMark/>若有填寫,必須為 1 或 2
7005 | InvoiceType 資料不符 | <InvoiceType/>值必須為「01、02、03、04、05、06」其中一個
7006 | DonateMark 資料不符 | <DonateMark/>必須為 0 或 1
7007 | 捐贈發票 NPOBAN 資料不可為空 | <DonateMark/> 當值等於 '1' 時,則 <NPOBAN/> 不可為空值
7008 | PrintMark 為紙本電子發票已列印時, CarrierId1, CarrierId2, DonateMark 不符合要求 | <PrintMark/> 值=Y,則<CarrierId1/>載具顯碼 ID, <CarrierId2/> 載具隱碼 ID 必須為空白, <DonateMark/>捐贈註記必為 N
7009 | RandomNumber 資料長度不符 | <RandomNumber/> 若非為空值時,則長度不可小於四位。
7010 | SequenceNumber 不可重複 | <SequenceNumber/> 不可重複
7011 | SalesAmount 為負值 | <SalesAmount/> 不可為負數
7012 | FreeTaxSalesAmount 為負值 | <FreeTaxSalesAmount/> 不可為負數
7013 | ZeroTaxSalesAmount 為負值 | <ZeroTaxSalesAmount/> 不可為負數
7014 | TaxType 資料不符 | <TaxType/> 值限為「1、2、3、4、9」其中一項
7015 | TaxAmount 為負值 | <TaxAmount/> 不可為負數
7016 | TotalAmount 為負值 | <TotalAmount/> 不可為負數

## Query issued invoices

* Request：
    * Action：`IN_InvoiceMapS.action`
    * XmlData：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
QryEvent | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;InvoiceDateTimeS | 發票日期時間 (查詢開始) | N | 數 | 14 | yyyyMMddHHmmss
&nbsp;&nbsp;&nbsp;&nbsp;InvoiceDateTimdE | 發票日期時間 (結束) | N | 數 | 14 | yyyyMMddHHmmss
&nbsp;&nbsp;&nbsp;&nbsp;DataNumberS | 單據號碼 (查詢開始) | N | 英數 | 20 | -
&nbsp;&nbsp;&nbsp;&nbsp;DataNumberE | 單據號碼 (結束) | N | 英數 | 20 | -
&nbsp;&nbsp;&nbsp;&nbsp;SyncStatusUpdate | 是否更新同步狀態 | N | 英 | 1 | 'Y' or 'N'(default)

註：若不放條件,請將 Node 的值為空,不可省略節點。

* Response：
    * 回應結構與訊息對照表：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
Result | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statcode | 錯誤代碼 | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statdesc | 錯誤描述 | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;data | 資料區塊 | N | - | - | 狀態碼=0000 時,才有此 Node
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceMapRoot | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceMap | 逐筆發票對應資料集合 | Y | - | - | 若有多筆發票對應資料,此 TAG 可重複
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DataNumber | 單據號碼 | Y | 英數 | 20 | 為未配號發票檔中單據號碼
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceNumber | 發票號碼 | Y | 英數 | 10 | 客戶須於本系統維護發票號碼後,本系統方可配號,並回傳此一值給營業人
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceDate | 發票日期 | Y | 英數 | 10 | `YYYY/MM/DD` 西元年月日
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceTime | 發票時間 | Y | 英數 | 8 | HH:MM:SS(24hr);[00-23]:[00-59]:[0 0-59] 範例:23:59:59

## Cancel an issued invoice

* Request：
    * Action：`IN_CancelInvoiceS.action`
    * XmlData：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
CancelInvoiceRoot | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;CancelInvoice | 逐筆作廢發票資料集合 | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;InvoiceDate | 發票日期 | Y | 英數 | 10 | `YYYY/MM/DD` 西元年月日,發票當初開立之日期
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;SellerId | 賣方識別碼 | Y | 英數 | 10 | 賣方營業人統一編號
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CancelDate | 作廢日期 | Y | 英數 | 10 | `YYYY/MM/DD` 西元年月日
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CancelTime | 作費時間 | Y | 英數 | 8 | HH:MM:SS; (24hr);[00-23]:[00-59]:[00 -59] 範例:23:59:59
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CancelReason | 作費原因 | Y | 英數 | 20 | 長度至少為 1
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ReturnTaxDocumentNumber | 專案作費核准文號 | N | 英數 | 60 | 若發票的作廢時間超過申報期間,則此欄位為必填欄位。若不填寫由上傳營業人自行負責。一般營業人二個月申報一次營業稅,則申報期為單月 15 號,超過申報期限則須與轄區國稅局申請專案核准文號方可作廢此張發票
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Remark | 備註 | Y | 英數 | 200 | -

* Response：
    * 回應結構與訊息對照表：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
Result | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statcode | 錯誤代碼 | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statdesc | 錯誤描述 | Y | - | - | -

----

statcode | statdesc | description
:-------:|:---------|:-----------
7001 | SellerId 不符 | StoreCode 取得商店統一編號與 <SellerId/> 是否相同且該 <SellerId/> 必須存在於該商家的分支統編中
7002 | CancelReason 資料長度最少一位 | <CancelReason/> 資料長度最少一位

## Allowance of an invoice

* Request：
    * Action：`IN_AllowanceS.action`
    * XmlData：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------

* Response：
    * 回應結構與訊息對照表：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
Result | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statcode | 錯誤代碼 | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statdesc | 錯誤描述 | Y | - | - | -

----

statcode | statdesc | description
:-------:|:---------|:-----------

## Cancel allowance of an invoice

* Request：
    * Action：`IN_CancelAllowanceS.action`
    * XmlData：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------

* Response：
    * 回應結構與訊息對照表：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
Result | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statcode | 錯誤代碼 | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statdesc | 錯誤描述 | Y | - | - | -

----

statcode | statdesc | description
:-------:|:---------|:-----------

## Assign invoice number for branches

* Request：
    * Action：`IN_BranchTrackS.action`
    * XmlData：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------

* Response：
    * 回應結構與訊息對照表：

Tag | Name | Required | Type | Length | Description
:---|:-----|:--------:|:----:|:------:|:-----------
Result | - | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statcode | 錯誤代碼 | Y | - | - | -
&nbsp;&nbsp;&nbsp;&nbsp;statdesc | 錯誤描述 | Y | - | - | -

----

statcode | statdesc | description
:-------:|:---------|:-----------
