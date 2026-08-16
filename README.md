# Einvoice

[![Build Status](https://github.com/abookyun/einvoice/actions/workflows/build.yml/badge.svg)](https://github.com/abookyun/einvoice/actions/workflows/build.yml)
[![codecov](https://codecov.io/github/abookyun/einvoice/graph/badge.svg?token=yxJNmXiUyp)](https://codecov.io/github/abookyun/einvoice)

A provider-agnostic **Taiwan e-invoice SDK** (財政部 MIG 4.0). The core models the
five operations once — issue (開立) / void (作廢) / allowance (折讓) /
void-allowance (折讓作廢) / query (查詢) — as a unified value model plus a
`Einvoice::Provider` contract. Each value-added center ships as a thin adapter
mapping the unified model to/from its wire format, so switching providers is a
one-line constructor change and never touches business code.

> **2.0 is a ground-up rewrite, and the 1.x line is now in maintenance mode.**
> 1.x was a single-provider (Tradevan) wire-format client with a different API.
> If you depend on that, pin `~> 1.4` — it continues on the
> [`1-x-stable`](https://github.com/abookyun/einvoice/tree/1-x-stable) branch.
> 2.0's unified model is not backward compatible.

## What this is

Every Taiwan value-added center wraps the same MOF MIG spec; only the wire
format (field names, signing, envelope) differs. This SDK models the operations
once and keeps each provider a thin adapter. Application code depends only on
`Einvoice::Provider` and the unified types, so moving from one center to another
is swapping the constructor.

## Status

Under active development toward 2.0. The provider-agnostic **core** —
value types, the `Provider` contract, capabilities, the normalized error
hierarchy, input validation, and an in-memory `MockProvider` — is in place.
Concrete adapters land next, **ECPay first** (it's the one value-added center
with public docs and a public sandbox). Coverage and completeness for other
centers will vary: their docs are less complete, and an adapter built from docs
alone carries some uncertainty until real production use confirms it.

## Installation

```ruby
gem "einvoice", ">= 2.0.0.alpha1"
```

## Usage

Depend on the `Einvoice::Provider` contract, not a concrete adapter. Every
provider is constructed per-instance (no global configuration), so a
multi-merchant app just holds one provider per set of credentials.

```ruby
# Any adapter — here the in-memory reference provider — is an Einvoice::Provider.
provider = Einvoice::MockProvider.new

result = provider.issue(
  order_id: "ORDER_1",
  buyer: { email: "buyer@example.com" },       # a ubn present ⇒ B2B (三聯式)
  items: [
    { description: "咖啡拿鐵", quantity: 1, unit_price: 100, amount: 100 }
  ],
  amount: { sales_amount: 100, tax_amount: 0, total_amount: 100 }, # integer TWD
  tax_type: "TAXABLE",
  price_mode: "TAX_INCLUSIVE",
  carrier: { type: "MEMBER" }
)

result.invoice_number   # => "MK10000000"
result.status           # => :issued

invoice = provider.query(order_id: "ORDER_1")
invoice.status          # => :issued

provider.void(invoice_number: result.invoice_number, reason: "客戶取消")
```

Inputs accept plain hashes (string or symbol keys) — enum fields take the
canonical symbol (`:taxable`) or a wire-style string (`"TAXABLE"`). They are
validated and coerced into immutable value objects before anything hits the
network; a malformed request raises `Einvoice::ValidationError` locally.

### Errors

Every failure is an `Einvoice::Error` subclass carrying a stable `#code`, the
provider's `#raw_code` / `#raw_message`, and an optional action-oriented
`#reason`. Rescue precisely or broadly:

```ruby
begin
  provider.void(invoice_number: "AB12345678", reason: "customer cancelled")
rescue Einvoice::ConflictError => e
  e.reason   # => :already_voided  (idempotent — treat as success)
rescue Einvoice::Error => e
  e.code     # => :network, :auth, :not_found, …
end
```

### Capabilities

A provider declares what it supports; feature-detect instead of discovering a
gap when a request fails.

```ruby
provider.supports?(Einvoice::Capability::FOREIGN_CURRENCY)  # => true / false
provider.assert_supports!(Einvoice::Capability::B2B)        # raises UnsupportedError if absent
```

## Development

```bash
bin/setup          # install dependencies
bundle exec rspec  # run the specs
bundle exec rake   # default task: rspec
```

The `"an invoice provider"` shared examples
(`spec/support/shared_examples/`) are the executable contract every adapter
runs, so a new adapter proves it honours the unified model by including one line.

## License

The gem is available as open source under the terms of the
[MIT License](http://opensource.org/licenses/MIT).
