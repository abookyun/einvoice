# Upgrading from 1.x to 2.0

English | [繁體中文](upgrading-to-2.0.zh-TW.md)

1.x is a client for one value-added center, Tradevan 關貿. You build Tradevan's own payload, and you read Tradevan's own response. 2.0 has one interface for several centers. You describe the invoice in a unified model, and an adapter turns it into Tradevan's payload. So 2.0 is not a drop-in update: every call changes.

This guide is for a 1.x user who wants to keep Tradevan. The 2.0 README describes the unified model in full.

## Should you upgrade now?

The 2.0 Tradevan adapter is **experimental**. Tradevan gives its API docs to customers only, so the adapter is built from the 1.x client and its README. Nobody has run it against the live API yet.

If you need Tradevan in production and cannot test the adapter first, stay on 1.x. Pin it, and it keeps getting bug and security fixes on the [`1-x-stable`](https://github.com/abookyun/einvoice/tree/1-x-stable) branch:

```ruby
gem "einvoice", "~> 1.4"
```

If you can test 2.0 against your own Tradevan account, read on. Please report what you find, above all the answer to the `qty` question below.

## Requirements

- Ruby 3.2 or later. 1.x needed 3.1.
- 2.0 has no runtime dependencies. faraday, multi_xml, activemodel and activesupport are gone. If your app uses one of them itself, add it to your own Gemfile.

## Setup

1.x had a global configuration and a `Client`. 2.0 has no global configuration. You build a provider with its settings, one per account:

```ruby
# 1.x
Einvoice.configure do |config|
  config.endpoint = ENV["EINVOICE_ENDPOINT"]
  config.client_id = ENV["EINVOICE_CLIENT_ID"]
  config.client_secret = ENV["EINVOICE_CLIENT_SECRET"]
  config.encryption_keys = { key1: ENV["KEY1"], key2: ENV["KEY2"] }
end
client = Einvoice::Client.new(Einvoice::Tradevan::Provider.new)
```

```ruby
# 2.0
require "einvoice/tradevan"

provider = Einvoice::Tradevan::DefaultAPI::Provider.new(
  base_url: ENV["EINVOICE_ENDPOINT"],
  acnt: ENV["EINVOICE_CLIENT_ID"],
  acntp: ENV["EINVOICE_CLIENT_SECRET"],
  key1: ENV["KEY1"], key2: ENV["KEY2"],
  company_un: "12345678", org_id: "ABCDE",
  paper_print_mode: "0", invoice_alarm_mode: "4",
  invoice_paper_returned: "N", allowance_paper_returned: "N"
)
```

| 1.x | 2.0 |
| --- | --- |
| `endpoint` | `base_url`, the same value. It must use https |
| `client_id`, `client_secret` | `acnt`, `acntp` |
| `encryption_keys[:key1]`, `[:key2]` | `key1`, `key2` |
| `endpoint_url` | Gone. `base_url` takes any host |
| `format` | Gone. 2.0 sends JSON |
| `ssl_verify` | Gone. 2.0 always checks the TLS certificate |
| `companyUn`, `orgId`, `paperPrintMode`, `invoiceAlarmMode`, `invoicePaperReturned`, `allowancePaperReturned` in each payload | Constructor settings, set once |

A member carrier also needs `member_carrier_type:`, your 6-character code from Tradevan.

## Issue an invoice

In 1.x you built the whole `issueData`: the `saleIdentifier`, the date and time, the totals and the tax of each item. In 2.0 you give the order, the buyer and the items. The core computes the tax and the totals, and the adapter builds the rest.

```ruby
# 1.x
result = client.issue(
  companyUn: "12345678", orgId: "ABCDE", type: "I",
  saleIdentifier: "12345678_ABCDE_53b2a44e4b3c", transactionNumber: "53b2a44e4b3c",
  transactionDate: "20160425", transactionTime: "12:34:56", total: "20000",
  paperPrintMode: "0", invoiceAlarmMode: "4", donate: "N",
  carrierType: "3J0002", carrierId: "/ABC1234", carrierIdHidden: "/ABC1234",
  receiverEmail: "john@example.com",
  itemList: [{ saleIdentifier: "12345678_ABCDE_53b2a44e4b3c", serialNumber: "0001",
               productName: "Coffee Latte", qty: "4", price: "5000",
               itemTotal: "20000", taxType: "T" }]
)
result.data["invoiceNumber"]
```

```ruby
# 2.0
result = provider.issue(
  order_id: "53b2a44e4b3c",
  buyer: { email: "john@example.com" },
  carrier: { type: "MOBILE_BARCODE", code: "/ABC1234" },
  tax_type: "TAXABLE",
  price_mode: "TAX_INCLUSIVE",
  items: [{ description: "Coffee Latte", quantity: 4, unit_price: 5000, amount: 20000 }]
)
result.invoice_number   # => "GX38551078"
store(result.reference.to_h)
```

- The adapter builds `saleIdentifier` as `"#{company_un}_#{org_id}_#{order_id}"`. Your `order_id` becomes `transactionNumber`.
- Store `result.reference.to_h` with your order. Void, allowance and query read what they need from it, so you do not keep the `saleIdentifier` or the invoice date yourself.
- A buyer with a `ubn` makes a B2B invoice. Tradevan's adapter takes a tax rate of 5% only, and no mixed tax.

## Void, allowance and void allowance

1.x had `cancel` for both voids, and `issue` with `type: "A"` for an allowance. 2.0 has one method for each:

```ruby
provider.void(invoice: reference, reason: "客戶取消")

allowance = provider.allowance(
  invoice: reference, allowance_id: "53b2a44e4b3d", price_mode: "TAX_INCLUSIVE",
  items: [{ description: "Coffee Latte", quantity: 1, unit_price: 5000, amount: 5000 }]
)

provider.void_allowance(allowance: allowance.reference)
```

- A void needs a `reason` now, at most 20 characters.
- An allowance takes the tax type and rate from the reference, and the core computes `itemExclude`, `tax` and the totals.
- `allowance_id` becomes `transactionNumber`, and the adapter builds `allowanceIdentifier` with the same prefix as `saleIdentifier`.

## Invoices that 1.x issued

Those invoices have no 2.0 reference. Pass what you stored instead:

```ruby
provider.void(
  invoice: { number: "GX38551078" },
  reason: "客戶取消",
  provider_options: { sale_identifier: "12345678_ABCDE_53b2a44e4b3c" }
)

provider.allowance(
  invoice: { number: "GX38551078" },
  tax_type: "TAXABLE", tax_rate: 0.05,
  allowance_id: "53b2a44e4b3d", price_mode: "TAX_INCLUSIVE",
  items: [{ description: "Coffee Latte", quantity: 1, unit_price: 5000, amount: 5000 }],
  provider_options: { sale_identifier: "12345678_ABCDE_53b2a44e4b3c" }
)
```

If your 1.x `saleIdentifier` was `"#{companyUn}_#{orgId}_#{transactionNumber}"`, you can pass `invoice: { number:, order_id: transactionNumber }` instead, and the adapter builds it again. For an allowance without the invoice date, the adapter queries the invoice by number first.

## Results and errors

1.x returned a `Result`. You checked `successful?`, read `data`, and matched the text in `failReason`. 2.0 returns value objects on success, and raises an `Einvoice::Error` on failure:

```ruby
begin
  provider.void(invoice: reference, reason: "客戶取消")
rescue Einvoice::ConflictError => e
  # Only :already_voided means that the invoice is voided. Another reason,
  # such as :void_blocked_by_allowance, means that it is not.
  raise unless e.reason == :already_voided
rescue Einvoice::Error => e
  e.raw_message   # Tradevan's own text
  raise
end
```

The README lists what each error class asks you to do. Tradevan publishes no error codes, so the adapter matches known text, and unknown text is a `ProviderError`.

## Other 1.x calls

The unified model has `issue`, `void`, `allowance`, `void_allowance` and `query`. The other DEFAULTAPI endpoints are still there through `raw`, which encrypts the parameters and returns the decrypted response:

| 1.x | 2.0 |
| --- | --- |
| `search_invoice_detail(number)` | `provider.query(invoice: { number: })` |
| `search_invoice_by_member_id(payload)` | `provider.raw("get/searchInvoiceByMemberId", payload)` |
| `search_invoice_by_transaction_number(payload)` | `provider.raw("get/searchInvoiceInfoByTransactionnumber", payload)` |
| `send_card_info_to_cust(payload)` | `provider.raw("get/sendCardInfotoCust", payload)` |
| `get_invoice_mark_info(payload)` | `provider.raw("get/getInvoiceMarkInfo", payload)` |
| `get_invoice_content(payload)` | `provider.raw("get/getInvoiceContent", payload)` |
| `get_donate_unit_list(company_un)` | `Einvoice::MOF::DonationCodes`, see below, or `provider.raw("get/getDonateUnitList", { companyUn: })` |

## Donation codes

1.x shipped a list of 愛心碼 in `donation_unit_list.json`, and the list went out of date. 2.0 checks the format of a 愛心碼 (3 to 7 digits) and leaves the list out. To check that a code is registered, ask 財政部's open data:

```ruby
require "einvoice/mof"

Einvoice::MOF::DonationCodes.new.exist?("2718")  # => true
```

## Before you go live

- **Check `qty`.** The sources disagree on whether Tradevan reads `qty` as units, or as units × 1000. The adapter sends units, so 4 items are `qty` `"4"`. If your 1.x code sent units × 1000 and Tradevan accepted it, please open an issue. Issue one test invoice and check the quantity in Tradevan's back office before you go live.
- **Test every operation you use** against your own account. [`docs/providers/tradevan/defaultapi.md`](providers/tradevan/defaultapi.md) lists what the adapter guesses, and how sure we are of each guess.

## Switching to another center

With 2.0, the five unified calls (`issue`, `void`, `allowance`, `void_allowance` and `query`) take the same input for ECPay, Amego and ezPay too. Moving to one of them needs a contract and an account with that center, and you change the `require` and the constructor. Some things do not move with you:

- **Invoices stay at the center that issued them.** Void, credit and query an old invoice with the provider for that center.
- **A plain invoice number is not always enough.** The reference from `issue` holds what each center needs. With a number alone, ECPay also needs the issue date or the order id, and ezPay needs the random code.
- **The `raw` calls in the table above.** Each center has its own endpoints, and its own `raw` arguments.

The README lists what each center supports.
