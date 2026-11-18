# Known issues

This note collects the issues that we found while the adapters went into `2.0.0-alpha` (PRs #39 to #42), and that we chose to handle together. It is a working list, not user documentation. Remove an item when it is fixed, and remove the note when the list is empty.

Each item says what is wrong, where, and what it would take. Items under "Decide first" need a decision before anyone writes code.

## Fix before the next release

### 1. The Amego client prints its app key and takes any endpoint

- **Where:** `lib/einvoice/amego/client.rb`.
- **What:** The client does not override `inspect`, so `inspect`, `pp` and logging print `app_key`. The `endpoint` argument is not checked, so a remote `http://` URL sends invoice data without TLS. The ECPay, ezPay and Tradevan clients do both through `Redaction.base_url!` and their own `inspect`.
- **Fix:** As in the ezPay client: check the URL with `Redaction.base_url!`, and show `app_key` as `[FILTERED]`.
- **Found by:** CodeRabbit, in the review of the ezPay client (#42). The Amego client was already merged.
- **Risk today:** none outside this repo. The tag `v2.0.0.alpha1` was made before the Amego adapter.

### 2. The Amego client calls its URL `endpoint`

- **Where:** `lib/einvoice/amego/client.rb` and `lib/einvoice/amego/provider.rb`.
- **What:** The other three adapters take `base_url:`. A caller who switches providers has to rename the argument.
- **Fix:** Rename it to `base_url:`. Fix it together with item 1. 2.0 is not released yet, so no deprecation is needed.

## Consistency across the adapters

### 3. Each client has its own HTTP handling

- **What:** Every client builds the request, reads the body and maps HTTP failures by itself. The same two bugs (an unchecked HTTP status, and `rescue StandardError`) had to be fixed in Amego (#41) and again in ezPay (#42). Tradevan still has `rescue StandardError` (see the Tradevan PR).
- **Fix:** Move the shared part into the core: the network rescue, the "a body the provider wrote decides, else the HTTP status" rule, and the `base_url` check. Each client then keeps only its envelope and its crypto.
- **When:** after all four adapters are merged, so the shared part is cut from four real clients.

### 3a. `base_url` checks that every client needs

- **Query or fragment:** `Redaction.base_url!` accepts `https://host/gateway?region=tw`. A client that appends its path builds `/gateway?region=tw/DEFAULTAPI/...`, and the request goes to the wrong path. The check should refuse a query and a fragment. It lives in the core, so it changes every client.
- **Frozen:** the Tradevan client freezes `base_url` (#43), so a caller cannot change it after the checks. The ECPay, Amego and ezPay clients do not.
- **Found by:** CodeRabbit, in the review of the Tradevan adapter (#43). Fix it with item 3.

## Decide first

### 4. Query status means different things

- **What:** ECPay and Amego return `ISSUED`, `VOIDED` or `ALLOWANCE`. ezPay returns only `VOIDED` and else `nil`, because its status does not show an allowance. Tradevan returns only `ALLOWANCE` and else `nil`, because its status codes are unknown. The shared contract accepts `nil` everywhere, so a caller cannot tell in advance which values a provider gives.
- **Options:** a capability that says the status is complete, or a list on each adapter of the statuses it can return.

### 5. The zero-rated fields have a different key per adapter

- **What:** The customs clearance mark is `provider_options[:clearance_mark]` for ECPay, `:customs_clearance_mark` (with `:zero_tax_rate_reason`) for Amego, and `:customs_clearance` for ezPay. Tradevan does not send it. An export invoice cannot switch providers without code changes.
- **Option:** unified input fields for the MIG `CustomsClearanceMark` and `ZeroTaxRateReason`.

### 6. Provider limits raise different error classes

- **What:** An input that the MIG allows but one provider refuses is sometimes `UnsupportedError` and sometimes `ValidationError`. ezPay shows both: mixed tax on B2B is `UnsupportedError`, a carrier on B2B is `ValidationError`. A caller who rescues `UnsupportedError` to fall back misses the second.
- **Option:** a rule in the unified model: a provider limit is `UnsupportedError`, and `ValidationError` is only for input that breaks the MIG.

### 7. A stale timestamp is a different error class

- **What:** ECPay maps it to `AuthError`. Amego and ezPay map it to `ValidationError`. All three set `Reason::STALE_TIMESTAMP`.
- **Option:** pick one class. It is a clock problem, not a credentials or an input problem.

### 8. ECPay's `RqHeader.Revision`

- **What:** The adapter sends `Revision: "3.0.0"`. The current ECPay docs do not list it, and stage accepts a request without it. See open question 1 in `docs/providers/ecpay/b2c.md`.
- **Decide:** keep the field or drop it.

## Gaps in the shared contract

### 9. The contract does not test some promises of the unified model

- **What:** It does not test that a reference survives `to_h` and a JSON round trip, the `reason` of a `ConflictError`, or that a provider limit is `UnsupportedError`. Every case uses the same small input: one whole-number item, a member carrier, an ASCII order id and a short reason. So the gaps in items 4 to 6 pass the contract.
- **Fix:** add these cases once items 4 to 6 are decided.

## Ideas from a user's point of view

These came from a review that read the gem as a new user would. None of them is a bug.

- **`amount` could come from the core.** The core computes the tax breakdown, but the caller still has to give `amount` for the core to check.
- **`raw` takes different arguments per adapter**, so code that uses `raw` cannot switch providers.
- **No upgrade guide from 1.x.** The CHANGELOG only says that 2.0 is not compatible.
- **No callbacks.** Delayed issue and online allowances need them.
