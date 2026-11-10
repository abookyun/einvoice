# Einvoice

English | [繁體中文](README.zh-TW.md)

[![Build Status](https://github.com/abookyun/einvoice/actions/workflows/build.yml/badge.svg)](https://github.com/abookyun/einvoice/actions/workflows/build.yml) [![codecov](https://codecov.io/github/abookyun/einvoice/graph/badge.svg?token=yxJNmXiUyp)](https://codecov.io/github/abookyun/einvoice)

A provider-agnostic **Taiwan e-invoice SDK** (財政部 MIG 4.0). The core models the five operations once — issue (開立) / void (作廢) / allowance (折讓) / void-allowance (折讓作廢) / query (查詢) — as a unified value model plus a `Einvoice::Provider` contract. Each value-added center ships as a thin adapter mapping the unified model to/from its wire format, so switching providers is a one-line constructor change and never touches business code.

> **2.0 is a ground-up rewrite, and the 1.x line is now in maintenance mode.** 1.x was a single-provider (Tradevan) wire-format client with a different API. If you depend on that, pin `~> 1.4` — it continues on the [`1-x-stable`](https://github.com/abookyun/einvoice/tree/1-x-stable) branch. 2.0's unified model is not backward compatible.

## What this is

Every Taiwan value-added center wraps the same MOF MIG spec; only the wire format (field names, signing, envelope) differs. This SDK models the operations once and keeps each provider a thin adapter. Application code depends only on `Einvoice::Provider` and the unified types, so moving from one center to another is swapping the constructor.

## Status

Under active development toward 2.0. The provider-agnostic **core** — value types, the `Provider` contract, capabilities, the normalized error hierarchy, input validation, and an in-memory `MockProvider` — is in place, and the first real adapter, **ECPay (綠界)**, ships with it: the five operations plus carrier validation, verified against ECPay's public stage API.

Other centers follow. Coverage and completeness for those will vary: their docs are less complete and they have no public sandbox, so an adapter built from docs alone carries some uncertainty until real production use confirms it.

## Installation

```ruby
gem "einvoice", ">= 2.0.0.alpha1"
```

## Usage

Depend on the `Einvoice::Provider` contract, not a concrete adapter. Every provider is constructed per-instance (no global configuration), so a multi-merchant app just holds one provider per set of credentials.

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

invoice = provider.query(invoice: result.reference)
invoice.status          # => :issued

provider.void(invoice: result.reference, reason: "客戶取消")
```

`result.reference` is an `InvoiceReference`. It holds the facts about the invoice that providers ask for when you void, credit or query it later: the number, `invoice_datetime`, `random_code`, `order_id`, `total_amount`, `buyer_ubn`, and its `tax_type` and `tax_rate`. Store `result.reference.to_h` with your order. It holds JSON-safe values only (`invoice_datetime` is an ISO 8601 string in UTC+8), so it survives a JSON column. Pass it back as it is as `invoice:`, or pass the reference itself. A stored time has to carry its offset: `"2026-08-01 10:00"` is refused rather than read in the wrong zone, and a plain `"2026-08-01"` is that day in Taipei. A plain invoice number also works, but a provider that needs more raises `ValidationError` and names the field. To find an invoice without its number, query `invoice: { order_id: "ORDER_1" }` on a provider that declares `QUERY_BY_ORDER_ID`. `void_allowance` takes `allowance:`, an `AllowanceReference` from `AllowanceResult#reference`.

Inputs accept plain hashes (string or symbol keys) — enum fields take the canonical symbol (`:taxable`) or a wire-style string (`"TAXABLE"`). They are validated and coerced into immutable value objects before anything hits the network; a malformed request raises `Einvoice::ValidationError` locally.

The checks:

- A buyer `ubn` is 8 digits, a company's 統一編號. (MIG 表 4-7 allows a BAN of 8 to 10 digits; the 9- and 10-digit forms are not used for a buyer.) A B2B invoice needs one, and an explicit `category` has to agree with it.
- Totals are whole numbers and not negative. Item quantity, price and amount are numbers with at most 7 decimal places.
- A mobile barcode is `/` and 7 characters. A citizen certificate is 2 letters and 14 digits. These formats come from the providers' docs; the MIG lists the carrier types only.
- `tax_rate` is a decimal, such as `0.05`, and has to be a MIG rate. On an issue it defaults to `0.05` for taxable sales and `0` for zero-rated or tax-free sales. A special-tax invoice needs it.
- The amounts agree with the items (below).
- A void reason is at most 20 characters. A void allowance reason defaults to `作廢折讓`.

### Amounts and tax

The core computes the tax from the items. `price_mode` says if the item amounts include tax, `tax_type` is the type of the whole invoice (an item can have its own), and `tax_rate` is the rate. The result is `input.tax_breakdown`: the net amount, tax and gross amount of each line, and the MIG totals. Adapters read it and do not compute tax themselves. The core never changes your items.

Your `amount` is checked against it. An invoice follows F0401: for a consumer the tax is inside `sales_amount` and `tax_amount` is `0`. For a business buyer `tax_amount` is `round(taxable sales × tax_rate)`:

```ruby
amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }  # 100 with tax, to a business
```

An allowance follows G0401: `sales_amount` excludes tax, for a consumer too. It takes `tax_type` and `tax_rate` from the invoice reference, so pass `issued.reference`, or give them yourself. There is no default, so a zero-rated invoice is never credited with 5% tax. When the invoice has mixed tax, give every item its `tax_type`.

```ruby
provider.allowance(
  invoice: issued.reference, allowance_id: "AL_1", price_mode: "TAX_INCLUSIVE",
  items: [{ description: "退貨", quantity: 1, unit_price: 100, amount: 100 }],
  amount: { sales_amount: 95, tax_amount: 5, total_amount: 100 }
)
```

### Errors

Every failure is an `Einvoice::Error` subclass carrying a stable `#code`, the provider's `#raw_code` / `#raw_message`, and an optional action-oriented `#reason`. `#group` tells which side failed: `:invoice` (the request breaks a rule of the MOF, or the invoice is not in the state it needs) or `:provider` (the account, the connection, or the provider's own service). Rescue precisely or broadly:

```ruby
begin
  provider.void(invoice: invoice.reference, reason: "customer cancelled")
rescue Einvoice::ConflictError => e
  e.reason   # => :already_voided  (idempotent — treat as success)
rescue Einvoice::Error => e
  e.code     # => :network, :auth, :not_found, …
end
```

### Credentials and buyer data

- `inspect`, `to_s` and `pp` show results with `raw=[FILTERED]`, because `raw` is the provider's response and holds the buyer's data. Read `#raw` directly when you need it. An adapter's client shows its keys as `[FILTERED]`.
- `base_url` has to use https. Only localhost may use http, for tests.

### Capabilities

A provider declares what it supports; feature-detect instead of discovering a gap when a request fails.

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

Everything above works unchanged — `issue` / `void` / `allowance` / `void_allowance` / `query` take the same unified input and return the same value types. The AES-128-CBC envelope, ECPay's two layers of result codes, and its field rules stay inside the adapter.

To try it without an account, use ECPay's published sandbox credentials (shared with every other developer — never for anything real):

```ruby
provider = Einvoice::ECPay::Provider.new(**Einvoice::ECPay::SANDBOX)
```

A few things worth knowing:

- **Paper vs. electronic is derived.** An invoice with a carrier or a donation is electronic (`Print=0`); anything else prints, and ECPay then requires a buyer name and address.
- **Mixed tax rates are derived too.** Items that disagree on `tax_type` produce a 混合稅率 (TaxType 9) invoice; you don't ask for it explicitly.
- **Void, allowance and a query by number need the invoice's issue date.** It comes from `invoice.invoice_datetime`. If the reference has an `order_id` instead, the adapter looks the date up first. A failed lookup raises `ProviderError` with `reason: :lookup_failed`. A plain number is not enough.
- **Void allowance needs the invoice number**, so pass the `AllowanceReference`, not only the allowance number.
- **No foreign currency.** ECPay's B2C API has no such field, so a non-TWD `currency` raises `UnsupportedError` rather than being filed as TWD.
- **A taxable invoice is 5%.** ECPay fixes the rate by tax type, so another `tax_rate` raises `UnsupportedError`.
- **Carrier validation**: `validate_carrier({ type: "MOBILE_BARCODE", code: "/ABC1234" })` (the `Provider` method behind `CARRIER_VALIDATION`; ECPay can check a mobile barcode only), `validate_love_code("168001")`, `love_code_organ_name("168001")` — these ask ECPay, so they need this adapter and its credentials. For 愛心碼 there is also `Einvoice::MOF::DonationCodes` (below), which asks 財政部 directly and needs neither.
- **Anything else**: ECPay has ~25 further B2C endpoints (延遲開立, 字軌設定, 列印, 通知 …). Reach them through `provider.raw(path, payload)`, which applies the envelope, encryption and error mapping for you.

## 財政部 lookups

Provider-independent clients for 財政部's own public services. They issue nothing and hold no credentials, so they work whichever center you use — or before you have picked one.

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

This is **not** wired into `Input`, and deliberately so: validation there is local and synchronous, and issuing an invoice must never depend on a third party being reachable. `Input` checks the shape of a 愛心碼; whether it is *registered* is a question you ask when it suits you — at order time, or once at boot via `#all` to build your own set for offline checks.

The dataset needs no credentials today. Its published OpenAPI declares `api_key` and `oauth2` schemes even so, so a 401/403 raises `Einvoice::AuthError` saying exactly that rather than surfacing as a parse failure.

## Development

```bash
bin/setup          # install dependencies
bundle exec rspec  # run the specs
bundle exec rake   # default task: rspec
```

The `"an invoice provider"` shared examples (`spec/support/shared_examples/`) are the executable contract every adapter runs, so a new adapter proves it honours the unified model by including one line.

To write a new adapter, start with the provider notes in [`docs/providers/`](docs/providers/README.md). Read them in this order: the MOF MIG note (the standard every provider follows), then the ECPay note (the one provider with an adapter, to see how a note maps to code), then the note for your provider, and then the shared examples above.

The ECPay adapter is tested in three layers, two of which run offline in CI:

1. **The contract, against a wire-format fake.** The shared examples run through an in-process fake that speaks the real protocol — AES envelope, PHP url-encoding, ECPay's own RtnCodes — so a request only passes if the encryption and field mapping are genuinely correct. It is stateful, which is what lets the contract drive issue → allowance → void as a sequence.
2. **Recorded real responses (VCR).** `spec/einvoice/ecpay/recorded_spec.rb` replays cassettes captured from ECPay's stage host, so the field names, value types and error codes under test are ECPay's own rather than our reading of the docs. Re-record with `VCR_RECORD=1` after bumping the epoch in that spec — cassettes only ever hold sandbox traffic.
3. **The live API, opt-in.** What keeps the other two honest:

   ```bash
   ECPAY_LIVE=1 bundle exec rspec spec/einvoice/ecpay/live_spec.rb
   ```

   It defaults to the public sandbox credentials, so no setup is needed; override with `ECPAY_MERCHANT_ID` / `ECPAY_HASH_KEY` / `ECPAY_HASH_IV` to point it at your own stage account. Excluded from CI because it needs the network and a shared sandbox.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
