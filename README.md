# Einvoice
[![Build Status](https://travis-ci.org/abookyun/einvoice.svg?branch=master)](https://travis-ci.org/abookyun/einvoice)
[![Code Climate](https://codeclimate.com/github/abookyun/einvoice/badges/gpa.svg)](https://codeclimate.com/github/abookyun/einvoice)
[![Test Coverage](https://codeclimate.com/github/abookyun/einvoice/badges/coverage.svg)](https://codeclimate.com/github/abookyun/einvoice/coverage)

## What's Einvoice

To support the thriving e-commerce industry and lower the business costs and barriers associated with printing paper receipts, the Taiwan Executive Yuan announced plans in August 2000 to implement electronic receipts in Taiwan and launched a comprehensive project in May 2010 to promote e-invoice applications. This initiative employs innovative approaches such as allowing consumers to claim virtual receipts via multiple devices, offering automatic checking of receipt lottery numbers, and providing a variety of channels for retailers to issue receipts.

Hence, there are several e-invoice services for B2B, B2C in Taiwan as the intermediate and value-adding platform like CHT, allPay, Tradevan, Neweb, ..etc.

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/abookyun/einvoice.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
