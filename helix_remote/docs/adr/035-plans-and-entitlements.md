# ADR 035: Plans are server-side entitlements, bought by a manual payment the operator confirms

Status: accepted (2026-10-28). Release 1 of `docs/product/ORBIT_PREMIUM_PLAN.md`.

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§3 module list,
§12 change log).

## Context

Orbit has no income. The owner wants two plans on Helix Global, **Free** and
**Orbit Premium** (about BDT 20 a month), with no ads and no tracking, and
wants to be able to charge soon. Google Play Billing is a year or two away, so
people pay by hand: a bKash or Nagad payment to a number the operator owns,
then a transaction ID (TrxID) sent from the app, then the operator's approval
in Orbit Console.

Several modules already enforce limits (`identity` the device count, `media`
the quota, file size and retention). A plan changes those numbers per account.

## Decision

1. **A new `billing` module (schema `billing`) owns plans.** It holds the
   subscription of each account and the payment requests, and it answers one
   question for everybody else: what may this account do.
2. **`Entitlements` is a small immutable value type in `kernel/`**, with the
   limits that matter in release 1 (linked devices, attachment quota, max file
   size, attachment retention, backup media per file and in total). Modules ask
   `BillingApi.entitlements(accountId)` and never read billing tables.
   `identity` and `media` read it at the moment they decide, so a downgrade
   needs no job and nothing is deleted early.
3. **Plans are defined in code**, a typed catalogue reviewed and tested like any
   other code. Prices, the pay-to numbers and the plan's on/off switch are
   settings the operator edits in Orbit Console (`billing` config, audited), so
   a price change needs no release and no `.env` edit.
4. **Plans exist only where the operator switches them on** (the allow-listed
   flag `billing_enabled`, off by default). With the flag off, which is every
   personal server and a fresh Helix Global, every account gets the limits the
   server has always had (`Entitlements.standard`), so nothing changes until
   the operator decides.
5. **The server never trusts a client's claim of Premium.** The only ways to
   get it are an operator approval of a payment request, or an operator grant.
   A TrxID is accepted once: the same ID cannot be pending or approved twice.
6. **A downgrade is never destructive.** Premium ends after a grace period of
   three days; then Free limits apply. Existing files, backups and devices are
   kept. They only stop new uploads or new links beyond the Free limit, and
   they expire on their normal schedule.
7. **Bought time stacks**: a new period starts at the later of now and the end
   of the current one.
8. **Plans are per home account and are not federated.**
9. **Privacy.** The subscription record (plan, dates, source) and a payment
   request (duration, amount, method, TrxID, status) are new data about an
   account. A TrxID is not a phone number. Rows are in the account export and
   purged with the account. Request rows are kept one year (like audit rows),
   then purged.

## Added in phase 2 (same decision, built later)

- **A once-per-number trial** of 7 days, started with an account's first device, remembered as the keyed phone
  hash in `billing.trials_used` (kept after the account is deleted, no account id).
- **Downloadable packs are Premium's**, a soft gate in the app: the built-in themes and ringtones stay free,
  and nothing is locked while plans are off or the plan cannot be read.
- **A data-only `plan` wake-up** when a request is decided or the plan changes (`PushReason.plan`); the
  notification says only that a plan request was updated.
- **Per-account limit overrides** and **plan counts** for the operator, audited.

## What is deferred

Call time (daily minutes, per-call relay credentials, a second relay). It changes none of this and will need
its own ADR.

## Consequences

- One new module, one migration series, new admin and device routes, a new
  allow-listed flag, a new section in the account export.
- `identity` and `media` gain a dependency on `BillingApi` (through
  `kernel/entitlements.dart` and the module facade). Construction order puts
  `billing` right after `ops`.
- Docs that describe what the server stores or limits change in the same
  step: the privacy policy, retention, metadata inventory and the claim
  matrix keep saying only what is true.
- Free dropping to two linked devices is only felt once the operator switches
  `billing_enabled` on.
