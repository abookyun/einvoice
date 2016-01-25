# Einvoice
[![Build Status](https://travis-ci.org/abookyun/einvoice.svg?branch=master)](https://travis-ci.org/abookyun/einvoice)
[![Code Climate](https://codeclimate.com/github/abookyun/einvoice/badges/gpa.svg)](https://codeclimate.com/github/abookyun/einvoice)
[![Test Coverage](https://codeclimate.com/github/abookyun/einvoice/badges/coverage.svg)](https://codeclimate.com/github/abookyun/einvoice/coverage)

## What's Einvoice

To support the thriving e-commerce industry and lower the business costs and barriers associated with printing paper receipts, the Taiwan Executive Yuan announced plans in August 2000 to implement electronic receipts in Taiwan and launched a comprehensive project in May 2010 to promote e-invoice applications. This initiative employs innovative approaches such as allowing consumers to claim virtual receipts via multiple devices, offering automatic checking of receipt lottery numbers, and providing a variety of channels for retailers to issue receipts.

Hence, there are several e-invoice services for B2B, B2C in Taiwan as the intermediate and value-adding platform like CHT, allPay, Neweb, ..etc. They mostly provide services like below:

* Issue an new invoice
* Issue an existed invoice
* Query issued invoices
* Cancel an issued invoice
* Allowance of an invoice
* Cancel allowance of an invoice
* Manage invoice numbers

Therefore, we need a API wrapper to manage and access the APIs.

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

### Supported E-Invoice Providers

* [Neweb Technologies Co., Ltd.（藍新科技）](https://github.com/abookyun/einvoice/blob/master/docs/neweb.md)

### Setup

```ruby
Einvoice.configure do |setup|
  setup.endpoint = ENV['EINVOICE_ENDPOINT']
  setup.endpoint_url = ENV['EINVOICE_ENDPOINT_URL']
  setup.client_id = ENV['EINVOICE_CLIENT_ID']
  setup.client_secret = ENV['EINVOICE_CLIENT_SECRET']
  setup.format = "xml"
end
```

### Initialize a client with your provider e.g. Neweb

```ruby
client = Einvoice::Client.new(Einvoice::Neweb::Provider.new)
```

### Issue an invoice

Assume one of your customer just make an `order` including all transaction info for your `product`. After created the order you're ready to issue this invoice.

#### Generate invoice payload

```ruby
order = Order.find(params[:id])
product = order.product

payload = {
    data_number: "#{order.data_number}",
    data_date: "#{order.created_at}",
    seller_id: "#{order.product.seller_id}",
    buyer_name: "#{order.buyer_name}",
    buyer_id: "#{order.buyer_id}",
    customs_clearance_mark: "#{order.customs_clearance_mark}",
    invoice_type: "#{order.invoice_type}",
    donate_mark: "#{order.donate_mark}"
    carrier_type: "#{order.carrier_type}",
    carrier_id1: "#{order.carrier_id1}",
    carrier_id2: "#{order.carrier_id2}",
    print_mark: "#{order.print_invoice}",
    n_p_o_b_a_n: "#{order.n_p_o_b_a_n}",
    random_number: "#{order.random_number}",
    invoice_item: order.items.each_with_index.map do |item, index|
      {
        sequence_number: "#{index}"
        description: "#{order.product.description}",
        quantity: "#{item.quantity}",
        unit_price: "#{item.unit_price}",
        amount: "#{item.quantity * item.unit_price}",
      }
    end,
    sales_amount: "#{order.sales_amount}",
    free_tax_sales_amount: "#{order.free_tax_sales_amount}",
    zero_tax_sales_amount: "#{order.zero_tax_sales_amount}",
    tax_type: "#{order.tax_type}",
    tax_rate: "#{order.tax_rate}",
    tax_amount: "#{order.tax_amount}",
    total_amount: "#{order.total_amount}",
    contact: {
      name: "#{order.user.name}",
      address: "#{order.user.address}"
      t_e_l: "#{order.user.mobile}"
      email: "#{order.user.email}"
    }
  }
end
```

#### Issue an invoice and handle results

```ruby
result = client.issue(payload)

if result.success?
  logger.info "Issue invoice for #{order.id} is successful."
else
  logger.info "Issue invoice for #{order.id} is failed with #{result.errors}."
end
```

See [Einvoice::Result](https://github.com/abookyun/einvoice/blob/master/lib/einvoice/result.rb)

### Query invoices

#### Generate invoice payload

```ruby
payload = {
  data_number_s: "order_number1",
  data_number_e: "order_number5",
  invoice_date_time_s: "201512010000",
  invoice_date_time_e: "201501202359",
  sync_status_update: "N"
}
```

#### Query and handle results

```ruby
result = client.query(data)
if result.success?
  result.data["InvoiceMap"].each do |data|
    order_id = data.data_number
    invoice_number = data.invoice_number
    invoice_date = data.invoice_date #YYYY/MM/DD
    invoice_time = data.invoice_time #HH:MM:SS(24h)
  end

  logger.info "Query invoice for #{order.id} is successful."
else
  logger.info "Issue invoice for #{order.id} is failed with #{result.errors}."
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/abookyun/einvoice.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
