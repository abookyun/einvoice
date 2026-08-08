# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.4.0] - 2026-08-08

### Changed
- **TLS certificate verification is now enabled by default.** Previously every
  request was sent with `ssl: { verify: false }`, regardless of configuration.
  If you were relying on that behavior (e.g. against an endpoint with an
  incomplete certificate chain), set `config.ssl_verify = false` or pass
  `ssl_verify: false` to `Provider.new` to restore the old behavior.
- `Client` now delegates to the provider via `public_send` instead of `send`,
  and implements `respond_to_missing?`. Private provider methods (e.g.
  `encrypt`, `connection`) are no longer reachable through `Client`.

### Fixed
- `TotalValidator` comparison was inverted and compared a `String` against an
  `Integer`, so it never actually validated anything. It now correctly fails
  when `total` doesn't match the sum of item totals.
- `AllowanceNumberValidator` and `IssueItem#invoiceTime`'s format regexp had
  broken escape sequences (`\A` and `\d` collapsing to literal characters in a
  double-quoted string), causing them to reject all valid input.
- `ItemListValidator` pushed directly onto `record.errors[:itemList]`, which
  is deprecated in Rails 6.1 and removed in 7.0. It now uses `errors.add` and
  actually registers errors again.
- Tradevan response decoding used `JSON.load`, which is unsafe for untrusted
  input. Switched to `JSON.parse`.
- `lib/einvoice/donation_unit_list.json` was stale since 2023-12 (the
  scheduled update workflow had been silently broken), causing
  `DonationUnitValidator` to reject currently valid donation codes and accept
  retired ones. The list has been refreshed (~340 entries changed).

### Added
- Specs for `Client` delegation, `Configuration#ssl_verify`,
  `Provider#connection` SSL behavior, the validator fixes above, and the
  previously-untested `decode_tradevan` middleware.

### Internal
- CI coverage reporting migrated from Code Climate (discontinued) to Codecov.
- The scheduled `cron.yml` workflow that refreshes the donation unit list
  has been repaired — it depended on two archived GitHub Actions
  (`actions/setup-ruby`, `mikeal/publish-to-github-action`) and hadn't run
  successfully since 2023-12.

---

Versions prior to 1.4.0 were not tracked in this file. See the
[release history](https://github.com/abookyun/einvoice/releases) and
[commit log](https://github.com/abookyun/einvoice/commits/main/) for earlier changes.
