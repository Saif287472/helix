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
| `subscriptions` | one row per account with Premium time: `period_end`, `source` (`payment` or `admin`) | `extend` adds months after the later of now and the current end |
| `payment_requests` | `months` (1, 6, 12), `amount` (taka at the time), `method` (`bkash`, `nagad`), `trx_id`, `status` (`pending`, `approved`, `rejected`, `expired`), `reason` | unique `trx_id` while pending or approved; one pending request per account; a rejected or expired ID may be sent again |
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

## Jobs

`billing.expire_requests`, hourly: pending requests older than 7 days become
`expired`; decided requests older than a year are deleted.

## Invariants

- The server never trusts a client's claim of Premium: only an approval, a
  grant, or nothing.
- A TrxID is not a phone number, is shown to the operator and to its owner only,
  and is in the account export (`billing` section: subscription and requests).
- Account deletion deletes both tables' rows for the account (identity's
  `onAccountDeleted` hook, registered in `start()`).
- No log line carries a TrxID, a number or an amount: `payment_request_submitted`
  has the account id, months and method.

## Deferred (see the plan)

The 7-day trial, a push when a request is decided, per-limit overrides, plan
counts, call time.
