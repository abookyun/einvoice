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

Under active development toward 2.0. The provider-agnostic **core** — value
types, the `Provider` contract, capabilities, the normalized error hierarchy,
input validation, and an in-memory `MockProvider` — is in place, and the first
real adapter, **ECPay (綠界)**, ships with it: the five operations plus carrier
validation, verified against ECPay's public stage API.

Other centers follow. Coverage and completeness for those will vary: their docs
are less complete and they have no public sandbox, so an adapter built from docs
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

## Providers

### ECPay 綠界

```ruby
provider = Einvoice::ECPay::Provider.new(
  merchant_id: "2000132",
  hash_key: "...",          # 16 bytes, server-side only
  hash_iv: "...",           # 16 bytes, server-side only
  mode: :production         # :test (default) targets the stage host
)
```

Everything above works unchanged — `issue` / `void` / `allowance` /
`void_allowance` / `query` take the same unified input and return the same value
types. The AES-128-CBC envelope, ECPay's two layers of result codes, and its
field rules stay inside the adapter.

To try it without an account, use ECPay's published sandbox credentials
(shared with every other developer — never for anything real):

```ruby
provider = Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX)
```

A few things worth knowing:

- **Paper vs. electronic is derived.** An invoice with a carrier or a donation is
  electronic (`Print=0`); anything else prints, and ECPay then requires a buyer
  name and address.
- **Mixed tax rates are derived too.** Items that disagree on `tax_type` produce
  a 混合稅率 (TaxType 9) invoice; you don't ask for it explicitly.
- **Void and allowance need the invoice's issue date**, which the unified input
  has no field for. It defaults to today (Asia/Taipei) — for an older invoice
  pass `provider_options: { invoice_date: "2026-08-01" }`, or query by `order_id`.
- **No foreign currency.** ECPay's B2C API has no such field, so a non-TWD
  `currency` raises `UnsupportedError` rather than being filed as TWD.
- **Carrier validation**: `validate_mobile_barcode("/ABC1234")`,
  `validate_love_code("168001")`, `love_code_organ_name("168001")`.
- **Anything else**: ECPay has ~25 further B2C endpoints (延遲開立, 字軌設定,
  列印, 通知 …). Reach them through `provider.raw(path, payload)`, which applies
  the envelope, encryption and error mapping for you.

## 財政部 lookups

Provider-independent clients for 財政部's own public services. They issue
nothing and hold no credentials, so they work whichever center you use — or
before you have picked one.

```ruby
codes = Einvoice::MOF::DonationCodes.new

codes.lookup("2718")
# => #<data Einvoice::MOF::DonationCode code="2718",
#      name="社團法人台北市喜願協會", short_name="喜願協會",
#      ubn="92000392", city="臺北市">

codes.exist?("105")          # => false — well-formed, not registered
codes.for_ubn("92000392")    # => every 愛心碼 that organisation holds
codes.all                    # => the whole dataset (~2,000, five requests)
```

This is **not** wired into `Input`, and deliberately so: validation there is
local and synchronous, and issuing an invoice must never depend on a third party
being reachable. `Input` checks the shape of a 愛心碼; whether it is *registered*
is a question you ask when it suits you — at order time, or once at boot via
`#all` to build your own set for offline checks.

The dataset needs no credentials today. Its published OpenAPI declares `api_key`
and `oauth2` schemes even so, so a 401/403 raises `Einvoice::AuthError` saying
exactly that rather than surfacing as a parse failure.

## Development

```bash
bin/setup          # install dependencies
bundle exec rspec  # run the specs
bundle exec rake   # default task: rspec
```

The `"an invoice provider"` shared examples
(`spec/support/shared_examples/`) are the executable contract every adapter
runs, so a new adapter proves it honours the unified model by including one line.

The ECPay adapter is tested in three layers, two of which run offline in CI:

1. **The contract, against a wire-format fake.** The shared examples run through
   an in-process fake that speaks the real protocol — AES envelope, PHP
   url-encoding, ECPay's own RtnCodes — so a request only passes if the
   encryption and field mapping are genuinely correct. It is stateful, which is
   what lets the contract drive issue → allowance → void as a sequence.
2. **Recorded real responses (VCR).** `spec/einvoice/ecpay/recorded_spec.rb`
   replays cassettes captured from ECPay's stage host, so the field names, value
   types and error codes under test are ECPay's own rather than our reading of
   the docs. Re-record with `VCR_RECORD=1` after bumping the epoch in that
   spec — cassettes only ever hold sandbox traffic.
3. **The live API, opt-in.** What keeps the other two honest:

   ```bash
   ECPAY_LIVE=1 bundle exec rspec spec/einvoice/ecpay/live_spec.rb
   ```

   It defaults to the public sandbox credentials, so no setup is needed; override
   with `ECPAY_MERCHANT_ID` / `ECPAY_HASH_KEY` / `ECPAY_HASH_IV` to point it at
   your own stage account. Excluded from CI because it needs the network and a
   shared sandbox.

## License

The gem is available as open source under the terms of the
[MIT License](http://opensource.org/licenses/MIT).
