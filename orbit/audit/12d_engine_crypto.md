# Sweep 12d — engine: pairwise crypto glue, peer directory, session/prekey stores, local identity

Read line-by-line: `crypto/pairwise_crypto.dart` (195), `crypto/peer_directory.dart`
(295), `crypto/db_stores.dart` (147), `crypto/local_identity.dart` (76),
`util/keyed_lock.dart` (37), the `crypto_dao` session compare-and-set and
prekey writes (crypto_dao.dart:40-147), and the two `startSession`/`encrypt`
methods in the crypto package this glue drives (session.dart:343-410).
~800 lines. One structural proposal.

Verdict: the compare-and-set story (review finding C-01) is correctly built —
revision stamped on load, refused on a stale write, caller reloads inside a
per-device lock, and the FCM isolate is excluded by the engine lease. The
defect is in the *order* those two mechanisms are taken: two paths open a
database transaction first and then wait for a device lock, while every hot
path holds the lock first and then opens a transaction. Drift serializes
transactions, so that pair can wait on each other with no timeout.

---

### AUD-12d-1 Lock-order inversion: a peer-key update waits for a device lock inside a transaction, while senders hold the lock and wait for the transaction

**Severity** P2  **Confidence** likely (inversion confirmed in code; needs two paths to overlap)

**Where**
- [`crypto/peer_directory.dart:110`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/peer_directory.dart#L110) — `fetch` opens `_ctx.db.transaction` and then, inside it, calls `_applyKeyChange` (line 111) when the account's identity key changed.
- [`peer_directory.dart:162`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/peer_directory.dart#L162) — `_applyKeyChange` loops the account's devices and calls `_clearSessions` per device.
- [`peer_directory.dart:250`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/peer_directory.dart#L250) — `_clearSessions` runs inside `_ctx.deviceLocks.run(remote, …)`: **a device lock taken while the caller's transaction is open**. Same shape in `dropDevice` ([`peer_directory.dart:227`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/peer_directory.dart#L227)) and `retainDevices` (line 234).
- The opposite order, on both hot paths: [`pairwise_crypto.dart:135`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/pairwise_crypto.dart#L135) takes `deviceLocks.runAll` and opens the commit transaction at line 153; [`messaging/inbound.dart:205`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound.dart#L205) runs the whole apply under `_crypto.locked(sender, …)` and opens its transaction at line 275.
- [`util/keyed_lock.dart:11`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/util/keyed_lock.dart#L11) — locks are not re-entrant: a task that takes the same key twice waits on itself.
- [`db/src/daos/crypto_dao.dart:68`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/crypto_dao.dart#L68) — `saveSessions` itself opens a transaction (nested inside the caller's on the same zone, fine), and the CAS is what actually protects the record.

**What** `PeerDirectory.fetch`'s cache/key-change write is one transaction, and
inside it `_applyKeyChange`/`_clearSessions` acquire the per-device session
lock. Sending and inbound applying take that lock first and only then call
`db.transaction`. Drift serializes transactions on the engine's single
connection, so:

1. A `fetch` (send planning, `_bundlesFor`, or `PeerIdentityResolver`)
   detects a changed account key, opens the transaction, and waits for the
   lock of device D.
2. An inbound apply or a send for D holds D's lock and calls
   `db.transaction`, which queues behind (1)'s open transaction.
3. Neither can proceed. There is no timeout on either wait.

**Trigger** A peer's account identity key changes (or a `device_list_stale`
drop runs: `_applyStale` → `dropDevice`) while a message from that account's
device is being applied, or while another chat is sending to that device.

**Evidence** The two acquisition orders are both explicit: `transaction { …
deviceLocks.run }` in `fetch`/`dropDevice`, `deviceLocks.runAll { …
transaction }` in `_encryptFor`, and `locked { … transaction }` in the
inbound apply. `KeyedLock.run` queues unconditionally (keyed_lock.dart:12-16),
so the nested case also blocks rather than throws. `staleAttempts` retries
the CAS refusal but cannot break a lock wait.

**Impact** The engine stops: the inbound serial queue is stuck on one
envelope, the outbox worker's current op never returns, and the UI shows
"sending" forever. Only killing the app clears it (the DB is consistent: the
open transaction simply never committed). Occurrence is a race, but a key
change is exactly the moment the app is also retrying old messages.

**Fix sketch** One order everywhere: never take a device lock inside a
transaction. In `_applyKeyChange`/`dropDevice`, collect the device addresses
in the transaction (and write the person/device rows), then clear their
sessions after it commits, each with its own transaction. `_clearSessions`
already retries `StaleSessionState`, so it does not need the lock for
correctness — the CAS is the guard; the lock only avoids retries. The same
rule belongs in the coding conventions: locks outermost, transactions
innermost.

**Test that proves it** Engine test with two tasks and a gate: task A enters
`fetch` with a forced key change (hold it after the transaction opens), task B
holds the same device's lock and opens the inbound transaction; assert both
complete within a few seconds (today: a timeout).

**Overlap** AUD-12a-4 (lifecycle start/stop not serialized) — same class of
"two mechanisms, no owner of the order"; the CAS finding C-01 in the crypto
review is the mechanism this bug is a misuse of.

---

## Structural proposal (1 of max 3)

**S1 — make "lock outside, transaction inside" a checked rule, not a
convention.**
*Current shape.* Device locks live in `PairwiseCrypto`/`EngineContext` and are
taken ad hoc; transactions are opened ad hoc; nothing states their order.
*Hazard.* AUD-12d-1 is one instance; any new path that opens a transaction
and then touches a device (a key change, a device drop, a future prekey
rotation) can reintroduce it.
*Proposed shape.* A single helper pair on `EngineContext`
(`Future<T> withDevice<T>(DeviceAddress d, Future<T> Function() body)` and
`withDevices`) whose body is documented as "never open a transaction before
this is entered", plus a small assertion in `PairwiseCrypto`/`PeerDirectory`
debug builds that `db.inTransaction` is false when a lock is taken. Reviewers
then have one place to look.
*Migration.* Additive: the helpers wrap the existing `deviceLocks` calls; the
debug assertion catches violations in tests. No behaviour change.
*Risk.* An assertion that fires on a legitimate nested case would be noise;
the nested-in-transaction case is safe today only when the same task already
holds the lock — the helper must allow a re-entry check (`isBusy` plus a
task token) or the assertion must be scoped to the paths above.
*Size.* ~40 lines plus the call-site rewrites in `peer_directory.dart`.

## Verified safe (checked, no finding)

- **Session CAS.** `load` stamps `sessions.version`; `save` writes only when
  the stored slots still agree on it (crypto_dao.dart:68-98), so a second
  engine's interleaved write is refused, not lost. Slot rows that disagree
  read as version 0 so the first write repairs them.
- **Reload-on-refusal.** `locked` and `encryptFor` re-run the action from a
  fresh load up to `staleAttempts` and then rethrow for the caller's own
  retry (pairwise_crypto.dart:73-85, 122-129); `InboundProcessor` re-applies
  through the same lock.
- **Encrypt-before-commit.** Every ratchet advance is in the transaction that
  precedes the POST (pairwise_crypto.dart:153-157); a started session keeps
  `pendingPrekey`, so a lost POST is resent as a prekey message.
- **Session start preserves the revision.** `startSession` loads the record
  and returns `existing.withNewActive` (session.dart:374-376), so it cannot
  reset a record's version to 0 and wedge the CAS.
- **Key change is handled once.** A changed AIK clears every session of the
  account, keeps retired base keys (replay protection), marks devices stale,
  unpins verification, notices the user in the direct chat and in every group
  chat, and refuses a self key change outright (peer_directory.dart:103-198).
- **Trust on first use.** A first-use AIK is pinned in the same transaction
  as the device rows; a certificate that does not chain throws
  `UntrustedPeerException` instead of caching (peer_directory.dart:91-149).
- **Stale devices are not used for sends.** `devicesOf` filters
  `trust == trusted` by default (people_dao.dart:101-112), and
  `cachedIdentity` returns null for a stale device, so it is re-fetched.
- **Retired prekeys.** A retired signed prekey is answered until deleted
  (db_stores.dart:98-127); one-time prekeys are deleted in the transaction
  that applies the message that consumed them.
- **No secrets in logs.** `LocalIdentity.toString` and `PairwiseSession.toString`
  redact (local_identity.dart:75; session.dart:138).

## Coverage notes (12e+)

- `_encryptFor`'s comment says the fan-out commits in one transaction, but a
  newly *started* session is saved per device before the final commit
  (pairwise_crypto.dart:145-157). The effect is benign (an unanswered
  prekey session is reusable, and a retry re-encrypts from the reloaded
  state), but the comment overstates the guarantee.
- `fetch` is not serialized per account, so two concurrent send plans for a
  new device can both fetch a bundle; the server hands out one one-time
  prekey per request, so the loser's prekey is spent for nothing. Cost only.
- `_clearSessions` takes one device lock at a time; two callers clearing
  overlapping sets cannot deadlock each other on the locks (`KeyedLock` has
  no ordering requirement for single keys), only with the transaction as in
  AUD-12d-1.
- `PeerDirectory.fetch` never prunes devices the server no longer returns;
  they are dropped by `device_list_stale` handling or `retainDevices`, and
  stale rows are excluded from sends either way.
