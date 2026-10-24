# 02 — Identity and keys

## Overview

Identity is the strongest part of the server. One mint point for sessions
(`SessionIssuer.issue`), `ims` at millisecond precision so a sign-in right
after sign-out is not swallowed by the cut-off, refresh rotation that commits
the theft response before returning the error, decoy password sign-in that
does the same HMAC, transaction and lockout as a real account, single-use
tokens hashed at rest, constant-time comparisons, device revocation with its
hooks inside the transaction, and `lockActiveDevices` ordered by id so a
revoke cannot race a delivery. Keys is a small, correct X3DH directory:
`FOR UPDATE SKIP LOCKED` for one-time prekeys, signatures verified inside the
device-add transaction, and per-requester/per-pair/per-remote-target limits.

The findings are about bounds and ownership, not about auth bypasses: an SMS
outage spends the server's daily text budget, an account can hold an unlimited
number of devices, and two primitive methods trust their callers more than
they should.

## Files read

- `identity/MODULE.md` (184), `identity/api.dart` (251),
  `application/context.dart` (480), `sessions.dart` (178), `sign_in.dart` (270),
  `sign_up.dart` (241), `registration.dart` (243), `accounts.dart` (351),
  `administration.dart` (130), `inactive_devices.dart` (41), `hooks.dart` (83)
- `data/identity_store.dart` (496), `data/credential_store.dart` (275),
  `domain/jwt.dart` (57), `domain/secrets.dart` (98), `domain/phone_seal.dart`
  (47), `http/identity_routes.dart` (339), `migrations.dart` (144),
  `config.dart` (217), `module.dart` (247), `sms.dart` (126)
- `keys/MODULE.md` (31), `keys/api.dart` (41), `keys/module.dart` (366),
  `keys/data/prekey_store.dart` (98), `kernel/jwt.dart` (105)
- Cross-checks: repo-wide search for a device cap (`maxDevices`,
  `device_limit`, "too many devices") — none; `PhonePurpose` in the protocol;
  callers of `revokeDevice`, `KeysApi.bundles`, `purgeAccount`.

## Findings

### AUD-2-1 A failed text spends the number's hourly allowance and the server's whole daily budget
- **Severity:** P2
- **Confidence:** confirmed
- **Where:** [sign_up.dart:87-125](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/sign_up.dart#L87) — per-phone bucket at line 87, daily budget at line 90, row inserted at line 103, text sent at lines 113-125
- **What:** both budgets are charged and the `phone_challenges` row is
  committed before the gateway is called. When `sms.send` throws
  `SmsFailed`, the route answers `sms_unavailable` and leaves everything
  behind: the challenge (nobody has its code) and both charges. Nothing
  refunds a token bucket, and the challenge row is what the 30-second resend
  gap reads.
- **Trigger:** the SMS provider is down, slow past 15 s, or rejecting (bad
  key, sender id, balance). Every client retry or real user attempting to
  sign in during the outage pays again.
- **Evidence:** the daily budget is one bucket for the whole server
  (`HELIX_SMS_DAILY_LIMIT`, default 500, refilled over 24 h —
  [sign_up.dart:24-34](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/sign_up.dart#L24)). 500 failed attempts exhaust it; after the provider
  recovers, `requestPhoneChallenge` still refuses with "try again tomorrow"
  until the bucket refills. Per number, five failures reach the one-hour
  cap ([sign_up.dart:18-22](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/sign_up.dart#L18)), so even one user retrying five
  times is then locked out for an hour.
- **Impact:** a provider outage turns into a server-wide sign-in and sign-up
  outage that outlives the outage, on the product's only account path. The
  unused challenge rows are harmless by comparison (purged after two days).
- **Fix sketch:** delete the challenge row when the send fails (that restores
  the resend gap immediately). For the budgets: send first and insert the
  challenge after a successful send, or add a refund/compensating decrement
  for the daily bucket. Charging the daily budget after the send is a small
  overshoot risk under concurrency, which the per-IP and per-phone limits
  already bound; keeping the pre-charge and accepting the loss is the status
  quo that makes an outage sticky.
- **Test that proves it:** a fake provider that throws `SmsFailed`; assert
  the challenge row is gone (or that a following request for the same number
  is not `rate_limited` by the resend gap) and that a later request is not
  refused for budget after the provider fake starts succeeding. Today: one
  failed send leaves the row and consumes both buckets.
- **Overlap:** sweep 7 (ops alerts on `sms_failed`), sweep 18 (operator docs
  for the daily limit).

### AUD-2-2 Nothing bounds the number of devices an account can hold
- **Severity:** P2
- **Confidence:** confirmed
- **Where:** [sign_in.dart:78-117](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/sign_in.dart#L78) (add-device path), [context.dart:412-445](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/context.dart#L412) (`addDevice`, the one insert point), [migrations.dart:42-58](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/migrations.dart#L42) (no constraint), bundle fan-out [keys/module.dart:269-327](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/keys/module.dart#L269)
- **What:** `addDevice` inserts unconditionally; there is no count check in
  identity, keys, the schema, or a repo-wide constant. A client with a
  password (or a link approved by an existing device) can add devices at the
  per-IP route limit (20/h) indefinitely. Each device carries up to 1,000
  one-time prekeys (`keys/module.dart:30`), a signed prekey, refresh-token
  rows for 60 days, and a security event on every sign-in.
- **Trigger:** a scripted account (or a compromised password) adding devices
  from rotating IPs; no privileged step is needed.
- **Evidence:** every bundle fetch walks **all** active devices
  (`identity.activeDevices`, then per device: signed prekey SELECT,
  `putIfAbsent` marker, one-time prekey DELETE, count) and the response
  carries one bundle per device. A device with N peers multiplies that by N;
  messaging fan-out and `lockActiveDevices` also walk the same list. The
  1,100 figure in the messaging module is a per-envelope recipient cap, not a
  per-account device cap (`messaging/module.dart:59`).
- **Impact:** one account with a few thousand devices makes a single
  `GET /v1/keys/{account}` run tens of thousands of statements (each taking a
  pool connection in turn) and return megabytes; at 120 bundle fetches/hour
  for one requester device that is a self-service load generator against the
  shared database. Storage grows by 1,000 prekey rows per device, and every
  envelope to the account fans out across all of them.
- **Fix sketch:** cap devices per account (a constant in identity, e.g. 10 or
  20, checked inside `addDevice`) under a per-account lock so concurrent adds
  cannot exceed it (`pg_advisory_xact_lock` on the account id, or
  `SELECT id FROM identity.accounts WHERE id = … FOR UPDATE` then count).
  Refuse with `quota_exceeded` and a details field. Expand: add the check and
  the lock; migrate: leave existing over-cap accounts as they are (no forced
  revokes), they simply cannot add more; contract: document the cap in
  `identity/MODULE.md` and the API. Also cap the `?device=` selection (a
  long query string is currently passed straight through to the device
  filter).
- **Test that proves it:** add cap+1 devices in one account (through
  `addDevice` concurrently, to prove the lock); the last one is refused and
  the count stays at the cap. Today all succeed.
- **Overlap:** AUD-3-1 (fan-out cost per device), sweep 5 (bandwidth per
  bundle), sweep 18 (ops sizing).

### AUD-2-3 `IdentityContext.revokeDevice` accepts an account id and never uses it
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [context.dart:380-409](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/context.dart#L380), [identity_store.dart:257-277](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/data/identity_store.dart#L257) (UPDATE by device id only); the two current callers pre-check [accounts.dart:298-302](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/accounts.dart#L298) and [administration.dart:90-96](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/administration.dart#L90)
- **What:** the method's signature suggests it revokes a device *of*
  `accountId`, and it passes that account to the notification hooks, but the
  SQL updates any row with the device id. Safety depends entirely on both
  callers having read the device and compared `accountId` first.
- **Trigger:** a future caller (compliance, ops, a bulk tool) that trusts the
  signature and skips the read. That caller would revoke a device of another
  account while sending its own account's devices the "a device was revoked"
  signal.
- **Evidence:** `accountId` appears in the method only in
  `hooks.deviceListChanged(tx, accountId)` and `hooks.accountSignal(...)`,
  never in `store.revokeDevice(tx, deviceId, reason)`.
- **Impact:** latent cross-account revocation; no live exploit found (both
  current callers check, and `inactive_devices` gets the account from the
  same row it re-checks under lock).
- **Fix sketch:** pass `accountId` to `IdentityStore.revokeDevice` and add
  `AND account_id = @a:uuid` to the UPDATE. Return null when it does not
  match, which makes both callers' pre-checks redundant but harmless.
- **Test that proves it:** `revokeDevice(tx, accountA, deviceOfB, 'user')`
  returns false and leaves B's device active. Today it revokes it and sends
  A's devices the signal.
- **Overlap:** sweep 17 (admin device revoke), sweep 19 (primitive contracts).

### AUD-2-4 Every authenticated request runs an UPDATE that almost always changes nothing
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [sessions.dart:157-170](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/sessions.dart#L157), [identity_store.dart:316-322](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/data/identity_store.dart#L316)
- **What:** authentication is a JWT check plus a device/account row read,
  then `touchLastSeen` executes
  `UPDATE devices SET last_seen_on = current_date WHERE id = … AND (last_seen_on IS NULL OR last_seen_on < current_date)`.
  Once a device has been seen today the predicate is false, so every further
  request in the day pays a round trip and a primary-key probe for zero
  writes — including all polling, socket refresh and message fetches.
- **Trigger:** normal operation.
- **Evidence:** the call is unconditional in `device()`
  ([sessions.dart:164](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/sessions.dart#L164)); the SQL already contains the
  once-a-day condition, but the statement still runs.
- **Impact:** one extra statement per authenticated request — roughly double
  the identity cost on the hottest path in the server. Not correctness, but it
  is the kind of constant that will not scale with a polling client.
- **Fix sketch:** remember the last written date per device in an in-process
  map (`{device: date}`, a few thousand entries, pruned daily) and skip the
  UPDATE when today is already recorded. Multi-node means each node writes
  once a day instead of one write; that is exactly the intended semantics
  (a date, not a timestamp).
- **Test that proves it:** a counting Db wrapper sees zero `UPDATE` statements
  for the second authenticated request of the same device on the same day;
  today it sees one per request.
- **Overlap:** sweep 14 (app polling cadence), sweep 19 (hot-path budget).

### AUD-2-5 A link long-poll reads the ephemeral store four times a second
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [sign_in.dart:144-177](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/sign_in.dart#L144) (250 ms loop), route [identity_routes.dart:171-185](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/http/identity_routes.dart#L171)
- **What:** `pollLink` loops until a 30-second deadline, sleeping 250 ms and
  doing a database read each time. One HTTP request can issue ~120 reads
  against the UNLOGGED ephemeral table, and the loop uses `DateTime.now()`
  rather than the server clock.
- **Trigger:** the normal linking flow (a new device waits for approval), and
  any client that holds the poll open for the full `wait_s=30`.
- **Evidence:** 600 requests/hour/IP at the `link_poll` policy → up to 72,000
  ephemeral reads per hour from one IP, plus 120 transient connections per
  request if the pool is busy.
- **Impact:** cheap individually, but it is polling in the server, in the one
  flow that already has an event bus (`EventBus`) for exactly this kind of
  wake-up. Not a security issue.
- **Fix sketch:** sleep 1 s (30 reads) at minimum; better, publish on a
  `identity.link.<id>` bus topic from `approveLink` and await it with the
  deadline, keeping the 1 s DB fallback for a missed notification. Use
  `c.clock.now()` for the deadline.
- **Test that proves it:** with a fake clock/ephemeral counter, a 30 s poll
  does ≤ 30 reads; today it does ~120.
- **Overlap:** sweep 3 (bus semantics), sweep 11 (client poll behavior).

### AUD-2-6 The one-time-prekey gap marker is set even when no key was handed out
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [keys/module.dart:286-293](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/keys/module.dart#L286)
- **What:** the `keys:otk:<requester>:<device>` marker is created before
  `takeOneTime` runs. If the target device has no one-time prekeys left,
  `takeOneTime` returns null but the requester is still marked for an hour:
  subsequent bundles in that hour answer the signed prekey only, even if the
  target uploads a fresh batch a minute later.
- **Trigger:** a bundle fetch while the target's one-time prekeys are
  exhausted (exactly the state `prekeys_low` exists to repair), followed by a
  retry after the target replenishes.
- **Evidence:** the marker's `putIfAbsent` result is used as `hand`; nothing
  deletes it when `otk == null`. The enum in `keys/MODULE.md` states the gap
  as "at most one one-time prekey per target device an hour", which implies a
  key was actually delivered.
- **Impact:** sessions fall back to the signed prekey for up to an hour longer
  than needed (weaker forward secrecy, no failure). No data loss.
- **Fix sketch:** if `takeOneTime` returns null, delete the marker
  (`ephemeral.delete`) before returning the bundle; or set the marker only
  after a successful take (accepting a small double-take race, which the
  requester limit already bounds). The delete is the simpler, exact fix.
- **Test that proves it:** a target with zero one-time prekeys; fetch, upload
  keys, fetch again within the hour; the second bundle must contain an `otk`.
  Today it does not.
- **Overlap:** AUD-2-2 (bundle fan-out), sweep 9 (X3DH properties).

### AUD-2-7 Expired invites and recovery codes have no periodic purge
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [identity/module.dart:116-127](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/module.dart#L116) (periodic job purges only refresh tokens and challenges), [admin/module.dart:130-141](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L130) (admin periodic jobs), [admin/module.dart:755-760](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L755) (`purgeExpired` only on a manual admin route)
- **What:** `credential_store.purgeExpiredRefresh` and `purgeChallenges` run
  every six hours, but the invites and recovery-code deletions in
  `AdminStore.purgeExpired` are reachable only when an operator presses purge
  in the console. On Helix Global, `POST /v1/auth/invites/self` mints an
  invite (7-day life) at 3/hour/IP with no ceiling over time.
- **Trigger:** normal self-issue traffic, and admin-issued recovery codes
  (48-hour life) that are never used.
- **Evidence:** `identity.purge_expired` calls only the two credential-store
  purges; the admin module's periodic list contains only sign-in failures
  and audit retention. No other caller of `purgeExpired` exists.
- **Impact:** unbounded row growth in `identity.invites` and
  `identity.recovery_codes` on a public server; slow index and table bloat.
  Codes are hashed, so this is a storage issue, not a secret leak.
- **Fix sketch:** add the two deletes to the identity periodic job (for
  example: invites expired more than 30 days and recovery codes expired more
  than 7 days), keeping the admin purge for immediate operator action.
  `AdminStore.purgeExpired` already knows the statements; move the shared
  ones into `CredentialStore` and call them from both.
- **Test that proves it:** insert an expired invite/recovery code, run the
  periodic job, assert the rows are gone. Today only the admin route removes
  them.
- **Overlap:** sweep 7 (admin console), sweep 19 (retention summary).

### AUD-2-8 The verification-token purpose is only enforced when registering
- **Severity:** P3
- **Confidence:** likely
- **Where:** checked in [registration.dart:34-40](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/registration.dart#L34); not checked in [accounts.dart:81-92](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/accounts.dart#L81) (password change), [accounts.dart:142-149](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/accounts.dart#L142) (ownership proof), [registration.dart:196-206](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/registration.dart#L196) (recovery redeem)
- **What:** `PhonePurpose` carries `register`, `sign_in`, `reset_password`
  and `recover`, and the token stores it, but only `register` checks it. A
  token obtained for one flow is accepted by the others as long as it is for
  the account's number and is still unused.
- **Trigger:** a client/user completing one verification and the token being
  replayed into another flow within its 15-minute life.
- **Evidence:** `register` rejects a purpose outside
  `{register, signIn}`; the other three call sites call
  `c.verification(token)` and only compare `phoneHash`.
- **Impact:** low today — every purpose proves the same number, and the token
  is returned only to the client that requested the code, so there is no
  privilege escalation. It does mean the purpose field cannot be used as a
  safety boundary (e.g. to make a "recover" code unusable for a password
  change), and the asymmetry is easy to copy wrongly.
- **Fix sketch:** one helper `verificationFor(token, {required Set<PhonePurpose> purposes})`
  used by all four flows, with each flow naming the purposes it accepts.
- **Test that proves it:** a token issued for `sign_in` used against
  `setPassword` is refused. Today it is accepted.
- **Overlap:** sweep 8 (protocol purpose semantics), sweep 15 (app flows).

## Structural proposals

### S1 A device registry with a cap, owned by identity
- **Current shape:** `IdentityContext.addDevice` is the one insert point, and
  it inserts; nothing counts. Keys, messaging, realtime and refresh tokens
  all assume an account's device list is small.
- **Hazard:** the assumption is neither enforced nor documented as a bound;
  one account can make key fetches, envelope fan-out and storage arbitrarily
  large, and the first place it hurts is the shared database.
- **Proposed shape:** identity owns a `maxDevicesPerAccount` constant,
  enforced in `addDevice` under a per-account lock with a `quota_exceeded`
  error; `identity/MODULE.md` and the API doc state it. Keys and messaging
  can then keep their per-device loops (bounded by 10-20) without their own
  limits.
- **Migration path:** expand — add the count + lock + error, no schema. A
  backfill is not required (existing accounts keep their devices and cannot
  add); if a hard ceiling is wanted, a later job revokes the least recently
  seen devices above the cap with the usual hooks.
- **Risk:** a legitimate power user at the cap is told to remove a device;
  pick the cap high enough for phones + tablets + an old PC (20 is generous).
- **Size:** S/M (one method, one test, docs).

### S2 Charge the SMS budgets for texts that actually left
- **Current shape:** the route checks the resend gap and both buckets, then
  inserts the challenge, then calls the provider; a provider error is
  converted to an API error with every charge kept.
- **Hazard:** an external outage spends the budget that exists to stop
  pumping, turning an outage into a longer outage.
- **Proposed shape:** one `sendChallenge` step where a failed send leaves no
  row and (where the limiter allows) no charge; the provider call is the
  commit point for the number-level state.
- **Migration path:** expand — wrap the insert/send in a try that deletes the
  row on failure; then decide the daily-budget order (send before charge, or
  a compensating decrement). No schema.
- **Risk:** sending before the insert means a database failure can text a
  code that cannot be verified; that is strictly better than burning the
  day's budget, and the client shows "try again".
- **Size:** S.

### S3 Identity primitives take the owner explicitly
- **Current shape:** `revokeDevice(accountId, deviceId, reason)` ignores the
  account; `IdentityStore.revokeDevice(deviceId, reason)` has no owner at
  all. Correctness lives in two callers' pre-checks.
- **Hazard:** every new caller must remember to repeat the check; a missed
  one is a cross-account action that looks correct at the call site.
- **Proposed shape:** the store UPDATE includes `account_id = @a` and the
  hook/notification calls only happen when a row was returned; callers keep
  their early 404 but no longer carry the safety property.
- **Migration path:** contract — change the store signature and both callers
  in one commit; no schema, no API change.
- **Risk:** none; both callers already pass the right account.
- **Size:** S.

## Coverage gaps and notes

- Verified sound: `HmacJwt` signs and reads `ims` at millisecond precision
  (`kernel/jwt.dart:39-44`), so sign-out/sign-in in the same second works;
  `takeOneTime` is a single statement with `SKIP LOCKED`
  (`prekey_store.dart:52-66`); `lockActiveDevices` orders by id
  (`identity_store.dart:329-337`); the decoy path does the HMAC and a real
  transaction before counting a failure (`context.dart:240-283`); a suspended
  account can mint tokens but every route gate still sees
  `suspended: true`; phone challenges are limited to 5 attempts under
  `FOR UPDATE`; the SMS provider call itself has a 15 s timeout
  (`sms.dart:64-77`).
- Not audited here: `admin_store.dart` (operator views and export — sweep 17),
  the phone-seal key handling in the admin console (sweep 17), federation's
  use of `remoteBundles` (sweep 6), the app's refresh-token retry behavior
  (whether a benign double refresh hits the theft response — sweep 11/14),
  and the hook bodies in messaging/backup/keys (their transactions are
  covered by their own sweeps).
- `KeysApi.bundles` and `KeysApi.purgeAccount` currently have no callers in
  `server/lib` (`remoteBundles` is used by federation, the HTTP route calls
  the private path). Not a defect, but the facade is wider than its use; a
  future cleanup could shrink it.
- No test asserts the device cap, and no test asserts a wrong-account
  `revokeDevice` is refused — both are part of the fix sketches above.
