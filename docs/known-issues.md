# Known issues

This note collects the issues that we found while the adapters went into `2.0.0-alpha` (PRs #39 to #43). It is a working list, not user documentation. Remove an item when it is fixed, and remove the note when the list is empty.

Every item that could be fixed now is fixed. What is left is what 2.0 leaves out on purpose.

## Not in 2.0

- **Callbacks.** Only ECPay's delayed issue and online allowance call back, and the unified model has neither feature. A callback is a request from the provider to the caller's web server, the other way round from the gem, so it needs its own design. `Capability::SCHEDULED_ISSUE` stays, kept for that feature.
