# Sweep 12b — engine: outbound queue, sender, inbound runner

Read line-by-line: `messaging/outbox.dart` (482), `messaging/sender.dart`
(268), `messaging/inbound_runner.dart` (292), `db/src/daos/outbox_dao.dart`
(313, the claim/reschedule SQL these call), `groups/group_ops.dart` (76),
`groups/group_pipeline.dart` (77), `groups/group_keyring.dart` (196),
`groups/group_sender.dart` (287), `groups/group_rekey.dart` (167), plus
cross-reads: `groups/groups_service.dart` (create, `_updateState`),
`groups/group_inbound.dart` (`_rekeyDuty`, `_shareKeyDuty`),
`engine.dart` (`syncOnce`/`drainOutbox`/`signOut`), the app's
`session_providers.dart` (`SignOutAction`), `push_background.dart` (headless
`syncOnce`) and `calls/engine_call_signaling.dart` (`sendSealed` caller).
~2,000 lines; over the 1,500 guide because the group-key rotation path only
makes sense with its sender and service halves in view. The rest of the group
code stays for 12e/12f.

Verdict: the outbound pipeline's core is sound — idempotent enqueue, lease +
ordering, commit-before-send, prekey re-send until answered, stale-list
re-plan, ack after durable processing, and one engine per database file
(`EngineLease`). The one real defect is in how a *failed non-message op* is
classified and surfaced: a group key rotation can be lost permanently and
silently.

---

### AUD-12b-1 A failed group rekey is permanent and silent; group state edits then fail for everyone

**Severity** P2  **Confidence** confirmed

**Where**
- [`messaging/outbox.dart:217`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L217) — `classifyOpError`'s `case GroupException(): return GiveUp(...)` maps *every* reason to a permanent failure.
- [`groups/group_rekey.dart:145`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_rekey.dart#L145) — `rekey` retries `version_conflict` itself for `GroupLimits.stateRetries` (4), then throws `GroupException(versionConflict)`.
- [`groups/group_rekey.dart:120`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_rekey.dart#L120) — throws `GroupException(noGroupKey)` when this device holds no previous key and the title is empty (a "key has not arrived" state, not a permanent one).
- [`messaging/outbox.dart:468`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L468) — `_giveUp` sets the op `failed`; only `OutboxService.retry(opId)` brings it back ([`outbox.dart:160`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L160)).
- Retry is reachable only through a **message** row: [`features/chats_service.dart:538`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L538) and the conversation's retry button ([`conversation_screen.dart:536`](file:///J:/Projects/helix/helix_remote/app/lib/features/conversation/presentation/conversation_screen.dart#L536)). A rekey op has `messageRowid == null` ([`outbox.dart:141`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L141)), so `SendFailedEvent(messageRowid: null)` ([`outbox.dart:476`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L476)) has no listener at all (the app listens to nothing of this type).
- Enqueued by [`groups_service.dart:603`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L603) (the remover) and [`group_inbound.dart:581`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_inbound.dart#L581) (the first admin after a leave or server-side removal).

**What** After a removal the server bumps the group's epoch and exactly one
device runs `group_rekey`. If that op fails with a *transient* condition —
a `version_conflict` race against another device's state write (already
retried 4× inside `rekey`), or `noGroupKey` while the previous key is still
in flight — the op is marked `failed` forever. No code re-enqueues it, no UI
shows it, and `OutboxService.retry` cannot be reached for an op without a
message row.

**Trigger** An admin device rotating the key while another of that account's
devices (or another admin) writes the group state in the same window; or a
removal processed before the group key reached the first admin's new device.

**Evidence** The classifier is reason-blind (outbox.dart:217-222) while the
producer distinguishes them: `notAMember` is terminal, `versionConflict` is
raised only after an in-op retry loop (group_rekey.dart:102-156) and
`noGroupKey` is defined as "has not reached this device **yet**"
(errors.dart:169-171). Neither can be retried afterwards: `claimDueOrdered`
selects `pending`/`inFlight` only ([`outbox_dao.dart:177`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/outbox_dao.dart#L177)), and the app's retry path starts from a message row.

**Impact** The epoch key is never created for anyone, so
`GroupsService._updateState` throws `noGroupKey` for every member device
([`groups_service.dart:646`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L646)): renames, descriptions and avatars fail with an opaque error until a
later removal/leave/ban happens to enqueue a fresh rekey. The removed member
also keeps the key of the current epoch, so any state blob still sealed under
it stays readable to them if they captured it. Message *content* is not
affected — group sends use sender keys, which rotate on member removal
independently ([`group_sender.dart:20`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_sender.dart#L20)).

**Fix sketch** Classify per reason: `notAMember`/`notAllowed` → `GiveUp`;
`versionConflict`/`noGroupKey` → `RetryLater` (they are exactly "the world
moved / not yet"). Give non-message ops a way back: a periodic
`GroupsService` sweep (or the existing roster refresh) that re-enqueues a
rekey when the group's epoch has no held key, which also repairs devices that
crashed mid-rotation.

**Test that proves it** Engine test: force `setState` to answer
`version_conflict` for the first `stateRetries + 1` calls, drain the outbox,
assert the rekey op is `pending` with a `next_attempt_at` (not `failed`) and
that a second drain rotates the key and `_updateState` succeeds afterwards.

**Overlap** AUD-12a-1 (a dead-end state with no visible recovery), AUD-1b-1
(server-side jobs that are dropped permanently) — same failure shape on the
client side.

---

### AUD-12b-2 Sign-out and engine close can hang ~30 s offline behind an inbound retry

**Severity** P3  **Confidence** confirmed

**Where**
- [`messaging/inbound_runner.dart:133`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound_runner.dart#L133) — `_processRetrying` sleeps `inboundRetry.delay(...)` (1 s → 30 s, [`config.dart`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/config.dart)) while `_running`, and only checks `_running` *after* the sleep.
- [`inbound_runner.dart:97`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound_runner.dart#L97) — `stopRealtime` sets `_running = false` but then awaits the serial queue, which is occupied by that envelope.
- [`engine.dart:528`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L528) — `signOut` awaits `_stopWorkers()` first; [`engine.dart:417`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L417) makes that wait on `_inbound.stopRealtime()`.
- [`session_providers.dart:69`](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/session_providers.dart#L69) — the app awaits `engine.signOut()` before wiping and switching.

**What** One envelope that needs a network lookup (a peer's device list, a
group read) throws `TransientEngineException` while offline and sleeps in
backoff; sign-out/close cannot cancel the sleep, only wait it out.

**Trigger** Sign out, remove an account, or switch accounts while offline
with one unprocessed envelope (for example the first message from a new
contact, which needs a key fetch).

**Evidence** The retry loop's delay is not interruptible (no `Completer`
completed by `stopRealtime`), and `stopRealtime` has no deadline. `syncOnce`
in the push isolate is unaffected (it uses `_processGuarded`, inbound_runner.dart:159).

**Impact** The sign-out button appears frozen for up to ~30 s; on Windows the
window reports "Not responding". No data is lost — the wipe still runs.

**Fix sketch** Make the backoff cancellable (wait on a future that `stop`
completes, or check `_running` before sleeping and cap the delay when
stopping), or give `stopRealtime` a short deadline after which it stops
waiting for the queue.

**Test that proves it** Engine test: sign in, go offline, deliver an envelope
whose processing fetches keys, then `await engine.signOut()` and assert it
returns within ~1 s.

**Overlap** AUD-12a-4 (start/stop not serialized) — same stop path, different
symptom.

---

## Structural proposal (1 of max 3)

**S1 — op kinds need a retry policy, not one shared classifier.**
*Current shape.* Every op kind goes through `classifyOpError` (outbox.dart:203-239),
and failure handling is uniform: `GiveUp` marks it failed, and the only
recovery is a per-message retry button.
*Hazard.* Duty ops (rekey today, more later: prekey top-ups, key re-shares)
have no row a user can retry; a terminal classification silently deletes a
security-relevant action (AUD-12b-1).
*Proposed shape.* A per-kind policy object returned with the op
(`onFailure(op, error)`), where message ops keep today's behaviour and duty
ops either reschedule forever with backoff or are re-derived from state (the
group's epoch vs the held keys) by a periodic reconciler.
*Migration.* Additive: default policy = `classifyOpError`; adopt it for
`group_rekey` first; the reconciler is a few lines in the existing
maintenance pass. No schema change.
*Risk.* A reconciler that re-enqueues blindly could loop; it must check the
state it wants to reach (key for the current epoch absent) before enqueueing.
*Size.* ~80 lines plus tests.

## Verified safe (checked, no finding)

- **Lease/claim concurrency.** `claimDueOrdered` leases ≤20 ops for one
  `outboxLease` (2 min) and `runOnce` processes them serially. A second
  claimant could re-claim expired ones, but one engine per database file is
  enforced by `EngineLease` (`app/lib/core/platform/engine_lease.dart:80-119`),
  the worker's `_running`/`_again` guard prevents overlapping `runOnce`
  (outbox.dart:294-318), and `drain()` is only reachable from headless hosts
  (`syncOnce`/`drainOutbox`). The `EngineAlreadyRunning` catch in
  `push_background.dart:77` is what makes the FCM isolate safe.
- **Commit-before-send.** A POST that fails after `encryptFor` is recoverable:
  the initiator keeps sending prekey messages until a reply
  (`crypto/lib/src/v2/session.dart:82-84, 394-397`), so the retry decrypts.
- **Stale lists.** `device_list_stale` adopts new devices, drops gone ones and
  re-plans with its own attempt budget (sender.dart:87-144, group_sender.dart:144-158).
- **Empty-`onlyDevices`.** Filtering a peer's devices down to none throws
  `UntrustedPeerException` rather than posting an empty recipient
  (sender.dart:206-212); the call path turns that into an empty response
  (engine_call_signaling.dart:65), so a signal to a vanished device is dropped,
  not retried.
- **Ack placement.** `_ack` runs only after the envelope's transaction
  committed or it was quarantined; a failed ack re-delivers and
  `processed_envelopes` swallows the duplicate (inbound_runner.dart:208-227).
- **Ordering.** Ops without a conversation (session resets, rekeys) never block
  a chat, and a chat's first queued op blocks later ones even while backing
  off (outbox_dao.dart:186-195) — the intended semantics.
- **Blocked recipients.** `markBlocksMe` is skipped on a replayed response
  (sender.dart:63-77), and "everyone blocked me" gives up the op rather than
  reporting a false success.

## Coverage notes (12c+)

- `sendSealed` evaluates `_crypto.withoutSession(devices)` twice per attempt
  (sender.dart:102-107) — pure duplicate DB work, no correctness effect; not
  worth a finding at current audience sizes.
- `OutboxDao.claimDueOrdered` loads **every** queued row before applying its
  per-chat filter and limit (outbox_dao.dart:177-195) — no SQL `LIMIT`. A
  large held queue (an upload backlog) makes each worker pass read the whole
  set. DB-package concern, left to sweep 10's owner as agreed.
- `GroupKeyDistributor.share` rides the `send_content` op kind
  (group_rekey.dart:68-81), so a blocked audience can fail a key handover as
  `blocked`; only reachable when every member blocked this account, and the
  key is re-sent on the next send.
- Non-message ops (`session_reset`, `group_rekey`) carry no conversation id,
  so they run in parallel with chat traffic within a claim batch. The reset
  path is per-device and the rekey path re-reads the group, so this is safe
  today.
- `inbound_runner`'s `_safetyNet` swallows every error (inbound_runner.dart:174-180)
  — deliberate; the next wake/reconnect retries.
