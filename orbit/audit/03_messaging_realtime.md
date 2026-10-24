# 03 — Messaging + realtime

## Overview

`messaging` is the only delivery path in the server: one sealed envelope row
per recipient device in a hash-partitioned `mailbox`, a per-device `seq`
allocated under a row lock, a 10,000-row quota trimmed oldest-first, 30-day
expiry, per-(sender account, device, message id) idempotency, and a block hook.
`realtime` is the WebSocket gateway: it pumps the mailbox within a 100-envelope
credit window, routes each device to the node holding its socket through
ephemeral keys, and closes sockets on supersede, revoke, suspension and token
expiry. Delivery to an offline device is a stored row; "live" delivery means
socket if a route exists, otherwise a push. Both modules trust
`kernel/presence.dart` and the Postgres bus; neither keeps cross-node state.

## Files read

- `modules/messaging/MODULE.md` (116), `api.dart` (160), `module.dart` (773),
  `data/mailbox_store.dart` (318)
- `modules/realtime/MODULE.md` (51), `module.dart` (533)
- `kernel/presence.dart` (28)
- Cost of the primitives these call: `platform/ephemeral/ephemeral_store.dart:128-240`,
  `platform/bus/event_bus.dart:80-121`, `platform/jobs/jobs.dart:24-55`,
  `platform/db/postgres_db.dart:107-188` (tx + `afterCommit`)
- Call sites needed to judge impact: `modules/calls/module.dart:340-380, 510-535`,
  `modules/people/module.dart:650-663`, `modules/identity/application/context.dart:355-395`,
  `packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart:565-590`
- Tests (titles only): `test/modules/messaging_test.dart`, `test/modules/realtime_test.dart`
- `docs/architecture/ARCHITECTURE_V2_PLAN.md` (S3 rows, §3-6 messaging/realtime)

## Findings

### AUD-3-1 Ephemeral and urgent fan-out cost two DB round trips per recipient device
- **Severity:** P2
- **Confidence:** confirmed
- **Where:** [messaging/module.dart:635-665](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L635)
  (`deliverEphemeral` loops per device: one `ephemeral.put`, one `bus.publish`),
  [messaging/module.dart:595-600](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L595)
  (urgent path calls `enqueuePush` per device), [jobs.dart:32-49](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart#L32)
  (one INSERT + one `pg_notify` per enqueue),
  [ephemeral_store.dart:140-148](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/ephemeral/ephemeral_store.dart#L140)
  (no bulk put), [event_bus.dart:90-97](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/bus/event_bus.dart#L90)
  (`publish` is one `_db.notify`).
- **What:** the stored path is deliberately set-based (two `unnest` inserts),
  but the two side channels are not. An ephemeral send allocates and publishes
  once per online device; an urgent stored send inserts one outbox row per
  offline device, and each `enqueue` publishes a wake notification after
  commit. At the 1,100-device cap that is ~2,200 sequential round trips inside
  one HTTP handler, against a single-PC Postgres. Ephemeral sends store nothing
  and therefore skip the stored-envelope budget entirely
  ([module.dart:332-345](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L332)).
- **Trigger:** `POST /v1/messages` with `ephemeral: true` (typing indicators,
  call signals) to a large group, or `urgent: true` to 1,100 offline devices.
  The per-account send limit (400 burst, 10/s) allows it repeatedly.
- **Evidence:** `deliverEphemeral` awaits `put` and `publish` inside a `for`
  over `online`; `deliver` awaits `enqueuePush` inside a `for` over `devices`.
  The bus explicitly chunks wakes at 150 because NOTIFY payloads are limited,
  but each ephemeral publish is still its own round trip.
- **Impact:** a slow handler (seconds on this PC), pool pressure that stalls
  unrelated requests, and an authenticated amplification knob — one request in,
  thousands of DB operations out. No message is lost.
- **Fix sketch:** add `EphemeralStore.putAll(Map<String,String>, Duration)` and
  `Outbox.enqueueMany(tx, entries)` as single statements, then publish ephemeral
  refs in chunks of ≤150 (one bus message per chunk). Server/platform only; no
  wire, schema or app change. Optionally give ephemeral sends a small
  per-account unit budget (see `99_OPEN_QUESTIONS.md`).
- **Test that proves it:** a 1,100-device ephemeral send and a 1,100-device
  urgent send each execute a bounded number of DB statements (count them with a
  statement-tracing test double), not O(devices).
- **Overlap:** AUD-1b-1 (push dedupe keys are the same jobs), sweep 6 (calls are
  the heaviest `deliverEphemeral` caller).

### AUD-3-2 A crash between expiry sweep statements inflates `pending` and later trims drop undelivered envelopes early
- **Severity:** P2
- **Confidence:** confirmed (mechanism); requires a crash to trigger
- **Where:** [mailbox_store.dart:204-221](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L204)
  (`DELETE` then per-device `UPDATE` as separate autocommit statements),
  [messaging/module.dart:119-123](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L119)
  (periodic loop), [mailbox_store.dart:23-43](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L23)
  (`excess = pending - quota`), [mailbox_store.dart:51-68](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L51)
  (`trim` deletes `excess` oldest).
- **What:** `pending` is a derived counter mutated by four independent
  statements (`allocate`, `trim`, `ack`, `purgeExpired`). The sweep's DELETE
  commits on its own; the compensating pending decrements run afterwards,
  outside a transaction. A process kill in between leaves `pending` higher than
  the number of stored rows. The next delivery to that device computes
  `excess = pending - quota` and `trim` deletes that many oldest **undelivered**
  envelopes, so the device's mailbox is silently shortened until the drift is
  consumed.
- **Trigger:** server crash/forced restart during any `messaging.expire` batch
  (up to 5,000 rows), followed by a send to the affected device.
- **Evidence:** `purgeExpired` takes `SqlSession` (the pool, not a `Tx`) and
  issues the delete and then one update per device group; nothing ties them
  together. `allocate` trusts `pending` unconditionally.
- **Impact:** silent loss of undelivered messages for the affected device — the
  same class the quota tradeoff (review A-01) accepts, but *without* the device
  actually being over quota. Undelivered rows are also the only copy of those
  messages.
- **Fix sketch:** make it one statement:
  `WITH gone AS (DELETE … RETURNING device_id) UPDATE device_seq SET pending =
  greatest(0, pending - g.n) FROM (SELECT device_id, count(*) n FROM gone GROUP
  BY device_id) g WHERE device_seq.device_id = g.device_id`. Schema unchanged;
  server only.
- **Test that proves it:** seed expired rows, run the sweep, assert
  `pending == count(*)` per device; then a fault-injection variant that throws
  after the delete and shows the counter unchanged (transaction) rather than
  inflated.
- **Overlap:** AUD-1b-2 (periodic lease can overlap), AUD-3-5.

### AUD-3-3 A presence route outlives its node, so "delivered live" is reported for a device nothing reached
- **Severity:** P2
- **Confidence:** likely (traced; window depends on client reconnect speed)
- **Where:** [presence.dart:8](file:///J:/Projects/helix/helix_remote/server/lib/src/kernel/presence.dart#L8)
  (`routeTtl = 75 s`), [realtime/module.dart:337-341](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L337)
  (route written with that TTL), [messaging/api.dart:94-97](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/api.dart#L94)
  (`deliverEphemeral` "returns the devices it reached"),
  [calls/module.dart:368-380](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L368)
  (only `!delivered` devices are parked in `pending_calls`).
- **What:** "online" is "the ephemeral route key exists". A crashed node leaves
  routes for up to 75 s; even a planned restart leaves them until each client
  reconnects and overwrites its key. During that window `deliverEphemeral`
  returns the device as reached although no socket consumed the envelope (the
  parked envelope also expires in 60 s), and urgent sends skip the push because
  `Presence.online` said yes. For messages this only delays a push (the row is
  stored); for **call offers** the caller is shown "ringing" while the offer is
  neither delivered nor parked, so the callee never learns of the call.
- **Trigger:** server restart/crash while a device is connected, then a call
  offer arriving before that device's client reconnects (typically seconds;
  up to route TTL if the client is stalled).
- **Evidence:** the route is the only liveness signal; `Presence.online` does a
  single `getAll` of route keys and has no node-liveness component. The
  graceful shutdown path deletes routes, but a crash or network partition does
  not.
- **Impact:** a missed call that looks to the caller like a normal ring; a
  skipped push that delays a message notification. No message loss.
- **Fix sketch:** write a per-node liveness key (`rt:node:<nodeId>`, ~10 s TTL,
  refreshed with the sweep) and require both keys in `Presence.online`/`isOnline`;
  or, calls-side, always park offers and let the callee drop duplicates. The
  first is one kernel + realtime change, no schema or wire change.
- **Test that proves it:** stop a node's route refresher without deleting its
  routes, send an offer, assert the caller is not told it was delivered and the
  offer is parked.
- **Overlap:** AUD-3-4, sweep 6, ADR-025 (route keys), pending-redeploy list is
  unrelated.

### AUD-3-4 The 25 s route-refresh sweep has no in-flight guard and re-authenticates every socket serially
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [realtime/module.dart:147-150](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L147)
  (`Timer.periodic(... track(refreshConnections))`), [realtime/module.dart:188-195](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L188)
  (per connection: `refreshRoute`, `checkSession`).
- **What:** the timer launches a new refresh regardless of whether the previous
  one finished, and the pass awaits an ephemeral CAS plus a token validation
  (a DB read) per connection, one connection at a time. One slow pass (store or
  DB stall, or thousands of sockets) overlaps the next, doubling auth queries
  and route writes. Closes are idempotent, so this is load amplification rather
  than a correctness bug.
- **Trigger:** `refreshConnections` taking >25 s — a pool stall, or roughly
  thousands of sockets on one node at one auth query each.
- **Evidence:** no `_refreshing` flag; `Timer.periodic` does not wait for the
  returned future.
- **Impact:** bursts of duplicate DB/ephemeral traffic at the worst moment (the
  stall that caused the overlap).
- **Fix sketch:** skip a tick while one pass is in flight (and log/measure the
  skipped count). Server only.
- **Test that proves it:** a fake authenticator that sleeps > the interval;
  assert a second tick does not start a second pass.
- **Overlap:** AUD-3-13.

### AUD-3-5 `messaging.expire` is an unbounded `while` loop with no yield or cap
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [messaging/module.dart:119-124](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L119),
  [mailbox_store.dart:204-221](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L204).
- **What:** the periodic every-10-minutes job deletes 5,000-row batches in a
  tight loop until none are expired. After a long outage (or a large expired
  backlog) one run can take minutes, and because batches are not yielded the
  job cannot be paused or bounded. Combined with AUD-1b-2 the next periodic
  lease can start a second sweep concurrently over the same rows.
- **Trigger:** 30-day retention with the server down or the DB slow, then a
  large expired set; or a flood that expired.
- **Evidence:** the loop condition is the only limit; no batch cap, no delay,
  no rescheduling through the job runner.
- **Impact:** long-running maintenance that competes with request traffic on
  the same pool; no data loss.
- **Fix sketch:** cap a run (e.g. 50k rows) and enqueue an immediate follow-up
  job, or sleep/yield between batches; both keep the sweep bounded. Server only.
- **Test that proves it:** seed more than the cap of expired rows and assert one
  run stops at the cap and schedules the rest.
- **Overlap:** AUD-1b-2, AUD-3-2.

### AUD-3-6 A duplicate send re-charges the budget, re-relays, and is charged before blocks and relay
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [messaging/module.dart:313-321](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L313)
  (replay check outside any transaction), [messaging/module.dart:332-346](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L332)
  (charge, then relay), [messaging/module.dart:350-359](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L350)
  (block filtering), [messaging/module.dart:377-399](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L377)
  (the claim and store happen last).
- **What:** the same message id sent twice concurrently passes both `acceptedAt`
  checks, both pay `chargeStored`, and both relay to remote peers; only the
  delivery transaction's `recordSend` decides the winner. Separately, even a
  single send is charged for devices of recipients who blocked the sender, and
  the charge is not refunded when a later relay throws `device_list_stale` /
  `not_found`.
- **Trigger:** client retry racing the original (the client's transport retries
  sends on timeout); a blocked recipient; a remote peer refusing the device
  list.
- **Evidence:** `chargeStored` is called before `beforeDelivery` and before the
  blocker lookup; the only dedupe is the `sends` insert inside the final tx.
- **Impact:** the sender's stored-envelope budget is spent without a stored
  envelope, and the peer sees a duplicate HTTP relay (its own `sends` row
  dedupes the message, so no duplicate delivery). No message is lost or
  duplicated.
- **Fix sketch:** claim the id in a short transaction before charging and
  relaying (insert with `ON CONFLICT DO NOTHING`, return the stored response on
  conflict), or at minimum charge after block filtering and refund on relay
  failure. Server only.
- **Test that proves it:** two concurrent sends with one id perform one charge
  and one relay; a blocked-only send charges zero.
- **Overlap:** AUD-1a-3 (platform Idempotency-Key, a different layer),
  AUD-3-2's counter.

### AUD-3-7 A replayed send loses `blocked_by`
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [messaging/module.dart:319-321](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L319),
  [messaging/module.dart:388-399](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L388).
- **What:** the replay response is built from `acceptedAt` alone, so
  `blockedBy` is empty even though the original response said some recipients
  blocked the sender. A client that retries after a lost response therefore
  cannot tell the user why a message was not delivered.
- **Trigger:** a send whose response is lost and retried after the first was
  accepted.
- **Evidence:** both replay branches construct `SendMessageResponse` with only
  `acceptedAt`/`replayed`.
- **Impact:** the UI may show "sent" for a message a recipient never received.
- **Fix sketch:** persist the blocked list with the `sends` row (one small
  column; migration) or accept the difference and document it. Wire unchanged.
- **Test that proves it:** retry a blocked send and assert the replayed response
  still names the blocker.
- **Overlap:** AUD-3-6.

### AUD-3-8 The device-list check runs before block filtering
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [messaging/module.dart:324-331](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L324)
  (`checkDevices`), [messaging/module.dart:350-359](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L350)
  (blockers), [messaging/module.dart:673-713](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L673)
  (the 409 with `missing`/`extra`).
- **What:** a recipient who blocked the sender is still required to be
  addressed on his exact active device list. If that person added a device, the
  whole send fails with `device_list_stale` and the sender is handed the fresh
  device ids of someone who will never see the message — although the send
  succeeds for everyone else once the list is refreshed.
- **Trigger:** a blocker changes devices, then the sender sends with the cached
  bundle list.
- **Evidence:** `checkDevices` is called on `addressed` before `blockedBy`
  removes anyone; the stale details include that account.
- **Impact:** one failed send (then a retry after re-fetching bundles), plus a
  device-list disclosure to a blocked sender (device ids are not secret, and
  blocks are explicitly not secret).
- **Fix sketch:** read blockers first and remove them from `addressed` before
  `checkDevices` (the block read is one query; ordering costs nothing).
  Server only.
- **Test that proves it:** blocker gets a second device, sender's old list still
  succeeds for other recipients with `blockedBy` set.
- **Overlap:** sweep 4 (block policy), AUD-3-6.

### AUD-3-9 Realtime timers use the wall clock, not a monotonic clock
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [realtime/module.dart:399-414](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L399)
  (frame bucket refill from `DateTime.now()`), [realtime/module.dart:509-513](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L509)
  (`checkIdle`), [realtime/module.dart:326-329](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L326).
- **What:** the frame-token bucket and the idle timer both diff wall-clock
  `DateTime.now()`. When the host clock steps backwards (NTP correction, a
  manual change on the server PC), elapsed time goes negative: the bucket
  refills by a negative amount and `checkIdle` sees a huge interval.
- **Trigger:** a backward clock step while sockets are open.
- **Evidence:** both use `DateTime.now()`; nothing uses a `Stopwatch`.
- **Impact:** sockets can be closed with 4029 ("too many frames") or 4010
  ("idle") for no client misbehaviour; clients reconnect, so it is a blip.
- **Fix sketch:** one `Stopwatch` per connection (or an injectable monotonic
  clock, as the ephemeral store already has) for both measurements. Server only.
- **Test that proves it:** with a fake clock stepped back, no frame-bucket close
  and no idle close happen.
- **Overlap:** none.

### AUD-3-10 A failure between registering the socket and `start()` leaves a socket that presence calls online
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [realtime/module.dart:264-276](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L264)
  (map write, `saveRoute`, `bus.publish`, `start`), [realtime/module.dart:380-397](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L380)
  (listener, hello, first pump).
- **What:** `_accept` puts the connection in `_connections` and writes the
  route before `start()`. `start()` is also where the client's stream is
  listened to, so if `saveRoute`/`publish` throws, `track` logs it and the
  socket stays registered and "online" but is never pumped and never says
  hello. Idle close (two heartbeats) is the only recovery.
- **Trigger:** the ephemeral store or the bus failing during an upgrade (e.g. a
  Postgres blip).
- **Evidence:** the throw skips the listen, the hello and `pump`; nothing wraps
  the post-registration sequence in a close.
- **Impact:** ~50 s of false presence for that device: stored mail is not
  pushed (presence says online) and the client waits for a hello that never
  comes.
- **Fix sketch:** wrap the post-registration sequence in try/catch and
  `close(goingAway)` on failure; server only.
- **Test that proves it:** a bus double that throws on publish; assert the
  socket is closed and its route is gone.
- **Overlap:** AUD-3-3.

### AUD-3-11 The mailbox backlog gauge scans up to one million rows on every scrape
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [messaging/module.dart:41-48](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L41).
- **What:** the collected gauge runs `SELECT count(*) FROM (SELECT 1 FROM
  mailbox LIMIT 1000000)` — an index-only scan over every partition, on the
  scraped node, per scrape. It is bounded but expensive at the ceiling.
- **Trigger:** a scrape while the undelivered backlog is large (many offline
  devices at quota).
- **Impact:** steady CPU/IO on the production PC during exactly the incidents
  an operator is watching.
- **Fix sketch:** sum `device_seq.pending` (already maintained) instead of
  counting rows, or mark the gauge approximate/sampled. Server only.
- **Test that proves it:** none needed; a statement-plan or timing check.
- **Overlap:** AUD-3-2 (the same counter's correctness matters more if used).

### AUD-3-12 Two near-simultaneous upgrades of one device can close the newest socket
- **Severity:** P3
- **Confidence:** suspected (interleaving not reproduced)
- **Where:** [realtime/module.dart:243-277](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L243),
  [realtime/module.dart:134-146](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L134)
  (supersede subscriber).
- **What:** `_accept` awaits `messaging.resume` before it reads and replaces
  `_connections[deviceId]`, then awaits close/save/publish/start. Two upgrades
  for one device that interleave across those awaits can each publish
  `realtime.connected` while the map holds the other connection; the handler
  closes "the existing connection whose id is not mine", which can be the
  newer, working socket. The route may then point at a closed connection until
  the client reconnects.
- **Trigger:** an app reconnect racing a duplicate instance (two sockets with
  the same device token).
- **Evidence:** the supersede check is "id differs", not "this message is
  newer"; `_accept` has no per-device serialisation.
- **Impact:** both sockets may close (4008); the client's reconnect loop
  recovers. No message loss (mailbox rows remain).
- **Fix sketch:** serialise `_accept` per device with a small in-flight map, or
  compare a monotonically increasing connection generation and only close the
  older one. Server only.
- **Test that proves it:** open two upgrades in one event-loop turn; exactly one
  stays open.
- **Overlap:** none.

### AUD-3-13 Every open socket re-authenticates against Postgres every 25 seconds
- **Severity:** Idea
- **Confidence:** confirmed
- **Where:** [realtime/module.dart:188-195](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L188),
  [realtime/module.dart:362-374](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L362).
- **What:** the design refreshes each socket's route and re-validates its token
  on a 25 s timer. Expiry is knowable locally (JWT `exp`), and the events that
  invalidate earlier — revoke, sessions ended, suspension — already arrive on
  the bus. At 5,000 sockets this is ~200 auth queries/s plus a route CAS per
  socket per tick, on a single-PC server.
- **Trigger:** socket count growth.
- **Evidence:** `refreshConnections` calls `authenticator.device(token)` per
  connection every tick; the bus already closes sockets for the invalidation
  events.
- **Impact:** needless DB load that scales with connections; the periodic auth
  is the main defence against a missed bus message, not against expiry.
- **Fix sketch:** cache the principal until `min(token exp, next bus resync)`
  and re-validate then (plus on upgrade); keep the route CAS on the timer.
  Server only. Sized as an idea, not a defect.
- **Test that proves it:** with a fake clock and no bus events, no auth query
  happens before `exp`.
- **Overlap:** AUD-3-4.

## Structural proposals

### S1 Batch the fan-out side effects
- **Current shape:** stored fan-out is two `unnest` statements; ephemeral
  parking, push enqueues and wake publishes are per-device awaits.
- **Hazard:** an authenticated request costs O(devices) round trips and can
  stall the node (AUD-3-1).
- **Proposed shape:** `EphemeralStore.putAll`, `Outbox.enqueueMany`, and one
  bus message per ≤150 refs — the shape `deliver` already uses for wakes.
- **Migration:** add the bulk methods to the interfaces and Postgres/in-memory
  implementations, switch `deliverEphemeral`/`deliver`/calls, keep the
  single-item methods. No schema or wire change.
- **Risk:** medium (platform store and outbox are load-bearing); **size:** ~1-2
  days with tests.

### S2 Presence needs a second fact: is the node holding the route alive?
- **Current shape:** online == the route key exists; TTL 75 s, refreshed 25 s.
- **Hazard:** a crashed node's routes claim liveness for up to 75 s and
  `deliverEphemeral` reports a delivery that never happened (AUD-3-3).
- **Proposed shape:** `rt:node:<nodeId>` liveness keys refreshed with the sweep;
  `Presence.online` requires the route **and** its node's liveness key. A
  route whose node is dead is treated as offline (push/park, not silent drop).
- **Migration:** expand (write node keys, keep reading routes), migrate (read
  both, log disagreements), contract (require both and shorten route TTL to
  ~2× refresh). No schema change; kernel + realtime + calls only.
- **Risk:** medium (a wrong liveness read makes everyone look offline — the
  conservative direction is push/park, which is safe); **size:** ~1 day.

### S3 Make retention sweeps bounded, resumable jobs
- **Current shape:** periodic jobs do `while (purge > 0) {}` on the pool
  (messaging, and the same pattern in other sweeps).
- **Hazard:** one run can exceed its interval, overlap the next lease
  (AUD-1b-2) and monopolise the pool (AUD-3-5); the multi-statement pending
  update can drift (AUD-3-2).
- **Proposed shape:** each sweep is a self-rescheduling outbox job: one
  transaction per bounded batch (delete + pending adjustment in one statement),
  re-enqueued with a short delay while rows remain.
- **Migration:** add the job kind, run it alongside the periodic job, then
  remove the `while` loop. Server + a job-kind constant; no schema or wire
  change.
- **Risk:** low-medium (job runner already provides leases/backoff);
  **size:** ~1 day.

## Coverage gaps

- Did not read the internals of `IdentityApi.lockActiveDevices` /
  `activeDevicesOf`, `MessageRelay`, the S2S receive routes, or the groups
  sender-key fan-out; they are sweeps 2, 6 and 4. The findings above stop at
  the API boundary.
- Did not read the protocol DTO definitions (`SendMessageRequest`,
  `MailboxPage`, `ClientFrame`) or the client `RealtimeClient` beyond the
  heartbeat, so a field-level wire mismatch between these modules and sweep 8's
  contract is not ruled out.
- Did not execute tests: the findings are static and none needed a repro. The
  existing suites cover replay, stale lists, block filtering, quota/trim
  behaviour at a high level, the credit window, REST-ack credit, supersede and
  close codes; there is no test for the crash window in AUD-3-2, for fan-out
  statement counts (AUD-3-1), or for node death (AUD-3-3).
