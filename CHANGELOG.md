# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

2.0 is a rewrite. 1.x was a client for one provider, Tradevan. 2.0 has one interface for several providers, so an application can switch providers by changing the constructor. **2.0 is not backward compatible.** 1.x stays in maintenance on `1-x-stable`. Pin `~> 1.4` if you depend on it.

### Added
- **One interface for every provider.** `Einvoice::Provider` has the five operations: `issue`, `void`, `allowance`, `void_allowance` and `query`. They take plain hashes or value objects, and return value types (`Data.define`).
- **Load only the provider you use.** `require "einvoice"` loads the core. Each adapter loads with its own `require`, such as `require "einvoice/ecpay"`, and so do the 財政部 lookups (`require "einvoice/mof"`). 2.0 has no runtime dependencies.
- **Checks before the call.** Input is checked locally, and a bad request raises `Einvoice::ValidationError` before anything goes over the network. The core checks the MIG rules that hold at every provider, so every provider answers them alike: for example the 統一編號, the 愛心碼 (3 to 7 digits), carrier codes, the MIG tax rates and the MIG field lengths. The README lists them.
- **The core computes tax.** For an issue and an allowance, the core computes the tax of every line and the MIG totals from the items, `price_mode`, `tax_type` and `tax_rate`, as `#tax_breakdown`. Adapters do not compute tax, so the same input gets the same tax at every provider. `amount` is optional: without it, the core fills it in. A given `amount` is checked against the breakdown, by F0401 for an invoice and G0401 for an allowance.
- **References.** Issue, query and allowance results return a `#reference` that holds what a provider asks for later. Pass it to `void`, `allowance` and `query`, and you do not need to know each provider's needs. `reference.to_h` is JSON-safe, so you can store it with your order. A time without an offset is refused when it is read back. An allowance takes its tax type and rate from the reference, with no default, so a zero rated invoice is not credited with tax. An allowance item may not be negative (MIG 4.1). An invoice item may be, as a discount line.
- **MIG names and types.** Dates are `invoice_datetime` (a `Time` in UTC+8), `allowance_date` (a `Date`) and `cancel_datetime`. A zero rated invoice takes `customs_clearance_mark` and `zero_tax_rate_reason`.
- **Errors you can act on.** Every failure is an `Einvoice::Error` with a stable `#code`. `#group` says which side failed, the invoice or the provider, and `#reason` says what to do next. For example, `:already_voided` on a void is safe to treat as done, but `:allowance_blocked_by_void` means that no credit was made. A `ValidationError` means that no provider takes the input. An `UnsupportedError` means that this provider does not take it, but another one may. A `NetworkError` can be retried. `#raw_code` and `#raw_message` keep the provider's own answer.
- **Capabilities.** Each provider declares the optional features it has, such as B2B, mixed tax, query by order id and carrier validation (`#supports?`, `#validate_carrier`). A missing feature raises `UnsupportedError`. `#query_statuses` lists the statuses that `query` can return, because some providers cannot tell every state.
- **`Einvoice::MockProvider`**, an in-memory provider for testing your application. It follows the same contract and the same invoice states as a real adapter.
- **ECPay (綠界)**, the first adapter. Its live spec runs against ECPay's public stage, and its specs replay responses recorded there.
- **Amego (光貿).** Its live spec runs against Amego's public test account.
- **ezPay (簡單行動支付), experimental.** Built from ezPay's manuals, and checked against their samples. Nobody has run it against ezPay, so test it against your own test shop first.
- **Tradevan (關貿) DEFAULTAPI, experimental.** Ported from the 1.x client. Nobody has run it against the live API, so test it against your own account first.
- **`Einvoice::MOF::DonationCodes`**, which looks up a 愛心碼 in 財政部's open data, in place of the list that 1.x shipped.
- **Data kept out of logs.** `inspect`, `to_s` and `pp` show a result's raw response, a buyer's personal data and a client's credentials as `[FILTERED]`. `base_url` must use https (localhost may use http), and must not carry a user, a password, a query or a fragment.

Each provider's note in `docs/providers/` gives its mapping, its limits and what was verified, and how sure we are of each.

### Removed
- The 1.x Tradevan layer (`Client`, `Configuration`, `Connection`, `Result` and the Tradevan models). The unified core and the adapters replace it. Tradevan DEFAULTAPI is back as an adapter.
- `lib/einvoice/donation_unit_list.json` and the scheduled workflow that refreshed it. `Einvoice::MOF::DonationCodes` looks the codes up live.

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
