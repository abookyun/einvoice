# Known issues

This note collects the issues that we found while the adapters went into `2.0.0-alpha` (PRs #39 to #42), and that we chose to handle together. It is a working list, not user documentation. Remove an item when it is fixed, and remove the note when the list is empty.

Each item says what is wrong, where, and what it would take. Items under "Decide first" need a decision before anyone writes code.

## Consistency across the adapters

### 3. Each client has its own HTTP handling

- **What:** Every client builds the request, reads the body and maps HTTP failures by itself. The same two bugs (an unchecked HTTP status, and `rescue StandardError`) had to be fixed in Amego (#41) and again in ezPay (#42). Tradevan still has `rescue StandardError` (see the Tradevan PR).
- **Fix:** Move the shared part into the core: the network rescue, the "a body the provider wrote decides, else the HTTP status" rule, and the `base_url` check. Each client then keeps only its envelope and its crypto.
- **When:** after all four adapters are merged, so the shared part is cut from four real clients.

### 3a. `base_url` checks that every client needs

- **Query or fragment:** `Redaction.base_url!` accepts `https://host/gateway?region=tw`. A client that appends its path builds `/gateway?region=tw/DEFAULTAPI/...`, and the request goes to the wrong path. The check should refuse a query and a fragment. It lives in the core, so it changes every client.
- **Frozen:** the Tradevan client freezes `base_url` (#43), so a caller cannot change it after the checks. The ECPay, Amego and ezPay clients do not.
- **Status lost when the body fails:** every client calls `http.request` and reads the body in one step. When the headers arrive but reading the body fails, for example a read timeout, the error is a plain `NetworkError`. The HTTP status is lost, so an HTTP 429 does not get `RATE_LIMITED`. Read the status before the body, and keep it in the error. Found by CodeRabbit on #43.
- **Found by:** CodeRabbit, in the review of the Tradevan adapter (#43). Fix it with item 3.

## Decide first

### 4. Query status means different things

- **What:** ECPay and Amego return `ISSUED`, `VOIDED` or `ALLOWANCE`. ezPay returns only `VOIDED` and else `nil`, because its status does not show an allowance. Tradevan returns only `ALLOWANCE` and else `nil`, because its status codes are unknown. The shared contract accepts `nil` everywhere, so a caller cannot tell in advance which values a provider gives.
- **Options:** a capability that says the status is complete, or a list on each adapter of the statuses it can return.

### 6. Two provider limits still raise ValidationError

The unified model now says that an input the MIG allows but a provider does not take is an `UnsupportedError`. ECPay, Amego and ezPay follow it. Two places do not yet:

- **Tradevan:** `Rules.validate!` checks the whole `issueData` against the DEFAULTAPI schema and raises `ValidationError`. The schema mixes the caller's input, the merchant's settings and fields that the adapter builds, so each field needs a look before it can be split.
- **ECPay allowance:** `check_allowance!` refuses an item whose `ItemPrice × ItemCount` misses `ItemAmount` by more than 1. That is ECPay's rule, but it sits in one list with the MIG total check.

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
