# 01b — Platform: durability and background work

## Overview

`Db`/`Tx` is the only way modules touch Postgres: one connection per
transaction, nested `tx` joins the running one, serialization failures and
deadlocks are retried, every transaction sets `statement_timeout`/`lock_timeout`
against pool starvation, and `afterCommit` actions run only after a durable
commit. Migrations are compiled Dart constants, per module, checksummed and
applied under one advisory lock. The transactional outbox (`platform.jobs`)
gives at-least-once background work with leases, backoff and dead letters; a
separate periodic scheduler runs every interval on exactly one node. The
ephemeral store is an UNLOGGED table with TTL checked on read and a periodic
sweep. Platform housekeeping runs the three sweeps (ephemeral 1 min, rate
buckets 10 min, idempotency 1 h) through the same scheduler.

## Files read

- `db/db.dart` (182), `db/postgres_db.dart` (435), `db/migrations.dart` (147),
  `db/schema_names.dart` (29), `platform_migrations.dart` (76)
- `jobs/jobs.dart` (365), `ephemeral/ephemeral_store.dart` (239),
  `startup.dart` (50), `platform/platform.dart:60-219`
- Call sites needed to judge the outbox keys: `modules/messaging/module.dart:488-498`,
  `modules/groups/federation.dart:525-545`; repo-wide search for `EXPLAIN`
  tests and `purgeDead` callers.

## Findings

### AUD-1b-1 A dead outbox job holds its dedupe key forever and silently suppresses every later one
- **Severity:** P1
- **Confidence:** confirmed
- **Where:** [jobs.dart:32-47](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart#L32) (`ON CONFLICT (dedupe_key) DO NOTHING`), [jobs.dart:216-241](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart#L216) (dead rows are kept), [platform_migrations.dart:54](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/platform_migrations.dart#L54) (`dedupe_key text UNIQUE`, not partial), key shape at [messaging/module.dart:488-498](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L488) (`push:<reason>:<deviceId>`), [groups/federation.dart:535](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L535) (`gdev:<groupId>:<accountId>`)
- **What:** dedupe is a table-wide unique constraint on `dedupe_key`, but a
  failed job is not deleted — it becomes `status='dead'` and keeps its key.
  `enqueue`'s `ON CONFLICT … DO NOTHING` then drops every future job with the
  same key. The documented contract ("ignored while the first is still
  pending") is stronger than the implementation, which means "ignored for
  ever".
- **Trigger:** a push job (`maxAttempts: 5`, backoff 5/10/20/40 s) fails five
  times during any FCM outage of ~75 s, or is repeatedly rejected while the
  token is being refreshed. The row goes dead with
  `push:<reason>:<deviceId>`. From then on every wake-up of that kind for that
  device — including `call` — is inserted as a no-op. `gdev:<groupId>:<account>`
  is worse: one dead relay job stops that account's device-list updates for
  that remote group permanently.
- **Evidence:** the unique constraint and the enqueue conflict clause; the
  dead path keeps the row (`_run` only deletes on success). Checked for a
  guard: the only remover of dead rows is `Outbox.purgeDead`
  ([jobs.dart:59-60](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart#L59)),
  whose sole caller is the admin route
  ([admin/module.dart:759](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L759)) —
  a manual operator action, not a periodic job. Nothing retries a dead row.
- **Impact:** silent, permanent loss of push wake-ups and of group
  device-list relays for one device/account. Messages still reach the mailbox,
  but a call does not ring and notifications do not appear until the app is
  opened; the user sees nothing wrong on the server side.
- **Fix sketch:** make uniqueness apply only to live rows:
  `ALTER TABLE jobs DROP CONSTRAINT jobs_dedupe_key_key; CREATE UNIQUE INDEX
  jobs_dedupe_live ON jobs (dedupe_key) WHERE status = 'pending' AND
  dedupe_key IS NOT NULL;` (immutable predicate, so a legal partial index).
  New platform migration; enqueue needs no change. Optionally requeue a dead
  row when a new enqueue arrives with its key instead of inserting a second.
- **Test that proves it:** in `jobs_test.dart`: enqueue a job with a dedupe
  key, make it fail to death, enqueue the same key again, assert a new
  pending row exists and runs.
- **Overlap:** the admin dead-letter purge; PLATFORM.md:17 ("dead letters");
  review of the push path in sweep 3.

### AUD-1b-2 A periodic job's lease can expire while it is still running
- **Severity:** P2
- **Confidence:** confirmed (mechanism); impact depends on the job
- **Where:** [jobs.dart:334-345](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart#L334) (`lease = max(60 s, interval)`), timeout at [jobs.dart:281-284](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart#L281)
- **What:** the claim sets `locked_until = now() + max(60 s, interval)`, but
  the run may take up to `jobTimeout` (5 minutes). A run that outlives its
  lease is claimable by another node, which sets `last_run_at = now()` and
  starts the same job concurrently. The class comment promises "once per
  interval cluster-wide", not "once at a time".
- **Trigger:** two nodes, and a job that runs longer than 60 s (a sweep over a
  large table, a storage-budget measurement, a media orphan walk —
  the ops sets are module-owned and read in later sweeps).
- **Evidence:** the two constants are in the same class and inconsistent; the
  claim predicate only tests `locked_until < now()`, so nothing prevents the
  second claim. The failure path clears the lock in `finally`, which does not
  cover the still-running case.
- **Impact:** duplicate concurrent sweeps. Today's three housekeeping sweeps
  are idempotent deletes, so the practical impact is wasted work and lock
  contention on shared tables; a future periodic job that is not idempotent
  (a "move rows" migration, GC that lists then deletes) would double-run.
- **Fix sketch:** lease = `jobTimeout + margin` (or have `PeriodicJob`
  declare a worst-case duration and lease that), keeping the `interval`
  gate independent.
- **Test that proves it:** a scheduler test with a clock and two node ids
  that starts a slow job on node A and asserts node B cannot claim it inside
  the timeout.
- **Overlap:** AUD-1b-1 (both are lease/lifecycle state on the same table).

### AUD-1b-3 The plan's EXPLAIN guardrail for hot queries does not exist
- **Severity:** P2
- **Confidence:** confirmed
- **Where:** claim at [ARCHITECTURE_V2_PLAN.md:212](file:///J:/Projects/helix/helix_remote/docs/architecture/ARCHITECTURE_V2_PLAN.md#L212) and [ARCHITECTURE_V2_PLAN.md:566](file:///J:/Projects/helix/helix_remote/docs/architecture/ARCHITECTURE_V2_PLAN.md#L566); nothing under `helix_remote/server/test` matches `EXPLAIN` (repo-wide search for `EXPLAIN ANALYZE` in `.dart` files returns nothing)
- **What:** the plan of record says "every query in a repository has an index,
  verified by an `EXPLAIN` test for the hot paths (send, fetch mailbox, ack,
  auth lookup)" and lists "EXPLAIN tests on hot paths" as a v2 step. No such
  test exists; index correctness is convention.
- **Trigger:** any migration or query change that drops an index's usefulness
  (a new default collation, a predicate that is not sargable, a
  `LIKE 'prefix%'` under a non-C collation — see AUD-1b-4) passes CI.
- **Evidence:** the searches above. The rule is enforced for *some* things
  (architecture tests, route catalog) so the plan's other guardrails are real;
  this one reads as done and is not.
- **Impact:** hot-path query plans can regress silently; the plan's "verified
  by a test" claim is false, which is the kind of drift the audit exists to
  find. Not a runtime bug today.
- **Fix sketch:** a Postgres-backed test that runs `EXPLAIN (FORMAT JSON)` for
  the four named paths plus the platform claim/find queries on seeded data and
  asserts no `Seq Scan` on the driving table; wire it into `verify.ps1` where
  the server suite already needs the database. Docs only otherwise.
- **Test that proves it:** the test itself.
- **Overlap:** AUD-1b-4 (one concrete query this would catch).

### AUD-1b-4 The ephemeral prefix scan cannot use the primary-key index under a non-C collation
- **Severity:** P3
- **Confidence:** likely (Postgres behaviour; depends on the database's default collation)
- **Where:** [ephemeral_store.dart:223-230](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/ephemeral/ephemeral_store.dart#L223) (`key LIKE @p ESCAPE '\'`), table at [platform_migrations.dart:28-32](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/platform_migrations.dart#L28) (`key text PRIMARY KEY`, default collation)
- **What:** `scan(prefix)` is `WHERE key LIKE 'prefix%'`. Postgres can use a
  btree index for a `LIKE` prefix only with `text_pattern_ops` or a `"C"`
  collation; the table has neither, and the host database is created with the
  Windows default locale, so the planner falls back to a sequential scan of
  every live ephemeral row.
- **Trigger:** any call to `scan` once presence and WS routes are numerous —
  every scan walks the whole table and filters in memory.
- **Evidence:** the query and the table definition; `_escapeLike` correctly
  escapes, so this is only a plan issue, not correctness.
- **Impact:** latency and CPU on the shared node as presence grows; not
  data loss.
- **Fix sketch:** `CREATE INDEX ephemeral_key_c ON ephemeral (key
  text_pattern_ops);` (or declare the column `COLLATE "C"`, which also makes
  equality cheaper). Confirm with `EXPLAIN` first.
- **Test that proves it:** the EXPLAIN test from AUD-1b-3, seeded with enough
  rows that the planner prefers the index.
- **Overlap:** AUD-1b-3.

## Structural proposals

### P1. Dead letters become an explicit lifecycle, not a tombstone
- **Current shape:** one `platform.jobs` table, `status IN ('pending','dead')`,
  unique dedupe over both states, deletion only on success, operator purge
  only by a manual admin call.
- **Hazard:** AUD-1b-1 — a failed job silently disables a key-shaped feature
  (push for a device, relay for a group) with no signal except a metric and
  no automatic recovery. The dedupe key is being used for two different jobs:
  "coalesce while running" and "identify a tombstone".
- **Proposed shape:** dedupe unique among `pending` rows only; a dead row is
  addressable (`POST /v1/admin/jobs/{id}/retry` or the existing purge grows a
  requeue verb) and a periodic job ages dead rows out after N days. One owner
  (`Outbox`) for both the enqueue contract and the dead-letter lifecycle, so
  the shape is enforced in one place.
- **Migration path:** expand (partial unique index, keep the old constraint
  until the index is in place), migrate (drop the constraint), contract (drop
  the old index if Postgres left one). New platform migration 3.
- **Risk:** low for the index change; the admin verb is additive. Requeue of
  a job whose side effect partly ran relies on handler idempotence, which the
  outbox already requires (at-least-once).
- **Size:** 4-6 h with tests.

### P2. Periodic jobs declare their worst case, and the scheduler proves the lease covers it
- **Current shape:** `PeriodicScheduler` hard-codes `jobTimeout` 5 min and a
  lease of `max(60 s, interval)`; nothing ties the two.
- **Hazard:** AUD-1b-2, a class that grows with every new periodic job.
- **Proposed shape:** `PeriodicJob(name, interval, run, timeout)` (default
  unchanged), lease = `timeout + 30 s`, and a unit test that, for every
  registered job (the real list, not a fixture), asserts the lease exceeds
  the timeout.
- **Migration path:** constructor change across registrations; no schema,
  no wire.
- **Risk:** none beyond touching every `PeriodicJob` call site (mechanical).
- **Size:** 1-2 h.

### P3. Restore the EXPLAIN guardrail as a first-class test
- **Current shape:** plan §4.3/§10 claims EXPLAIN tests on hot paths; there
  are none (AUD-1b-3), and the platform's own scan has no covering index
  (AUD-1b-4).
- **Hazard:** query-plan regressions are invisible; "the plan says it is
  tested" is itself a hazard because reviewers trust it.
- **Proposed shape:** `server/test/platform/query_plans_test.dart`, skipped
  without a database like the rest of the DB tests, asserting no full scan on
  the driving table for: send (device seq update), mailbox fetch, ack, auth
  lookup, job claim, idempotency find, ephemeral prefix scan. A shared helper
  that renders `EXPLAIN (FORMAT JSON)` for a statement and fails on
  `Seq Scan` of a named table.
- **Migration path:** additive test + the AUD-1b-4 index migration if it
  fires. Then update the plan's line to point at the file.
- **Risk:** seeded data must be big enough for the planner to choose indexes
  (`enable_seqscan` manipulation is tempting but hides the problem); keep
  seeds realistic and small but indexed.
- **Size:** 1 day.

## Coverage gaps

- Not read: `blobs/object_storage.dart`, `push/push.dart`,
  `storage/storage_budget.dart`, `bus/event_bus.dart`, `module.dart`,
  `config/server_config.dart:1-295`, `platform.dart:1-59` — sweep 1c.
- Module-owned periodic jobs (media orphan sweep, backup retention, purge
  jobs) were not enumerated; AUD-1b-2's real-world trigger depends on their
  runtimes and is checked in their module sweeps.
- No tests were run; no code changed. The EXPLAIN claim was checked by
  searching the repo, not by running the suite.
- `PostgresDb`'s driver-level `query_timeout` URL parameter was not exercised
  (no live database in this sweep); the code path is standard
  `package:postgres` v3 but unverified here.
