# Einvoice
[![Build Status](https://travis-ci.com/abookyun/einvoice.svg)](https://travis-ci.com/abookyun/einvoice)
[![Code Climate](https://codeclimate.com/github/abookyun/einvoice/badges/gpa.svg)](https://codeclimate.com/github/abookyun/einvoice)
[![Test Coverage](https://codeclimate.com/github/abookyun/einvoice/badges/coverage.svg)](https://codeclimate.com/github/abookyun/einvoice/coverage)

## What's E-Invoice

To support the thriving e-commerce industry and lower the business costs and barriers associated with printing paper receipts, the Taiwan Executive Yuan announced plans in August 2000 to implement electronic receipts in Taiwan and launched a comprehensive project in May 2010 to promote e-invoice applications. This initiative employs innovative approaches such as allowing consumers to claim virtual receipts via multiple devices, offering automatic checking of receipt lottery numbers, and providing a variety of channels for retailers to issue receipts.

Hence, there are several e-invoice services for B2B, B2C in Taiwan as the intermediate and value-adding platform like [CHT](https://invoice.cht.com.tw/invoice/login.jsp), [allPay](https://www.allpay.com.tw/Business/invoice), [Tradevan](http://www.tradevan.com.tw/services/index.do?act=services_info&type=16), Neweb, ..[etc](https://www.einvoice.nat.gov.tw/index!showAddCenter?linkIsNew=Y&CSRT=3716270004994188830).

## Supported E-Invoice Providers

* Tradevan

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'einvoice'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install einvoice

## Usage

### Configure

```ruby
Einvoice.configure do |config|
  config.endpoint = ENV['EINVOICE_ENDPOINT']
  # endpoint_url will override endpoint for testing purpose
  # config.endpoint_url = ENV['EINVOICE_ENDPOINT_URL']
  config.client_id = ENV['EINVOICE_CLIENT_ID']
  config.client_secret = ENV['EINVOICE_CLIENT_SECRET']
  config.encryption_keys = ENV['ENCRYPTION_KEYS']
  config.format = "json"
end
```

### Initialize

```ruby
client = Einvoice::Client.new(Einvoice::Tradevan::Provider.new)
```

### Issue an invoice

```ruby
payload = {
  companyUn: "12345678",
  orgId: "ABCDE",
  type: "I",
  saleIdentifier: "12345678_ABCDE_53b2a44e4b3c",
  transactionNumber: "53b2a44e4b3c",
  transactionDate: "20160425",
  transactionTime: "12:34:56",
  total: "20000",
  paperPrintMode: "0",
  invoiceAlarmMode: "4",
  donate: "N",
  donationUnit: nil,
  carrierType: "3J0002",
  carrierId: "TP03000001234567",
  carrierIdHidden: "TP03000001234567",
  receiverName: "John Appleseed",
  receiverAddrZip: "95014",
  receiverAddrRoad: "1 Infinite Loop - Cupertino CA",
  receiverEmail: "john@gmail.com",
  receiverMobile: "415-284-0579",
  memberId: nil,
  itemList: [
    {
      saleIdentifier: "12345678_ABCDE_53b2a44e4b3c",
      serialNumber: "0001",
      productName: "Coffee Latte",
      qty: "4000",
      price: "5",
      itemTotal: "20000",
      taxType: "T",
      tax: "952"
    }
  ]
}
```

```ruby
result = client.issue(payload)
result.successful?
#=> true
result.data
#=>
# {
#   "saleIdentifier"=>"12345678_ABCDE_53b2a44e4b3c",
#   "issueStatus"=>"Y",
#   "failReason"=>"",
#   "invoiceNumber"=>"GX38551078",
#   "checkNumber"=>"4229",
#   "invoiceDate"=>"20160425",
#   "invoiceTime"=>"12:34:58",
#   "texclusiveAmount"=>"19048",
#   "oexclusiveAmount"=>"0",
#   "zexclusiveAmount"=>"0",
#   "tax"=>"952",
#   "inclusiveAmount"=>"20000",
#   "mainRemark"=>"",
#   "invoiceType"=>"",
#   "invoiceStatus"=>"V",
#   "allowanceNumber"=>"",
#   "allowanceDate"=>"",
#   "allowanceExclusiveAmount"=>"",
#   "allowanceTax"=>"",
#   "allowanceTotalAmount"=>"0",
#   "allowanceStatus"=>""
# }
```

### Cancel an invoice

```ruby
payload = {
  type: "I",
  saleIdentifier: "12345678_ABCDE_53b2a44e4b3c",
  invoiceNumber: "GX38551078",
  invoicePaperReturned: "Y",
}
```

```ruby
result = client.cancel(payload)
result.successful?
#=> true
result.data
#=>
# {
#   "saleIdentifier"=>"12345678_ABCDE_53b2a44e4b3c",
#   "voidStatus"=>"Y",
#   "failReason"=>"",
#   "type"=>"I",
#   "invoiceNumber"=>"GX38551078",
#   "allowanceNumber"=>""
# }
```

### Search invoice by memberId/memberId/sellTargetCode

```ruby
payload = {
  companyUn: "12345678",
  invoiceStartDate: "20160401",
  invoiceEndDate: "20160425",
  carrierId: "TP03000001234567",
  memberId: "",
  sellTargetCode: "",
}
```

```ruby
result = client.search_invoice_by_member_id(payload)
result.successful?
#=> true
result.data
#=>
# [
#   {
#     "saleIdentifier"=>"12345678_ABCDE_53b2a44e4b3c",
#     "invoiceNumber"=>"GX38551078",
#     "checkNumber"=>"4229",
#     "invoiceDate"=>"20160425",
#     "invoiceTime"=>"12:34:58",
#     "exclusiveAmount"=>"19048",
#     "tax"=>"952",
#     "total"=>"20000",
#     "status"=>"V",
#     "hasAllowance"=>"N",
#     "sellerName"=>"Starbucks",
#     "sellerUN"=>"12345678",
#     "sellerAddr"=>"1 Infinite Loop - Cupertino CA",
#     "sellerTel"=>"415-284-0579",
#     "receiverName"=>"John Appleseed",
#     "receiverAddr"=>"1 Infinite Loop - Cupertino CA",
#     "paper"=>"N",
#     "win"=>"N",
#     "donate"=>"N",
#     "carrierType"=>"CQ0001",
#     "carrierId"=>"TP03000001234567"
#   }
# ]
```

### Search invoice detail

```ruby
result = client.search_invoice_detail("GX38551078")
result.successful?
#=> true
result.data
#=>
# {
#   "saleIdentifier"=>"12345678_ABCDE_53b2a44e4b3c",
#   "invoiceNumber"=>"GX38551078",
#   "checkNumber"=>"4229",
#   "invoiceDate"=>"20160425",
#   "invoiceTime"=>"12:34:58",
#   "exclusiveAmount"=>"19048",
#   "tax"=>"952",
#   "total"=>"20000",
#   "status"=>"I",
#   "hasAllowance"=>"N",
#   "sellerName"=>"Starbucks",
#   "sellerUN"=>"12345678",
#   "sellerAddr"=>"1 Infinite Loop - Cupertino CA",
#   "sellerTel"=>"415-284-0579",
#   "receiverName"=>"John Appleseed",
#   "receiverAddr"=>"1 Infinite Loop - Cupertino CA",
#   "receiverPhone"=>"415-284-0579",
#   "paper"=>"Y",
#   "win"=>"N",
#   "donate"=>"N",
#   "carrierType"=>"CQ0001",
#   "detailList"=>[
#     {
#       "saleIdentifier"=>"12345678_ABCDE_53b2a44e4b3c",
#       "serialNumber"=>"0001",
#       "productName"=>"Coffee Latte",
#       "qty"=>"4000",
#       "price"=>"5",
#       "total"=>"20000",
#       "taxType"=>"T"
#     }
#   ]
# }
```

### Send card info to customer

```ruby
payload = {
  companyUn: "12345678",
  sellTargetCode: "xxx",
  invoiceStartYM: "201604",
  invoiceEndYM: "201604",
  receiverEmail: "john@gmail.com",
  receiverMobile: "",
}
```

```ruby
result = client.send_card_info_to_cust(payload)
result.successful?
#=> true
result.data
```

### Get invoice mark info

```ruby
payload = {
  companyUn: "12345678",
  orgId: "ABCDE",
  uniFiedNumber: "12345678",
  bookType: "API",
  period: "201604",
}
```

```ruby
result = client.get_invoice_mark_info(payload)
result.successful?
#=> true
result.data
#=>
# [
#   {
#     "unifiedNumber"=>"12345678",
#     "bookNumber"=>"API_M1",
#     "bookType"=>"API",
#     "period"=>"201604",
#     "duration"=>"201604",
#     "mark"=>"GX",
#     "start"=>"38551050",
#     "end"=>"38551249"
#   }
# ]
```

### Get donate unit list

```ruby
client.get_donate_unit_list("12345678")
```

### Get invoice content

```ruby
payload = {
  invoiceNumber: "GX38551078",
  sellTargetCode: "",
  invoiceStartDate: "",
  invoiceEndDate: "",
}
```

```ruby
result = client.get_invoice_content(payload)
result.successful?
#=> true
result.data
#=>
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/abookyun/einvoice.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
