# Tradevan E-Invoice APIs

## Overview

* Partnership
* Authentication
* Encode and Decode
* APIs

## Partnership

## Authentication

## Encode and Decode

## APIs

### POST /DEFAULTAPI/post/issue

You could use this API to do

1. issue an new invoice
2. issue an existed invoice
3. issue an allowance
4. issue an existed allowance

#### Parameters

* issueData
    * type: json

### POST /DEFAULTAPI/post/cancel

You could use this API to do

1. cancel an existed invoice
2. cancel an allowance

#### Parameters

* voidData
    * type: json

### GET /DEFAULTAPI/get/searchInvoiceByMemberId

#### Parameters

* invoiceStartDate
    * description: begining of invoice issued date interval
    * type: string
    * require: false
    * format: yyyyMMdd
* invoiceEndDate
    * description: end of invoice issued date interval
    * type: string
    * require: false
    * format: yyyyMMdd
* companyUn
    * description: company universal business number(ubn) of Taiwan
    * type: string
    * require: true
* memberId
    * description: customer's member id of your service
    * type: string
    * require: true if `sellTargetCode` and `carrierId` are empty
* carrierId
    * description: customer's carrier id of invoices
    * type: string
    * require: true if `memberId` and `sellTargetCode` are empty
* sellTargetCode
    * description: ?
    * type: string
    * require: true if `memberId` and `carrierId` are empty

### GET /DEFAULTAPI/get/searchInvoiceDetail

#### Parameters

* invoiceNumber
    * description: invoice number
    * type: string
    * require: true

### GET /DEFAULTAPI/get/sendCardInfotoCust

#### Parameters

* companyUn
    * description: company universal business number(ubn) of Taiwan
    * type: string
    * require: true
* sellTargetCode
    * description: ?
    * type: string
    * require: true
* invoiceStartYM
    * description: begining of invoice issued year and month interval
    * type: string
    * require: false
    * format: yyyyMM
* invoiceEndYM
    * description: end of invoice issued year and month interval
    * type: string
    * require: false
    * format: yyyyMM
* receiverEmail
    * description: receiver's email
    * type: string
    * require: true if `receiverMobile` is empty
* receiverMobile
    * description: receiver's mobile
    * type: string
    * require: true if `receiverEmail` is empty

### GET /DEFAULTAPI/get/getInvoiceMarkInfo

#### Parameters

* companyUn
    * description: your company universal business number(ubn) of Taiwan
    * type: string
    * require: true
* orgId
    * description: your orgId
    * type: string
    * require: true
* uniFiedNumber
    * description: your company or branch ubn used to issue invoices
    * type: string
    * require: true
* bookType
    * description: your book type
    * type: string
    * require: true
* period
    * description: query year with or without months
    * type: string
    * require: true
    * format: yyyymm

### GET /DEFAULTAPI/get/getDonateUnitList

#### Parameters

* companyUn
    * description: company universal business number(ubn) of Taiwan
    * type: string
    * require: true

### GET /DEFAULTAPI/get/getInvoiceContent

#### Parameters

* invoiceNumber
    * description: invoice number
    * type: string
    * require: true if `sellTargetCode` is empty
* sellTargetCode
    * description: ?
    * type: string
    * require: true if `invoiceNumber` is empty
* invoiceStartDate
    * description: begining of invoice issued date interval
    * type: string
    * require: false
    * format: yyyyMMdd
* invoiceEndDate
    * description: end of invoice issued date interval
    * type: string
    * require: false
    * format: yyyyMMdd
