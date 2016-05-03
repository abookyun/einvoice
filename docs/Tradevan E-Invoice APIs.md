# Tradevan E-Invoice APIs

## Overview

* Preparation
* Encode Request
* Decode Response
* APIs

## Preparation

After contacting with Tradevan, you'll get

* acnt: your account name
* acntp: your account password
* key1: 1st AES encryption key
* key2: 2nd AES encryption key

## Encode Request

* Method: POST/GET
* URL: "#{endpoint}/#{path}"
* Parameters: "#{v}"
* v: `Base64_strict.encode(AES.encrypt(key2, { acnt: "#{acnt}", acntp: "#{acntp}", api_key1: "#{encryption_of_api_value1}", api_key2: "#{encryption_of_api_value2}", ... }))`
* `AES.encrypt(key, content)`:
  * mode: CBC-128
  * key: use `key2` for outter encryption, use `key1` for inner value encryption
  * iv: same as key
  * padding: no, but you should manually pad with `"\u0000"`(character space in bytes format) to fit correct CBC block size
* encryption_of_api_value1: `Base64_strict.encode(AES.encrypt(key1, api_value1))`

## Decode Response

* Format: JSON, i.e. `{ "Success": "Y", "Message": "#{encryption_of_message}" }`
* Success: "Y" for OK, "N" for Failure, "E" for Error
* Message:
  * Plain Text when `"Success": "E"`
  * Encryption Text when `"Success": "Y"` or `"Success": "N"`
  * Decryption: `AES.decrypt(key2, Base64_strict.decode(response["Message"]))`
* `AES.decrypt(key, content)`:
  * mode: CBC-128
  * key: use `key2` for decrypt `response["Message"]` content
  * iv: key
  * padding: no

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
