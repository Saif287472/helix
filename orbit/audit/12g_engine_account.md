# Sweep 12g — engine: account, devices, prekeys, session store

Read line-by-line: `account/account_service.dart` (756, including the
`LinkProposal`/`NewDeviceLink` half), `account/device_service.dart` (158),
`account/key_maintenance.dart` (165), `account/session_token_store.dart` (38).
Cross-reads to settle the findings: `engine.dart:300-380, 520-571` (start,
`_activate`, `signOut`, `deleteAccount`), the API's `transport/auth.dart:60-210`
(`accessToken`/`refresh`/`signedIn`) and `drift`'s `insertOnConflictUpdate`
(2.34.0, `statements/insert.dart:288-307`, to rule out a lost-column upsert),
the server's `identity/application/registration.dart:56-70` (takeover), and the
sign-in feature's takeover note (audit 15a, AUD-15-5). ~1,400 lines. Two
structural proposals.

Verdict: the crypto in this folder is careful — the auth key is the only thing
that leaves, the provision seals the AIK to the link, prekeys are stored before
they are uploaded. The weakness is **ordering**: this folder's own prekey code
documents "stored locally FIRST and then uploaded", but every path that makes
a *new device identity* does the opposite, and the identity and the session are
two separate commits. The two P2s are both "a failure in the wrong half-second
leaves the account on a server this device can never use again".

---

### AUD-12g-1 The device identity and the session are two commits; between them the engine is "signed in" with no session and cannot repair itself

**Severity** P2  **Confidence** confirmed code path (the window is one commit; the trigger is a crash or a failed settings write)

**Where**
- [`account/account_service.dart:555-594`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L555) — `_persist` commits identity, prekeys, prekey counters and the account row in one transaction (566-591), then calls `auth.signedIn(session)` (592) and only then `_onSignedIn()` (593).
- [`transport/auth.dart:100-105`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/auth.dart#L100) — `signedIn` writes the session into `settings` (a second commit) and caches it.
- [`transport/auth.dart:115-123`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/auth.dart#L115) — with no stored session, `accessToken` throws `SignedOutException(noSession)` without consulting `reauthenticate`.
- [`transport/auth.dart:136-140`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/auth.dart#L136) — `_refresh` throws the same way before the `reauthenticate` rung (line 151) is reached.
- [`engine.dart:325-339`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L325) — `start()` treats a stored identity as "running" and never looks at the session; [`engine.dart:528-541`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L528) — the only exit, `signOut()`, wipes every local row.

**What** A successful registration/sign-in/link writes the account in two
transactions: the identity block, then the session. Kill the process between
them (or fail the second write — disk full, `SQLITE_BUSY` from the other engine
on the same file) and the database holds an identity and an account row but no
session. Every later launch loads the identity (so `isSignedIn` is true, the
router goes to Home and the workers start), and every API call throws
`noSession`: the auth layer only tries device-key re-authentication *after* a
refresh was attempted, and with no session at all it refuses before that. The
device is registered on the server and holds the private key that could sign
in, but the engine never asks. The user sees a signed-in app that is
permanently offline; the only way out is `signOut()`, which deletes the local
history and keys, after which the number must be registered again (or taken
over).

**Trigger** Process death or a failed write between the `_persist` transaction
and the `signedIn` write. On Android the process can be killed at any time; the
second write is a fresh transaction, so the window is a full fsync.

**Evidence** The two writes are deliberately in one method but not one
transaction, and `_persist` already writes to `settingsDao` inside the
transaction (571-580), so the session could be part of it. `DeviceSessionAuth`
has the repair rung (`reauthenticate`, wired to `deviceKeySignIn` at
engine.dart:335) but reaches it only from `_refresh`'s `ApiException` branch
(151), never from the `session == null` guards (119, 139). The state is
reachable, stable (nothing purges a session-less identity) and indistinguishable
from a healthy sign-in to everything above the engine.

**Impact** A local-history loss for the user: the only available action is the
wipe-and-sign-in-again flow, and on a device that signed in by link the link is
gone too. The account itself is fine — the server still holds the device — so
the data loss is entirely on this device.

**Fix sketch** Two one-line-ish changes, either is enough: (a) write the
session row inside `_persist`'s transaction (the store is the same database;
`signedIn` then only caches it), or (b) have `accessToken` fall through to
`reauthenticate` on `noSession` as `_refresh` does for a refused refresh, which
also covers a session row deleted out from under a running engine. (a) prevents
the state, (b) repairs it; do both.

**Test that proves it** Seed a database with an identity and account row and
no session, call `Engine.start()`, then a send: assert a device-key sign-in
happened (a challenge was requested) and the send succeeded. Today the send
throws `SignedOutException(noSession)` and no challenge is ever requested.

**Overlap** AUD-12a-1 (the account row without a usable session blocks every
sign-in path) and AUD-12a-2 (device-key re-auth treats a 429 as "device gone")
are the same dead-end state from other producers; this is the producer that
happens *during* sign-in, before the app has ever seen a session.

---

### AUD-12g-2 Every new-device flow keeps its generated keys in memory until the server call returns, so a lost response strands the account

**Severity** P2  **Confidence** likely (the ordering is unconditional; each flow's blast radius differs)

**Where**
- [`account/account_service.dart:84-123`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L84) — `register`: AIK, device keys and prekeys are made (84-96), the server call runs (100-115), and only then `_persist` (116).
- [`account_service.dart:210-246`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L210) — `recoverWithCode`: same order around `recoveryRedeem` (224-238).
- [`account_service.dart:512-552`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L512) — `_addDevice` (password sign-in at 294-300 and link accept at 490-499 share it): keys are made, `addDevice` runs, `_persist` follows.
- [`account_service.dart:699-704`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L699) — `LinkProposal.accept` spends the proposal before the call.
- `KeyMaintenance.initial`'s own doc states the rule the other order breaks: "stored locally FIRST and then uploaded: a key a peer might receive is always one this device can answer" ([`account/key_maintenance.dart:30-36`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/key_maintenance.dart#L30)).
- The single-use credentials: the recovery code is "good for 48 hours and one use" ([`account_service.dart:152-155`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L152)); a `verificationToken` is single-use (`PhoneVerifyResponse`); a link token comes from one approval.

**What** A timeout, reset or 5xx after the server has committed is
indistinguishable from a refusal. In all four flows the keys that the server
just stored are still only in Dart memory, so the catch/`finally` drops them:

- **recover:** the redeem rotates the account's identity key to the new AIK,
  signs every other device out, deletes the password and the history backup,
  and spends the code. The new AIK exists nowhere; the account is left with a
  single registered device whose private key is gone, and no way in except a
  *new* operator-issued recovery code, or SMS verification plus a takeover
  (`register(replaceExisting: true)`, which `_replaceIdentity` makes
  destructive).
- **register:** the number's account now exists with one device nobody can use.
  Retrying `register` with the same number is refused (`accountExists`); the
  user proceeds by takeover (re-verify the number) or by the password they
  chose, because the password wrap is server-side.
- **password sign-in / link:** a ghost device stays in the device list. Password
  sign-in is recoverable (`revokeOthers` from the next device, or the same
  password again); a link needs the other device to show a new QR and approve
  again, and the spent proposal never retries the token it already holds.

**Trigger** Any network-level failure (timeout, connection reset, 5xx at the
edge) after the server committed one of the four routes.

**Evidence** All four call sites place the only local write after the network
await; nothing keeps the generated `LocalDeviceKeys`/`Ed25519KeyPair` when the
call throws. The contrast inside the same package (prekeys first, upload
second, with a retry that re-uploads an unadvertised key) shows the codebase
already knows the safe order for key material.

**Impact** The recovery flow is the sharp one: a single timeout during the one
flow a user reaches for when they have lost access turns into "the recovery
code is no longer valid, and every device is signed out", with the backup
already deleted. The others leave an unusable or duplicate device row and cost
the user a second verification code or a second link approval.

**Fix sketch** Write the device identity before the call, in a state the engine
can resume: persist keys + prekeys + account row in one transaction with a
`pendingEnrollment` marker (or simply without the session), then call the
server, then flip to enrolled and write the session (which together with
AUD-12g-1's fix is one transaction). On a definitive `ApiException` delete the
staged rows; on a transport error keep them and let the next start resume —
`deviceKeySignIn` succeeds for register/recover/link because the server
registered the device in the same request, and `register` can be retried with
the stored account id. `LinkProposal.accept` then retries instead of spending
the proposal.

**Test that proves it** Point the identity client at a transport that commits
the request server-side and then throws a timeout; assert the local database
still holds the identity after the failure (today it is empty) and that a
second `Engine.start()` plus a device challenge completes the sign-in.

**Overlap** AUD-12e-1 is the same ordering mistake for the group master key
(create forgets the only copy). AUD-12a-1 is the dead end that a
half-completed sign-in feeds.

---

### AUD-12g-3 A link proposal is spent by the first attempt, including one that failed on the network

**Severity** P3  **Confidence** confirmed

**Where** [`account/account_service.dart:696-704`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L696) — `_used = true` is set before `_accept()` runs; every later `accept()` throws `StateError`.

**What** The guard exists so a proposal cannot be accepted twice (two device
registrations under one link token). But it also makes a *failed* accept
unretryable: the link token is still valid on the server and the new device
still holds the ephemeral key, yet the in-memory proposal refuses. The user has
to go back to the approving device and show a new code.

**Trigger** A transport failure on `POST /v1/devices` from the new device (the
same window as AUD-12g-2's link case, one step earlier in the UX).

**Evidence** `accept()` flips the flag before awaiting `_accept`; nothing resets
it. `reject()` sets the same flag, so the two outcomes are indistinguishable.

**Impact** A repeated QR flow, and under AUD-12g-2 a ghost device row too. No
data loss beyond the extra attempt.

**Fix sketch** Set `_used` after the call succeeds (or on a definitive
`ApiException`); keep a transport failure retryable. A second concurrent call
is still refused by the same flag while the first is in flight.

**Test that proves it** Approve a link, make the first `addDevice` throw a
`NetworkException`, call `accept()` again: it should attempt the registration
again with the same token.

**Overlap** AUD-12g-2.

---

### AUD-12g-4 A device-list operation reports failure when only its follow-up refresh failed

**Severity** P3  **Confidence** confirmed

**Where** [`account/device_service.dart:66-89`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/device_service.dart#L66) — `rename`, `revoke` and `revokeOthers` each await the API call and then `await refresh()`; [`device_service.dart:29-52`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/device_service.dart#L29) — `refresh` is a second network call.

**What** The mutation already succeeded on the server; the refresh that
updates the local list is a separate request that can fail on its own (a
dropped connection right after the mutation). The exception propagates, so the
UI shows the operation as failed and the list still shows the old state — for
`revoke` the device appears active after the user was told the revoke failed.

**Trigger** The network failing between the mutation and the list fetch.

**Evidence** `revoke`/`rename` do not touch the local rows themselves; the
local state changes only inside `refresh`, so there is nothing to fall back on.

**Impact** Confusion in the most safety-relevant screen (devices): the user
repeats the revoke (the server answers "already revoked"/not found, another
error) or believes the lost device is still trusted. `refresh` also drops the
revoked device's cached sessions and bundles (`_peers.retainDevices`), so the
local cache keeps them until a later successful refresh.

**Fix sketch** Apply the mutation to the local row (and call
`_peers.retainDevices` for a revoke) from the response the mutation returns,
then refresh best-effort inside a `try` that swallows transport errors.

**Test that proves it** With a client whose device list throws after a
successful `revokeDevice`, assert `revoke` returns normally and the local row
is gone.

**Overlap** AUD-12a-2 is the read side of the same "a second call decides the
first one's outcome" pattern.

---

## Structural proposals

**S1 — one enrollment flow for the four new-device paths.**
*Current shape:* `register`, `recoverWithCode`, `signInWithPassword` and
`LinkProposal.accept` each generate keys, call one of four routes, and call
`_persist`; the differences (who supplies the phone number, who supplies the
profile key, which token is spent) are arguments. `_persist` itself is split
from the session write.
*Hazard:* AUD-12g-1 and AUD-12g-2 — the ordering rules (keys before upload,
identity and session atomically, staged state on an ambiguous failure) are
restated at four call sites and currently wrong at all four.
*Proposed shape:* `DeviceEnrollment` in `account/` owning
`begin()` (make keys, write a staged identity in one transaction), `submit()`
(call the route), `finish(session)` (one transaction: session + enrolled flag)
and `discard()`. The link proposal becomes a thin wrapper that can `submit()`
again.
*Migration:* expand (add the type and convert `register`), migrate (one flow at
a time, each with its ambiguous-failure test), contract (delete `_persist` and
the loose sequences).
*Risk:* medium — a staged identity must be recognised by `start()` and by
`_requireEmpty`; do it behind the marker column so an old database is
unaffected.
*Size:* ~250 lines moved/added, four call sites, four tests.

**S2 — let the auth layer repair a missing session, not only a refused one.**
*Current shape:* `DeviceSessionAuth` has three outcomes — no session, expired,
refused — and only the refused one reaches `reauthenticate`; the engine's
identity is what makes device-key sign-in possible.
*Hazard:* AUD-12g-1 (a session-less identity is stranded) and AUD-12a-2 (the
same rung misclassifies a 429 as "gone").
*Proposed shape:* a single `_repair()` used by `accessToken`/`refresh` when
there is no usable session, with the "is this device gone?" decision left to
the engine callback (it already returns null for revoked) rather than to the
API's catch block.
*Migration:* expand (add `_repair`, call it on `noSession`) → migrate (move the
`ApiException` classification into `deviceKeySignIn`) → contract.
*Risk:* low; the worst case is one extra challenge request per call when the
device really is revoked, which `onRevoked` already handles by stopping the
engine.
*Size:* ~60 lines across the API and the engine, two tests.

## Verified safe

- **`_persist`'s transaction and upsert.** All identity rows go in one
  transaction; `accountDao.save` uses drift 2.34's `insertOnConflictUpdate`,
  which updates "the columns that are present on the entity", so
  `_ownProfileKey`'s partial companion (device_service.dart:147-155) does not
  null out `phoneNumber`/`helixName`.
- **Prekey ordering.** `KeyMaintenance.replenish` and `_syncSignedPrekey` store
  private keys before uploading, advance the id counter inside the same
  transaction, and re-upload an unadvertised signed prekey on the next pass;
  the retire step runs only after the upload.
- **Id counters.** Prekey ids come from settings counters written in the same
  transaction as the rows, so a consumed id is never reused; overlapping
  replenishments are AUD-12a-3.
- **`deleteAccount` leaves everything as it was on failure**
  (engine.dart:552-571), and only then runs `signOut`.
- **`leaveOnServer`** revokes, falls back to ending the session, and swallows
  both failures so the local sign-out always proceeds (account_service.dart:643-655).
- **Provisioning.** The link's provision is checked (`Provisioning.open`
  verifies the approver's certificate and its signature over this link) before
  `LinkProposal` exists, and the user's confirmation is the only path to
  `accept` (743-753).
- **Password plumbing.** Only the HKDF auth key is sent; the wrapped identity
  key returned by sign-in is unwrapped with the expected public key checked
  (283-293); `changePassword` derives the current auth key from the server's
  stored parameters and never stores the password.
- **`DbSessionTokenStore`** is one settings row, cleared by `forget`; a
  malformed row is dropped rather than wedging the API.

## Coverage notes

- A password sign-in (and a link accept) passes `profileKey: null` unless a
  backup restore supplies one; the first `approveLink` then mints a *new*
  profile key (`device_service.dart:142-157`). Whether two devices disagreeing
  on the account's profile key breaks own-profile reads is a data-flow question
  for 12h (`people_service`) and the backup sweep; noted here so it is not
  lost.
- `securityEvents` takes a fixed `limit` (default 50) with no cursor; the
  server pages, so a long list is truncated in the UI. Not a finding on its
  own — the devices screen may already be meant to show only recent events.
- `device_service.watch/list` read the stored list; `otherDeviceIds` refreshes
  only when it is empty. A newly linked device reaches existing devices through
  the server's `device_list_stale` answer (the send adopts it), so a stale list
  is self-healing rather than a finding.
- `key_maintenance.run` is driven by the maintenance scheduler; its overlap
  behaviour is AUD-12a-3 and was not re-audited.
