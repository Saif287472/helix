# billing module

Plans and manual payments (ADR-035; the plan is `docs/product/ORBIT_PREMIUM_PLAN.md`).
Schema `billing`. Built right after `ops` (it reads the flag) and before
`identity` and `media` (they read it); it reaches identity lazily, for the
account-deleted hook, when the server starts.

Off until the operator turns on the allow-listed flag `billing_enabled`
(Orbit Console > Settings > Feature flags). With it off every account has the
limits the server always had (`Entitlements.standard`), `GET /v1/billing/plan`
says `enabled: false`, and nothing can be bought. Personal servers never turn
it on.

## Entitlements

`kernel/entitlements.dart` holds the value type and `EntitlementSource`;
`BillingApi.forAccount` answers it. Plans are code, not rows:

| | standard (flag off) | Free | Orbit Premium |
|---|---|---|---|
| linked devices | 10 | 2 | 10 |
| attachment quota | 4 GiB | 4 GiB | 16 GiB |
| one attachment | `HELIX_MAX_ATTACHMENT_BYTES` | same | 4x |
| attachment kept | 30 days | 30 | 90 |
| backup media, one file / all | 100 MiB / 1 GiB | same | 400 MiB / 4 GiB |

An account is Premium while `now < period_end + 3 days` (the grace period). The
enforcers read it where they decide: `identity` (`addDevice`), `media`
(`createUpload`: size, quota, retention of the new object). Nothing is deleted
when Premium ends; an object uploaded under Premium keeps the retention it was
given, and devices over the Free limit stay (they only block a new link).

## Tables

| Table | Holds | Rules |
|---|---|---|
| `subscriptions` | one row per account with Premium time: `period_end`, `source` (`payment`, `admin` or `trial`) | `extend` adds months after the later of now and the current end |
| `payment_requests` | `months` (1, 6, 12), `amount` (taka at the time), `method` (`bkash`, `nagad`), `trx_id`, `status` (`pending`, `approved`, `rejected`, `expired`), `reason` | unique `trx_id` while pending or approved; one pending request per account; a rejected or expired ID may be sent again |
| `trials_used` | the keyed phone hash and the date of each trial | one trial per number, kept after the account is deleted; no account id, no number |
| `entitlement_overrides` | account, limit key, value, the operator's reason, optional expiry | applied over the plan by `forAccount`; expired rows are purged hourly |
| `settings` | prices (`price_1`, `price_6`, `price_12`, taka) and the numbers (`bkash_number`, `nagad_number`) | edited in the console, audited; a method with no number is not offered |

## Routes

| Route | Notes |
|---|---|
| `GET /v1/billing/plan` | plan, limits, prices (`list_price` = months x monthly price), numbers, the open and the last decided request. Also while suspended. |
| `POST /v1/billing/requests` | `unavailable` when plans are off or the method has no number; `invalid_field` for months, method or an ID that is not 6-20 letters and digits (stored upper case); `conflict` for an open request (`details.reason: request_open`) or an ID already used (`trx_id_used`). 10 per hour per account. |
| `GET /v1/billing/requests` | the account's own, newest first |

The operator's routes (queue, approve, reject, grant, revoke, settings) are in
the admin module, which calls `BillingApi` inside its own transaction and writes
the audit row there.

## Trial

A new account gets 7 days of Premium once per phone number (`BillingLimits.trialDays`): when plans are on and
identity adds an account's **first** device (`onDeviceAdded`), billing records the keyed phone hash
(`identity.phoneHash`) in `trials_used` and extends the account by 7 days with source `trial`. An account that
already has a subscription row, or a second device of an account, gets nothing. Paid time stacks after the
trial (`GREATEST(period_end, now) + months`), and the source becomes `payment`.

## Overrides and counts

The operator changes one limit for one account (`max_devices`, `attachment_quota_bytes`, `max_attachment_bytes`,
`attachment_retention_days`, `backup_max_bytes`, `backup_quota_bytes`) for some days or until removed, through
the admin module's `PUT/DELETE /v1/admin/accounts/{id}/plan/overrides/{key}`. `forAccount` applies the live ones
over Free or Premium (`Entitlements.withOverrides`), so every enforcer sees them. `GET /v1/admin/billing/summary`
counts Premium, trial and grace accounts, waiting requests, and the approved requests and taka of the last 30 days.

## The wake-up

A decided request, a grant, a revoke and an override change enqueue `billing.push` for each of the account's
active devices in the same transaction (deduplicated per device). The job sends a data-only `plan` wake-up
(`PushReason.plan`: normal priority, a day's time-to-live) through the platform push provider and records one
`push` line and one counter like every wake-up. It carries nothing about what changed.

## Jobs

`billing.expire_requests`, hourly: pending requests older than 7 days become `expired`; decided requests older
than a year and expired overrides are deleted. `billing.push`: the wake-up above.

## Invariants

- The server never trusts a client's claim of Premium: only an approval, a
  grant, or nothing.
- A TrxID is not a phone number, is shown to the operator and to its owner only,
  and is in the account export (`billing` section: subscription and requests).
- Account deletion deletes both tables' rows for the account (identity's
  `onAccountDeleted` hook, registered in `start()`).
- No log line carries a TrxID, a number or an amount: `payment_request_submitted`
  has the account id, months and method.

## Call time (ADR-036)

Applies to an account only when plans are on and it is not Premium (`isMetered`: `Entitlements.unlimitedCalls`
is false). Everyone else is unmetered and nothing is recorded.

| Table | Holds |
|---|---|
| `call_claims` | one row per account and Dhaka day (`day`, unique with the account): `voice_left`, `video_left`, `expires_at` (end of the third day) |
| `call_reservations` | minutes set aside for one call or one group-call room (`room_id`, unique): pool, `reserved`, `parts` (which claims they came from), `expires_at`, `answered_at`, `last_end_at`, `finalized_at`, `used` |
| `call_reservation_calls` | the call ids under a reservation and their caller |

| Route | Notes |
|---|---|
| `GET /v1/billing/call-time` | pools (`minutes`, `daily_minutes`, `cap_minutes`, oldest `expires_at`), `can_claim`, `next_claim_at`; `unlimited: true` when unmetered. Also while suspended. |
| `POST /v1/billing/call-time/claim` | today's 100 voice and 30 video minutes; `conflict` (`already_claimed`) the second time. 20 per day per account. |

`BillingApi.grantCall` is what the calls module asks when relay credentials are requested: a metered caller's
minutes are taken (oldest claim first, under a per-account advisory lock) and the grant expires when they end; a
`quota_exceeded` with `details.reason: call_time` and `details.pool` refuses an empty pool; a callee's grant
ends with the caller's reservation; the legs of a group call share the starter's reservation, charged once per
clock minute. `callEnded` (on the `end` signal) settles the reservation: used whole minutes are kept
(per started minute, with a one-minute grace to the end), the rest go back to their claims.

Jobs: `billing.settle_calls`, every minute (reservations whose time ran out or that never saw an end, so
nothing stays reserved for ever); `billing.purge_calls`, every 6 hours (claims and reservations 7 days after they
expire or settle). Account deletion and the export cover the three tables.
