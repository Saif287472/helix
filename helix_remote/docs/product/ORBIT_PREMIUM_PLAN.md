# Orbit Premium: plan

Status: **plan agreed in discussion, nothing built** (2026-10-27). Implementation is not expected for
about a month. Scope: Helix Remote (Orbit) on Helix Global. Never `helix_local/`.
Anything marked **verify** was not checked against the code and must be before work starts.

## 1. What we are doing and what we are not

Doing
- Two plans on Helix Global: **Free** and **Orbit Premium**.
- Premium sells capacity (devices, storage, file size, retention, backup size), unlimited calls, and the
  downloadable theme, ringtone and animation packs.
- Free is a complete messenger with limited call time. Chats are unlimited on every plan.
- Payment is manual through bKash or Nagad, confirmed by the operator in Orbit Console.

Not doing
- **No ads**, no ad network, no ad ID, no tracking. The privacy claims stay as they are.
- No Google Play Billing for now (not possible for a year or two). The design leaves room for it.
- No family plan and no second paid tier.
- No plans on personal servers: everything is unlocked there and the owner sets their own limits.
- Never paywalled: messaging, E2EE, one-to-one and group calls (within Free call time), backup and restore,
  safety numbers, app lock, account export and deletion.
- No destructive downgrade: nothing is deleted early when Premium ends.

## 2. The plans

| | Free | Orbit Premium |
|---|---|---|
| Chats | unlimited | unlimited |
| Linked devices | 2 | 10 |
| Attachment quota | 4 GiB | 16 GiB |
| Max size of one file | today's `HELIX_MAX_ATTACHMENT_BYTES` | 4x |
| Attachment kept on server | 30 days | 90 days |
| Full backup size | 100 MiB | 400 MiB |
| Voice call time | 100 min a day (see 5) | unlimited |
| Video call time | 30 min a day (see 5) | unlimited |
| Packs | Orbit and Orbit Night (built in) | every downloadable pack |

Today every account may link 10 devices (`IdentityContext.maxDevices`), so Free dropping to 2 is a real
change in code. The Free values for storage, file size and retention are today's values.
**Verify:** the backup caps. `media/MODULE.md` lists a `backup` kind of 100 MiB with a 1 GiB quota, while
the backup module caps a full-backup envelope at 64 MiB. Find out which cap actually limits a full backup
and whether the 1 GiB backup quota must grow for Premium's 400 MiB.

Plan definitions live in code as a typed, versioned catalogue (so they are reviewed and tested), with an
admin per-account override for support cases.

### Price (BDT, shown in the app)

| Duration | Price | Crossed-out price |
|---|---|---|
| 1 month | about 20 | none |
| 6 months | 100 | 120 |
| 12 months | 180 | 240 |

Bought time adds after the current end date (a lapsed plan starts at approval). The crossed-out prices are
6x and 12x the monthly price, so the discount is real.

### Trial
Each new account gets 7 days of Premium, once per phone number. The server already keeps a keyed hash of
the number, so a deleted and re-created account does not get a second trial. There are no real users yet,
so nothing special is needed for existing accounts (they are the owner's test numbers).

### When Premium ends
A short grace period (proposed 3 days), then Free limits apply. Existing files and backups are never deleted
early; they only block new uploads over the Free limit and expire on their normal schedule (an object
uploaded under Premium keeps the retention it was given). A device count above 2 is kept as it is; the
account just cannot link another until it is under the limit. The selected pack falls back to the default
theme or sound.

## 3. How people pay (manual)

1. In You > Orbit Premium the person picks a duration. The page shows the bKash or Nagad number and the
   amount.
2. They pay, then type the **transaction ID** (TrxID) in the app. Only the ID is collected: no screenshot,
   no sender number (a screenshot needs storage and review and can be faked; a number is a phone number
   to protect).
3. The request goes to a queue in Orbit Console. The operator matches the TrxID and amount in their own
   bKash or Nagad history and approves or rejects, with a short reason on a rejection.
4. The person sees Pending, Approved or Rejected in the app, and gets a push saying only that the plan
   request was updated. A rejected person can send a corrected ID. A request nobody answers expires after
   7 days. One open request per account.
5. Approval turns Premium on, adds the time, and the account's other devices refresh.

Safeguards: the server refuses a TrxID that is already pending or approved; every approve, reject and
grant writes an `audit` row; submissions are rate limited; TrxIDs are kept for a year like audit rows and
then purged. A later bKash or Nagad merchant API, or Google Play, can feed the same approval path.

## 4. Server design

New module `billing` (schema `billing`) with `module.dart`, `MODULE.md`, `api.dart`, `http/`,
`application/`, `data/`, `domain/`. Inert until the flag `billing_enabled` is on.

Tables (module migrations; never edit one that has run):
- `subscriptions`: account, plan, source (`payment`, `trial`, `admin`), period end, grace end, status.
- `payment_requests`: account, duration, amount, method, trx_id (unique while pending or approved), status,
  reason, decided_by, timestamps.
- `trials_used`: keyed phone hash, used_at (so the trial is once per number).
- `entitlement_overrides`: account, limit key, value, reason, by whom, expiry.
- Step 2 adds the call-time tables (section 5).

Entitlements: a small immutable value type in `kernel/` (plan, limits, features). Other modules ask
`BillingApi.entitlements(accountId)` and never read billing tables. Computed from the live subscription and
overrides; nothing live means Free; cached briefly and invalidated by a bus event. Enforcement points,
each reading the entitlement at the moment it decides (so downgrade needs no cron):
`identity` (device cap), `media` (quota, max size, retention at upload), `backup` (envelope size).
Architecture rules: add `billing` to the module dependency list and `v2PackageDependencies` where needed.

Routes (declared in `helix_remote_protocol` first, documented in `REST_V2.md`, one api-client method each):

| Route | Access | Purpose |
|---|---|---|
| `GET /v1/billing/plan` | session | plan, limits, end date, trial state, price list, payment numbers, open request |
| `POST /v1/billing/requests` | session | submit a payment request |
| `GET /v1/billing/requests` | session | own request history and status |
| admin: list and decide requests; grant, revoke and override a plan; summary counts | admin | the console queue |

No new public route is needed. Realtime: an `account_signal` subtype tells the other devices to refresh the
plan. Push: a new data-only wake kind (today `message`, `call`, `call_ended`) saying a plan request changed.
Decision for the console: payment numbers and prices are editable config in the admin config (no restart)
rather than env lines; **to confirm** when building.

Privacy and security: the server never trusts a client claim of Premium; plan changes happen only through
approval, trial or admin grant. Admin routes are limited to the operator. Account deletion purges billing
rows; account export gets a `billing` section (plan, dates, request status).

## 5. Call time (step 2)

Rules decided:
- Free gets a **voice pool** and a **video pool**, separate. Screen sharing counts as video.
- Each day the person taps **Claim** to receive 100 voice and 30 video minutes. Unclaimed days are lost.
- A claim expires after 3 days, so at most 300 voice and 90 video minutes are held. Minutes are spent oldest
  first.
- The **caller** pays; answering costs nothing. A group call is charged once per clock minute to whoever
  started it, to the pool that matches its media.
- The app warns both people 2 minutes before a Free caller runs out; at zero the call ends with a clear
  message. A call cannot start with an empty pool (the screen says why before dialing).
- Premium is unlimited.

Mechanism (direction, **verify** against `calls` and `platform` before settling):
- Calls are relay-only through the owner's TURN server, and the server issues the relay credentials
  (random usernames). Make a Free caller's credentials short-lived and renewed against the balance: the
  server debits as it renews and stops renewing when the pool is empty. This ends media without the
  server seeing any call content. Precision is about the renewal interval, so minutes are charged per
  started interval (to decide: per minute).
- For a group call the starter's credentials gate the call; other members' legs follow the call id.
- The day boundary (UTC or Dhaka time) must be decided.
- Anti-farming: claims and trials are tied to a verified phone number, which already limits multiple
  accounts.

Tables: a per-account ledger of claims (kind, claimed day, minutes left, expiry) and a reservation record
per call. Routes: claim, balance, and the credential renewal changes.

**New metadata:** the server will know how long a Free caller's calls ran. That must go into
`METADATA_INVENTORY.md`, `PRIVACY_POLICY.md` and the claim matrix honestly, and calls stay
signalled in the dark and relay-only.

## 6. Clients

- `helix_remote_protocol`: billing DTOs and routes, error codes (for example `plan_required`, a `reason` of
  `plan` on `quota_exceeded`, `trx_id_in_use`), golden fixtures changed deliberately.
- `helix_remote_api`: a billing client (route-parity test needs exactly one method per route).
- `helix_remote_engine`: fetch and cache the plan, refresh on the account signal and on resume.
  Prefer the existing settings store over a drift schema change; if a table is needed that is schema 8 to 9
  with a step migration, schema dump and codegen.
- App: `features/plans/` (You > Orbit Premium: plan comparison, price list with crossed-out prices, pay
  instructions, TrxID entry, request status, trial state) and later a Claim and balance view and the
  low-minutes warning in the call screen. Locked pack rows in the theme and ringtone pages.
- **Premium packs:** packs stay signed data. The app hides or locks downloadable packs for Free accounts,
  by rule (built-in free, downloaded Premium), so no manifest change is needed. This is a soft gate that a
  modified build could bypass, which is fine for cosmetics; anything that costs server resources is enforced
  on the server.
- `orbit_ui`: the plan, payment and claim screens are **not in the Orbit prototype**. By the Orbit rules I
  need your designs or your approval of a proposal first.
- `admin`: a Payment requests queue, plan grants and overrides, plan counts.

## 7. Docs, legal and decisions on record

- ADR-035 (plans and entitlements) and ADR-036 (call-time metering), plus your approved change-log entry in
  `ARCHITECTURE_V2_PLAN.md` (new modules change the target architecture).
- Update: `PRIVACY_POLICY.md`, `PRIVACY_CLAIM_MATRIX.md`, `METADATA_INVENTORY.md` (subscription and
  payment-request records, call durations), `RETENTION_AND_DELETION.md` (90-day attachments, TrxID purge),
  `THREAT_MODEL.md` (fake TrxIDs, request spam, operator error), the terms (paid plan, no refunds policy,
  expiry) with a new `HELIX_TERMS_VERSION`, `V2_SERVER_HANDOFF.md` and `server/.env.example` for any new
  line. Not needed now: ad and Play disclosures.
- A BDT revenue, tax and mobile-wallet question belongs to you and an accountant; nothing in code depends
  on it. Check that bKash or Nagad personal numbers may be used for this.

## 8. Testing

- Server on real Postgres: entitlement computation, trial once per number, stacking and expiry, grace,
  device cap by plan (Free refuses a third link; existing extras are kept), media quota, size and
  retention by plan, backup size, request lifecycle, duplicate TrxID refusal, expiry of unanswered
  requests, admin audit rows, deletion hook, export section, redaction. Step 2: claims, expiry after 3 days,
  oldest-first spending, caller-only charging, group charging, warning and end at zero.
- Client tests under `server/test/client/` drive the real api and engine against the server.
- Architecture tests: module imports, the new module in the dependency map.
- App and packages: protocol fixtures, api route parity, engine unit tests, widget tests for the plan page
  and pack locks, plus the rule tests (tooltips, 48 px, theme colours, English only).
- On a device, by hand: a pay-and-approve cycle across two devices, trial expiry, the call warning and cut.
  Reported honestly as untested until run.

## 9. Order of work

| Step | Content | Migration |
|---|---|---|
| 0 | Open decisions below, ADR-035 and ADR-036, change-log entry | none |
| 1a | `billing` foundation: plans in code, `subscriptions`, entitlements, flag; device, media and backup limits read them; everyone Free | billing 1 |
| 1b | Trial; payment requests; admin queue, grant and override; push and signal | billing 2 |
| 1c | App plan page and pack locks | none |
| 2a | Call-time ledger, Claim, balance | billing 3 |
| 2b | Relay credential metering, warning and end at zero | calls or billing |
| 2c | Call UI: balance, warning | none |

Step 1 is sellable by itself. After each step I will report what changed, tests with real numbers, whether
a new APK is needed, whether the server must restart and migrate, and any `.env` line to add.

## 10. Risks

| Risk | Mitigation |
|---|---|
| Operator workload and mistakes with manual approval | one-tap queue, duplicate TrxID check, audit rows; merchant API later |
| Fake or reused TrxIDs | unique check, operator matches amount and ID in their own history |
| Free call limit is hard to enforce | relay credentials as the control point; verify before committing to step 2 |
| New call-duration metadata | document it plainly; keep calls signalled in the dark and relay-only |
| Many accounts to farm trials or minutes | phone verification, one trial per number, claims per account |
| Paid user loses access by mistake | grace period, admin override, never destructive downgrade |
| Server disk fills with 16 GiB quotas | the existing server-wide storage budget still applies |

## 11. Still to decide

1. Day boundary for claims (UTC or Dhaka) and whether call time is charged per started minute.
2. Grace length after Premium ends (proposed 3 days).
3. Whether payment numbers and prices live in admin config (proposed) or env.
4. Size of the Premium backup quota (see 2) once the real caps are checked.
5. Designs for the plan, payment and claim screens, and the exact wording of the crossed-out price display.
