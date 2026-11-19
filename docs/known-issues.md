# Known issues

This note collects the issues that we found while the adapters went into `2.0.0-alpha` (PRs #39 to #43). It is a working list, not user documentation. Remove an item when it is fixed, and remove the note when the list is empty.

The items that needed no decision are fixed. What is left needs a decision before anyone writes code, or is an idea for later.

## Decide first

### 1. ECPay's `RqHeader.Revision`

- **What:** The adapter sends `Revision: "3.0.0"`. The current ECPay docs do not list it, and stage accepts a request without it. See open question 1 in `docs/providers/ecpay/b2c.md`.
- **Decide:** keep the field or drop it.

## Ideas from a user's point of view

These came from a review that read the gem as a new user would. None of them is a bug.

- **`amount` could come from the core.** The core computes the tax breakdown, but the caller still has to give `amount` for the core to check.
- **`raw` takes different arguments per adapter**, so code that uses `raw` cannot switch providers.
- **No upgrade guide from 1.x.** The CHANGELOG only says that 2.0 is not compatible.
- **No callbacks.** Delayed issue and online allowances need them.
