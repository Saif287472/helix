# Sweep 12k — engine: calls, part one (state machine and signalling)

Read line-by-line: `calls/calls_service.dart` (1,061),
`calls/call_signaling.dart` (61), `calls/engine_call_signaling.dart` (192) and
`calls/call_config.dart` (49), plus the cross-reads that settle them:
`engine.dart:311-460` (start, reconnect, `syncOnce`, `_stopWorkers`), the app's
`core/calls/call_host.dart` (91) and `features/calls/application/call_effects.dart`
(313, the notification-decision half), the headless call notifications
(`core/push/push_background.dart:142-178`), and the server's calls module
(`_pending` and its `ORDER BY`, `_endPending`, the pending insert and the
per-device push job, `calls/module.dart:330-560`), with the engine's existing
`test/calls/calls_test.dart` pending-call group (436-504). ~1,650 lines.
Part two (log mirror, media, models, transfer queue's call loops) is 12l.

Verdict: the state machine is sound: one call at a time on one queue key, glare
decided the same way on both sides, signals sealed per device and committed
before acting, every way out passes through the idempotent `_finish`, and a
headless wake never rings (`syncOnce` peeks). Two defects: the offline
catch-up rings the **oldest** pending offer while its own doc says newest (so
the newer caller is told "busy" and logged missed), and `release()` ends a
live call outside the queue it belongs to.

---

### AUD-12k-1 Offline catch-up rings the oldest pending offer, not the newest: every newer caller is told "busy" and logged missed

**Severity** P2  **Confidence** confirmed

**Where**
- [`calls/calls_service.dart:192-196`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/calls_service.dart#L192) — "rings the newest unexpired one (the rest are answered as busy)"; repeated in the app port ([`calls_port.dart:36-38`](file:///J:/Projects/helix/helix_remote/app/lib/features/calls/application/calls_port.dart#L36)).
- [`calls/calls_service.dart:197-222`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/calls_service.dart#L197) — `fresh` keeps the server's order and the loop takes the first that rings, then busy-ends every later one.
- [`server/.../calls/module.dart:537-542`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L537) — the query is `ORDER BY created_at`, i.e. **ascending**: the oldest offer comes first.
- [`calls/calls_service.dart:421-438`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/calls_service.dart#L421) — with a call already up, an offer is answered `busy` and `_logMissed` writes a missed row for it.
- [`core/push/push_background.dart:142-175`](file:///J:/Projects/helix/helix_remote/app/lib/core/push/push_background.dart#L142) — the headless pass shows a full-screen incoming notification for **every** pending offer, in the same oldest-first order.

**What** When a device reconnects with more than one unexpired offer parked on
the server (two callers, or a caller retrying under a new call id), the loop
opens them in server order and the first one rings. Because the order is
oldest-first, the call with the least ringing time left wins, and every newer
caller is sent `end: busy` and written into the callee's call log as missed —
on a device that is in fact free. The doc comment, the app's port and the
notification stack all assume the newest is the one that rings.

**Trigger** A callee device is offline (or its socket is down) for long enough
for two callers to start a call within the 60 s pending window, then resumes or
reconnects. `CallHost._ringPending` runs `fetchPending` on every resume
([`call_host.dart:49-63`](file:///J:/Projects/helix/helix_remote/app/lib/core/calls/call_host.dart#L49)) and the engine runs it on every socket connect
(`engine.dart:393-397`), so the path is the ordinary one.

**Evidence** `fetchPending` builds `fresh` from `_signaling.pending()` with no
sort (199-202); the server's `_pending` is `ORDER BY created_at` (540); the
engine's fake network in the tests returns offers in send order, and the tests
only ever park one offer (`calls_test.dart:436-504`), so nothing pins the
choice. The older offer is still valid — a caller that hangs up deletes its own
pending row (`module.dart:408-422`, `_endPending`), so any row left is a caller
still ringing — it simply has less time left.

**Impact** The call that rings is the one most likely to vanish within seconds
(its `expiresAt` is nearest), while the caller who just called is told the
callee is busy and gets a "Missed call" entry. The callee also sees one
full-screen call notification per pending offer, so their Answer press is
matched against the ringing call id and ignored when it was for a newer one
([`call_effects.dart:296-312`](file:///J:/Projects/helix/helix_remote/app/lib/features/calls/application/call_effects.dart#L296)). No content or key material is
affected; the damage is a wrongly rejected call plus wrong log rows.

**Fix sketch** Order `fresh` newest-first (`b.createdAt.compareTo(a.createdAt)`)
before the loop, which makes the code match its doc; alternatively make the
server `ORDER BY created_at DESC`. Since the rest are then busy-ended in
oldest-last order, their callers all still get a correct `busy`. If the intent
is really "oldest first", change the doc and the notification stack instead —
but one of them must move.

**Test that proves it** Engine test (fake network): park two offers for a
woken account (older from A, newer from B), call `fetchPending`, and assert
B's call is the one ringing and A got `end: busy`; today it is the reverse.

**Overlap** AUD-3-3 (presence routes outlive the node, so an offer is neither
delivered nor parked and the caller never rings) is the server-side twin of
this path; AUD-6-1 (metrics cost) is unrelated. No overlap with the server
sweep's call findings beyond `_pending` itself.

---

### AUD-12k-2 `release()` finishes the live call outside the call queue, so an engine stop can mislabel the log and race an in-flight accept

**Severity** P3  **Confidence** likely

**Where**
- [`calls/calls_service.dart:262-272`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/calls_service.dart#L262) — `hangUp().timeout(signalTimeout)`, then `_finish(still, CallEnd.failed, post: false)` directly, not through `_run`.
- [`calls/calls_service.dart:292-293`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/calls_service.dart#L292) — every other entry point runs on `_queue` under `_queueKey`.
- [`calls/calls_service.dart:540-550`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/calls_service.dart#L540) — `_hangUp` waits on `_signalEnd` (best effort, up to `signalTimeout` = 10 s) before its own `_finish`.
- [`calls/calls_service.dart:476-532`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/calls_service.dart#L476) — `_accept` awaits the media factory and the answer send on the queue with no timeout of its own.
- [`calls/calls_service.dart:764-806`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/calls_service.dart#L764) — `_finish` is idempotent, cancels the timers it knows about.
- [`engine.dart:409-421`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L409) — `_stopWorkers` awaits `calls.release()` and then closes the runtime.

**What** `release()` is the one caller that mutates the call outside
`_queue`. The timeout it sets bounds only the *wait*, not the queued
`_hangUp`, which keeps running; when the timeout fires (the stalled-network
case it exists for) `release` finishes the call itself with `CallEnd.failed`.
Two outcomes follow: the log records `failed` for a call whose hang-up signal
was already or later sent (log state `ended`), and if the queue was held by an
`_accept`, that accept resumes after the `_finish`, sets `phase = connecting`,
publishes a "connecting" snapshot for an ended call and installs a fresh
`connectTimer` **after** `_finish` cancelled the timers — a 30 s timer that is
never cancelled and fires into a closed service.

**Trigger** Engine stop (sign-out, account switch, runtime close, app
backgrounding to the headless isolate, hot restart) while a call is up or being
answered and the network is slow enough that a best-effort signal takes the
full 10 s. That is exactly when `release()` is used.

**Evidence** `_hangUp`'s path is `_signalEnd` → `_best` → `await
action().timeout(_config.signalTimeout)` (`calls_service.dart:914-942`), i.e.
the inner timeout and `release`'s outer one are the same 10 s, so the outer one
regularly fires mid-`_signalEnd`. `_accept` awaits
`_signaling.send(...)` with no timeout (506-520); `_finish` from `release` can
run between those awaits. `_connectTimedOut` guards on `call.finished`
(684-688), so the stray timer is harmless in effect, but it keeps the isolate
scheduled and the snapshot was already published.

**Impact** Rare, cosmetic-to-log only: a "failed" row instead of "ended", a
one-frame connecting snapshot on a call the UI is about to close, and a delayed
timer. Nothing reaches the peer differently (the hang-up send still runs) and
no data is lost. The queue invariant, however, is broken by exactly the method
that is supposed to make shutdown safe — worth fixing before the next
modification adds a second out-of-queue path.

**Fix sketch** Make `release` a queued operation: `_run(() async { if (_call
== null) return; await _best(() => _signaling.send(... hangup ...)); await
_finish(call, CallEnd.failed, post: false); })`, run it with an outer timeout
only for the caller's benefit, and let `_finish` stay the single place that
touches the call. A signal timeout inside the queue is enough; the local end
must not depend on winning the wait.

**Test that proves it** Engine test: start an incoming call, make the fake
signaling's `send` never complete, call `release()` with a short
`signalTimeout`, and assert (a) the log row's state, (b) `current == null`,
(c) no timer is left pending (`fakeAsync`/`flushTimers`). Today the row is
`failed` and a connect timer can be created after release only in the
accept-race variant, so the test should drive `release()` during `accept()`.

**Overlap** None. The call-log wording half of it (which `CallEnd` maps to
which row) meets the structural note below.

---

## Verified safe (checked, no finding)

- **One call, one queue.** Every public entry point (`startCall`, `accept`,
  `decline`, `hangUp`, `onSignal`, `onEndedElsewhere`) runs on `_queue` under
  the single key `calls` (292-293); `release` is the only exception (finding
  2). There is no path that mutates `_call` from another isolate.
- **Glare is symmetric.** Both sides compare call ids the same way and the
  incoming offer wins only when it is smaller (`calls_service.dart:401-420`);
  the loser sends `end: glare` to the single device and forgets the row
  (`_finish`, 785-786). The engine test suite covers both directions.
- **One device answers; the others are told.** The caller binds the first
  answering device, sends `answeredElsewhere` to a second one
  (`calls_service.dart:584-602`), and a sibling's `answeredElsewhere` before
  binding is ignored so the real answer can follow (641-643). The callee's
  other devices learn from the server's payload-less notice, accepted only
  when it names this account (`engine_call_signaling.dart:91-129`).
- **Signals are sealed per device and committed before acting.**
  `EngineCallSignaling._open` rejects sender-key messages, pins a new session
  against the stored identity key, refuses a same-account claim under another
  key, commits the ratchet in a transaction, and only then decodes the
  payload (`engine_call_signaling.dart:131-191`); a signal that cannot be
  opened is dropped, never retried or surfaced.
- **Nothing private is kept.** SDP lives in memory (`offerSdp`), ICE is
  drained and cleared on the bound device, remote candidates are capped at
  `maxQueuedCandidates` (64, `call_config.dart:11`), and `_finish` clears
  every queue and cancels every timer. No call content reaches the log.
- **Timers.** Ring (60 s, or the offer's own `expiresAt` for a pending
  offer, `calls_service.dart:456-462`), connect (30 s) and ICE batching (80 ms)
  are cancelled on every finish path; a timed-out ring on the caller sends
  `cancelled` then logs unanswered (376-384).
- **No ringing from a background wake.** `syncOnce` uses `peekPending` only
  (`engine.dart:445-456`); the headless isolate shows notifications and opens
  the offer only when the app runs.
- **Crash recovery.** `recoverUnfinished` (277-283) closes rows the log still
  shows as ringing/live at start-up, and `_stopWorkers` releases the call
  before closing.
- **Outcome message.** `_postOutcome` posts only for calls this device placed,
  with `answered`/`declined`/`failed`/`missed`, and a glare posts nothing
  (808-838); a failure to post is swallowed because the log row is the fact.
- **Incoming while busy.** The offer is busy-ended to the caller's device and
  a missed row plus notice is written for the callee (421-438), so the callee
  sees the attempt and the caller is not left ringing.

## Coverage notes

- **`_unreadable` is never pruned** (`calls_service.dart:83, 216`): a call id
  whose stored payload does not decode, or decodes to a non-offer, is kept for
  the process lifetime. Each entry is small and costs the sender a parked offer
  and a push, so it is bounded in practice; noted, not filed.
- **`fetchPending` opens offers sequentially**, each under the crypto lock and
  possibly a key fetch, so N parked offers cost N round trips before the
  screen rings. Bounded by the pending window; a newest-first pick (finding 1)
  would also cut the work to one open in the common case only if the loop
  stopped early — it must still busy-answer the rest.
- **`_postOutcome` maps `busy` to `CallOutcome.missed`** (808-838), so the
  caller's chat shows a missed-call entry for a callee who was on another
  call. A product choice, not a defect.
- **A live offer that arrives while the socket is down** is delivered when the
  socket reconnects and also parked only if the server saw the device as
  unreachable, so the two paths cannot both open the same ciphertext
  (`messaging` stores `payloads[device]` only for undelivered devices,
  `calls/module.dart:369-406`).
- **The call-log mirror** (`call_log_mirror.dart`, 54) and the media wrapper
  (`call_media.dart` 106, `fake_call_media.dart` 185) are 12l, together with
  the transfer queue's call loops.

## Structural proposal

**S1 — one table for how a call ends.** `logFacts` (1043-1060),
`_postOutcome` (808-838) and `_logMissed` (840-862) each encode part of the
same mapping from `CallEnd`/`CallOutcome` to row direction/state and chat
entry, and they already disagree in places (`busy` is "unanswered" in the row
and "missed" in the chat; `glare` is "cancelled" in the row and nothing in the
chat). Current shape: three switches over the same enum in a 1,061-line class
that also owns signaling, media and events. Proposed shape: a `CallOutcomeFacts`
table (`CallEnd → (direction, state, outcome?, missedNotice?)`) in
`call_models.dart`, consumed by `_writeLog`, `_postOutcome` and
`_emitMissedNotice`; expand by adding the table beside the switches, migrate
the three call sites, contract by deleting the switches. Risk: low — pure
mapping, no wire change. Size: ~120 lines moved plus a small test. This also
gives finding 2's "which row for a shutdown" question one place to answer.
