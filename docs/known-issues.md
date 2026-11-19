# Known issues

This note collects the issues that we found while the adapters went into `2.0.0-alpha` (PRs #39 to #43), and that we chose to handle together. It is a working list, not user documentation. Remove an item when it is fixed, and remove the note when the list is empty.

Each item says what is wrong, where, and what it would take. Items under "Decide first" need a decision before anyone writes code.

## Left from the fixes

### 6. Two provider limits still raise ValidationError

The unified model now says that an input the MIG allows but a provider does not take is an `UnsupportedError`. ECPay, Amego and ezPay follow it. Two places do not yet:

- **Tradevan:** `Rules.validate!` checks the whole `issueData` against the DEFAULTAPI schema and raises `ValidationError`. The schema mixes the caller's input, the merchant's settings and fields that the adapter builds, so each field needs a look before it can be split. Then its provider spec can pass `unsupported_issue:` to the shared contract, as the other three do.
- **ECPay allowance:** `check_allowance!` refuses an item whose `ItemPrice × ItemCount` misses `ItemAmount` by more than 1. That is ECPay's rule, but it sits in one list with the MIG total check.

## Decide first

### 4. Query status means different things

- **What:** ECPay and Amego return `ISSUED`, `VOIDED` or `ALLOWANCE`. ezPay returns only `VOIDED` and else `nil`, because its status does not show an allowance. Tradevan returns only `ALLOWANCE` and else `nil`, because its status codes are unknown. The shared contract accepts `nil` everywhere, so a caller cannot tell in advance which values a provider gives.
- **Options:** a capability that says the status is complete, or a list on each adapter of the statuses it can return.

### 8. ECPay's `RqHeader.Revision`

- **What:** The adapter sends `Revision: "3.0.0"`. The current ECPay docs do not list it, and stage accepts a request without it. See open question 1 in `docs/providers/ecpay/b2c.md`.
- **Decide:** keep the field or drop it.

## Ideas from a user's point of view

These came from a review that read the gem as a new user would. None of them is a bug.

- **`amount` could come from the core.** The core computes the tax breakdown, but the caller still has to give `amount` for the core to check.
- **`raw` takes different arguments per adapter**, so code that uses `raw` cannot switch providers.
- **No upgrade guide from 1.x.** The CHANGELOG only says that 2.0 is not compatible.
- **No callbacks.** Delayed issue and online allowances need them.
