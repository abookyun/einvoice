# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

2.0 is a ground-up, provider-agnostic rewrite. The 1.x line (a single-provider Tradevan wire-format client) is now in maintenance mode on `1-x-stable`; pin `~> 1.4` if you depend on it. **2.0's unified model is not backward compatible.**

### Added
- A `Einvoice::Provider` contract modeling the five e-invoice operations (issue / void / allowance / void-allowance / query) once, provider-agnostic, backed by unified value types (`Data.define`) and an input coercion + validation layer that raises `Einvoice::ValidationError` locally before anything hits the network. The checks cover buyer `ubn`, B2B and `category`, non-negative totals, item numbers, carrier code shapes (from the providers' docs: the MIG lists only the carrier types), `tax_rate` (a decimal MIG rate) and void reasons. A value object built with `.new` goes through the same checks as a Hash.
- A normalized error hierarchy (`Einvoice::Error` and subclasses) carrying a stable `#code`, the provider's raw `#raw_code` / `#raw_message`, and an optional action-oriented `#reason` (e.g. `:already_voided`). `#group` says which side failed: `:invoice` or `:provider`.
- Dates follow the MIG names and types: `invoice_datetime` (a `Time` in UTC+8), `allowance_date` (a `Date`) and `cancel_datetime` (a `Time`, or `nil` when the provider does not return it). An issue input has no date: the provider records the time of the operation.
- References: `void`, `allowance` and `query` take `invoice:`, an `InvoiceReference` (or a plain invoice number). `void_allowance` takes `allowance:`, an `AllowanceReference`. Issue, query and allowance results return one as `#reference`, so a caller passes it on and does not need to know what each provider asks for. A query by order id is `invoice: { order_id: }`. When a provider needs a field the reference lacks, the adapter may look it up; a failed lookup raises `ProviderError` with `Reason::LOOKUP_FAILED`. `reference.to_h` is the stored form: JSON-safe, with times as ISO 8601 in UTC+8. Input reads it back, and refuses a time string without an offset.
- The core computes tax, for issue and allowance alike, from the items, `price_mode`, `tax_type` and `tax_rate`. The result is `#tax_breakdown` on the input: each line's net amount, tax and gross amount and unit prices, and the MIG totals. Adapters read it and do not compute tax. The caller's `AmountSummary` is checked against it: an invoice follows F0401 (for a business buyer `tax_amount` is `round(taxable sales × tax_rate)`, for a consumer it is `0`), and an allowance follows G0401 (`sales_amount` excludes tax). The core does not change the caller's items.
- An allowance takes `price_mode`, `tax_type` and `tax_rate`. The tax type and rate come from the invoice reference when the input has none, and there is no default, so a zero-rated invoice is not credited with tax. `InvoiceReference` and the issue and query results carry `tax_type` (`:mixed` for mixed tax) and `tax_rate`.
- `Provider#validate_carrier` is the method behind `CARRIER_VALIDATION`. It raises `UnsupportedError` when the provider does not declare it. ECPay implements it for a mobile barcode and drops `validate_mobile_barcode`.
- Results show `raw=[FILTERED]` in `inspect`, `to_s` and `pp`, and the ECPay client hides its HashKey and HashIV. `base_url` has to use https (localhost may use http).
- A `Capability` system so providers declare what they support (`#supports?`, `#assert_supports!`) instead of feature gaps surfacing as runtime failures. This alpha's only adapter (ECPay) declares issue / void / allowance / void-allowance / query, B2B, mixed tax rates, query by order id, and carrier validation. It does not declare foreign currency.
- `Einvoice::MockProvider`, an in-memory reference implementation of the `Provider` contract for testing application code without a real adapter. It refuses a duplicate order id, and refuses B2B and mixed tax rates unless it declares them, as a real adapter does.
- **ECPay (綠界) provider**: the first real adapter on the unified core, covering all five operations plus carrier validation, with AES envelope crypto and specs replayed from VCR cassettes recorded against ECPay's public stage API.
- ECPay error mapping distinguishes a voided invoice being idempotently re-voided (no-op, safe to treat as success) from an allowance being refused because the invoice was already voided (no credit was recorded; treating it as success would book a refund that never happened). Reusing one reason for both was a real risk of double-crediting a customer.
- ECPay follows its note in `docs/providers/ecpay/b2c.md`: a cancelled (註銷) invoice queries as status `nil`, HTTP 403 is a `NetworkError` with `RATE_LIMITED`, `TransCode` 104 and 115 are `AuthError`, three more business codes from the shared fixtures are mapped, a taxable rate other than 0.05 raises `UnsupportedError` (on an allowance too), and an allowance sends tax-included unit prices and amounts from the core's breakdown, with its total checked before the call.
- A live client for 財政部's 愛心碼 (donation code) dataset (`Einvoice::MOF::DonationCodes`), replacing the previously bundled static snapshot with a real-time lookup.

### Fixed
- Core input claimed to validate a donation's 愛心碼 but only checked that `npoban` was present, so `"abc"`, `"1"`, and a 14-digit code all reached the provider unrejected. It now enforces the MIG shape (3–7 digits) up front, via a single pattern (`Donation::CODE_FORMAT`) shared with the ECPay payload check and the 財政部 client, instead of three copies that could silently drift apart.

### Removed
- The legacy Tradevan direct-API layer (`Client`, `Configuration`, `Connection`, `Result`, and the Tradevan-specific models) — superseded by the unified core and the provider adapter model.
- `lib/einvoice/donation_unit_list.json` and the scheduled workflow that refreshed it, now that donation codes are looked up live against 財政部 instead of shipped as a static snapshot.

### Changed
- CI now also runs for pull requests targeting `2.0.0-alpha`.

## [1.4.0] - 2026-08-08

### Changed
- **TLS certificate verification is now enabled by default.** Previously every request was sent with `ssl: { verify: false }`, regardless of configuration. If you were relying on that behavior (e.g. against an endpoint with an incomplete certificate chain), set `config.ssl_verify = false` or pass `ssl_verify: false` to `Provider.new` to restore the old behavior.
- `Client` now delegates to the provider via `public_send` instead of `send`, and implements `respond_to_missing?`. Private provider methods (e.g. `encrypt`, `connection`) are no longer reachable through `Client`.

### Fixed
- `TotalValidator` comparison was inverted and compared a `String` against an `Integer`, so it never actually validated anything. It now correctly fails when `total` doesn't match the sum of item totals.
- `AllowanceNumberValidator` and `IssueItem#invoiceTime`'s format regexp had broken escape sequences (`\A` and `\d` collapsing to literal characters in a double-quoted string), causing them to reject all valid input.
- `ItemListValidator` pushed directly onto `record.errors[:itemList]`, which is deprecated in Rails 6.1 and removed in 7.0. It now uses `errors.add` and actually registers errors again.
- Tradevan response decoding used `JSON.load`, which is unsafe for untrusted input. Switched to `JSON.parse`.
- `lib/einvoice/donation_unit_list.json` was stale since 2023-12 (the scheduled update workflow had been silently broken), causing `DonationUnitValidator` to reject currently valid donation codes and accept retired ones. The list has been refreshed (~340 entries changed).

### Added
- Specs for `Client` delegation, `Configuration#ssl_verify`, `Provider#connection` SSL behavior, the validator fixes above, and the previously-untested `decode_tradevan` middleware.

### Internal
- CI coverage reporting migrated from Code Climate (discontinued) to Codecov.
- The scheduled `cron.yml` workflow that refreshes the donation unit list has been repaired — it depended on two archived GitHub Actions (`actions/setup-ruby`, `mikeal/publish-to-github-action`) and hadn't run successfully since 2023-12.

---

Versions prior to 1.4.0 were not tracked in this file. See the [release history](https://github.com/abookyun/einvoice/releases) and [commit log](https://github.com/abookyun/einvoice/commits/main/) for earlier changes.
