# Open questions for the owner

Decisions only the owner can make. Findings stay in the `NN_` files; this file
records the choices and what each one changes.

## Q1 — Should ephemeral sends draw a budget?

**Context.** Ephemeral sends (`POST /v1/messages` with `ephemeral: true`) store
nothing and are deliberately not charged against the stored-envelope budget
(`messaging/MODULE.md`, `messaging/module.dart:332-345`). Typing indicators and
call signals use them. Rate limits are per sending device (200 burst, 5/s) and
per account (400 burst, 10/s), but one request may address up to 1,100 devices,
and each recipient device costs two DB round trips (AUD-3-1). Today the
per-request shape, not the rate limit, is what a large fan-out can abuse.

**Options.**
1. Keep it as is; fix the cost shape (batch the store writes and the bus
   publishes, S1 in `03_messaging_realtime.md`). Fan-out becomes cheap, no
   product change.
2. Also charge ephemeral sends a small per-device unit against a separate
   budget (say a fraction of `messaging.stored_account`), so a client cannot
   turn the endpoint into a fan-out amplifier even if batching is slow. Needs a
   new rate-limit policy name and a documented `rate_limited` on a send that
   today never gets one.
3. Charge ephemeral sends the same stored-envelope units as stored sends. This
   would make a large group's typing indicators compete with messages; not
   recommended.

**What the answer changes:** whether S1 is sufficient on its own, and whether
the protocol docs need a note that ephemeral sends can return `rate_limited`.
No wire shape changes in any option.

**Answer (owner, 2026-10-24): option 1.** Ephemeral sends stay uncharged; B2
fixes the cost shape with S1's batching and does not add a policy name or a
`rate_limited` outcome to `/v1/messages`. Re-measure the fan-out once S1
lands — if a single request addressing ~1,100 devices is still expensive,
option 2 returns as the fallback, and the docs then have to say the endpoint
can be rate-limited.

## Q2 — Should `block_change` be a stored envelope?

**Context.** Blocking and unblocking notify the target's devices so their chat
can say so before the next send (`people/MODULE.md`; `_tellBlocked` in
`people/module.dart:539`). The notification is a *stored* envelope: one mailbox
row per target device, charged against that device's 10,000-row quota, which
trims the oldest undelivered envelopes when full (`mailbox_store.dart`).
Neither route has a per-account rate limit, so an account that alternates
block/unblock can flush an offline victim's queued messages (AUD-4a-1). The
same state is already discoverable at send time via `blocked_by`.

**Options.**
1. Keep it stored, but bound it: notify at most once per (blocker, target,
   state) per window and add a per-account limit to block/unblock. Offline
   devices still see the event when they reconnect; the protocol and app are
   unchanged. Leaves a residual risk if the window is short and many accounts
   coordinate.
2. Make it advisory: deliver to online sockets only (ephemeral path), like
   typing indicators. Offline devices learn the state from the next send's
   `blocked_by`, as a remote blocked sender does today. Requires the engine to
   accept a server-generated envelope with no mailbox `seq`, and the docs to
   say the notice is best-effort.
3. Stop notifying at all and rely on `blocked_by` on the next send. Simplest
   and safest for mailboxes, but the chat no longer warns before the user
   types into a void.

**What the answer changes:** whether server-generated envelopes need the
"advisory vs required" split in S1 (`04a_people.md`), whether the engine's
frame handling must change, and what `people/MODULE.md` promises about blocks.
No new REST fields in any option.

**Answer (owner, 2026-10-24): option 2 for `block_change`, stored-but-coalesced
for `roster_change`.** A block or unblock notice goes to online sockets only,
so an offline target learns the state from the next send's `blocked_by` the way
it does today for a remote blocked sender; a group removal stays a stored
mailbox row because a removed member must find it on reconnect, but it
coalesces per (group, device, state) so flapping cannot fill the quota. The
engine must accept a server-generated envelope with no mailbox `seq`, and the
docs say the block notice is best-effort.

## Q3 — When an account's export is huge, should it be truncated or fail?

**Context.** `GET /v1/account/export` builds one JSON document in memory.
Identity (500 security events) and people (500 reports) cap their sections;
the media section lists every object row with no limit (`media/module.dart:52`,
AUD-7-2). The media quota is byte-based, so a large number of tiny uploads
makes the section large while the quota stays empty (AUD-5-3).

**Options.**
1. Cap each section and report what was left out (e.g. `truncated: true` and
   `total`) — a `data-subject` export that is honest about its bounds, and
   S5 can enforce it for every module.
2. Stream the export (chunked JSON) and keep it complete; memory stays flat
   but a very large export still takes a long time on a phone.
3. Refuse with `payload_too_large` above a threshold and tell the person to
   delete media first; simplest, but the export is a data right and refusing
   it is a product statement.

**What the answer changes:** S5's shape (budget vs streaming vs refusal), the
protocol docs for the export response, and whether the media section needs a
new `total` field. No schema change in any option.

**Answer (owner, 2026-10-25): option 1.** Every section of the export is capped
and the response says what was left out (`truncated`, `total`), which is also
what fixes the media section's missing limit (AUD-7-2). B15/S5 applies the same
shape to every module's section, so the export is a data right that always
arrives, with honest bounds — no streaming machinery and no refusal. No schema
change.

## Q4 — Should the platform-credential backup wrap be shipped, and how should open fall back?

**Context.** `BackupCrypto.seal` writes a second wrap under an OS/platform key
when one is given and `open` prefers it over the recovery secret
(`packages/helix_remote_crypto/lib/src/v2/backup.dart:243-296`). No product
caller passes a `platformKey`: the app's create and restore paths use the
recovery secret only
(`app/lib/features/backup/application/backup_gateway.dart:213-241`), so in
practice every backup has one wrap. `open` also has no fallback — a caller
that passes a stale platform key plus a correct recovery secret gets a
`DecryptionFailedException` (`backup.dart:275-293`).

**Options.**
1. Ship it: create the platform key with the recovery wrap, and on restore try
   the platform wrap, then the recovery secret. A user who still has the OS
   credential can restore without the written phrase; the phrase remains the
   portable fallback.
2. Keep recovery-only and delete the platform wrap from the crypto package
   (less code, one documented path, no keystore dependency in the engine).
3. Keep the capability but always add the fallback in `open` so a future caller
   cannot create a restore path that only works with one credential.

**What the answer changes:** whether ADR-030's backup format ships one or two
wraps, `restoreFullBackup`'s signature (already accepts both), and the
restore UI's wording. No wire shape change — `key_wraps` already carries both.

**Answer (owner, 2026-10-25): option 2 — delete the platform wrap (the audit
recommended option 3).** Backups stay recovery-secret only: `seal` writes one
wrap, `open` takes the recovery secret, and the crypto package and engine keep
no OS-keystore dependency. Nothing in the product ever passed a `platformKey`,
so no existing backup has a second wrap to lose, and the stale-key trap cannot
exist once the path is gone. ADR-030's format documents one wrap; if the
capability is ever wanted it returns as its own ADR, with the fallback and the
restore UI designed in together.

## Q5 — Should `open` cap the Argon2id work a stored envelope can demand?

**Context.** The recovery-secret wrap carries its own KDF parameters, and
`open` enforces the v2 floor but honours the ceiling:
`memoryKib ≤ 262,144`, `iterations ≤ 10`
(`packages/helix_remote_crypto/lib/src/v2/backup.dart:33-39`, `:286-293`).
Anyone who can modify the stored envelope (the server) can therefore make one
restore attempt cost up to 256 MiB × 10 iterations before authentication
fails. The attacker could equally refuse to serve the backup, so this is
amplification, not a new capability; `open` uses the first wrap of each method
only, so it is one Argon2id run per attempt.

**Options.**
1. Leave it: the ceiling matches what a legitimate 2026 device is expected to
   spend, and restore is user-initiated.
2. Cap accepted *open* parameters at what the app itself seals with
   (`BackupKdfParams()` defaults), and treat higher values as `Malformed` —
   restore becomes cheaper for old or hostile envelopes.
3. Keep the ceiling and add a confirm prompt when the header asks for more
   than the default, so the user sees the cost before it starts.

**What the answer changes:** the compatibility window for envelopes sealed by
older/newer builds, and the restore page's flow. No stored-format change.

**Answer (owner, 2026-10-25): option 3.** The ceiling stays — the v2 floor is
still enforced and `memoryKib <= 262,144`, `iterations <= 10` are still
honoured — and the app asks before a restore whose header demands more than the
app's own sealing defaults, so the person sees the cost before the work starts.
Envelopes sealed by older or stronger builds still open; only the flow changes.
No stored-format change.

## Q6 — How is a device whose session ended recovered?

**Context.** When the server refuses both a refresh and a device-key sign-in
(the device was revoked, or a server was restored from a backup), the local
account row and all local history stay, but every sign-in path refuses because
`_requireEmpty` sees the account (`account_service.dart`, the four sign-in
entries). The documented recovery is "sign in again"; the app shows "Could not
sign in", and the only exit that clears the error deletes the local data.
AUD-12a-1 (P1) has the lines.

**Options.**
1. Re-enrol in place: allow a sign-in whose server account id equals the local
   `account.account_id`, replacing the identity, prekeys and session rows.
   Chats and messages are not keyed by device, so history survives. Engine-only;
   matches the documented promise.
2. A distinct "session ended, data kept" state, with its own screen offering
   "Sign in again" and "Sign out and remove". Needs new app copy and a state
   the UI understands.
3. Keep refusing and document that the data must be deleted. Cheapest, but it
   contradicts the recovery doc and makes a server restore destructive.

**What the answer changes:** what a person sees after a server restore, and
whether the engine or the app owns the repair. Option 1 is engine-only; option
2 needs a product screen. No wire change in any option.

**Answer (owner, 2026-10-25): option 1.** A sign-in whose server account id
equals the local account's replaces the identity, prekey and session rows in
place. Chats and messages are not keyed by device, so the history survives;
"sign in again" becomes the documented repair instead of a dead end whose only
exit deletes the data. Engine-only, no wire change, and the app's "Could not
sign in" page stops offering deletion as the way out.

## Q7 — How many devices may one account hold?

**Context.** Nothing counts devices (`IdentityContext.addDevice` inserts;
AUD-2-2). Every key fetch, envelope fan-out and prekey download is
O(devices), and the database pays for it. One account can register devices
without bound.

**Options.**
1. Cap at 20 (phones, tablets, an old PC), enforced under a per-account lock
   with `quota_exceeded`. Existing accounts keep their devices and cannot add
   more.
2. Cap lower (10). Tighter, but a person with two phones and a laptop plus
   reinstalls hits it.
3. No cap, but charge device registration against a rate limit. Leaves the
   fan-out multiplier in place.

**What the answer changes:** whether the keys and messaging modules can keep
their per-device loops without their own bounds, and one new error outcome
(`quota_exceeded` on registration). No schema change.

**Answer (owner, 2026-10-25): option 2 — cap at 10 (the audit recommended
20).** `addDevice` refuses the eleventh registration with `quota_exceeded`
under the per-account lock. No existing device is revoked to make room, so an
account at the cap has to revoke one itself — the device screen must make that
obvious and safe. B14 then keeps its per-device loops bounded by the cap rather
than by their own limits. No schema change.

## Q8 — Should there be an in-app way to stop server wake-ups?

**Context.** `PushService.unregister` exists and no screen calls it
(AUD-12j-1). The only way to stop the server waking the device is to sign out;
the OS setting stops delivery but the server keeps sending. The route and the
client method already exist, so "ship it" is mostly a Settings switch and a
call.

**Options.**
1. Ship a per-device "Notifications" toggle in Settings that unregisters the
   token server-side; re-enabling registers it again. The promise in the code
   becomes true.
2. Keep the OS setting as the only control, delete `PushService.unregister`
   and record the decision in the product docs. Less code, one less route.
3. Leave the dead method in place. Not recommended: it is a promise no screen
   keeps.

**What the answer changes:** one Settings control and its tests, or the
deletion of an unused client method. No wire change (the route exists).

**Answer (owner, 2026-10-25): option 1.** Settings gets a per-device
"Notifications" control: off calls `PushService.unregister` so the server stops
waking that device, on registers the token again. The OS setting stays what it
always was (whether the platform delivers), and the server route needs no
change. AUD-12j-1 closes with the control and its tests, and the method stops
being a promise no screen keeps.

## Q9 — Do call-quality telemetry and ICE restart ship?

**Context.** Two call capabilities are unreachable. The metrics pipeline has a
route, a client method and a serializer, but nothing ever sends a sample, so
`call_metrics` stays empty (AUD-12l-3); its `outcome` field is unbounded and
would be a ~9 GB-per-account exposure if it were ever fed (AUD-6-1). The
ICE-restart path has no caller, the adapter drops the offer it would emit, and
`CallSignalType` has no renegotiation kind (AUD-12l-4).

**Options.**
1. Delete both: the sampler, `sendMetrics`, `call_metrics` and its sweep, the
   renegotiation event and `restartIce`. Removes the storage exposure and a
   protocol gap in one change; call quality can return later with bounds and a
   signal kind designed for it.
2. Wire both: send samples (bounded field, account column, indexed cleanup) and
   add a renegotiation signal kind plus adapter handling. A protocol addition
   and an app release, for a feature with no UI today.
3. Keep the metrics route and bound it, delete only ICE restart. Mixed, and
   keeps a pipeline that produces nothing.

**What the answer changes:** whether the calls protocol gains a signal kind
(wire change, option 2), whether `call_metrics` exists at all, and whether
AUD-6-1 closes by bounding or by removal. No option changes stored user data.

**Answer (owner, 2026-10-25): option 1.** Both dead paths are deleted: the
quality sampler, `sendMetrics`, the `call_metrics` table and its sweep, the
renegotiation event and `restartIce`. AUD-6-1 closes by removal — the unbounded
`outcome` column is gone rather than bounded — and the calls protocol gains no
signal kind, so no wire change and no APK for this. Call quality, if the
product wants it later, comes back with bounded fields, an account column,
indexed cleanup and a renegotiation kind designed for it. Server: dropping
`call_metrics` is a new migration (never an edit of the one that created it).

## Q10 — Should the anomaly queue be per server?

**Context.** `AnomalyLog`'s queue is device-global and deliberately spans
sign-in: entries recorded before a session exists are sent after one is, and
entries carry types, routes and stacks rather than content (AUD-14h's coverage
note). On a device with accounts on two servers, entries recorded while one
account was signed in can be sent through whichever server signs in next, and a
crash during one account's session can be delivered to the other server after a
switch. Nothing is exposed beyond what the log already sends — the question is
whose log it is.

**Options.**
1. Tag each entry with the account/server it was recorded under; send only that
   server's entries. Pre-sign-in entries are tagged when the next runtime
   resolves, or kept in a separate pre-session batch sent to the server that
   signs in. Needs one additive payload/field and a small queue split.
2. Keep it device-global, and record in the docs that a crash log may reach the
   account's server rather than the one that was open at the time. No code
   change; the current behaviour becomes the stated contract.
3. Clear the queue on an account switch. Simplest, but the crash that caused a
   switch (or happened just before it) is exactly the one worth keeping.

**What the answer changes:** whether B24's fix carries a queue split and an
additive field, or a documentation line. No option touches message content or
keys. No schema change server-side.

**Answer (owner, 2026-10-25): option 1.** An entry records the account/server
it was seen under and only that server receives it; entries recorded before any
session exist are tagged when the next runtime resolves, or held as a
pre-session batch sent to the server that signs in. So a crash in one account's
session can no longer be delivered to another operator. One additive field in
what the anomaly log sends and a small queue split; the log still carries
numbers, routes, types and stacks only. No server schema change.
