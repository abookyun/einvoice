# Shared wire fixtures

These files are a copy of the cross-language wire fixtures in [paid-tw/einvoice](https://github.com/paid-tw/einvoice/tree/16b4d9e9f489625f048625686a2a4c8d642e61ee/fixtures). The TypeScript SDK runs the same files.

- Source commit: `16b4d9e9f489625f048625686a2a4c8d642e61ee` (2026-08-15)
- Copied on: 2026-10-30
- Files: `ecpay/*.json`, not changed

They pin what ECPay receives for a given input, and how ECPay's error codes are classified. `spec/einvoice/ecpay/shared_fixtures_spec.rb` runs them.

The fixture inputs use the TypeScript input shape. The spec translates each input to the Ruby shape and leaves the expected wire data and errors as they are. The Ruby shape is different on purpose: the original invoice is an `InvoiceReference` (see `docs/providers/README.md`), not `invoiceNumber` with `providerOptions.invoiceDate`. The amounts are translated too: the TypeScript inputs give tax `0` with the tax inside the total, and the Ruby core keeps the tax apart for a B2B invoice (F0401) and for an allowance (G0401).

To update, copy the files from a newer commit, then change the commit and the date above.
