# Remediation plan — Helix Remote / Orbit audit

Sweep 19, first written 2026-10-23 and rebuilt 2026-10-24 after sweeps 14i and
14j landed. This is the synthesis of every findings file in this folder. It
proposes work; it changes nothing itself.

**Snapshot (rebuilt 2026-10-24):** 210 findings in 53 findings files — P1 7,
P2 39, P3 158, Idea 6 (confirmed 165, likely 44, suspected 1). Every sweep is
read — 11 through 19, including every `a`/`b`/`c` split of 14 — and the rebuild
was machine-checked against the files: every id occurs once in the appendix,
in exactly one batch, with the severity its own file states. The original
synthesis (151 findings, 36 files, six sweep areas unread) was written before
12m–14j landed; the findings appended since then live in the batches named
below and in the appendix. The per-finding detail, with file and line
evidence, stays in the `NN_*.md` files named under each batch.

## How the batches are ordered

Three rules, applied in this order:

1. **Fix the instrument first.** A release gate that reports success for
   failed steps (AUD-18-1, measured) turns every later "verified" claim into
   an assumption. B1 lands before anything it is used to verify.
2. **Reach before severity.** A P2 that any stranger can aim at any stranger
   (B2: trim an offline victim's mailbox) outranks a P1 that one account
   triggers against itself (B5: a stranded device). Rank is *who can trigger
   it × who is hurt × whether it is silent*, not the label.
3. **One batch, one code seam, one test that holds it.** Findings that share
   a path or a test are merged even when severities differ; a batch is never
   split because one member is "only P3", and never merged because two
   members share a label but not a fix site.

Each batch carries a rollout class:

| Class | Meaning |
|---|---|
| **S** | Server deployment with a migration (expand → migrate → contract). |
| **W** | Wire-adjacent: server and clients must land in a stated order. |
| **A** | App/engine-only: a person must update; the server cannot force it. |
| **C** | Config, tooling, docs; no runtime behaviour. |
| **D** | Decide first — the owner's call; the batch waits. |

**Verification standard for every batch** (not repeated below): the new test
fails on today's code before it passes; `flutter analyze` / `dart analyze` on
the touched packages; the relevant suite; and for anything device-only (push,
notifications, calls, camera, the console's window chrome) a recorded
real-phone or real-window check in
[REMOTE_RELEASE_CHECKLIST.md](file:///J:/Projects/helix/helix_remote/docs/release/REMOTE_RELEASE_CHECKLIST.md).
Server suites need Postgres (`HELIX_REQUIRE_TEST_DATABASE=1`), and are never
run at the same time as a Flutter suite.

**Likely findings are reproduced before they are fixed.** 44 findings are
`likely` and one is `suspected`; each batch starts by turning its own into a
failing test. A fix for an unconfirmed mechanism is a guess. The one
`suspected` finding is AUD-3-12 (two upgrades of one device), in B11.

## Batch summary

| Batch | What it changes | Closes | Class | Rough size |
|---|---|---|---:|---|
| B1 | The gate can fail; the register check sees every row | 6 | C | 1–1.5 d |
| B2 | Stored fan-out is budgeted; presence tells the truth | 13 | S→W | 3–4 d |
| B3 | Dead jobs are recoverable; sweeps are bounded | 6 | S | 2–3 d |
| B4 | Every read has a deadline or a limit | 15 | S+C | 4–5 d |
| B5 | A stranded account is repairable on the device | 18 | A | 4–5 d |
| B6 | An action that cannot be applied says so | 12 | A | 5–6 d |
| B7 | Media follows its row and its quota | 6 | S | 3–4 d |
| B8 | Newest caller rings; call log is bounded | 8 | S+A | 2–3 d |
| B9 | The transport finishes what it starts | 12 | A | 3 d |
| B10 | An undrawable pack is refused before it is chosen | 9 | A+C | 2–3 d |
| B11 | One clock, one registration, one re-auth on sockets | 6 | S | 2–3 d |
| B12 | The protocol refuses what it cannot represent | 6 | W | 2–3 d |
| B13 | Local maintenance survives a large history | 21 | A | 1–2 d |
| B14 | Texts are charged when sent; devices are capped | 8 | S | 2–3 d |
| B15 | Reports and exports are honest about their bounds | 7 | S+W | 3 d |
| B16 | Group data and federation have one writer | 6 | S | 2–3 d |
| B17 | Sign-in and backup copy match the code | 9 | A | 2–3 d |
| B18 | The console never strands the operator | 8 | A | 1–2 d |
| B19 | The CLI obeys the client rules and says what happened | 7 | A | 1–2 d |
| B20 | The app's own gate and lifecycle answer again | 3 | A | 1–1.5 d |
| B21 | An attachment is what it is, cleaned, or it does not go | 5 | A | 1 d |
| B22 | A player and a recorder tell the truth about a failure | 2 | A | 0.5–1 d |
| B23 | The notification tells the truth about what arrived, and cleans up after an account | 9 | A | 0.5–1 d |
| B24 | The anomaly log sends what it recorded | 1 | A | 0.5 d |
| B25 | A chat day is a calendar day, and a snippet cuts a character | 2 | A | 0.5 d |
| T4 | Ideas and dead paths: decide, do not schedule | 5 | D | — |

**Total: 210 findings.** The order is the order in this document; the table is
the index, not a second priority. (151 at synthesis; sweeps 12m-12r appended
twenty-one — 12m's four, 12n's three queue findings, 12o's staging-retention
finding, 12p's four transfer-lifecycle findings, 12q's delete-resurrection and
truncation findings and 12r's three receive/send-lifecycle findings to B13,
12q's post-merge identity refusal to B17; 12n's presigned-upload, 12o's
download-cap and 12r's transfer-cap findings to B9, below. Sweep 13 appended
seven to B19, the new batch for the CLI: it is the only client outside the
app's address and status rules, and no earlier batch owns its code path.
Sweep 14a appended four: AUD-14a-1..3 to B5, the batch that already owns the
app half of the engine's lifetime (a settings stream outliving its runtime, an
account list read as "none" and deleting the folders, and a teardown that gives
up halfway), and AUD-14a-4 to B9, whose subject is the transport's headers.
Sweep 14g appended seven to B23, the new batch for app-side notifications: no
earlier batch owns what a notification says, what it counts, or what is
cleaned up when the account it belongs to is removed. Sweep 14h appended two
more to B23 — the ringtone copy and channel that the same removal path deletes
— and one to B24, the new batch for the anomaly log: no earlier batch owns
`core/diagnostics`. Sweep 14i appended two to B25, the new batch for the app's
own time labels and search snippets: no earlier batch owns `core/format` or
`core/chat`'s presentation helpers. Sweep 14j appended two to B10, the batch
that already owns the theme parse and the pack store: a folder read must not
throw for one bad pack (and the bad pack must be removable), and the offer
probe must be bounded and remembered.)

**By rollout:** 13 batches are app/engine-only (B5, B6, B9, B13, B17–B25 —
a person must update), 5 are server-only migrations (B3, B7, B11, B14, B16),
1 is wire-adjacent (B12), 5 are mixed (B2, B4, B8, B10, B15), 1 is config
(B1) and 1 is decide-first (T4). The rough sizes in the table sum to about
49–67 developer-days before parallelism; the server migrations and B5/B6's
fault-injection seams dominate that total.

## Decide first

Nothing in B2, B5, B8, B14, B15, B17, B24 or T4 can be designed until these are
answered (eight of the twenty-six batches). The options and their consequences
are in
[99_OPEN_QUESTIONS.md](file:///J:/Projects/helix/orbit/audit/99_OPEN_QUESTIONS.md);
the recommendation column is the audit's, not a decision.

| # | Question | Blocks | Recommendation |
|---|---|---|---|
| Q1 | Do ephemeral sends draw a budget? | B2 | **Decided 2026-10-24, option 1:** keep them uncharged, with B2's batching. Re-check fan-out cost afterwards; option 2 is the fallback if batching alone is not enough. |
| Q2 | Is `block_change` a stored envelope? | B2 | **Decided 2026-10-24, option 2:** advisory for `block_change` (the state is already in the next send's `blocked_by`), but keep a **stored, coalesced** removal notice for `roster_change`, because a removed member must learn it while offline. |
| Q3 | Truncate, stream or refuse a huge export? | B15 | Option 1: cap each section and say what was left out (`truncated`, `total`). |
| Q4 | Ship the platform-credential backup wrap? | B17 | Option 3: keep the capability, but `open` always falls back to the recovery secret. No product caller passes a platform key today, and the trap (stale key + correct phrase = failure) is removed without a new keystore dependency. |
| Q5 | Cap the Argon2id work an envelope may demand? | B17 | Option 3: keep the ceiling, and confirm with the person before a restore that will cost more than the app's own defaults. |
| Q6 | How is "session ended" recovered? (new) | B5 | Option (a): let a sign-in whose server account id equals the local one replace the identity and session, keeping chats and messages. It matches the documented promise and is engine-only. |
| Q7 | How many devices may one account hold? (new) | B14 | 20 (phones, tablets, an old PC), enforced in `addDevice` with `quota_exceeded`; no forced revocation of existing devices. |
| Q8 | Ship an in-app "stop wake-ups" control? (new) | T4 | Ship it: the client method and the server route exist, and the alternative is a promise no screen keeps. If not shipped this cycle, delete `PushService.unregister` and record the decision. |
| Q9 | Do call-quality telemetry and ICE restart ship? (new) | B8, T4 | Delete both dead paths: the quality sampler, `sendMetrics`, the `call_metrics` table and its sweep, the renegotiation event and `restartIce`. Nothing calls them, and deleting removes AUD-6-1's storage exposure outright. Re-add with bounds (and a protocol kind, for restart) only if the product wants call quality. |
| Q10 | Is the anomaly queue per server? (new) | B24 | Tag an entry with the account/server it was recorded under and send only that server's entries; pre-sign-in entries stay queued, but they are no longer sent to whichever server signs in next. Numbers, routes and types only, so no content question — a scope question. |

Q1–Q3 are protocol-visible only through documentation and one additive export
field; none changes a wire shape. Q4 and Q5 are app/crypto only. Q6 changes
what a person sees after a server restore. Q7 is a new error outcome. Q8 is a
new setting. Q9 is a deletion — or, under option 2, a new call signal kind.
Q10 adds a field to what the anomaly log sends; the wire accepts it additively.

---

# Tier 1 — trust the instruments, stop cross-account loss, stop the node falling over

## B1 — The gate must be able to fail
**C · ~1–1.5 days · no migration, no wire · depends on nothing**

**Closes:**
- AUD-18-1 (P2) — `remote_release_gate.ps1`'s steps test `$?` after a
  scriptblock that ends in `Pop-Location`; client tests, server tests (with a
  real database), API tests and both release builds report success when they
  fail. Measured, not inferred.
- AUD-18-2 — a scheduled or manual CI run is gated on a path filter that
  describes only the tip commit, so it can verify nothing.
- AUD-18-3 — the dependency register's version check silently skips nine rows
  (comma/plus/parenthetical layouts and the deferred table) while the register
  says "any table".
- AUD-18-4 — the lockfile policy claims the governance checker covers controls
  it does not check (committed lockfiles, the SBOM job, the stale Orbit
  sentence).
- AUD-18-5 — the performance-budget document's runnable commands name files
  and a `backend/` directory that do not exist.
- AUD-1b-3 (P2) — the plan's EXPLAIN guardrail for hot queries does not exist.
  It belongs here because it is the same class ("a document claims a check")
  and it is test infrastructure, not product code.

**Why this batch first:** every batch below is accepted on a gate run. The
current gate gives a false green on exactly the steps that matter most (the
release builds), so "the tests pass" is not yet evidence. This is also the
cheapest batch and touches no runtime code, so it can land immediately.

**Structure:** the correct pattern already exists in
[verify.ps1:29-40](file:///J:/Projects/helix/helix_remote/scripts/verify.ps1#L29)
— reset `$global:LASTEXITCODE`, run, check it. The release gate adopts it.
One gate list, three hand-kept copies (`verify.ps1`, `verify.sh`,
`remote_release_gate.ps1`) becomes `tool/gates.dart` with the shells reading
it (proposal in
[18_ci_scripts_docs.md](file:///J:/Projects/helix/orbit/audit/18_ci_scripts_docs.md));
that is the end state, not a prerequisite — the exit-code fix lands on its own.

**Verification:** a harness test that runs a command exiting 7 through the
step helper and asserts the step fails; a dry run of the gate with one test
forced to fail, asserting a non-zero exit; the governance check gains
"register rows parsed == register rows present" and a committed-lockfile
assertion, proven by running it both ways; `query_plans_test.dart` (skipped
without a database) asserting no sequential scan on send, mailbox fetch, ack
and the auth lookup.

**Rollout:** tooling and documents only —
`.github/workflows/ci.yml`, `scripts/remote_release_gate.ps1`,
`tool/check_governance_controls.dart`, `docs/performance/PERFORMANCE_BUDGETS.md`,
`docs/dependencies/*`. Nothing to deploy, nothing to migrate.

## B2 — A stranger's mailbox must not be trimmed by someone else's fan-out
**S, and the W turned out to be nothing (S5) · ~3–4 days · server-only, no migration · depends on Q1, Q2**

**Closes:**
- AUD-4b-1 (P1) — any account can add people to a group and loop add/remove;
  each change stores a `roster_change` in every member device's mailbox, and
  the 10,000-row quota then trims the oldest *undelivered messages*. No prior
  relationship needed (group default privacy lets anyone add).
- AUD-4a-1 (P1) — the same with `block_change`, on every block/unblock flap,
  with no per-account limit.
- AUD-4b-2 (P2) — ephemeral group sends bypass both budgets and fan out to
  every member device.
- AUD-3-1 (P2) — ephemeral/urgent fan-out costs two DB round trips per
  recipient device: the shape that makes the abuse cheap.
- AUD-3-3 (P2) — a presence route outlives its node by up to 75 s, so
  `deliverEphemeral` reports devices as reached that nothing reached (a call
  offer is neither delivered nor parked, and the caller hears a normal ring).
- AUD-3-6, AUD-3-7, AUD-3-8 — a duplicate send re-charges and re-relays; a
  replay loses `blocked_by`; the device-list check runs before block filtering.
- AUD-4b-3, AUD-4b-4, AUD-4b-5, AUD-4b-6 — a refused group send still burns
  the budget; no message-id dedupe; `add_members` bounded only by the body;
  the roster is snapshotted outside the delivery transaction.
- AUD-4a-3 — `setContacts` rewrites up to 5,000 rows per call with no
  per-account limit (the other unthrottled fan-out on this path).

**Why here:** the only findings in the audit where one person can silently
delete another person's undelivered messages, with no relationship and no
trace. AUD-3-1 is the cost shape; AUD-3-3 is the delivery lie in the same
path; the group P3s are the same budget/charge/dedupe code.

**Structure:** batch the fan-out side effects (`EphemeralStore.putAll`,
`Outbox.enqueueMany`, one wake publish per ≤150 refs — proposal S1 in
[03_messaging_realtime.md](file:///J:/Projects/helix/orbit/audit/03_messaging_realtime.md));
a route is online only while its node is alive (S2, same file); server-generated
stored envelopes get one budgeted path with a per-actor rate limit (S1 in
[04a_people.md](file:///J:/Projects/helix/orbit/audit/04a_people.md)). Q2 picks
the stored/advisory split.

**Verification:** in `server/test/modules/people_test.dart`, fill a victim's
mailbox to quota−1, queue one ordinary message, then block/unblock N times and
assert the ordinary message still fetches. The same in
`groups_test.dart` for add/remove. In `messaging_test.dart`, one duplicate send
charges once, a replay keeps `blocked_by`, and a second block inside the window
writes nothing. In `realtime_test.dart`, a route whose node is dead is reported
offline. In `hardening_db_test.dart`, an ephemeral group send draws the budget
chosen in Q1.

**Rollout:** server-only, rate-limit policies are code, no schema. If Q2 =
advisory, the envelope is seq-less: the server change must be preceded by an
engine release that tolerates it (**W**), and the docs must say the notice is
best-effort. If Q2 = bounded stored, no client change at all.
*Settled at S5:* Q2 = advisory, and the **W** half never existed — a seq-less
frame was already tolerated by every client, so the batch stayed server-only.

**Does not cover:** the mailbox quota itself. It stays 10,000 rows per device;
the fix removes the cheap way to fill it, which is the finding.

**Landing log (2026-10-24):**
- S1 `9fc82f7` — AUD-3-1. `EphemeralStore.putAll`, `Outbox.enqueueMany`
  (+ `QueuedJob`), ephemeral parked as `msg:eph:<ref>:<device>`, wake and
  ephemeral publishes chunked at 150 devices. Calls' per-callee loops and the
  urgent path use the batch call. Verified: shared_state, jobs, messaging,
  realtime, calls, groups, two_node, availability.
- S2 `619aab2` — AUD-3-3. `rt:node:<nodeId>` renewed every 5 s with a 20 s
  TTL, and `Presence.isOnline`/`online` require route **and** node; a graceful
  stop deletes its own key after the socket drain; `RealtimeModule
  .stallRefreshers()` is the test hook for a node that died where it stood.
  New `test/platform/presence_test.dart`; the stranded-device case is in
  `two_node_test.dart`; realtime asserts the writer. Docs: realtime +
  messaging MODULE.md, PLATFORM.md, REALTIME_V2.md, V2_OPERABILITY.md. No
  migration, no new env var, no wire change — deployable with the server
  alone.
- Next: S3 (AUD-3-6/7/8), S4 (AUD-4b-3/4/5/6), S5 (AUD-4a-1 + AUD-4b-1/2,
  which is the **W** step and needs the engine/APK first), S6 (AUD-4a-3).
- S3 `07d8603` — AUD-3-6/7/8. Blocks are read before `checkDevices` and
  before the charge (a blocker is not demanded a device list and costs
  nothing); the id is claimed in the ephemeral store
  (`msg:send:<account>:<device>:<id>`, 2 min while running, 24 h carrying the
  answer) before anything is spent, so a racing retry charges and relays
  once; a refused send releases the claim; a replay repeats `blocked_by` for
  24 h (durable beyond that it answers from `sends` with an empty list, as
  before). New client-visible outcome: a truly concurrent duplicate can get
  `rate_limited` with `retry_after` 2 s, which the transport already retries.
  No migration. Docs: messaging MODULE.md steps 2-6, REST_V2.md send row,
  METADATA_INVENTORY.md two new ephemeral-store rows. Verified: messaging
  (+5 cases), people, groups, availability, calls, federation, two_node,
  hardening_db, server_hardening, engine messaging.
- Next: S4 (AUD-4b-3/4/5/6), S5 (AUD-4a-1 + AUD-4b-1/2, which is the **W**
  step and needs the engine/APK first), S6 (AUD-4a-3).
- S4 `c04bc84` — AUD-4b-3/4/5/6. The group's `fan_out` budget is hit **before**
  the sender is charged, so a send a flooded group refuses costs the sender
  nothing to retry (the limiter has no refund, so the order is the fix). A
  stored group send is now idempotent by its own `id`, with no new table:
  `MessagingApi.acceptedAt` answers a retry before the roster is read or
  anything is charged, and `MessagingApi.recordSend` takes the id inside the
  delivery transaction, so a rolled-back send frees it; the retry answers
  `replayed: true`, which the engine's own comment already assumed. The
  delivery transaction takes the group's row lock and re-reads membership,
  the `send_messages` permission and the roster, then filters both the
  distributions and the fan-out, so a member removed while a send is in
  flight neither sends nor receives it (lock order group row → device rows
  is the one every roster change already uses; remote members stay the other
  server's roster to police). `add_members` refuses a list longer than
  `Group.maxMembers` before taking the lock. Residual, accepted: a delivery
  transaction that fails after the charge still costs the sender's tokens,
  and two copies of one id that race to the same row can each charge once
  (the `sends` insert decides who delivers). No migration, no new env var,
  no wire change. Docs: groups + messaging MODULE.md, REST_V2.md group-send
  and add-members rows. Verified: groups (+3 cases; the in-flight-removal one
  fails when the inside-tx filter is reverted), messaging, group_federation,
  availability (+1, ordering proven from `rate_buckets.updated_at` with a
  row-lock gate), hardening_db, two_node, engine groups. The engine's
  two-server case failed once in a four-file run and passed twice alone (its
  `pump` gives the relay 40 s) - a load flake, not this change.
- Next: S5 (AUD-4a-1 + AUD-4b-1/2), S6 (AUD-4a-3).
- S5 `dc43d8f` — AUD-4a-1 + AUD-4b-1/2, ruled **Q1 = keep ephemeral sends
  uncharged to the sender, bound the cost per group** and **Q2 = `block_change`
  becomes an advisory live-only notice, `roster_change` stays stored but is
  coalesced**. It was marked **W** (client work first); it needed none — a frame
  with `seq == null` was already the shape the engine neither acks nor
  re-delivers, proved by `test/e2e/two_node_test.dart`'s engine case "a blocked
  sender reaches nobody, and is told so" passing with the notice live-only.
  `MailboxStore.dropNewest` + `EnvelopeKind.isServerGenerated`: a server signal
  arriving at a device that is already at its quota drops *itself* instead of
  trimming that device's oldest unread mail, counted by
  `helix_mailbox_signal_dropped_total`; real mail over quota still trims as
  before. Blocks tell the target's online devices through `deliverEphemeral`
  after commit and store no row, so a block/unblock flap cannot fill another
  account's mailbox; an away target learns from `blocked_by`. A live group send
  pays `groups.live` (20,000 burst, 2,000/s, keyed by group id) one token per
  device reached, so the fan-out is bounded by the group and the sender still
  pays nothing. `people.block` (60, 2/s) and `groups.mutate` (40, 2/s) are
  per-device pipeline limits on the block routes and the eleven group routes
  that take the group row lock. `roster_change` is coalesced per account and
  kind for `announceWindow` (15 s) under
  `grp:announce:<group>:<account>:<kind>`; a change naming no account and a
  remote sync always fan out, and the changed account is always told.
  Residuals, accepted and documented: the announce marker is written inside the
  open transaction and does not roll back, so a retried change can reach
  bystanders folded into the retry; a device parked at its quota stops hearing
  server signals until it collects; an offline blocked person no longer finds a
  stored notice; a missed roster notice is caught up by fetching the group; the
  marker writes happen while holding the group row lock. No migration, no new
  env var, no wire change, no APK. Docs: messaging/people/groups MODULE.md,
  REST_V2.md block + group-send + roster rows, V2_OPERABILITY.md one metric and
  three policies, METADATA_INVENTORY.md the blocks row and the marker.
  Verified: `dart analyze server tool` clean; people, groups, availability
  43/43 (+7 cases); messaging 16/16 alone; realtime, retention,
  group_federation, hardening_db, architecture, two_node 27/27; engine
  blocked-sender case.
- Next: S6 (AUD-4a-3, the last step of B2), then the B2 full gate and report.
- S6 `8566cca` — AUD-4a-3. `PUT /v1/people/contacts` no longer deletes the
  account's rows and re-inserts the whole list: it reads the stored set inside
  the transaction and writes the difference — `contact = ANY(@gone)` for what
  left, `ON CONFLICT (account_id, contact) DO NOTHING` for what joined — so an
  unchanged phone book issues no write statement at all. The diff is computed
  in Dart, not with the finding's `contact <> ALL(@ids)` sketch, which is
  O(n²) on 5,000 rows. Concurrency keeps delete-all's last-write-wins because
  the read stays in the transaction. `people.contacts` (12 per hour per
  device, a route limit so the pipeline pays it before reading the body; a
  limiter hit cannot go inside a transaction) bounds what is left: a list that
  really changed. Residual, accepted: a client that re-posts the same set in a
  different uuid case rewrites the rows it should have left alone. Two new
  people cases — same list twice moves no row's `xmin` while a changed list
  moves only the rows it moved, and the emptied bucket answers
  `rate_limited`/`retry_after` with another device still at 204; the SQL
  drain is sound here only because 12 an hour refills at 0.0033 tokens a
  second. No migration, no new env var, no client change, no APK: nothing
  calls the route today but the api client and the route-parity table. Docs:
  people MODULE.md, REST_V2.md's contacts row, V2_OPERABILITY.md's policy
  table. Verified: `dart analyze server tool` (the one info left is the other
  agent's uncommitted `platform/push/push.dart`), people 14/14 on Postgres.
- Next: the B2 full gate and batch report, then B3.
- B2's gate, run 2026-10-24 after B3 S1-S5 so both batches stand or fall
  together: the whole `server/` suite on Postgres at `--concurrency=3` — 470
  green, one failure, and that failure ("a send that only reaches people who
  blocked you pays nothing") is already on the timing-flake list and passes
  alone. This includes `test/client/**`, which had shown 46 failures only while
  two server suites overlapped in this worktree (the `.dart_tool` SQLCipher
  extraction cannot be shared); with one run at a time it is green, so those
  were the collision and not B2's work. `dart analyze server tool` clean. The
  Flutter-side gate (app, admin, orbit_ui and the pure-Dart packages) was not
  run for B2: B2 changed no client code, and this worktree currently holds
  another agent's uncommitted `app/`, `admin/` and `packages/` work, so an
  analysis or widget run would report their state, not this batch's.

## B3 — A dead job must not disable a feature; a sweep must finish
**S · ~2–3 days · platform migration 3 · depends on B1**

**Closes:**
- AUD-1b-1 (P1) — a dead outbox job keeps its dedupe key forever; every later
  push (`push:<reason>:<device>`) or group relay (`gdev:…`) with that key is
  silently dropped. A device stops ringing and stops being notified until the
  person opens the app, and the server sees nothing wrong.
- AUD-1b-2 (P2) — a periodic job's lease can expire while it is still running,
  so two copies run at once.
- AUD-3-2 (P2) — a crash between the expiry sweep's DELETE and its pending
  updates inflates `pending`, and later sends trim undelivered envelopes early.
- AUD-3-5 — `messaging.expire` is an unbounded `while` loop with no yield or cap.
- AUD-4a-4 — discovery budget rows are never swept, and the refusal names the
  wrong retry time.
- AUD-2-7 — expired invites and recovery codes have no periodic purge.

**Why here:** the first is permanent, silent, per-device loss with no signal;
the second causes silent message loss. Both are the same table's lifecycle, and
every other sweep in the codebase copies the same `while (purge > 0)` shape.

**Structure:** unique dedupe among `pending` rows only, a dead row addressable
(retry/requeue) and aged out (proposal P1 in
[01b_platform_core.md](file:///J:/Projects/helix/orbit/audit/01b_platform_core.md));
a periodic job declares its timeout and the scheduler proves `lease > timeout`
for every registered job (P2, same file); retention sweeps become
self-rescheduling bounded-batch jobs (S3 in
[03_messaging_realtime.md](file:///J:/Projects/helix/orbit/audit/03_messaging_realtime.md)).
`04c-6` (leaving remote groups depends on a one-shot job) is closed by the same
requeue and is verified in B16.

**Verification:** `server/test/platform/jobs_test.dart` — a job fails to
death, the same key is enqueued again, and a new pending row runs; for every
registered periodic job, lease > timeout (the real list, not a fixture); a
sweep killed between statements leaves `pending` equal to the surviving rows.
`retention_test.dart` — invites, codes and discovery rows are purged;
`messaging_test.dart` — a large expiry backlog drains in bounded batches
without blocking the pool.

**Rollout:** expand → migrate → contract on `platform.jobs`: add the partial
unique index, keep the old constraint for one release, then drop it. New job
kinds are additive. The migration runs at start or via `bin/migrate.dart`; the
owner deploys with `deploy-helix.ps1 -Tag`, and the release note names
"platform migration 3".

**Landing log (2026-10-24):**
- S1 `1a9b1a2` — AUD-1b-1. Platform migration 3 drops `jobs_dedupe_key_key`
  and creates `jobs_dedupe_live`, a partial unique index on `dedupe_key`
  `WHERE dedupe_key IS NOT NULL AND status = 'pending'`; `Outbox.enqueue`'s
  `ON CONFLICT` carries the same predicate, so a key is spent only while its
  job is still pending and a dead row no longer swallows every later
  `push:<reason>:<device>` or `gdev:…` for ever. The dead row itself stays for
  the operator to retry. Done in one step rather than the planned expand →
  contract: this deployment stops the node, migrates and starts it, so there is
  never a window with two binaries, and a kept constraint would be a second
  arbiter nothing reads. A binary from before this commit cannot run against a
  database the migration has touched (its un-predicated `ON CONFLICT` cannot
  infer the partial index), which is the ordering the deploy already enforces.
- S2 `1480512` — AUD-1b-2. `PeriodicJob` takes an optional `timeout` (the
  scheduler's 5 minutes otherwise) and the row lease is that worst case plus
  `leaseMargin` (30 s), so a run that uses its whole timeout is never claimed
  by a second node while it is still going; `server_test.dart` asserts
  `leaseFor > limitFor` for every registered job on the real list, not a
  fixture. Cost, accepted: a node that dies mid-run now blocks that job for its
  worst case rather than the interval — every reader of what these sweeps clean
  filters by time, so a late sweep costs space, not correctness.
- S3 `b5758e2` — AUD-3-2 + AUD-3-5, and an unreported one the repro found.
  `messaging.expire` now purges `sends` and queues `messaging.expire_batch`,
  which drains the mailbox 5,000 rows at a time and re-queues itself only when
  a full batch went; a periodic tick no longer runs an unbounded `while` over
  the pool, and the dedupe key (S1) makes coalesced kicks one batch. The delete
  and the `device_seq.pending` decrement are one statement
  (`WITH picked … gone … by_device … uncounted`), so a crash between them can
  no longer leave `pending` above the rows that survived and make a later send
  trim live mail early. The batch picks by `(device_id, seq)`, not `ctid`: the
  mailbox is hash-partitioned into sixteen tables and `ctid IN (SELECT ctid …)`
  matched the same block and offset in *every* partition, so the old sweep also
  deleted sixteen live, undelivered envelopes belonging to fifteen other
  devices - each the only copy its recipient would ever get.
  Verified: retention_test "an expiry batch deletes exactly the rows it picked"
  and "a backlog drains in bounded batches that queue the rest" (both stop the
  node's own job and periodic loops so only the test drives a batch).
- S4 `dfe6e79` — AUD-4a-4. The discovery budget's day is
  `(now() at time zone 'utc')::date`, not the session time zone's
  `current_date`, and the refusal's `retry_after` is the distance to the next
  UTC midnight plus a second, instead of the constant hour that sent a
  well-behaved client back hourly all day for the same refusal (each attempt
  running the upsert and rolling it back). `people.purge_discovery` (daily)
  keeps today's row and `discoveryHistory` (one more day); only account
  deletion removed a past day before, so the table grew one row per account per
  day for ever. Deploy-facing: the budget now refills at UTC midnight, which on
  a database whose session zone is UTC+6 is six hours later than before.
- S5 `9b0f7b5` — AUD-2-7. The invite and recovery-code deletes moved out of
  `AdminStore.purgeExpired` (reachable only from `POST /v1/admin/purge`) into
  `purgeExpiredCodes`, which `identity.purge_expired` (6 h) runs and
  `purgeExpired` composes, so the button and the job cannot drift apart and
  `PurgeResult` counts what it always counted. A redeemed invite still stays:
  one row per account, the record of who joined. The button remains the only
  way to run its own harsher refresh-token and challenge windows and to clear
  dead jobs.
- Next: B4 (nothing reads without a deadline or a limit). B3's gate: 470 tests
  green on Postgres at `--concurrency=3`, one failure
  (`messaging_test.dart` "a send that only reaches people who blocked you pays
  nothing", the token-bucket drain already listed as a timing flake in
  `AGENTS.md`), and "every wake-up says what became of it" once in a solo run
  straight after that suite; each passed alone on the next run.
  `dart analyze server tool` clean. Owner-facing: **platform migration 3**
  (`jobs_dedupe_live`) means the production node must migrate and restart, no
  new `.env` line, a new job kind `messaging.expire_batch` appears in
  `platform.jobs`, no wire or client change, no APK.

## B4 — Nothing reads without a deadline or a limit
**S + C · ~4–5 days · platform migration 4 · depends on B1**

**Closes:**
- AUD-1a-1 (P1) — a slow client holds the node's body budget forever; one
  unauthenticated attacker can 503 every buffered-body route.
- AUD-1c-1 (P1) — every S3 request is unbounded; a stalled store hangs media
  requests and accumulates readiness probes.
- AUD-1a-2 (P2) — path parameters are percent-decoded twice (latent `/`, `..`).
  Closed in S6 as **not a bug**: the router decodes once and the finding's
  premise about `request.url.path` is false.
- AUD-1a-3 (P2) — concurrent duplicates with one `Idempotency-Key` both run.
- AUD-1a-4 — an idempotent replay loses every response header but content-type.
- AUD-1a-5 — the access log is synchronous disk I/O with no per-day cap.
- AUD-1b-4 — the ephemeral prefix scan cannot use the primary-key index.
- AUD-1c-2 (P2) — `LocalObjectStorage.append` is check-then-write; concurrent
  retries corrupt an upload.
- AUD-1c-3 (P2) — a malformed `HELIX_S3_ENDPOINT` passes config and fails only
  at request time.
- AUD-1c-4, AUD-1c-5 — S3 `read` downloads the whole object; a test double
  ships in the production library.
- AUD-8-1 (P2) — `ContentLimits` covers five fields; every other string and
  list decodes unbounded.
- AUD-6-2 (P2) — federation reads peer responses with no size cap, and fetches
  the peer identity before authentication.
- AUD-6-6 — inbound S2S bodies are rate-limited per request, never per byte.
- AUD-11a-2 — a device POST retried after `internal` can run twice because the
  idempotent result is stored only for status < 500, after the handler
  committed. The fix site is the server's idempotency wrapper.

**Why here:** the two P1s plus every unbounded read on the same edge. Fixing
them separately means four passes over the request pipeline and four test
harnesses.

**Structure:** claim-before-execute idempotency, keeping the response headers
(P2 in [01a_platform_http.md](file:///J:/Projects/helix/orbit/audit/01a_platform_http.md));
one bounded `_send` for all S3 calls (S1 in
[01c_platform_io.md](file:///J:/Projects/helix/orbit/audit/01c_platform_io.md));
one byte budget on the S2S surface (S4 in
[06_calls_federation.md](file:///J:/Projects/helix/orbit/audit/06_calls_federation.md));
deterministic route ordering with a no-shadowing assertion (P1 in 01a, small);
decode limits on the protocol's string and list fields.

**Verification:** `server/test/platform/http_test.dart` — a request declaring a
body sends nothing, waits past the deadline, and the reservation is released
(a second request gets 200, not 503); two concurrent requests with one key run
the handler once; a replay preserves headers including `retry-after`; a path
parameter is decoded once, so a double-encoded `%2F` arrives as `%2F` and never
as a `/`; `infra_test.dart` — a hanging S3 send times out, `ping` is
single-flight, a malformed endpoint stops start-up with the variable named.
`federation_test.dart` — an oversize response is refused and no identity fetch
precedes signature verification. Protocol tests — every string and list field
has a limit.

**Rollout:** platform migration 4 adds `state` and `taken_at` to
`platform.idempotency` (expand-only; the headers ride inside the sealed answer,
so they need no column, and a stale claim is retaken by the next request rather
than by a sweeper job). Config validation turns a bad `HELIX_S3_ENDPOINT` into a
start-up failure: **check the production `.env` before deploying**, because the
node will refuse to start with the value that today silently fails per request.
Wire: none; a replay simply carries more headers.

**Landing log (2026-10-25):**
- S1 (AUD-1a-1) — `BodyBudget` takes `idleGap` (10 s) and `deadline` (30 s) and
  `_readBody` applies both: `Stream.timeout` on the chunk stream, and an elapsed
  check per chunk so a body that dribbles one byte every second cannot dodge the
  idle gap. Either gives up with the new `ErrorCode.requestTimeout` (408),
  added to `isRetryable`; the `TimeoutException` is mapped inside the catch that
  already releases the reservation, so the release stays single-owner and
  `inFlight` returns to zero. The code is additive and safe for old clients by
  the rule already written in `errors.dart` (`fromWire` → `unknown`, unknown
  codes handled by status class); every `switch` over `ErrorCode` in app, admin
  and engine has a catch-all, verified by reading each site. Media upload is
  `streamBody` and never entered this path, so it is still the one read with no
  time bound — S2. Docs: `REST_V2.md` Bodies bullet, `PLATFORM.md` HTTP row.
  Tests: `http_test.dart` "a body that stops arriving is refused and stops
  holding the budget" (a stream that never emits; then a second request gets
  204, not 503) and "a body that dribbles for ever is refused at the overall
  deadline".
- S2 (AUD-1c-1, 1c-2, 1c-3, 1c-4, 1c-5) — one `_send` for every S3 call,
  signed with its own headers so a `Range` is part of the request, bounded by
  `S3ObjectStorage.timeout` (10 s) twice over: headers, then the gap between
  two body chunks (`_signed` drains, `_streamed` passes through). The client
  now has a 5 s `connectionTimeout`, so a blackholed endpoint fails in seconds
  instead of the operating system's minutes. `ping` answers from one shared
  probe (single-flight, result cached 5 s), which is what stops a dead store
  from growing a socket per readiness request; `Future.timeout` in
  `HealthRegistry` never cancelled the HTTP call, so this is the bound that
  matters. `read` asks for its range and stops at the window instead of
  downloading the object and slicing it, and 404 / 416 are `ObjectMissing` /
  `ObjectShort` on both backends (the local one honours the same contract now,
  which is why the assertions are in both groups). `LocalObjectStorage.append`
  serializes per key in-process — the local backend is single-node by
  construction — and returns the file's own length, never its writer's
  counter, so a retry that overtakes the request it retried gets
  `OffsetMismatch` and the route cannot seal two interleaved uploads as one
  complete object. `HELIX_S3_ENDPOINT` is validated in config (scheme http(s),
  a host, no userinfo, query or fragment) and `?? Uri()` is gone.
  `RecordingPushProvider` moved to `test/support/recording_push.dart`;
  `NoPushProvider` and the FCM provider stay in platform, and
  `RecordingSmsProvider` stays where it is because `identity/config.dart`
  selects it in dev mode.
  Tests: `infra_test.dart` "a store that never answers fails instead of
  hanging the caller", "a body that stops arriving abandons the request",
  "a dead store is probed once, not once per readiness request", "a live store
  answers one shared probe", "a range read asks the store for the range and
  stops at its end", "a store that will not answer a range says so", "a missing
  object and an unsatisfiable range are typed errors", "two writers at one
  offset: one appends, the other is told to resume", "a malformed S3 endpoint
  is named at start-up, not at request time".
  **Owner-facing:** the validation makes a malformed endpoint a start-up
  failure — check the production `.env` before deploying. Helix Global uses
  `HELIX_BLOB_STORE=local`, so today's node is not affected.
- S3 (AUD-1a-3, AUD-1a-4, AUD-11a-2) — `IdempotencyStore` is
  `claim`/`record`/`release` instead of `find`/`save`, and `_idempotent` claims
  the key before the handler runs: one `INSERT … ON CONFLICT DO UPDATE …
  RETURNING` takes the key or says why not, and the answer only ever comes from
  the holder (`record` updates a `pending` row carrying that request's hash).
  A duplicate that overlaps the first gets `unavailable` (503, retryable,
  `Retry-After: 2`) and the transport waits it out and then replays; a
  concurrent different-body key still gets `idempotency_conflict`; a handler
  that throws or answers 5xx gives the claim back, because a failed request
  committed nothing and its retry must be free to act. `state` says claim or
  answer, `taken_at` is the lease (15 min, `idempotencyClaimLease`): a node that
  dies with a claim cannot burn the key past it, and the same statement takes
  over an answer past the 24-hour retention, which is what `find` already
  treated as gone — so no new sweeper. AUD-11a-2 closes with the claim: the
  answer is written after the commit and a failed write leaves the key claimed,
  so a retry waits or replays instead of running the mutation a second time.
  AUD-1a-4: the headers are stored with the body inside the envelope (new `e2:`
  format, one seal over both, the AAD unchanged), an `e1:` row from before the
  deploy still opens so an in-flight request replays rather than repeats, and a
  replay that cannot be opened is re-claimed by its exact contents rather than
  answered twice. A 204 replay no longer grows a `content-type`.
  Tests: `http_test.dart` — "two requests with one key at the same time: one
  runs, one is told to wait", "a retry whose answer could not be written does
  not run the handler again", "a request that failed gives the key back, so its
  retry runs", "a replay keeps every header the first answer carried", "a replay
  of a 204 stays a 204 with no content type"; `hardening_test.dart` — the `e2`
  envelope opens with its headers and the `e1` row of the previous release still
  opens; `hardening_db_test.dart` — the claim states against Postgres, the lease
  takeover, and a row this build cannot open being claimed not replayed. The
  lease is passed in **milliseconds**: the first draft used `inSeconds`, and a
  60 ms test lease became 0 seconds, so every duplicate stole its own claim —
  the test caught it before the docs did.
  **Owner-facing:** platform migration 4 (`idempotency_claim`) runs at start-up
  or with `bin/migrate.dart`; it is expand-only and safe to deploy in any order
  (an old node reads a `pending` row as "no answer yet" and re-runs, exactly as
  today). No `.env` line, no wire change: a replay carries more headers and a
  concurrent duplicate is the only new answer, and it is a retryable one the
  client already handles.
- S4 (AUD-6-2, AUD-6-6) — federation now reads a peer *to a limit*.
  `_readBounded` replaces `http.Response.fromStream` on both outbound paths and
  stops at 64 KiB for an identity document and 8 MiB for an API answer
  (`PeerDirectory.identityDocumentMaxBytes`, `FederationClient.answerMaxBytes`),
  applying the cap **as the body arrives** rather than to the declared
  `content-length`, so a lying header buys an attacker nothing; the config
  timeout (5 s) bounds the whole read *and* the gap between two chunks, the two
  bounds S1 put on the device-facing body reader. Every throw happens inside the
  loop, which cancels the subscription, so no abandoned read keeps running.
  The ordering the finding names cannot be reversed — a signature cannot be
  checked before an unknown domain's key has been fetched — so the *cost* of a
  forged header is what got bounded: one lookup per domain, shared including
  its cache write (the join is checked **before** reading the cache; reading
  first is what let a second request miss the row the first was still writing
  and fetch again), and at most 16 domains at a time, past which a caller gets
  `PeerUnavailable` - a relay requeues, a peer retries. AUD-6-6:
  `federation.bytes` (64 MiB a minute per server, the token bucket's `cost` in
  bytes) is charged by `_charged`, which wraps each of the five body-carrying
  S2S routes and runs *before* `q.json`, so an accepted peer's parsing volume -
  not only its request count - is bounded; only verified bodies are charged, so
  a stranger cannot spend a peer's budget, and a peer past it gets
  `rate_limited` with `Retry-After` and its batch is not applied.
  Tests: `federation_test.dart` — "an identity document over the cap is refused,
  not buffered", "a peer answer too big or too slow to read is refused", "one
  domain is fetched once while twenty callers wait for it", "forged headers do
  not cost one peer lookup per request", "a peer that spent its byte budget is
  refused before parsing" (3 MiB body, budget drained, 429, mailbox empty); the
  group's fake peer now counts identity hits and can hold a document open.
  **Residual, deliberate:** the answer test asserts `PeerUnavailable` for either
  bound because an 8 MiB loopback read measures ~3.8 s here and would race the
  5 s timeout on a busy machine - the 5 s bound is the one `fromStream` already
  had, so no legitimate answer that used to arrive now fails, but a real peer
  that needs longer than that is a tuning question for the operator, not a
  behaviour this step changed. No migration, no `.env` line, no wire change:
  `rate_limited` and `PeerUnavailable` are both answers peers already handle.
- S5 (AUD-8-1) — the limit is in the reader, not in the field. `_limited` was
  called by five fields, so the other ~350 strings, byte arrays and lists took
  whatever the sender chose. `JsonReader.string/optString/nonEmpty` now take
  `maxLength`, `bytes/optBytes` take `maxLength` **on the decoded value** (the
  base64url text is refused at its 4/3 size before anything is allocated),
  `bytesOf`/`optBytesOf` fix a length exactly, and `objects/optObjects/
  strings/optStrings` take `maxItems`, checked before the first item decodes.
  Each defaults to a backstop (`maxWireStringLength` 64 KiB, `maxWireBytes`
  1 MiB, `maxWireListItems` 20 000), so forgetting a limit is no longer
  possible; a call site names the real number where the contract knows it.
  `ContentLimits` gained the counts the finding asked for (`maxMentions` 1024
  = the largest group, `maxContactEntries` 4096, `maxSystemFields` 32,
  `maxContactNumbers` 32, `maxDevices` 256) plus sizes for the strings a peer
  writes about something (`maxNameLength`, `maxUrlLength`, `maxNumberLength`,
  `maxIdLength` 512/4096/32/512) and `keyBytes` 32, and every content body now
  uses them: a 60 KiB poll question, a 5000-strong mention list, a contact name
  of any length and a `option_ids` list of ten thousand ids are all decode
  failures, as is a chain / group / profile key or a message `profile_key`
  that is not 32 bytes — previously a crypto failure later. `ReceiptBody` and
  `ResendRequestBody` carry the same 500 the engine already enforced for
  resends; `HistoryBackup.data` names its own 16 MiB (it is the one field above
  the backstop, and the only deliberate exception). `_pollVote` also stores a
  voter's choice **deduplicated**, so repeating an option cannot grow that
  voter's row on every member's device — the sharp half of the finding.
  Tests: `json_and_ids_test.dart` "every read is bounded, by default or by the
  call site" (each accessor at limit, limit+1 and under a smaller named one,
  and no item of a refused list decoded); `content_test.dart` replaces "limits
  are enforced on decode" with 34 refusals — one per field the
  finding names — plus "a body at exactly its limit decodes" (the caps are not
  off by one) and "a message profile key of the wrong length is refused";
  `inbound_test.dart` "poll votes and RSVPs update the poll message" now votes
  `['a','b','a','b']` and asserts the row stores `["a","b"]`. Nothing in
  `app/`, `admin/` or the engine produces a value over these limits (checked
  by reading every producer: there is no poll or event composer in the app
  yet, `people_service` syncs one entry per message, `newSymmetricKey` is
  32 bytes), and protocol 120, engine 313, api 205, db 140, cli 13, orbit_ui
  230 and app 1022 tests pass on the tightened decode.
  Docs: `MODULE.md` rules (a new field inherits the backstop; a new *large*
  field must name its limit) and `CONTENT_V2.md` §1 "Bounds".
  **Residual, deliberate:** transport DTOs ride the backstop instead of a named
  number (a roster change is capped at 20 000 accounts, not at
  `Group.maxMembers`), `SystemBody` caps the field *count* while a value stays
  arbitrary JSON inside the 256 KiB payload, and `UnknownBody.raw` keeps the
  body map it was handed — all three are bounded by the payload cap, which is
  the point of it. No migration, no `.env` line, no wire change: every limit is
  receive-side, an over-limit body already means "quarantine this envelope" on
  the engine path and `invalid_field` on the server path.
- S4 follow-up — the S5 server gate gave S4's own single-flight test three
  identity fetches instead of one. `resolve` checked `_lookups`, then awaited
  the cache read, and registered only after more awaits, so every caller could
  pass the "is one running?" gate before the first reached it; and a caller
  whose cache read was slower than the 300 ms fetch it should have joined woke
  to a `_lookups` the winner had already removed and a `cached` it had read as
  null, so it fetched again. The lookup shared by `_lookups` is now the whole
  operation - cache read, fetch, save - joined synchronously with no await
  before the map is read and written. The refresh rate limit and the one-minute
  down marker moved inside it (one decision per domain per burst, same values);
  `checkAllowed` still runs per caller, so a refused address never joins.
  Federation's 21 tests pass alone with the assertions unchanged
  (`identityHits == 1`, forged headers "under four"); the four load flakes of
  that gate each passed alone and are noted in AGENTS.md. No migration, no
  `.env` line, no wire change.
- S6 (AUD-1a-5, AUD-1b-4, the route-ordering item in 01a; AUD-1a-2 closed) —
  `FileSink` gets off the request thread: lines pile into a buffer and one
  chained asynchronous flush (`flushInterval` 200 ms, sooner once
  `flushBeforeBytes` 64 KiB have gathered) puts them on the disk, so a flood or
  a reconnect storm costs writes as fast as the disk can take them instead of
  one blocking write per request line. Only whole lines are buffered and a
  rotation always falls between two batches, so no rotation can split a line;
  each batch is stamped with the day its *own* lines were written, so a flush
  that runs after midnight files yesterday's lines under yesterday; at most
  `maxQueuedBatches` 32 batches wait, so a disk slower than the requests costs
  log lines and not unbounded memory (stdout still carries every one).
  `HELIX_LOG_MAX_BYTES_PER_DAY` (default 256 MiB; `0` = no size bound, only the
  daily one) is the new per-day cap: a day that reaches it rotates to the next
  numbered file of the same day, and at each rotation that day's oldest file is
  deleted until the day is back inside the bound. Retention by day alone bounds
  nothing for a day that never ends, which is what 5k requests a second of
  access lines (~86 MB an hour) actually looks like.
  AUD-1b-4: platform migration 5 adds `ephemeral_key_pattern` on
  `key text_pattern_ops`, so the ephemeral store's `LIKE 'ws:12:%'` prefix scan
  reaches its rows through an index under this database's non-C collation. It
  joins the `EXPLAIN` guard in `query_plans_test.dart`, seeded with 20 000
  ephemeral keys and `ANALYZED` — a plan read against unanalyzed rows is not
  the plan production picks, and the first draft of this case failed exactly
  that way.
  Route ordering: `build()` sorts by specificity, then by the template (a
  literal sooner in the path wins, then the literal text, then the longer
  path), with `HEAD` placed before its `GET`, so two routes scoring the same no
  longer answer in whichever order they happened to be added.
  `RouteRegistry.ambiguousPairs` groups the catalog by method with parameter
  *names* erased, and `build()` refuses to start with a `StateError` if two
  routes land in one group: the current catalog has none, and the tests pin
  both halves (the same pair registered in either order answers the same, and
  `{one}` over `{other}` on the same literal shape is reported).
  AUD-1a-2 was worth the check and is **not a bug**: it read
  `router.dart:182` (`route.match('/${request.url.path}')`) as matching a path
  `Uri` had already decoded, but Dart hands the segment over still
  percent-encoded, so the registry's `Uri.decodeComponent` is the *one* decode
  that exists. Measured rather than argued — with the decode dropped, a name
  sent as `Helix%20Name` reached the handler as `Helix%20Name` and `%252F` as
  `%252F`, which is the regression the finding would have caused. What the code
  does today is right and is now a test (`Helix%20Name` → `Helix Name`,
  `%252F` → `%2F` and never `/`, `foo%25` → `foo%` so a name holding a literal
  `%` stays addressable, and shelf itself refuses a truncated escape before the
  router ever runs). The sentence the finding leaned on was ours, not the
  dependency's: `request.dart`'s "already percent-decoded" now reads "decoded
  once, in the router".
  Tests: `operations_test.dart` "a line is buffered, not written on the request
  thread" and "a day past its byte bound rotates early and stays bounded"
  (~800 KiB against a 256 KiB cap: the day holds at most two caps and one
  batch, the tail survives, the head went first, and a numbered second file of
  the same day proves it rotated *within* the day); `http_test.dart` "a path
  parameter is decoded once, not twice", "routes of equal specificity are
  ordered by their template", "no two catalog routes can answer the same
  request"; `query_plans_test.dart` "a prefix scan of the ephemeral store uses
  the pattern index".
  **Residual, deliberate:** the per-day bound is a soft one — it is checked per
  batch, so a day can end up one flush-buffer over it, and a cap smaller than
  that buffer rotates every batch rather than every line (`_rollFor` refuses to
  rename a file that holds nothing yet). `logRotate`-style external rotation is
  still not supported on Windows, which is why the sink rotates itself.
  **Owner-facing:** platform migration 5 (`ephemeral_key_pattern`) runs at
  start-up or with `bin/migrate.dart`; it creates one index and touches no
  data, so any deploy order is safe — and migration 4 (S3) is still owed with
  it. `HELIX_LOG_MAX_BYTES_PER_DAY` is new and optional: the default needs no
  `.env` line, so production changes only if the operator wants a smaller day.
  No wire change.
- Next: B5 waits on Q6, so B6. B4's steps: S1 `88fdae1`, S2 `fb0a1c1`,
  S3 `2c8e1eb`, S4 `408a556` (plus `a47cd52`, the single-flight hole its own
  gate found), S5 `793440f`, S6 `07c3668`. B4's gate: **501 tests green** on
  Postgres at `--concurrency=3`, with the two `messaging_test.dart` timing
  flakes already listed in `AGENTS.md` (both green, with the platform trio, on
  the solo re-run straight after), and `dart analyze server tool` clean; the
  S5 gate ran the clients too (protocol 120, engine 313, api 205, db 140,
  cli 13, orbit_ui 230, app 1022) against the tightened decode.
  One finding closed as not a bug (AUD-1a-2) and one deliberately left as a
  cost bound rather than an ordering fix (AUD-6-2: a signature cannot be
  checked before the peer's key is known).
  **Owner-facing, whole batch:** production owes **platform migrations 3, 4 and
  5** at the next start (`bin/migrate.dart` or the node's own migration), and a
  malformed `HELIX_S3_ENDPOINT` now fails start-up instead of failing per
  request — Helix Global runs `HELIX_BLOB_STORE=local`, so it is not affected.
  One optional new env line, `HELIX_LOG_MAX_BYTES_PER_DAY`. No wire change
  anywhere in the batch, so no APK is needed for any of it.

## B5 — A stranded account must be repairable without deleting history
**A · ~4–5 days · no migration, no wire · depends on Q6**

**Closes:**
- AUD-12a-1 (P1) — when a session ends (refresh and device-key sign-in both
  refused), the account row stays and every sign-in path refuses; the app shows
  "Could not sign in", and the only exit deletes local history. A server
  restore from backup becomes a fleet-wide lockout.
- AUD-12a-2 (P2) — a 429/5xx during device-key re-authentication is treated as
  "this device is gone" and a still-valid session is forgotten.
- AUD-12a-3 (P2) — maintenance passes can overlap; two replenishments save
  different private keys under ids the server already holds.
- AUD-12a-4, AUD-12a-5, AUD-12a-6 — a stop during a start leaves workers
  running; `signOut()` can throw before the wipe and leave `running`; `start()`
  ignores status and made the backup timer unreachable.
- AUD-12g-1 (P2) — identity and session are two commits; a crash between them
  leaves a "running" engine with no session and no repair path.
- AUD-12g-2 (P2) — every new-device flow keeps its generated keys in memory
  until the server call returns; a lost response strands the account.
- AUD-12g-3, AUD-12g-4 — a link proposal is spent by a failed attempt; a
  device-list op reports failure when only its refresh failed.
- AUD-12h-1 (P2) — a password sign-in with no restored profile key mints a
  second key, cannot read its own photo, and the next name-only save drops the
  photo for everyone.
- AUD-12h-2 — clearing a nickname cannot undo the phone-book rename.
- AUD-12b-2 — sign-out and close can hang ~30 s offline behind an inbound retry.
- AUD-14a-1 (P2, appended) — a setting stream resolves the runtime once, so a
  provider first read on the sign-in page (the app does it at start for the
  media policy) stays in `NoServerChosen` for the whole run, and one read
  before an account switch keeps following the closed old database while
  writes land on the new account.
- AUD-14a-2 (P2, appended) — an account list that is empty *or undecodable* is
  read as "no accounts", and `_deleteUnlisted` then deletes every folder under
  `accounts/` with its database, WAL files and key: a silent, unrecoverable
  local-history loss for every secondary account on a lost or corrupt keystore
  entry.
- AUD-14a-3 (P3, appended) — `HelixRuntime.close` skips `api.close`/`db.close`
  when `engine.close` throws, yet releases the lease anyway, so the next
  runtime may open the same database beside the one that failed to close.
- AUD-14b-1 (P3, appended) — the network reading treats a VPN (and the
  plugin's `other` bucket) as Wi-Fi, so with a VPN on mobile data the
  "Wi-Fi only" media policy downloads up to 50 MiB per video and the backup
  upload gate sends backups over the metered connection.
- AUD-14d-2 (P3, appended) — a rename through Helix writes a fresh
  `Name(first:)` into the phone's contact, so its middle, family and prefix
  are cleared and the whole display name lands in the given-name field; the
  person's own address book is damaged by a feature that only meant to add a
  name.

**Why here:** the P1 is the only way the audit found to lose a person's entire
local history through no fault of their own, and it is triggered by an operator
action the status doc recommends (restore from backup). Everything else is the
same state machine or the same key-before-commit ordering — including the app
half of the same lifetime: which runtime a surviving reference points at
(14a-1), what the app does when the list of databases it should keep cannot be
read (14a-2, the same "history gone without anyone asking"), and a teardown
that gives up halfway while giving the database away (14a-3).

**Structure:** one serialized lifecycle object (S1 in
[12a_engine_core.md](file:///J:/Projects/helix/orbit/audit/12a_engine_core.md));
one session-state owner shared by transport and engine (S2); one enrollment
flow for the four new-device paths (S1 in
[12g_engine_account.md](file:///J:/Projects/helix/orbit/audit/12g_engine_account.md));
the auth layer repairs a missing session, not only a refused one (S2); one owner
for the profile key (S1 in
[12h_engine_people.md](file:///J:/Projects/helix/orbit/audit/12h_engine_people.md));
one naming policy including write-back (S2), whose app half is S14d-1 in
[14d_core_media_io.md](file:///J:/Projects/helix/orbit/audit/14d_core_media_io.md)
(the adapter preserves the parts of the name it did not mean to change). The app half adds S14-1 (a setting
belongs to the live runtime), S14-2 (restore answers read/absent/unreadable and
deletes only folders it knows are abandoned) and S14-3 (one step-wise teardown
contract, awaited by whoever replaces the runtime), all in
[14a_core_engine.md](file:///J:/Projects/helix/orbit/audit/14a_core_engine.md).

**Verification:** `packages/helix_remote_engine/test/account_test.dart` — the
session-ended state accepts a sign-in for the same server account and the
device is re-enrolled with chats and messages intact; a failed model commit
between identity and session leaves a state `start()` can repair; a 429 during
re-auth keeps the session. `keys_test.dart` — two overlapping replenishments
persist one prekey per id. `two_engines_test.dart` — after a password sign-in,
the profile key is the account's, not a new one. `recovery_test.dart` — a
refused register/recovery keeps the generated keys locally for a retry. If Q6 =
option (b), the app's new page gets a widget test. In the app:
`test/account_slots_test.dart` starts with the keystore entry missing and then
with it corrupt, and the second account's folder and key survive; a provider
test opens one runtime, reads a setting, swaps in a second runtime and sees the
stream follow it (and `set` write where the stream reads); a fake whose
`engine.close` throws still leaves the API and the database closed and the lease
held until then. The address book's write-back gets a fake-contact test: a
contact saved with a prefix, middle and family name is renamed and keeps them
(14d-2).

**Rollout:** app/engine only. Local schema unchanged (the status is a text
column). The server cannot force the update: a server restore still strands
builds older than this release, so the operations doc gains one line — "after a
restore, affected people must update the app once". No wire change.

---

# Tier 2 — stop silent loss inside a conversation

## B6 — An action that cannot be applied must say so
**A · ~5–6 days · no migration, no wire**

**Closes:**
- AUD-12b-1 (P2) — one `version_conflict` or `noGroupKey` race silently kills
  the post-removal key rotation; group renames and avatars then fail for
  everyone, the removed member keeps the old epoch key, and no retry surface
  exists because a rekey op has no message row.
- AUD-12c-1 (P2) — every arriving message queues two `delivered` receipts
  (double sends, double ratchet steps, double receipt rows).
- AUD-12d-1 (P2) — lock-order inversion: a peer-key update waits for a device
  lock inside a transaction while senders hold the lock and wait for the
  transaction. An engine can hang forever on a key change that overlaps a send.
- AUD-12e-1 (P2) — a group create whose response is lost forgets the only copy
  of the master key; the group is nameless for every member, cannot be renamed
  or re-keyed, and a retry creates a duplicate.
- AUD-12e-2 (P2) — group trust is read-modify-write JSON with no CAS; a person's
  confirm racing a roster apply releases an unconfirmed member with the sender
  key and group key.
- AUD-12f-1 (P2) — a delete, edit, reaction, poll vote or RSVP that fails to
  decrypt is dropped silently, because quarantine repairs only `urgent`
  envelopes; "delete for everyone" then silently fails on that device.
- AUD-12i-1 (P2) — a terminal send failure drops an edit/reaction/delete with
  no error, no retry, and no way to express a delete again.
- AUD-12c-2, AUD-12e-3, AUD-12f-2, AUD-12f-3, AUD-12i-2 — the edit/delete
  window measured against a sender-chosen timestamp; a lost add/approve response
  leaving the new member without the key; a stored `typing` envelope replayed on
  every reconnect; the wrong first key winning; "delete for me" on a pending
  message not cancelling it.

**Why here:** every item is silent, and three are irreversible (a removed
member keeps a key; an edit is lost; a group can never be re-keyed). They share
the ops/outbox path, so one retry policy and one test harness cover them.

**Structure:** an explicit retry policy per op kind (S1 in
[12b_engine_send.md](file:///J:/Projects/helix/orbit/audit/12b_engine_send.md));
"lock outside, transaction inside" as a checked rule (S1 in
[12d_engine_crypto.md](file:///J:/Projects/helix/orbit/audit/12d_engine_crypto.md));
one writer for per-group state and one post-mutation reconcile (S1/S2 in
[12e_engine_groups.md](file:///J:/Projects/helix/orbit/audit/12e_engine_groups.md));
one quarantine policy keyed by content kind (S1 in
[12f_engine_group_crypto.md](file:///J:/Projects/helix/orbit/audit/12f_engine_group_crypto.md))
and one arbiter for the master key (S2); action ops carry their target and
surface failure (S1/S2 in
[12i_engine_chats.md](file:///J:/Projects/helix/orbit/audit/12i_engine_chats.md)).

**Verification:** `outbox_test.dart` — a rekey that gets `version_conflict`
retries, and a permanent failure is visible and repeatable from the UI model.
`inbound_test.dart` — a `DeleteBody` that cannot decrypt leaves a placeholder
and sends a reset request; a stored `typing` is processed once. Engine
`groups/` tests — a lost create response keeps the key (persist before the
call); a confirm racing an apply never releases an unconfirmed member; a lost
add/approve response still yields the key. A lock-order test with a fake that
blocks in `_applyKeyChange` while a send is in flight (it deadlocks today).

**Rollout:** app/engine only. No schema change; the retry policy uses the
outbox's existing columns. The reset request uses an existing frame. Users must
update to be protected.

**Landing log (2026-10-25):**
- S1 (AUD-12c-1) — the second `_delivered` call is gone; the one that stays is
  the earlier call (messaging/apply.dart), not the one the finding sketched,
  because a call log that already rang on this device returns early and still
  owes its author a delivered receipt. Deleting the first call would have
  dropped that case, which is a trust-adjacent behaviour change, so the fix
  removes the duplicate below the call-log branch instead. Nothing else in the
  path deduped it: `_delivered` mints a fresh content id per call
  (`_ctx.ids.next()`), and that id is the outbox idempotency key.
  Test: `inbound_test.dart` "an arriving message is acknowledged once" counts
  what one exchange actually costs — the sends Bob's device made and the
  envelopes waiting for Alice (1 and 1; with the duplicate put back by hand, 2
  and 2, so the guardrail bites). Gate: engine suite **314 green**,
  `dart analyze lib test` clean. No schema, no wire change, so no APK is
  needed for this step on its own; the batch's rollout note still says users
  must update to be protected.
- S2 (AUD-12f-1) — not implemented as the finding sketched it. The sketch was
  "one quarantine policy keyed by content kind", but the receiver cannot see
  the content kind: reading the body is exactly what failed, so the wire offers
  no classifier. What is implementable is the split the finding was really
  after: `urgent` is a push hint and stays the rule for *showing* a
  placeholder, and it stops being the rule for *asking for repair*. New
  `messaging/quarantine_policy.dart` holds both decisions in one place
  (`showsPlaceholder` = `urgent` and stored; `asksForRepair` = the crypto
  layer's own curable flag and stored), and `messaging/inbound.dart` and
  `groups/group_inbound.dart` both call it, so the two pipelines cannot drift
  again. Repairing a quiet envelope is cheap and bounded: the reset op's
  idempotency key is `reset:<device>:<envelope id>`, `hasFreshUnansweredSession`
  limits a session start to one per `resetCooldown` per device, and the sender
  only re-sends rows it holds and authorises the requester. A delete that one
  device cannot read now at least starts a fresh session there instead of
  vanishing.
  Tests: `inbound_test.dart` "a quiet action asks for repair but leaves no row"
  (a non-urgent `DeleteBody` with Bob's session gone → no `undecryptable` row,
  exactly one send out of Bob's device, and the next message still arrives) and
  `groups_test.dart` "a quiet group action is repaired, and leaves no row" (the
  same with a lost sender key in a trio). With `urgent` put back on
  `asksForRepair` both fail on the send count (0), so they bite.
  Gate: engine suite **316 green**, `dart analyze lib test` clean. Docs that
  claimed a non-urgent envelope gets "no repair request: there is nothing the
  sender could re-send" corrected: CRYPTO_V2.md §13a engine policy and the
  engine MODULE.md quarantine rules (direct and group).
  Follow-up this step deliberately left open: the sender still cannot answer
  for an action — `_resend` looks the target up with `messagesDao.find(id,
  sender: self)` and actions are not stored as rows, so a quiet edit, delete,
  reaction or vote now gets a new session but no re-send. That is AUD-12i-1,
  and it is the same missing piece the finding names there.
- S3 (AUD-12b-1) — two halves, because the retry alone does not save a duty op.
  **Classification:** `classifyOpError` read the error *class* only, so every
  `GroupException` was a give-up — including `versionConflict` and `noGroupKey`
  — and the server's `version_conflict` reached the same branch once
  `GroupKeyDistributor.rekey()` had spent its own `GroupLimits.stateRetries`
  loop (it rethrows the raw `ApiException`). One lost race therefore marked the
  post-removal rotation dead for good: the removed member kept the epoch key and
  `_updateState` then fails with `noGroupKey` for *every* member, so the group
  could never be renamed again — silently, and with nothing to retry, because a
  rekey op has no message row for a "retry" button to sit on. Now the reason
  decides: `notAMember`, `notAllowed`, `badLink` and `badMention` (facts no
  retry changes) give up; `noGroupKey` and `versionConflict`, and the API's
  `version_conflict`, retry; and `NoSessionException`, which the
  `CryptoV2Exception` case was swallowing into `crypto`, retries, since the
  session is one bundle fetch away.
  **Re-derivation:** a duty that gives up still has no UI, so housekeeping reads
  it back from the state. `OutboxService.enqueueRekey(groupId, epoch)` is now the
  only way a rekey enters the queue (the roster envelope, `GroupsService.rotateKey`
  and `_afterRemoval` all call it) and keys it `rekey:<group>:<epoch>`, so a
  double ask is one op and a failed one is put back.
  `GroupKeyDistributor.reconcileRekeyDuties()`, run by `MaintenanceService`
  (which now takes a *list* of extra passes; `engine.dart` adds the reconciler
  beside the backup schedule), asks only where the rotation demonstrably has not
  landed — the same "the stored blob opens under this device's key for the
  current epoch" test `rekey()` uses to decide the duty is done — and only of the
  account that owes it (`isFirstAdmin`, moved out of `GroupInbound` so the two
  paths cannot drift). The finding's own signal ("re-enqueue when the group's
  epoch has no held key") is not usable: `rekey()` stores the epoch key *before*
  it writes the state, so a rotation that crashed halfway has a key and a blob
  that does not open — which is exactly why the check reads the sealed state.
  Bounded by `GroupLimits.rekeyDutyRetries` re-asks, then
  the row stays failed for an admin to trigger: a pass that re-asked a hopeless
  duty every five minutes forever would be its own unbounded cost. An explicit
  ask (a roster change, `rotateKey`) is never bounded.
  Tests: `groups_test.dart` "a rotation the state keeps moving under is retried,
  not dropped", "a rotation that gave up is asked for again by housekeeping" and
  "a rotation that keeps failing is asked for a bounded number of times". Each
  bites: without the `version_conflict` retry the first leaves the op failed;
  without the reconciler in `extraWork` the second never re-asks; without the
  bound the third re-asks past it.
  Note for the next test in this area: `FakeServer.callsTo(route)` compares the
  recorded `PUT /v1/groups/<id>/state` against the route's *template* path, so it
  is always 0 for a parameterised route — a count-through-the-server assertion
  there passes vacuously. The bound test counts the op row's `attempts` instead.
  Gate: engine suite **319 green**, `dart analyze lib test` clean, and
  `server/test/client/engine/groups_test.dart` green against Postgres. No schema
  and no wire change (the policy rides the outbox's existing columns), so no APK
  is needed for this step. Docs: engine MODULE.md gains the classification rules
  and the duty re-derivation, and the "Known limits" line about a lost rotation.
  Left open: a `session_reset` duty op that gives up is still not re-derived —
  narrower than it looks, since the next undecryptable envelope from that sender
  asks again — and the sender still cannot answer for an action (AUD-12i-1).
- S4 (AUD-12e-1) — `GroupsService.create` wrapped the POST in `on Object`, which
  treats a refusal and a silence alike and forgets the group key for both. A
  silence is not an answer: the server may have committed the group this device
  named, and this device held the only copy of its first key — the members had
  not been sent it and no other device can seal the state — so the group
  existed, nameless, unrenameable and unrecoverable, and the user's retry made a
  second one. `GroupsService._postCreate` splits them: an `ApiException` still
  forgets the key (no group, no use for it); anything else reads the group back
  by the id chosen and, if the server has it, the call finishes as though the
  answer had arrived — the roster is applied and the follow-up key share runs,
  which is the half that left the members staring at an empty title. Only the
  server's `not_found` justifies the forget; if the read-back itself fails the
  key stays where a group that exists can still use it, and the caller gets the
  create's own error and trace (`Error.throwWithStackTrace`).
  Two parts of the sketch deliberately not done. "Treat a retry that meets
  `alreadyExists` the same way": the id is minted inside `create`, so an engine
  retry never reuses it and the duplicate the finding describes comes from the
  *user* retrying the button — which the read-back removes by making the first
  call succeed. "Give `rekey` an explicit empty-state path (mint a key when the
  blob will not open and the title is empty)": refused, because those three
  facts also describe a device that simply never received the key (AUD-12e-3),
  and minting there seals an *empty* state over a name other members can still
  read — a data-destroying move made on a local guess. Recovering a genuinely
  lost key needs the opposite direction (ask a member for the epoch key), which
  is a new pairwise message and so not a "no wire change" step. MODULE.md's
  "Known limits" records the one window this fix cannot close: a request still
  in flight when the read-back answers `not_found` forgets a key that the
  committed group then needs.
  Tests: `groups_test.dart` "a create whose answer is lost still returns the
  group, and the key reaches the members" (the fake commits and the answer is
  lost: no throw, the owner reads the name, exactly one group on the server, and
  Bob receives the key) and "a create that never reached the server reports the
  failure and keeps nothing" (nothing was committed: the call rethrows the
  network failure, no local rows, and the setting that held the key is gone).
  Both bite — the old blanket catch makes the first throw and the second never
  ask, and dropping only the forget leaves the key of a group that does not
  exist. The second compares that setting as a boolean, because
  `expect(value, isNull)` prints the value on failure and the value is a group
  master key.
  Gate: engine suite **321 green**, `dart analyze lib test` clean, and
  `server/test/client/engine/groups_test.dart` green against Postgres. No schema
  and no wire change (the read-back is the existing `GET /v1/groups/{id}`), so no
  APK is needed for this step.
- S5 (AUD-12d-1) — `PeerDirectory` took the per-device session lock *inside* its
  caller's transaction (a key change cleared every device of the account, and
  `dropDevice` cleared one), while a send (`encryptFor`) and an inbound apply
  hold that lock and open their transaction after. Drift serializes transactions
  on the engine's single connection, so the two could wait on each other with no
  timeout — and because the engine's `KeyedLock` is not re-entrant, a third
  shape needed no second task at all: an inbound prekey message from an account
  whose key just changed is applied under that device's lock, and resolving its
  identity reaches the same clearing, which waits on itself. The finding's
  confidence ("likely: inversion confirmed in code; needs two paths to overlap")
  understates it — the self-wait makes one path enough. Sessions now go
  **before** the transaction that pins the new key and before the row delete in
  `dropDevice`, each in its own transaction, and `_clearSessions` takes no lock:
  the record's `version` (C-01's compare-and-set) is the guard and the reload-
  and-clear-again loop converges, which is what the finding's fix sketch argued
  and what the old doc comment already half-said. Clearing first is also the
  order that fails safe: a throw or a crash before the commit leaves the *old*
  pin, so the next fetch clears again, where clearing after a committed pin would
  leave a session on the retired key that nothing ever revisits (the devices are
  re-listed as trusted by that same transaction). The consequence of that rare
  loss is one undecryptable message and a §13a repair, not a wedged engine.
  Not done from the sketch: the `withDevice`/`withDevices` helpers and the debug
  assertion that `db.inTransaction` is false when a lock is taken. Drift exposes
  no transaction state to the engine, so the check needs a wrapper around all 52
  `db.transaction` call sites in this package — a change of its own, in files
  other work is touching, for a rule that now has one implementation left
  (`PeerDirectory` takes no lock at all, and `encryptFor` already locks before
  it transacts). The rule is instead written into the engine MODULE.md's data
  conventions and enforced by a test.
  Tests: `test/lock_order_test.dart`, two cases (a key change and a device drop
  each racing a lock holder that then writes through a transaction), both of
  which hang and fail on the 5 s timeout with the old order restored —
  "Bad state: the device lock and the open transaction waited on each other" —
  and pass in 2 s with the fix. The key-change case is forced by overwriting the
  pinned AIK locally, which the crypto layer reports as `changed` while the
  served bundles still verify.
  Gate: engine suite **323 green**, `dart analyze lib test` and `dart analyze
  server tool` clean, format clean, and the live-socket engine tests that walk
  this path green against Postgres — `server/test/client/engine/security_test.dart`
  (the key change is pinned, announced and resets "verified"; "signed prekeys
  rotate when due" hit the documented pool-lock flake in a multi-file run and
  passed alone), `recovery_test.dart`, and `devices_test.dart` +
  `messaging_test.dart` (17 green, the `dropDevice` paths). No schema and no
  wire change; no APK needed for this step on its own.
- S6 (AUD-12e-3) — the key share after an add or an approval was chained to the
  one response, so an ambiguous answer left the new member in the group with no
  key: the server's repeat of that add reports them `already_member`, the
  audience built from `result.added` was empty, and the roster event's own share
  defers to the actor, who is this account. `addMembers` and
  `approveJoinRequest` now take the audience from the refreshed roster
  (`update.added`) as well as the response, and `addMembers` explains an
  `already_member` that this device's roster has not seen — that is what its own
  lost call added — before the roster is read, so the apply does not hold her
  back as a member the server put there on its own. An account *already* in the
  local roster is deliberately not explained: the marker would sit unused and a
  later addition of that account by anyone else would consume it, which is the
  one way this could weaken the §14 confirmation gate. The gate itself is
  untouched: `GroupKeyDistributor.share` already removes everyone in
  `GroupTrust`'s pending set, so widening the audience cannot key an
  unconfirmed member, and the tests below assert both halves.
  `_afterRemoval` does the two steps that need no server answer first — the
  removed member's sender keys and the rotation duty, keyed by the epoch the
  removal's own response named (`removeMember` returns it; a ban answers nothing
  and uses this device's epoch, which is right because `rekey` re-reads the
  group when it runs) — and reads the roster back last, so an offline device
  after a removal no longer leaves the group unrotated with the removed member
  still holding the key.
  Not done from the sketch: the durable "share with whoever is new" *duty*. The
  roster-diff audience already covers the reachable cases at the moment the
  mutation is made; a background duty needs a way to tell "this member has
  never been given the current key" from "they have" (the keyring keeps no
  record of whom a key was sent to), so it would re-share on every pass and,
  worse, would hand the key to a member whose confirmation is still pending on
  this device if the pending set were ever read wrong. A lost *approval* answer
  has the same shape (the request is consumed, so a retry 404s and names nobody),
  and there the joiner waits in the pending set for the admin to confirm them —
  visible in the app's member list, not silent, and not this step's fix.
  Tests: `groups_test.dart` "an add whose answer is lost still hands the group
  key to the new member" (the fake commits the add and the answer is lost; the
  retry reports `already_member` and shares; Carol's title opens, and she is not
  in Alice's pending set), "an add that reads the roster wide still keys nobody
  the user has not confirmed" (a silently injected member is named by the same
  refreshed roster and still gets no key, while the real add does) and "a
  removal whose roster read fails still forgets the member and queues the
  rotation" (the `GET` after the removal is dropped: the duty is queued and,
  once the network returns, the rotation lands and a rename reaches Bob). The
  first and the last fail on the previous code — Carol held back as
  `unattributed` with no key, and a queue count of 0 — and pass with the fix.
  Gate: engine suite **326 green**, `dart analyze lib test` and format clean,
  and `server/test/client/engine/groups_test.dart` **16 green** against Postgres
  (it is where the approval and two-server key paths actually run). No schema
  and no wire change; no APK needed for this step on its own.

- S7 (AUD-12e-2) — the group's trust and key state were JSON documents in
  `settings` read-modify-written by four actors with no CAS. A roster apply
  held a member back inside its transaction; a `confirmMember` that had read
  the pending map before it then wrote the map it held, and the member the
  apply had just withheld was released — permanently, because the hold-back
  only marks accounts new to the previous roster, so no later refresh re-holds
  them, and that gate is the only defence against a server silently adding
  someone. The same shape could drop an epoch key (the state sealed under it
  unreadable on that device) and restore an old description.
  **What changed:** every entry is one settings row — `group.key.<id>.<epoch>`,
  `group.pending.<id>.<account>`, `group.explained.<id>.<account>` — and the
  metadata is one row per field, split between the fields the server states
  (`settings`, `home_server`) and the fields the decrypted state carries
  (`description`, `avatar`), so a write is an upsert or a delete of exactly the
  entry it is about and two writers cannot lose each other's. `SettingsDao`
  gained prefix read/watch/reset/prune helpers and a `remove` that reports
  whether the row was there (confirm and takeExplained are consumes).
  `explain` prunes the markers by row age instead of the old FIFO list; `put`
  writes its epoch and drops only epochs beyond `GroupLimits.keptEpochKeys`.
  The four legacy documents are migrated on first read and dropped; a
  migration that interleaves with a live write can re-insert an entry it read
  before the release landed, which errs toward withholding, never toward
  releasing.
  **The state write:** `_apply` compared `stateVersion` with a row read
  *before* its transaction and then wrote the state, title and avatar
  unconditionally. It now re-reads the group row inside the transaction: a
  roster older than the stored epoch writes nothing, and a stored state newer
  than this answer (`rolledBack`, or a `setState` that landed meanwhile) keeps
  its blob, version, title and avatar, with the state-derived metadata not
  written at all.
  Not done from the sketch: a `GroupStateStore` owning every write. With the
  entries as rows there is no shared document left to lose, and the lock the
  sketch warned about (taking `GroupRosterSync`'s non-reentrant lock inside
  `_apply`) is not needed: `_apply` and `attributeAdded` already run under it,
  and the writers left outside it (`confirm`, `explain`) only delete or upsert
  their own rows.
  Tests: `test/groups/group_store_test.dart`, seven tests over the stores
  directly, where the interleaving is deterministic: "a confirm cannot drop a
  member the roster holds back at the same time" and "two explanations landing
  at once are both remembered" fail on the document shape (the first leaves
  `{}`; the second loses one explanation), "two epoch keys stored at once both
  survive" fails on the whole-map `put` (`[1, 3]` for `[1, 2, 3]`), and the
  other four cover the retention bound and the four migrations. Two assertions
  elsewhere read the old `group.keys.<id>` layout
  (`packages/helix_remote_engine/test/groups/groups_test.dart` and
  `server/test/client/engine/groups_test.dart`) and now read the per-entry row,
  so they cannot pass vacuously.
  Gate: engine suite **333 green**, db suite **140 green**, `dart analyze lib
  test` clean in both, and `server/test/client/engine/groups_test.dart` **16
  green** against Postgres. No schema change (the settings table carried it
  all) and no wire change; no APK needed. Docs: engine MODULE.md "State kept in
  settings", "Writes that cannot drop each other" and the pending-members
  bullet.
- S8 (AUD-12i-1) — an action op (reaction, edit, delete, vote, RSVP) was
  enqueued with a conversation but no message, so a terminal failure emitted
  `SendFailedEvent(messageRowid: null)`: no line, no retry, and a failed
  "delete for everyone" could not be expressed again because the local row was
  already marked deleted.
  **What changed:** the target rides the op payload (`target_rowid` in
  `SendContentPayload` and `SendGroupContentPayload`, absent on message ops),
  never `outbox_ops.message_rowid` - that column means "this op delivers this
  message" and drives status advances, so an action under it would move the
  message's own ticks. `OutboxDao.forConversation`/`watchForConversation` read
  a chat's ops newest first and `discard` drops a superseded failure;
  `ChatsService.watchFailedActions` decodes the failed
  `send_content`/`send_group_content` ops into `FailedAction` (op id, target
  row, body type, last error code), `retryAction(opId)` goes back through
  `OutboxService.retry`, and a new action of the same type on the same message
  discards the older failed op with it. A payload that does not decode is
  skipped (that op already failed as `bad_payload`), and a failed message send
  is not reported as an action failure.
  **UI:** `HelixMessage.failedAction` draws a second failed line under the
  bubble ("Couldn't delete for everyone", "Couldn't send your edit", ...) with
  RETRY; the timeline entry resolves the content id back to its local row and
  retries every failed action on it. The message's own ticks stay its own (a
  sent message whose reaction failed still shows sent).
  Not done from the sketch: no `SendFailedEvent` consumer for actions - the
  app reads the outbox rows instead, so a failure survives a restart - and
  `retrySend` still handles only message ops, because a row can owe several
  actions and they retry by op.
  Tests: `packages/helix_remote_engine/test/outbox_test.dart` - "a delete for
  everyone that fails is shown on its message and can be retried; the
  message's own status does not change" (before this change `failedActions`
  is empty and nothing can re-express the delete) and "a new attempt at the
  same action clears its old failure" (the superseded op is gone and only the
  new edit arrives); "a failed message is not a failed action" guards message
  ops. `app/test/conversation_test.dart` "an action that failed for good is
  shown on its message and retried from there" draws the line and taps RETRY.
  Gate: engine suite **336 green**, db suite **140 green**, orbit_ui suite
  **232 green**, app `conversation_test.dart` **22 green**, `dart analyze`
  clean in engine, db, orbit_ui and app, and
  `server/test/client/engine/groups_test.dart` **16 green** against Postgres.
  No schema change (the target is in the payload) and no wire change; no APK
  needed. Docs: engine MODULE.md outbound pipeline and the `chats` row.
- S9 (AUD-12i-2) — "delete for me" on a pending message removed the row but
  left its outbox op, so the message was delivered as soon as the network
  returned, invisibly, and no later "delete for everyone" could recall it
  (the row was gone). Clear chat and delete chat had the same shape, and a
  failed action about a removed row stayed queued for a retry nothing could
  show.
  **What changed:** `OutboxDao.cancelForMessages` and
  `cancelForConversation` delete pending and failed ops (an in-flight op is
  left alone - its request may already be on the wire), and
  `MessagesDao.removeMessages` / `clearConversation` call them in the same
  transaction, which covers delete-for-me, clear chat, delete chat,
  disappearing expiry and the transfer paths that remove a row.
  `ChatsService.deleteForMe` also discards queued actions whose payload
  target is one of the removed rows, and `deleteChat` empties the chat's
  queue before deleting it. The only removal offered on an unsent message is
  now a cancel.
  Not done: stopping the upload itself (and deleting a partly uploaded
  object) stays with AUD-12l; deleting an unsent media message now cancels
  its held send at once, and the existing maintenance pass reaps its
  transfer job.
  Tests: `packages/helix_remote_engine/test/outbox_test.dart` - "deleting a
  message for me cancels a send that has not left" (before this change the
  op survives and the drained outbox sends it), "clearing a chat cancels
  everything still queued in it", "deleting a chat cancels what was queued in
  it" and "deleting a message for me drops a failed action about it"; the
  media housekeeping test in `test/transfers/transfer_worker_test.dart` now
  also asserts the held send is gone with the row.
  Gate: engine suite **340 green**, db suite **140 green**, `dart analyze`
  clean in both. No schema change and no wire change; no app change; no APK
  needed. Docs: engine MODULE.md outbound pipeline and db MODULE.md rules and
  `OutboxDao` list.
- S10 (AUD-12c-2) — the edit and delete windows compared the action's own
  sender-chosen time with the target's, and a time earlier than the target
  gave a negative difference that passed every `>` check: a modified peer
  could edit or retract a message of any age, indefinitely (and the local
  `editedAt` moved backwards).
  **What changed:** `_inWindow` in `messaging/apply.dart` requires the action
  time to fall after the target and within the window; an edit or delete
  dated before its message is ignored. Delivery time is deliberately not the
  bound - an honest action composed in time but delivered after the receiver
  was offline days still applies, which the existing out-of-order test pins.
  Tests: `test/inbound_test.dart` "an edit or delete dated before its message
  is refused" - a forged edit and a forged delete dated an hour before the
  target, applied three days later, leave the text, `editedAt` and
  `deletedAt` untouched (before this change both applied). The existing
  "only the author may edit or delete, within the windows" still covers the
  upper bounds and late delivery.
  Gate: engine suite **341 green**, `dart analyze` clean; the db package is
  untouched (its **140 green** is the S9 gate). No schema change, no wire
  change, no app change; no APK needed. Docs: engine MODULE.md inbound rules.
- S11 (AUD-12f-2) — typing took a shortcut: it committed the ratchet (or the
  group chain) and returned `ignored` without recording the envelope. The
  `ephemeral` flag belongs to the sender, so a stored `TypingBody` came back
  on every reconnect while it stayed the newest: a second chain iteration,
  and outside the skipped-key window a quarantine (or an undecryptable row
  for an urgent one). This client only sends typing as ephemeral, so Helix
  itself could not hit it.
  **What changed:** the direct branch commits the session and marks the
  envelope in one transaction (`_commitSessionOnly(record:, at:)`); the group
  branch returns `_record(envelope, mark, ignored)` after committing the
  chain. `_mark` already ignores `seq == null`, so ephemeral typing is still
  never stored or acked.
  Tests: `test/inbound_test.dart` "a stored typing envelope is processed
  once" and `test/groups/groups_test.dart` "a stored typing envelope is
  processed once" - each sends a non-ephemeral `TypingBody` through the
  outbox/group send and asserts `processed_envelopes` holds it and the
  cursor reaches its seq (before this change both stay behind). The direct
  test guards the transaction shape; the group test guards the early return.
  Gate: engine suite **343 green**, `dart analyze` clean. No schema change,
  no wire change, no app change; no APK needed. Docs: engine MODULE.md
  inbound rules (the ephemeral bullet).
- S12 (AUD-12f-3, with AUD-12e-1) — three writers stored epoch keys (group
  creation, the rotation, an inbound `group_key`) and the keyring kept
  whatever it was handed, so the first arrival won. A rotation re-used any
  held key for the new epoch and sealed the state under it: a key a member
  handed the group became the group's for good, and that device could read
  every later state.
  **What changed:** `GroupKeyAuthority` owns the decision and `GroupKeyring`
  only stores. The stored state arbitrates whenever it can: an arrival that
  opens it is promoted (the key it replaced stays beside it as the
  candidate), a held key that opens it refuses an arrival that does not, and
  when it opens under neither the arrival is kept as the epoch's second key.
  The rotation stops only when the blob opens under a held key; otherwise it
  mints one, so it never seals the state under a key the blob could not
  confirm. Opening the state or a write promotes the key that opened it, so
  whichever competing state write lands settles the order on the first read.
  Tests: `test/groups/groups_test.dart` "a key the old state cannot confirm
  is kept beside the first one, and the key the state is sealed under wins"
  (a member's key arrives first; the rotation's key overtakes it and the
  group stays readable), "a rotation seals the state under its own key, not
  one a member handed it" (the rotation mints its own; the injected key is
  kept only as the candidate), and "a held key that opens the state refuses
  one that does not" (the original key is not displaced).
  Gate: engine suite **346 green**, `dart analyze` clean. No schema change,
  no wire change, no app change; no APK needed. Docs: engine MODULE.md
  (group master key, file map, known limits - two keys per epoch).

## B7 — Media must not outlive its row or its quota
**S · ~3–4 days · media module migration · needs B4's request timeout**

**Closes:**
- AUD-5-1 (P2) — deleting an account frees media only through one
  8-attempt/5-minute job that loads every row first; `persistent` media never
  expire, objects have no account FK, so a dead-lettered purge keeps avatars
  and group blobs forever.
- AUD-5-2 — deleting or replacing the recovery backup leaves its ciphertext
  (and 1 GiB of quota) for 90 days.
- AUD-5-3 — a byte-only quota lets one account turn 4 GiB into millions of
  rows; the sweeps that clean them are per-object and time-boxed.
- AUD-5-4 — upload quota is read-then-insert with no serialization.
- AUD-5-5 — two concurrent chunk uploads of one object can interleave and
  leave a corrupt, over-size blob.
- AUD-5-6 — backup PUTs have no per-route limit; 64 MiB of JSON per request.

**Why here:** the second-largest privacy gap in the audit (deleted data kept
for 90 days, claimable by nobody) and the only path that can produce a corrupt
object. One lifecycle owner fixes all six.

**Structure:** one media lifecycle with reconciliation (S3 in
[05_backup_media.md](file:///J:/Projects/helix/orbit/audit/05_backup_media.md));
`append` as a serialized, resumable protocol returning the actual length (S2 in
[01c_platform_io.md](file:///J:/Projects/helix/orbit/audit/01c_platform_io.md)).

**Verification:** `media_backup_test.dart` — deleting an account frees its
objects without depending on one job; deleting or replacing a backup deletes
the ciphertext immediately; concurrent creates never exceed the quota; two
interleaved chunk uploads yield one 409 and one intact object; the backup PUT
route is rate-limited; an account's object-row count is capped independently of
bytes.

**Rollout:** media module migration — object rows gain the account reference
and an expiry for `persistent`, with a backfill of existing orphans before the
constraint (expand → backfill → migrate → contract). No wire change.

- S1 (AUD-5-6) — the two backup `PUT`s had no per-route policy while every
  other heavy authenticated write did. Each request buffers up to 64 MiB,
  scans it byte by byte, decodes it and re-encodes it into a parameter, so
  one account could keep a node parsing JSON at the global 10 requests a
  second.
  **What changed:** `putFullBackup` is limited to 6 a minute per account and
  `putHistoryBackup` to 12; past that the answer is `rate_limited`, before
  the body is read. Backups are occasional (a device start or a settings
  change), so the allowance is headroom, not a schedule.
  Tests: `test/modules/media_backup_test.dart` "both backup PUTs are limited
  per account" — six full-backup PUTs and twelve history PUTs succeed, the
  next of each is `rate_limited`.
  Gate: `test/modules/media_backup_test.dart` **8 green**, `dart analyze`
  clean on the changed files. No schema change, no wire change, no app
  change; no APK needed. Docs: backup MODULE.md.
- S2 (AUD-5-4, AUD-5-3) — upload quota was a read-then-insert: two
  concurrent creates both saw the old sum and both inserted. It also
  counted only bytes, so one-byte objects could turn 4 GiB into millions of
  rows, each costing a blob delete inside a five-minute job.
  **What changed:** migration 2 adds `media.account_usage` - bytes and
  object count per account and kind, backfilled from `objects`. A create
  reserves both in one `INSERT ... ON CONFLICT DO UPDATE ... WHERE ...
  RETURNING`, so concurrent creates serialize on the row and the guard is
  re-evaluated after the wait; the cap is `maxObjectsPerKind` (100,000 per
  kind). Deleting or expiring an object releases both in the same
  transaction as its row, and the account purge drops the usage row with
  the last object.
  Tests: `test/modules/media_backup_test.dart` "concurrent creates stay
  inside the quota" (six concurrent creates with room for three: three
  201s, three `quota_exceeded`, the counter lands exactly on the quota),
  "the object count is capped independently of bytes" (a full count
  refuses the next create and names `quota_objects`), and "deleting an
  object gives its bytes and its row back".
  Gate: media/backup file **11 green**; availability plus the engine media
  and backup suites **34 green**; `dart analyze` clean on the changed
  files. Migration 2 (`media_usage`) is new and production owes it. No
  wire change, no app change; no APK needed. Docs: media MODULE.md.
- S3 (AUD-5-3) — `media.expire` looped until it found no expired rows, one
  blob delete (each an unbounded store call) per object, and the account
  purge materialised every row before its first delete. A slow store could
  hold either past the scheduler's timeout, which kills the run mid-sweep.
  **What changed:** both work in keyset batches of `sweepBatch` (500) under
  a deadline taken from the module clock - `expireBudget` (4 minutes,
  below the periodic scheduler's 5-minute timeout) and `purgeBudget` (45
  seconds, below the outbox runner's 60-second timeout). Every object's
  blob and row are committed before the next starts. A sweep that runs out
  of budget returns with its progress kept and logs
  `media_expire_stopped`; a purge that runs out throws, so the job retries
  only the rows that are left, and its usage row stays until the last one
  is gone.
  Tests: `test/modules/retention_test.dart` "an expire sweep stops at its
  budget, and the next run continues where it left off" (a fake clock moves
  two minutes per blob delete against a one-minute budget: exactly one
  object goes, its counter is released, the rest remain; a second run
  finishes) and "a purge stops at its budget with what it deleted kept, and
  the retry finishes the rest".
  Gate: retention **10 green**, media/backup **11 green**, availability
  **6 green**; `dart analyze` clean on the changed files. No schema change,
  no wire change, no app change; no APK needed. Docs: media MODULE.md.
- S4 (AUD-5-2) — deleting the recovery backup removed only its row, and a
  higher-version replacement extended only the ids it named: the dropped
  ids' ciphertext stayed downloadable for 90 days and kept its 1 GiB of
  backup quota.
  **What changed:** `MediaApi` gained `expireBackupMedia`,
  `expireBackupMediaExcept` and `deleteBackupMedia`, all owner- and
  kind-scoped (a client-supplied `media_ids` can never name an attachment
  or another account's object). `DELETE /v1/backups/full` locks and reads
  the row, marks its ids expired and drops the row in one transaction,
  then deletes the objects (blob first, quota released) under a 10-second
  `deleteBudget`; a replacement `PUT` marks the objects the new `media_ids`
  no longer name in the same transaction as the upsert, then deletes them
  the same way. Expiry-first makes both crash-safe: an object the request
  could not finish is still collected by `media.expire`, so the ciphertext
  and quota never outlive the backup indefinitely.
  Tests: `test/modules/media_backup_test.dart` "deleting a full backup
  deletes its media and frees the quota" (download 404, usage counter back
  to zero, the room reusable), "a replacement full backup deletes the media
  it stopped naming" (dropped 404, kept 200, one object left), "a backup
  delete never touches media of another kind".
  Gate: media/backup **14 green**, retention **10 green**, availability
  **6 green**; `dart analyze` clean on the changed files. No schema change,
  no wire change, no app change; no APK needed. Docs: backup and media
  MODULE.md.
- S5 (AUD-5-1) — account deletion had exactly one path to its media bytes:
  the `media.purge_account` job. If it dead-lettered, timed out or the store
  stayed unreachable through its 8 attempts, the rows stayed for ever:
  `persistent` objects never expire and a live row keeps its blob from
  looking like an orphan. Nothing tied objects to an existing account.
  **What changed:** a weekly `media.reconcile` walks the distinct owners in
  keyset batches of 200 under `reconcileBudget` (4 minutes) and, for an
  owner `IdentityApi.account` does not know, deletes its objects blob-first
  and drops its usage row. Existence is asked through the identity facade,
  never by SQL into another schema; a live account is not touched. The
  purge job now shares the same batched deletion helper, and the reconcile
  also reports `account_usage` rows that disagree with the stored objects
  (`quotaDrift`) instead of silently correcting them.
  Tests: `test/modules/retention_test.dart` "the weekly reconcile deletes
  the media of an account whose purge job died" (the job runner and
  scheduler are stopped, the account is deleted through the identity
  facade, the purge row is marked dead: the reconcile removes the object,
  its blob and its usage row and leaves a second, live account's media
  alone) and "the reconcile reports quota drift instead of correcting it".
  Gate: retention **12 green**, media/backup **14 green**, server **5
  green** in the same run; `dart analyze` clean on the changed files. No
  schema change, no wire change, no app change; no APK needed. Docs: media
  MODULE.md, and `media.reconcile` added to the periodic-jobs invariant in
  `test/server_test.dart`.
- S6 (AUD-5-5) — two concurrent chunk uploads of one object could both pass
  the length check and both append, leaving a blob holding two interleaved
  bodies that the route then sealed as complete. The storage protocol that
  prevents it landed with B4 S2 (`LocalObjectStorage.append` holds a per-key
  gate, re-reads the file's real length after the gate, and answers
  `OffsetMismatch`, which the route turns into 409 `conflict` with
  `upload_offset`); what was missing was a test at the route, where the two
  requests actually meet.
  **What changed:** no production code — one regression test drives the real
  upload route with two streamed PUTs (two chunks each, sent over a chunked
  body) at offset 0. Exactly one answers 204, the other 409, and a download
  is exactly one of the two payloads at its declared length: not doubled,
  not interleaved.
  Tests: `test/modules/media_backup_test.dart` "two concurrent uploads of one
  object leave one intact copy"; the storage-level sibling from B4,
  `test/platform/infra_test.dart` "two writers at one offset: one appends,
  the other is told to resume", stays the protocol test.
  Gate: media/backup **15 green**, the new test also green three runs alone;
  `dart analyze` clean on the changed file. No schema change, no wire change,
  no app change; no APK needed.
  **Batch report.** All six B7 findings are closed. B7's steps: S1 `7567303`,
  S2 `e85da5f`, S3 `b0e4c35`, S4 `9a9205c`, S5 `7cb97e4`, S6 `c176dbe`.
  B7's gate: **514 tests** on Postgres at `--concurrency=3`, 513 green, the
  one failure the `messaging_test.dart` token-bucket timing flake already
  listed in `AGENTS.md` (green alone in 2 s straight after), and
  `dart analyze server tool` clean. No app or admin code changed.
  **Residual, deliberate:** the weekly reconcile asks whether an owner still
  exists; it does not compare rows to blobs. A row whose blob vanished still
  fails its download and holds its quota until expiry, and a blob without a
  row is left to `media.sweep_orphans` - the two are separate stores and
  comparing them costs a full listing per run. For the same reason
  `quotaDrift` reports a counter that disagrees with the rows and never
  rewrites it: the disagreement is the evidence. Because the reconcile is
  weekly, a dead purge's guarantee is "bounded by a week", not "immediate";
  the purge job remains the prompt path. `quotaDrift` is one aggregate over
  `objects` run after the account walk, outside `reconcileBudget` - a scan,
  not a write, so a timeout can lose a report but never progress; a much
  larger node would want it batched.
  **Owner-facing, whole batch:** production owes **media migration 2
  (`media_usage`)** at the next start (`bin/migrate.dart` or the node's own
  migration): it creates `media.account_usage` and backfills it from
  `media.objects` in the same migration, before the node serves. Platform
  migrations 3, 4 and 5 are still owed with it. A new weekly job
  `media.reconcile` runs by itself; no `.env` line. The two backup PUTs now
  refuse a burst per account (6 full and 12 history a minute) with
  `rate_limited`; the app's backup schedule is far below that. No wire
  change, no app change, so no APK.
- Next: B8 waits on Q8/Q9, so B9.

## B8 — Calls: the newest caller rings, and the log is bounded
**S + A · ~2–3 days · calls module migration · depends on B1**

**Closes:**
- AUD-12k-1 (P2) — on reconnect with several parked offers, the loop rings the
  **oldest** one (the server orders ascending), so the call with the least
  ringing time left wins and every newer caller is answered "busy" and logged
  missed. The headless push pass shows the same order.
- AUD-12k-2 — `release()` finishes the live call outside the call queue, so an
  engine stop can mislabel the log and race an in-flight accept.
- AUD-12l-1 — a failed media setup leaks the peer connection (and any
  initialised renderer), and its ICE callback can fire into a closed stream.
- AUD-12l-2 — `ice_config.dart` claims the server enforces relay-only and drops
  leaking candidates, but call signals are sealed and the server never parses
  them. `PRIVACY_CLAIM_MATRIX.md` has the correct claim; the code comment
  contradicts it and would lead the next maintainer to rely on a control that
  does not exist.
- AUD-6-1 (P2) — call metrics keep a free-text `outcome` per row: ~9 GB per
  account over the 90-day window, with no account column and an unindexed
  cleanup scan. If Q9 = delete, this closes by removing the table and sweep
  instead of bounding the field.
- AUD-6-3 — `PUT /calls/{id}/state` has no policy and fans out to every device.
- AUD-6-4 — a non-offer call signal is delivered to any addressed device; only
  pending-row writes are party-scoped.
- AUD-6-5 — TURN credentials are capped per device, so one account can mint
  many one-hour relay credentials.

**Why here:** 12k-1 is a missed call the callee never sees (the product's
primary promise), 12l-1 leaks a capture device on a failed setup, and 6-1 is a
storage bomb one account can plant. All are in the calls module and its
retention job.

**Verification:** engine `calls/` tests — two parked offers ring the newest and
the other is ended busy; `release()` during an accept produces one log row and
one end; a media setup that fails at the microphone, at a renderer and at
`addTrack` releases the peer connection and emits no event into a closed
stream. `server/test/modules/calls_test.dart` — the state route is limited;
a signal to a non-party device is refused; TURN minting is capped per account;
`outcome` is bounded and the cleanup query uses an index (the B1 EXPLAIN
harness), or the table is gone (Q9). A doc assertion (the governance checker or
a comment-level test) that `ice_config.dart` no longer claims server-side
candidate filtering.

**Rollout:** two independent halves. The server migration bounds `outcome`,
adds the account column and its index (or drops the table, Q9); the app/engine
half changes the ring order, the release path and the media-setup cleanup.
Land the server first (it accepts both orders), the app next.

**Coverage note:** 12m–12r have since been read; their findings are in B13
(the local media lifecycle), B9 (the transport's caps) and B17 (the post-merge
identity refusal), and none adds to this batch. 12l-3 and 12l-4 are in T4 (Q9).

## B9 — The client transport must finish what it starts
**A · ~3 days · no migration, no wire**

**Closes:**
- AUD-11a-1 (P2) — one 30 s deadline covers the whole body, so full/history
  backup (32 MiB), export and presigned uploads cannot finish on ordinary
  mobile links; a retry restarts from byte 0.
- AUD-11a-3, AUD-11a-4 — `isUnauthenticated` is true for `invalid_credentials`
  (the engine would show sign-in for a wrong password); a failed session-store
  write after a refresh re-exposes the rotated-out refresh token, which the
  server treats as theft.
- AUD-11b-1..AUD-11b-4 — a refused upgrade can hang or leak; the negotiated
  subprotocol is never checked; `reconnect()` after `dispose()` leaves a live
  socket; the silence detector uses wall-clock time.
- AUD-11c-1 — `accountKeys` is a GET that consumes a one-time prekey, so the
  transport's automatic retry silently burns one and returns a bundle with no
  OTK.
- AUD-12n-4 (P3, appended) — the presigned-target branch of the upload runner
  reads the whole staged ciphertext into memory, with no upload-size cap; an
  out-of-memory failure then falls to the generic `internal` retry instead of
  stopping. Only S3-style deployments take this branch (production uses the
  resumable local path).
- AUD-12o-1 (P3, appended) — the cap for a whole-object download is computed
  with the *largest* legal chunk size, but ciphertext grows with *more* chunks,
  so an object sealed at the default 64 KiB is longer than the cap: a thumbnail
  over 64 KiB fails permanently as `size_mismatch`, and so does every file on a
  server that answers the first ranged GET with the whole object.
- AUD-12r-1 (P1, appended) — the same arithmetic in the device-to-device
  transfer: the receiver caps a segment with the 1 MiB max chunk size while
  `_put` sealed it at the 64 KiB default, so every segment over 64 KiB
  exceeds the cap and `_readCapped` throws `ResponseTooLargeException`. With
  the app's 4 MiB `segmentBytes`, every history transfer over 64 KiB fails on
  its first segment; the tests pin 3 000 and 20 000-byte segments and the
  engine's fake relay ignores `maxBytes`.
- AUD-14a-4 (P3, appended) — the app fills `x-helix-client` with
  `EngineConfig.deviceName`, and the runtime factory never injects the provider
  that knows the real one, so every app request and socket handshake carries
  the constant `Helix device` where the header documents `<platform>/<app
  version>`; the CLI and the console send theirs correctly.

**Why here:** 11a-1 is the difference between "backup works" and "backup times
out on a phone"; 11c-1 costs a prekey per retry, which degrades every later
session; 11a-4 is the one that can turn a local write failure into a forced
sign-out of every device.

**Structure:** a deadline per route class, not per attempt (S1 in
[11a_api_transport.md](file:///J:/Projects/helix/orbit/audit/11a_api_transport.md));
the in-memory session is authoritative and persistence best-effort (S2); one
connection lifecycle state machine (S1 in
[11b_api_realtime.md](file:///J:/Projects/helix/orbit/audit/11b_api_realtime.md));
the catalog states retry safety instead of the transport guessing (S1 in
[11c_api_clients.md](file:///J:/Projects/helix/orbit/audit/11c_api_clients.md)).
The upload runner streams a presigned PUT from the staging file (or refuses
over a ceiling with `tooLarge`) rather than buffering it — the same bounded
body the long deadline already has to carry. A whole-object fetch is bounded by
the *smallest* legal chunk size (the most chunks the plaintext can imply), not
the largest — or, better, by a single helper every reader shares (S12r-1 in
[12r_transfer_receiver.md](file:///J:/Projects/helix/orbit/audit/12r_transfer_receiver.md)),
since four call sites currently guess three different chunk sizes. 12r-1 also
needs the transport's other exceptions in `BackupException.translate`, so a
too-large body names a backup problem instead of leaving the transfer stuck.
14a-4 is the header's other half: the client name is built from the platform
and the app version (as the header says), and the runtime is constructed with
the device configuration it already has a provider for.

**Verification:** `packages/helix_remote_api/test/v2/transport_test.dart` — a
slow-body route gets the long deadline and a small route does not; a 401 with
`invalid_credentials` is not "unauthenticated"; a failing store write does not
re-send with the old refresh token; a GET that consumed a prekey is not
retried. `packages/helix_remote_engine/test/transfers/` — a presigned upload of
a file over the chosen ceiling either streams without materialising it or ends
`tooLarge` at once; a 100 KiB thumbnail sealed at the default chunk size
fetches whole under its cap; a history transfer with the *default*
`segmentBytes` (4 MiB) and a history over 64 KiB completes — with
`FakeRelay.download` enforcing its `maxBytes`, and the server e2e "large
history" test no longer pinning `segmentBytes: 20000`. `realtime_client_test.dart` — a wrong subprotocol is
refused; no socket survives `dispose()`; a backward clock step does not silence
the heartbeat; a runtime built by the app's factory sends
`x-helix-client: <platform>/<version>` (not the device name).

**Rollout:** app/API package only. The server needs no change. The resumable
upload pairs with B7's chunk protocol but does not require it.

- S1 (AUD-11a-1) — one 30 s deadline covered every attempt *and the whole body
  transfer*: a full or history backup (≈22 MiB of JSON), the account export
  and a presigned whole-object `PUT` all inherited it, so they failed on any
  link slower than ~6 Mbps, and each retry re-sent the body from byte 0.
  Nothing widened it except the link long-poll, which passes its own.
  **What changed:** a request whose body or declared response cap is over
  `bulkTransferBytes` (4 MiB, the normal JSON cap) is a bulk transfer: its
  deadline is an *inactivity* limit (`bulkIdleTimeout`, 30 s) that re-arms on
  every chunk sent or received, while a small call keeps the whole-transfer
  deadline. A bulk body is handed to the server as a lazily produced stream
  (`AbortableStreamedRequest` subclass) rather than one buffer, so the clock
  follows the socket and a presigned upload no longer needs the ciphertext in
  memory; `external` gained the matching `stream`/`contentLength` form. The
  detection is automatic, so every existing large-cap caller (backups,
  export, media downloads and presigned uploads) is covered without touching
  the clients; a caller may still pass `timeout:` as the idle limit.
  Tests: `transport_test.dart` "a bulk transfer is deadlined by silence, a
  small one by its total time" (the same drip-feed response: a 32 MiB-capped
  call succeeds across 600 ms with 50 ms gaps under a 250 ms limit, while a
  small route times out), "a bulk upload counts every slice it sends as
  progress" (a 4 MiB+ JSON body takes longer than the 300 ms total deadline
  and still succeeds, in 65 slices).
  Gate: api **207 green** (205 before, +2), `flutter analyze` clean on the
  package. No wire change, no app change; no APK needed.
- S2 (AUD-11a-3, AUD-11a-4) — `isUnauthenticated` was true for any 401, so
  the engine's "sign in again" branches would have treated a wrong password
  as a lost session (the transport itself already declined to refresh it);
  and `signedIn` wrote the store *before* caching, so a failed write after a
  refresh left the rotated-out refresh token in memory, and the next refresh
  presented it again - which the server treats as theft and refuses the
  family.
  **What changed:** the getter excludes `invalid_credentials`; `signedIn`
  sets the in-memory session first and persists afterwards, reporting a
  failed write through a new `onPersistFailed` callback (threaded through
  `HelixApi`, wired in the app runtime to `AnomalyLog.state`) instead of
  failing the call; `forget` clears the cache first for the same reason. A
  full disk can still lose the new session at restart - one sign-in - but the
  running app never presents a rotated-out token.
  Tests: `transport_test.dart` "a failed store write keeps the rotated
  session in memory" (the write throws once: the callback is told, the store
  still holds the old token, every later request uses the new one, and the
  refresher runs once) and "a wrong password is an answer, not an
  authentication failure" (the getter on both 401s, and a 401
  `invalid_credentials` on a device route is thrown without a refresh).
  Gate: api **209 green**; `flutter analyze` clean on the package and the
  runtime. No wire change; the only app change is the diagnostic line; no
  APK needed.
- S3 (AUD-11c-1) — `GET /v1/keys/{account}` looks safe by its method, but each
  call takes one one-time prekey per device from the target (the hourly gap
  marker). The transport repeated every GET after a timeout, so the repeat
  consumed another prekey (or, once the gap marker was set, returned a bundle
  with none) and the first answer was lost. The same guess would burn any
  future consuming read.
  **What changed:** the catalog states retry safety. `ApiRoute` gained
  `retrySafety` (`RetrySafety.byMethod` default, `never`, `idempotent`), and
  `Routes.accountKeys` is `never`; the transport's `repeatable` is a switch on
  it, keeping the method rule for everything not marked. An `idempotent` mark
  cannot make a public POST repeatable (a repeated refresh is token reuse).
  A protocol snapshot test pins the exception list to exactly the one route,
  so a new consuming read cannot be added silently.
  Tests: `routes_test.dart` "routes that may not be repeated are named
  explicitly"; `transport_test.dart` "a GET that consumes a one-time prekey is
  sent once" (a connection failure and a retryable `unavailable` both reach
  the server once, with no backoff), while the existing exponential-backoff
  test still sees four attempts on `GET /v1/devices`.
  Gate: protocol **121 green** (120 before, +1), api **210 green** (209
  before, +1); `flutter analyze` clean on both. No wire change, no app change;
  no APK needed.
- S4 (AUD-11b-1..4) — four edges of the socket lifecycle. A refused upgrade
  read its error body with no deadline, so a server that answered the headers
  and stalled held `_open` in `connecting` forever while a `HttpClient` closed
  without force kept the request alive; the 101's negotiated subprotocol was
  never compared with the offered one; `reconnect()` after `dispose()` built a
  live socket whose first frame threw into a closed controller; and the silence
  detector diffed wall-clock times, so a backward clock step suppressed it and
  a forward one killed a healthy connection.
  **What changed:** `connectPlatformSocket` takes a `timeout` (30 s) that
  bounds the response headers *and* the refusal body (the read cancels its
  subscription on expiry), and closes its client with `force: true` unless the
  socket was detached. A 101 must name one of the offered protocols; an absent
  header is accepted only when nothing was offered (the admin log stream offers
  none). `reconnect()` after dispose throws the same `StateError` as `start`,
  `_open` refuses to run when stopped, and envelope/wake/error adds check
  `isClosed` like `_emit`. Heartbeat and backoff decisions use elapsed time
  from a monotonic `Stopwatch` by default (the test seam is now `elapsed:`,
  replacing `now:`), and a source that moves backwards is treated as a silent
  server, not a fresh one.
  Tests: new `io_socket_test.dart` (real loopback server): a stalled refusal
  body fails within the injected deadline; a 101 that omits or rewrites the
  offered subprotocol is refused; an accepted upgrade still carries a frame
  after the client is closed. `realtime_client_test.dart` "reconnect after
  dispose throws and opens nothing" and "a time source that steps backwards
  reconnects instead of waiting for it to catch up".
  Gate: api **215 green** (210 before, +5); `flutter analyze` clean. No wire
  change, no app change; no APK needed.
- S5 (AUD-12n-4, AUD-12o-1, AUD-12r-1) — one arithmetic error at three
  readers, and one unbounded read at the writer's far end. A whole-object
  download cap was computed with the *largest* legal chunk size, but a
  ciphertext grows with *more* chunks: a thumbnail sealed at the default
  64 KiB and larger than 64 KiB, a file from a server that answers the first
  ranged GET with the whole object, and every device-transfer segment over
  64 KiB were each longer than their own cap, so the API's capped reader threw
  `ResponseTooLargeException` and the transfer ended `size_mismatch` (or, for
  a transfer, as an unknown error that left the offer stuck). The presigned
  upload branch read the entire staged ciphertext into memory with no
  ceiling.
  **What changed:** `AttachmentCrypto.maxCiphertextLength(size)` is the
  longest ciphertext a legal writer can produce (the formula at
  `minChunkSize`, the most chunks the plaintext can imply); `_fetch`,
  `_fetchThumbnail` and the app's group-picture reader use it, and the app
  reader also passes it as `maxBytes` so a hostile body is cut while it
  streams. `MediaClient.uploadStream(target, bytes, length:)` sends a
  presigned PUT from a stream (the transport's `external(stream:)` form), and
  the upload runner feeds it `read(staging, end: expected)` instead of
  `readBytes`: the ciphertext never has to fit in memory. Segments stay
  sealed at the default chunk size, so a new receiver still reads objects an
  older device already uploaded. `BackupException.translate` maps the
  transport's `ResponseTooLargeException`, `RangeNotHonoredException` and
  `MalformedResponseException` to `corrupt`, so a refused body names a
  backup problem instead of vanishing into `unknown`.
  Tests: `layout_test.dart` "§12 maxCiphertextLength bounds every legal chunk
  size" (a property over 0, 64 KiB ± 1, 100 KiB, 1 MiB and 4 MiB at the
  minimum, 1 KiB, default and maximum chunk sizes, plus a default-sealed
  100 KiB object longer than the old cap). `transfer_test.dart` "a
  default-size transfer moves a segment over 64 KiB" (the 4 MiB default, 800
  messages, `FakeRelay.download` now enforcing `maxBytes`);
  `media_flow_test.dart` "a thumbnail over one chunk still fetches whole"
  (100 KiB, on-demand video); `transfer_worker_test.dart` "a presigned upload
  streams the staging file" (`MemoryBlobStore.onRead`: every staging read
  names its end) and "a server that ignores Range still delivers" now moves
  90 KB. The server e2e "a large history" runs 70 000-byte segments (above
  one chunk), proves the first relay object is over 64 KiB before deleting
  it, and still recovers after the gap. Each of the three new reader tests
  was confirmed to fail with the old arithmetic before the fix stayed.
  Gate: crypto **75 green** (74 before, +1), api **215 green**, engine **349
  green**, the app's group tests **107 green**, the server backup e2e **10/10
  on Postgres**, `flutter analyze` clean. No wire change, no migration. The
  app's group-picture reader changed too, so a new APK would carry that half;
  the engine, server and transfer fixes need no APK.
- S6 (AUD-14a-4) — the app sent `EngineConfig.deviceName` as `x-helix-client`,
  and the runtime factory was built without the configuration provider, so
  every app request and socket handshake carried the constant `Helix device`
  (the documented value is `<platform>/<app version>`), while the CLI and the
  console sent theirs correctly.
  **What changed:** `HelixRuntime` names the client from the platform and the
  app version (`appClientName`, e.g. `android/2.0.0`, the version constant the
  About page already uses) instead of the device name; the realtime client
  inherits it through `transport.clientName`. `DeviceRuntimeFactory` now
  *requires* the config callback — a fallback was the way the constant
  slipped in — and `runtimeFactoryProvider` supplies
  `engineConfigProvider`, so the engine also registers with the real device
  name it reports at sign-in. The push background keeps its own config (it
  cannot touch providers) but now sends the same platform/version header.
  Tests: new `app/test/client_identity_test.dart` — the helper's values, and a
  real headless runtime's request through a loopback server carries
  `android/2.0.0` (not the model in its config), with the socket's client
  name the same; the runtime path is the one the factory opens, and the
  factory's config is now a required argument.
  Gate: the full app suite **1028 green** (2 new), `flutter analyze` clean on
  the workspace. No wire change, no migration, no server change. A new APK
  carries it.
  **Batch report.** All six B9 findings are closed. B9's steps: S1 `b6e72f1`,
  S2 `321bbc0`, S3 `26989ca`, S4 `0acbde2`, S5 `e8938f9`, S6 `b5b1bfc`.
  B9's gate: **514 server tests** on Postgres at `--concurrency=3`, 513 green;
  the one failure is the `messaging_test.dart` token-bucket timing flake
  already listed in `AGENTS.md`, and it was green alone in 3 s straight after.
  The client packages, each run at the step that last changed it and none
  touched afterwards: protocol **121**, api **215**, crypto **75**, engine
  **349**; the full app suite **1028**; `flutter analyze` clean on the
  workspace and `dart analyze server tool` clean. No server code, schema,
  wire or `.env` changed in this batch (only a server test did).
  **Residual, deliberate:** the in-memory session is now authoritative and
  persistence best-effort, so a full disk can still lose a refreshed session
  at restart - one sign-in - but the running app never presents a
  rotated-out refresh token, which the server treats as theft; the failed
  write is reported through the diagnostic seam instead. The bulk deadline
  is an inactivity limit, not a total one: a peer that keeps dribbling bytes
  can hold a bulk request as long as its route allows, the same bound any
  long download has. Transfer segments stay sealed at the default 64 KiB
  chunk size (so receivers read what older devices already uploaded), which
  is why every whole-object reader must bound a body by the *smallest* legal
  chunk size - `AttachmentCrypto.maxCiphertextLength` is that arithmetic and
  should not be re-derived at a call site. AUD-12r-2 (a transfer offer stuck
  on an error `translate` does not know) is left to B13, which owns the
  transfer state machine.
  **Owner-facing, whole batch:** no deploy, no migration, no `.env` line -
  the server's code is unchanged and the fixes are in the API package, the
  engine and the app. A new APK carries the app's half (the `x-helix-client`
  header and the group-picture cap); the engine and API fixes ride inside any
  rebuilt client, including the CLI. No wire change.
- Next: B10 (a theme pack the app cannot draw must be refused before it is
  chosen), then B11, B12, B13, B16 and the app-only batches after them; B8
  still waits on Q8/Q9 and B5 on Q6.

## B10 — A theme pack the app cannot draw must be refused before it is chosen
**A (+ C for the server half) · ~2–3 days · no migration, no wire**

**Closes:**
- AUD-16-1 (P2) — a signed pack that parses but is missing a token (or a
  pattern parameter the painter needs) is accepted and offered; choosing it
  makes the app throw above the router, and the persisted choice repeats that
  on every launch until app data is cleared.
- AUD-16-2, AUD-16-3 — `OrbitTokens.lerp` returns the wrong theme at both ends
  (every theme change flickers); tokens are keyed by bare name in one flat map,
  so a document can silently replace a token from another group.
- AUD-16-4, AUD-16-5 — a field label is not associated with its input and an
  inline error is not announced; fixed-height controls clip a label that wraps
  at large text sizes.
- AUD-16-6 — a theme download reports success for a pack the page cannot offer
  and leaves its bytes behind.
- AUD-14j-1 (P3) — the store's decode converts only `FormatException` and the
  folder's read only `FileSystemException`, while `OrbitTokens.fromThemeJson`
  also raises `_TypeError`/`ArgumentError`; one stored signed theme that
  gradient-refs a missing token, names an unknown transform, or has a numeric
  `name` makes every pack read throw. Start-up silently opens on Orbit with all
  downloaded themes gone, the gallery's installed rows vanish, and
  `ThemePackActions.remove` reads before deleting, so the pack cannot be removed
  in-app. This is the read-side twin of 16-1: 16-1 is a chosen pack that
  crashes, this is a *stored* pack that hides every other pack.
- AUD-14j-2 (P3) — `hostedPacks` probes up to 64 manifests one after another
  inside an `autoDispose` provider, so More themes re-pays the whole probe on
  every visit and sits on "loading" for the sum of those round trips.
- AUD-7-4 — `GET /v1/packs` rescans and stats the whole folder on every
  request.

**Why here:** 16-1 is a self-inflicted launch crash that survives restarts; the
fix also repairs installs that already chose such a pack. The rest are the same
token contract or the same pack store. 14j-1 is the exception that proves the
seam: making 16-1's parse strict without widening the read's catch would turn
one bad theme into a dead folder.

**Structure:** one generated theme contract checked by the same code for
built-ins and packs (S16-1 in
[16a_orbit_ui_theme.md](file:///J:/Projects/helix/orbit/audit/16a_orbit_ui_theme.md));
decode before the rename so nothing is installed until it can be drawn (16b);
one decode contract on the read side — no decode failure may leave a folder
read, and the page removes before it reads (S14j-1 in
[14j_core_theme.md](file:///J:/Projects/helix/orbit/audit/14j_core_theme.md));
an index instead of a directory walk for the pack host (S6 in
[07_ops_admin_compliance.md](file:///J:/Projects/helix/orbit/audit/07_ops_admin_compliance.md)),
plus bounded concurrency and a per-`id@revision` verified-kind memory for the
offer probe.

**Verification:** `packages/orbit_ui/test/` and the app's theme tests — a pack
missing a token is refused at install; `lerp(t=0)` and `lerp(t=1)` return their
own endpoints; a duplicate bare token name is refused; the field label and
error are exposed through semantics; the pack pages survive 2× text at phone
width; a failed download leaves no file. Start-up test — a persisted pack that
cannot be drawn falls back to Orbit and offers to remove it. The 14j-1 test —
a trusted pack with `"transform": "no-such-transform"` (or a gradient token
ref that is not defined) leaves the other installed packs readable, and
`ThemePackActions.remove(id)` deletes it. The 14j-2 test — a fake source counts
in-flight probes (bounded, not one at a time) and a second call for the same
ids issues no manifest requests. `packs_test.dart`
— the folder is scanned once and served from an index.

**Rollout:** app-only for 16-1…16-6 and 14j-1/14j-2; server-only for 7-4.
Neither needs a migration or a wire change. The gate gets stricter for *new*
packs only.

- S1 (AUD-16-1, AUD-16-3) — `OrbitTokens.fromThemeJson` walked whatever token
  groups a document happened to have and stored each token under its bare leaf
  name, so a signed theme missing a token (or a pattern setting the painter
  reads with `!`) was accepted, offered and choosable; choosing it saved the
  id, and the first screen that read the token threw above the router on every
  later launch. Two groups sharing a leaf shadowed one another silently, and a
  gradient stop naming a missing or non-colour token, an unknown `transform`,
  or a non-string `name` escaped as `_TypeError`/`ArgumentError` instead of
  `FormatException` (the read-side consequence is AUD-14j-1, next step).
  **What changed:** the generator emits `orbitRequiredTokenNames` (111 names,
  `group.key`) beside the getters, and the parse refuses a document that lacks
  one, naming it. Tokens stay keyed by short name (no screen call-site churn),
  but a second group with the same leaf is a `FormatException`; the gradient
  groups are read in a second pass so a stop can name a colour whatever order
  the JSON groups are in. The pattern registry gained the settings each painter
  reads without a fallback (`grain` r/g/b/a/size, `neonGrid` v/va/h/ha/size,
  `scanlines` colour/a, `contours` stroke/width/size) with their JSON types,
  checked at load. Every parse failure reachable from a pack is now a
  `FormatException`: gradient stops, transform names, meta strings, the swatch
  container, group and token keys, colour hex.
  Tests: `orbit_tokens_test.dart` — a real theme minus one token is refused
  naming `colour.accent`; the JSON's `group.key` set equals the generated
  contract; a colliding `em.accent` is refused; `scanlines` without `colour`,
  with a string `a`, and `neonGrid` without `size` are refused; a
  brand-gradient stop naming a length token or a missing one is a
  `FormatException`; a `wobble` transform and `"name": 42` are refused. The
  "none invented" test also stopped comparing `MapEntry` stringifications (it
  had only counted, so a wrong key spelling never showed).
  `app/test/settings/theme_packs_test.dart` — a signed theme carrying only
  `colour.accent` still passes the domain gate (it knows nothing about tokens)
  and installs, but `load()` and `themeTokens()` return nothing, so it can
  never be offered or chosen; S2 makes the install itself refuse it.
  Gate: orbit_ui **236 green** (the token file 15, four new), the app's
  theme-pack file **42 green** (41 before), `flutter analyze` clean on the
  workspace. No wire change, no migration, no server change. A new APK carries
  the app half.
- S2 (AUD-14j-1, AUD-16-6) — S1 made the theme parse strict, which turned two
  older gaps into live ones: the store decoded a pack **after** the rename, so
  a document the gate allows but this build cannot read left a folder that no
  page offered and no page could delete, and reported it as "downloaded"; and
  the folder's read caught only `FormatException` around the parse and
  `FileSystemException` around the files, so one stored pack could still take
  every other pack's read down. `ThemePackActions.remove` also read the pack
  first, so the undeletable pack was exactly the one whose read failed.
  **What changed:** `PackFolder.install` decodes an in-memory `PackBytes` probe
  after the gate and **before** anything is staged; a null decode is a
  `PackRefused` ([OrbitPackFailure.badTheme](file:///J:/Projects/helix/helix_remote/packages/helix_remote_domain/lib/domain/theme_packs.dart)),
  so no folder and no staging bytes are left behind and the page says "cannot
  be used" instead of "downloaded". On the read side a manifest that is not
  JSON/an object/a manifest is caught as `Object`, and `decode` is wrapped in
  `_decode`, which reads anything a decoder raises as "this device holds no
  such pack today": one bad stored theme cannot hide the others, and a later
  decoder may raise more than `FormatException`. `remove` names the pack from
  the theme library already in memory and never opens the folder before
  deleting it. The store gained the same `PackFolder` contract for sounds for
  free (the sound decoder only names the stored file; it reads nothing).
  Tests: `app/test/settings/theme_packs_test.dart` — a signed theme missing
  its tokens, and one with `lengthPx.r-md = "wide"`, are refused at install
  with no `packs/<id>` and no `.staging` folder (the first replaces S1's
  "installs but cannot be loaded" expectation); a hand-placed signed pack with
  `transform.display-transform = "wobble"` leaves the good pack installed and
  drawable, and `ThemePackActions.remove("oldtheme")` deletes it and says
  "theme deleted"; a `PackFolder` whose decoder throws `StateError` reads as
  no pack rather than a failed folder.
  Gate: the app's theme-pack file **45 green** (42 before), the sounds file
  **12 green** (shared store, unchanged), `flutter analyze` clean on the
  workspace. No wire change, no migration, no server change. A new APK carries
  the app half.
- S3 (AUD-16-2) — `OrbitTokens.lerp` returned the **other** theme at both
  endpoints (`t <= 0 → other`, `t >= 1 → this`), the reverse of the
  `ThemeExtension` contract `ThemeData.lerp` follows. `MaterialApp` wraps every
  screen in `AnimatedTheme`, so every theme change - including the fallback to
  Orbit when a chosen pack is deleted - drew the target theme, snapped back to
  the old one, faded, and drew the old one again before the new landed. The
  unit test asserted the inversion, so it could not catch it.
  **What changed:** each end returns itself (`t <= 0 → this`, `t >= 1 →
  other`), with the contract in the doc. The cross-fade test now asserts that,
  and a new test runs the fade through `ThemeData.lerp(OrbitTheme.of(a),
  OrbitTheme.of(b), 0|1)` - the caller that matters - checking both the token
  identity and the brightness on either side.
  Gate: orbit_ui **237 green** (236 before), the app's settings folder **234
  green**, `flutter analyze` clean on the workspace. No wire change, no
  migration, no server change. A new APK carries the fix.
- S4 (AUD-16-4, AUD-16-5) — the field's label was drawn as a sibling above the
  box and the error as a sibling below it, so the editable node announced only
  the hint (or nothing once text was typed) and an error that appeared after a
  submit was silent; `OrbitButton` put a deliberately wrapping label inside a
  fixed `SizedBox(height:)` and `OrbitSegmented` inside a fixed
  `Container(height: 36/40)`, so at 2× text a second line painted outside the
  box and `Material` clipped it, with nothing throwing.
  **What changed:** the input is wrapped in `MergeSemantics` + `Semantics(label:
  the drawn label, hint: the error while one shows)`, which is what puts the
  label on the field's own node; the drawn label is `ExcludeSemantics` (it
  would be read twice), and the eye and paste buttons stay outside the merge,
  each still its own labeled node. The error row is now
  `Semantics(container: true, liveRegion: true, label:, excludeSemantics:
  true)`, so it is announced when it appears rather than waiting to be swiped
  to. Button and segment heights became `minHeight` constraints with vertical
  padding (6 px, 4 px): a wrapped label grows the control, while a one-line
  label stays at the same height; segment labels are `Flexible` so they wrap
  instead of overflowing. The group-create picture control is now
  `Semantics(container: true)`: beside the merged name field Flutter's
  sibling-merge compiler absorbed the 64 px picture button into the row's node
  (the whole row answered the picture's action, and the app's
  tap-by-semantics-label test failed) — an interactive control has to be its
  own semantics boundary.
  Tests: `orbit_ui/test/primitives_test.dart` — a 40 px `OrbitButton` at 2×
  text draws a two-line label taller than its minimum and still taps; a
  segmented control at 2× in 260 px grows past 36 px rather than clipping its
  label (and is found by `OrbitSegmented<String>`, not the raw generic); an
  `OrbitTextField` exposes `isTextField` with the label on the editable node
  and the error as a live region carrying the same words. The semantics handle
  is disposed in the body, because Flutter checks for a leaked handle before
  tear-downs run.
  Gate: orbit_ui **240 green** (237 before), the full app **1032 green** (the
  group-create picture test caught the sibling-merge side effect before the
  `container: true` fix), `flutter analyze` clean on the workspace. No wire
  change, no migration, no server change. A new APK carries the change.
- S5 (AUD-14j-2) — `hostedPacks` read one signed manifest per pack id in a
  serial `await` under the 64-id cap, inside an `autoDispose` provider: a full
  folder cost 64 round trips per visit to More themes and the whole sum again
  on every revisit, with the page on "loading" for the duration and the host
  absorbing the reads. Nothing was remembered between calls.
  **What changed:** the probe runs through a small worker pool
  (`hostedPackProbeConcurrency = 6`), so twelve ids take two waves instead of
  twelve round trips while the cap stays the market bound. A session-level
  [verifiedPackKindsProvider](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_packs.dart#L737)
  (`Provider<Map<String, String>>`, deliberately outside the pages'
  autoDispose providers) remembers the kind a manifest verified as, keyed
  `id@revision`; `hostedPacks` takes that map as `verified`, answers a hit
  without a request, and writes only a manifest that fully verified - an
  outage or a refusal is asked again next visit, because it is not a fact about
  the pack. Both pages pass the same map, so a kind proved for More themes is
  free for Ringtones. Rows are still assembled in id order and the
  cap/`unverified` accounting is unchanged, so what is offered does not change.
  Tests: `app/test/settings/theme_packs_test.dart` — twelve signed packs with a
  50 ms manifest delay: all twelve offered from one read each, peak in-flight
  between 2 and 6, none left in flight, finished inside six delays (two
  waves); a second call with the same map reads nothing and returns the same
  rows; a revision the host adds reads only `synthwave@2`; a sound pack is
  counted unverified on the themes page and offered on the sounds page with no
  second read; one failing id still offers the other, and only the answered
  pack is remembered; and closing the autoDispose page provider and reopening
  it issues no manifest request. The fake host gained `manifests`,
  `manifestDelay`, `inFlight`/`peakInFlight` and a `failing` id set.
  Gate: the app's theme-pack file **51 green** (45 before), the sounds file
  **20 green**, the full app **1038 green** (1032 before), `flutter analyze`
  clean on the workspace. No wire change, no migration, no server change. A
  new APK carries the change.
- S6 (AUD-7-4) — `GET /v1/packs` walked the whole folder per request: every
  pack id, every revision, and every file twice (`length()` and `lastModified`),
  on a public route, with a fresh `PackHost` built per request so nothing
  survived between calls. A gallery browse by N clients was N walks, and a
  folder with many revisions made the list the most expensive thing those
  addresses could ask for.
  **What changed:** `PackHost` keeps the walk it made
  ([`_index`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/pack_host.dart#L56))
  and answers from it for `defaultListLifetime` (10 s); requests that arrive
  during a walk await the same one, and the list handed out is unmodifiable.
  The module now holds one `PackHost` for the node's life instead of
  constructing one per request. The lifetime is a field with a clock seam, so
  a test holds time still. A folder mtime is deliberately not the key: probed
  on this machine, Windows does not move a directory's mtime when a
  subdirectory is created (only for files) and its timestamps are
  one-second-resolution, so it would miss exactly the publish this route
  serves; the bounded lifetime is the honest bound and `ops/MODULE.md` states
  it. Reads did not change: the manifest and file routes still stat and open
  the file, so a stale index entry can only be a 404, never a wrong byte.
  Tests: `server/test/modules/packs_test.dart` — one walk serves identical
  lists inside the lifetime (a revision and a new id published meanwhile are
  not seen), the next walk after it sees both; three concurrent callers get
  the same list instance (one walk); and a revision deleted after the walk
  still misses its manifest read.
  Gate: the pack file **19 green** (16 before), `ops_admin_test` +
  `architecture_test` **32 green**, `dart analyze` clean on the changed files;
  the batch gate below is the full server suite. No wire change, no migration,
  no app change, no APK; a server restart (or the next deploy) picks it up.
  **Batch report.** All nine B10 findings are closed. B10's steps: S1
  `76c7649`, S2 `717b351`, S3 `e0ba939`, S4 `29a1573`, S5 `07fe963`, S6
  `7a4924f`. B10's gate: the full server suite **518 tests** on Postgres at
  `--concurrency=3`, 516 green; the two failures are the timing flakes already
  listed in `AGENTS.md` - `test/client/engine/devices_test.dart` "changing the
  password needs the current one..." and `messaging_test.dart` "a send that
  only reaches people who blocked you pays nothing" - and each was green alone
  straight after (5 s and 3 s). The full app suite **1038 green** (the theme
  file 51, sounds 20), orbit_ui **240 green**; `flutter analyze` clean on the
  workspace and `dart analyze server tool` clean. No migration, no wire change.
  **Residual, deliberate:** the server's pack list is an index with a 10 s
  lifetime, so a publish appears within it (reads never come from the index,
  so the worst case is a 404, not a wrong byte); the app's verified-kind map
  lives for the session, so a cold start re-probes each offered id once (at
  most 64, six at a time) and a failed probe is asked again next visit because
  an outage is not a fact about the pack. S1's token contract is the gate
  getting stricter on purpose: a signed theme missing any of the 111 required
  tokens, or naming one twice, is refused at install and a stored one is no
  longer offered - it could never have been drawn, and `remove` still deletes
  it. Interactive controls that sit beside a merged field now need their own
  `Semantics(container: true)` (S4's group picture): Flutter's sibling-merge
  compiler will otherwise absorb the button's node and bounds into the row's.
  **Owner-facing, whole batch:** no migration and no `.env` line. The server
  half (the pack list index) is picked up by a restart or the next deploy; the
  app half needs a new APK (the stricter theme gate, the field label/error
  semantics, controls that grow at large text, the theme fade fix, and the
  pack probe's bounded reads and session memory). Any pack published from now
  on must be built and signed with the current `theme_pack_tool.dart`, because
  the app now requires every token the generator emits.
- Next: B11 (realtime), then B12, B13, B16 and the later batches; B8 still
  waits on Q8/Q9 and B5 on Q6.

## B11 — Realtime sockets: one clock, one registration, one re-auth
**S · ~2–3 days · no migration (an index if the gauge needs one) · depends on B1**

**Closes:**
- AUD-3-4 — the 25 s route-refresh sweep has no in-flight guard and
  re-authenticates every socket serially.
- AUD-3-9 — realtime timers use the wall clock, not a monotonic clock.
- AUD-3-10 — a failure between registering the socket and `start()` leaves a
  socket that presence calls online.
- AUD-3-11 — the mailbox backlog gauge scans up to one million rows on every
  scrape.
- AUD-3-12 (suspected) — two near-simultaneous upgrades of one device can close
  the newest socket. Reproduce first; it is the only `suspected` finding.
- AUD-3-13 (Idea) — every open socket re-authenticates against Postgres every
  25 s. Decide with this batch: a node-level auth cache is the candidate, not a
  promise. (S6 decided against the cache; batch the check if scale demands it.)

**Why here:** one of these makes presence lie (3-10), one disables the
heartbeat after a clock step (3-9), and two are per-socket cost that grows
linearly with connections. All in the realtime module's sweep.

**Verification:** `server/test/modules/realtime_test.dart` — a failed `start()`
unregisters the route; a refresh sweep already running does not start a second;
a monotonic clock drives the timers (inject a stepping clock); two upgrades
leave exactly one live socket; the gauge query is cheap under an EXPLAIN
assertion; a re-auth cache (if adopted) never serves a revoked device.

**Rollout:** server-only. No wire change. If the gauge needs a partial index,
it is platform migration 5 or a messaging migration — choose whichever owns the
table at implementation time.
- S1 (AUD-3-4) — the 25 s sweep started a new pass on every tick, finished or
  not, and a pass awaits an ephemeral compare-and-set plus a token check (a
  database read) per socket, one socket at a time. A store or pool stall — or
  a node with thousands of sockets — therefore doubled that traffic at the
  worst moment, and a long enough stall could add a third pass on top.
  **What changed:**
  [`refreshConnections`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L220)
  is single-flight: a tick that arrives while a pass is still running returns
  at once and increments `helix_ws_refresh_skipped_total`, and a `try/finally`
  clears the flag so the next tick runs normally. `realtime/MODULE.md` states
  it. `allModules` (and `Harness.start`) gained a test-only authenticator
  override beside the existing SMS one, so a sweep can be held mid-pass.
  Tests: `server/test/modules/realtime_test.dart` gained a `refresh sweep`
  group: with one open socket and an authenticator gated after its first
  device check, a second `refreshConnections()` returns within a 2 s timeout,
  the device-check count stays at 1 and the counter reads 1; once the gate
  opens the held pass finishes and the following tick checks again (count 2).
  Gate: the realtime file **20 green** (19 before), `dart analyze` clean on
  the changed files. No wire change, no migration, no app change, no APK; a
  server restart (or the next deploy) picks it up.
- S2 (AUD-3-10) — `_accept` put the new connection in `_connections`, wrote
  its route and then started it. `start()` is also where the client's stream
  is listened to and the `hello` is sent, so if the route save, the
  `realtime.connected` publish or the first mailbox read threw, `track`
  merely logged it: the socket stayed registered and its route stayed in the
  store, so presence reported the device online, sends skipped its push and
  nothing reached the client until the 50 s idle close.
  **What changed:**
  [`_accept`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L289)
  now wraps the whole post-registration sequence (route save, previous
  socket's supersede close, publish, `start`) in a `try` whose catch closes
  the connection with 4503 and rethrows for the log. The route save moved
  ahead of the previous close: once the route names the new connection, a
  later failure's close takes that route with it, whereas closing first
  would leave the old route behind if the save then failed. The gateway can
  take its bus from a test (as it already takes the authenticator), so
  `allModules`/`Harness.start` gained a `realtimeBus` override.
  `realtime/MODULE.md` states the close and the cleanup.
  Tests: `server/test/modules/realtime_test.dart` gained a `registration`
  group: on a node whose bus publishes throw, one upgrade closes with 4503,
  the device's route key is gone and the open-connection gauge reads 0.
  Gate: the realtime file **21 green** (20 before), `dart analyze` clean on
  the changed files. No wire change, no migration, no app change, no APK; a
  server restart (or the next deploy) picks it up.
- S3 (AUD-3-9) — the frame-token bucket and the idle timer both diffed
  `DateTime.now()` against a wall-clock mark. A backwards step (an NTP
  correction, a manual change on the server PC) refilled the bucket by a
  negative amount, so the next ordinary frame could close a socket with 4029
  for no client misbehaviour; either direction also skewed the idle check.
  **What changed:** a monotonic
  [`Uptime`](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/clock.dart#L32)
  (`StopwatchUptime`, next to `Clock`/`ManualClock`) is now the only source for
  both marks: `_frameAt` and `_lastHeard` are `Duration`s read from it,
  [`_onFrame`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L472)
  clamps a negative elapsed to zero before refilling, and
  [`checkIdle`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L583)
  subtracts the same source. `hello`'s `server_time` still uses the wall clock,
  as the wire requires. `RealtimeModule` takes an uptime override (beside the
  authenticator and bus ones), so a test can step it;
  `allModules`/`Harness.start` pass `realtimeUptime`. `realtime/MODULE.md`
  states the split.
  Tests: `server/test/modules/realtime_test.dart` gained a `timing` group with
  a `ManualUptime`: stepping it back an hour, five pings still answer with
  pongs and a sweep neither rate-limits nor idles the socket; advancing it 51 s
  and sweeping then closes it with 4010, proving the same source drives the
  idle timer.
  Gate: the realtime file **22 green** (21 before), `dart analyze` clean on
  the changed files. No wire change, no migration, no app change, no APK; a
  server restart (or the next deploy) picks it up.
- S4 (AUD-3-12) — reproduced, confirmed, and fixed. Two upgrades of one
  device accepted close together could leave no live socket: `realtime.connected`
  was delivered with the *older* connection's id after the newer one was in
  `_connections`, and the subscriber closed on "id differs", taking the newest
  socket down. The same interleaving could also let the older accept write its
  route after the newer one, so presence pointed at the wrong connection until
  the next sweep. The audit's sketch (a connection generation) does not hold on
  its own: UUIDv7 ids minted in the same millisecond are not strictly ordered,
  so id comparison can still call the newer socket older.
  **What changed:** accepts for one device are serialized by a per-device
  [`_acceptTails`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L64)
  turn, so the map write, route save, previous close and bus hint happen in
  accept order ([`_register`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L337)/[`_registerNow`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L360);
  a failed accept never fails the one queued behind it). The
  [`realtime.connected`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/realtime/module.dart#L157)
  subscriber now closes the local socket only when the route no longer names
  it, so a lagging hint for an older accept cannot close a newer socket; its
  own publish is skipped without a store read. `realtime/MODULE.md` states
  both.
  Tests: `server/test/modules/realtime_test.dart` gained an `upgrade race`
  group with a `_HeldBus` that holds `realtime.connected` hints: after two
  concurrent upgrades exactly one socket answers a ping, and when both hints
  are released the same socket still answers while the other is closed. Before
  the fix the test failed at exactly that point ("the hint for the older
  connection must not close it", actual false).
  Gate: the realtime file **23 green** (22 before), three repeats of the race
  test green, `dart analyze` clean on the changed files. No wire change, no
  migration, no app change, no APK; a server restart (or the next deploy)
  picks it up.
- S5 (AUD-3-11) — the `helix_mailbox_backlog` collected gauge ran
  `SELECT count(*) FROM (SELECT 1 FROM mailbox LIMIT 1000000)` on every
  scrape: a bounded but expensive index-only walk of every partition, on the
  node an operator is watching, during exactly the incidents that produce a
  backlog. `device_seq.pending` already counts the same undelivered rows
  transactionally (quota, trim, ack, expiry and device purge all settle it -
  AUD-3-2), so the mailbox need not be walked at all.
  **What changed:** [`MailboxStore.backlog`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L208)
  sums `pending` where it is positive - one narrow row per device that ever
  got mail - and the
  [gauge](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L46)
  reads it. No partial index on `pending`: the table is bounded by the device
  count, whereas an index on the column every send increments would turn each
  send's update into a non-HOT one (the migration the batch allowed is not
  needed). `messaging/MODULE.md` states the source.
  Tests: [`query_plans_test.dart`](file:///J:/Projects/helix/helix_remote/server/test/platform/query_plans_test.dart#L204)
  runs the store method through the recording session on the seeded 20,000
  device schema, checks the reply is the 50,000 seeded pending envelopes, and
  asserts the `EXPLAIN (FORMAT JSON)` plan's only sequential scan is
  `device_seq` - no mailbox partition appears. The case is declared before the
  send and ack cases, which change pending counts (in the first full run it
  ran after them and read 49,855). The metrics-route test
  (`hardening_db_test.dart`, D4) still reads `helix_mailbox_backlog 0.0` on an
  empty schema.
  Gate: the plan test green, the D4 metrics test green, `dart analyze` clean
  on the changed files. No wire change, no migration, no app change, no APK; a
  server restart (or the next deploy) picks it up.
- S6 (AUD-3-13, Idea) — **decided: no node-level auth cache.** The sweep's
  per-socket `authenticator.device(token)` is the backstop for a revocation,
  session cut-off or suspension whose bus hint was missed while the LISTEN
  connection was down; a cache that lives until the token's `exp` (or until
  the next resync) widens that window for as long as the listener is down,
  and the bus's own contract only says a missed hint delays work until the
  next poll or reconnect. Caching for one sweep interval would not remove a
  query, so the only cache worth having is one that weakens the backstop. The
  finding is an Idea on a single-PC server where the sweep is one indexed
  lookup per socket (and the route CAS stays on the timer regardless); it is
  not worth that trade. If socket count ever makes the sweep cost matter, the
  direction is one batched token check per sweep (the same exact
  re-validation for N sockets in one query), not a cache - recorded in
  `realtime/MODULE.md` so the next reader does not re-litigate it. No test is
  owed: there is no cache to prove safe. No wire change, no migration, no app
  change, no APK.
  **Batch report.** All six B11 findings are closed (five fixed, AUD-3-13
  declined with the reason recorded). B11's steps: S1 `9c208ec`, S2 `a7178c4`,
  S3 `75a2a1f`, S4 `900d0f1`, S5 `c97ed02`, S6 `0f62a29`. B11's gate: the full
  server suite **523 tests** on Postgres at `--concurrency=3`, 519 green in the
  run; three failures were load flakes already known here or listed in
  `AGENTS.md` (`calls_test.dart` "non-offer signals are limited per sending
  device" green alone in 3 s, `messaging_test.dart` "a send that only reaches
  people who blocked you pays nothing" green alone in 4 s, and
  `hardening_db_test.dart` "stored idempotent responses are sealed and still
  replay" green alone in 18 s - the latter two are now in the known list).
  The fourth was this batch's own new case: the backlog gauge case was declared
  after the send and ack cases in its group, which change `device_seq.pending`,
  so it read 49,855 instead of the 50,000 seed; it now runs first and the file
  is **8 green** alone. `dart analyze server tool` clean on the whole
  workspace. No migration, no wire change, no app change, no APK.
  **Residual, deliberate:** supersede is decided by the route, not by the hint
  (UUIDv7 ids in one millisecond are not ordered), so a hint is only a
  wake-up and a stale one costs one ephemeral read; accepts are serialized per
  device, so a slow accept delays only the next socket of the same device. The
  backlog gauge sums `device_seq.pending` with no index on purpose: the table
  is bounded by the device count, while an index on the column every send
  updates would turn each send's increment into a non-HOT update. The 25 s
  per-socket re-auth stays uncached; if socket count ever makes it matter, the
  direction is one batched token check per sweep.
  **Owner-facing, whole batch:** server-only, no migration and no `.env` line;
  a restart (or the next deploy) picks it up.
- Next: B12 (protocol refusals), then B13, B16 and the later batches; B8 still
  waits on Q8/Q9 and B5 on Q6.

## B12 — The protocol must refuse what it cannot represent
**W · ~2–3 days · no migration**

**Closes:**
- AUD-8-2 — an unknown conversation kind is a hard decode failure, unlike an
  unknown body.
- AUD-8-3 — an unknown device-transfer state decodes as `cancelled`: a lie
  that can lose a transfer's real state.
- AUD-8-4 — an unknown error code is never retryable, against the catalog's own
  rule.
- AUD-8-5 — golden fixtures pin 9 shapes; the rest of the wire has only
  round-trip tests.
- AUD-9-1 — stored crypto state decodes any-length keys and any counters, so a
  damaged row either wedges a peer or silently breaks its ratchet.
- AUD-9-2 — `DeviceSessions` has two serializations; the one the app stores
  lives in the engine and the other is dead.

**Why here:** these are wrong-data bugs, not crashes: a value the code cannot
represent becomes a plausible wrong value. They are all in the two shared
packages, so one release order covers them.

**Structure:** split `content/bodies.dart` with an explicit body registry (S7
in [08_protocol.md](file:///J:/Projects/helix/orbit/audit/08_protocol.md)); a
dedicated corrupt-local-crypto failure type (S9-1 in
[09_crypto.md](file:///J:/Projects/helix/orbit/audit/09_crypto.md)); one
`DeviceSessions` serialization, in the package that owns the type.

**Verification:** protocol round-trip and unknown-tag cases for every
discriminator; new golden fixtures for the new variants (deliberate
`HELIX_UPDATE_FIXTURES=1`); crypto vectors for bad key lengths and counters;
a store test that a damaged row raises the new failure type rather than
wedging.

**Rollout:** wire-adjacent but shape-compatible — valid values are unchanged.
Server first (it decodes inbound), clients next. An older client that receives
a new `unknown` error code treats it as non-retryable, which is safe.
- S1 (AUD-8-2) — an unknown conversation kind was a hard
  `ProtocolFormatException`, so a message from a newer client was
  committed-then-quarantined as `bad_content`: a "couldn't decrypt" row in the
  sender's direct chat that could never resolve, because there is no body to
  repair. **What changed:** [`ConversationRef.fromJson`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/content_message.dart#L13)
  now returns [`UnknownConversation`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/content_message.dart#L64)
  for any kind other than `direct`/`group`, keeping the whole `conv` object so
  `toJson()` re-encodes it unchanged (the kind itself must still be a string).
  The engine already resolves a chat only from a direct or group ref
  (`_chatOf`), so the content is acknowledged and ignored (`misaddressed`) with
  no row and no reset request - the honest outcome, since this version has no
  chat to file it in; the group pipeline likewise marks it ignored. No server
  change: the server never decrypts content.
  Tests: `content_test.dart` decodes `{"kind":"channel","channel":"c-1",
  "thread":7}` at `v:2`, asserts the unknown ref carries the kind and that
  `toJson()['conv']` is the same map; `inbound_test.dart` sends one from Alice
  (which also proves the outbox payload, decoded through the same
  `ContentMessage.fromJson`, still sends) and asserts Bob's sync has no notice,
  no `EnvelopeQuarantined`, no row in Alice's chat, the envelope marked
  processed and the mailbox empty.
  Gate: protocol `content_test.dart` **54 green** (53 before), engine
  `inbound_test.dart` **28 green** (27 before), `flutter analyze` clean on the
  workspace. No migration; valid wire shapes unchanged; an app needs the new
  package to stop quarantining such messages.
- S2 (AUD-8-3) — an unknown `state` on a `device_transfer_offer` decoded as
  `cancelled` (`optEnum(..., orElse: cancelled)`), the one destructive default
  in the package: a mixed-version pair had its live transfer aborted with no
  error, because a newer own device wrote a step this client did not know.
  **What changed:** [`DeviceTransferState.unknown`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L1155)
  is the decode fallback, and
  [`TransferInbox.apply`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/inbox.dart#L46)
  ignores it (returns false, so the envelope is recorded as ignored) instead
  of touching the ledger. `toJson` omits it exactly like `offer`, deliberately:
  writing a literal `unknown` would be read as `cancelled` by a client that
  predates this fix - the outcome being removed. Known states are unchanged,
  and state absent still means offer.
  Tests: `content_test.dart` decodes `state: "importing"` as `unknown` and
  asserts no `state` key on re-encode; `transfer_test.dart` offers history
  from Alice to Alice2, then Alice sends a crafted `device_transfer_offer`
  with the real transfer id and `state: "importing"` through `debugSendRaw`,
  and Alice2's offer must stay `waiting`. The engine test was confirmed to
  fail with the old default restored (the first draft passed for the wrong
  reason - it used a placeholder transfer id that matched nothing; the test
  now uses the id `offer()` returned).
  Gate: protocol `content_test.dart` **55 green** (54 before), engine
  `transfer_test.dart` **19 green** (18 before), `dart analyze` clean on both
  changed packages. No migration; no server change; an app needs the new
  package.
- S3 (AUD-8-4) — a parsable error body naming a code this client does not know
  became `ErrorCode.unknown`, whose `status` is 500 and whose `isRetryable` is
  false, even when the response was really a 503 or a 429: the header promises
  old clients judge unknown codes by HTTP status class, but only an
  *unparseable* body got that treatment.
  **What changed:** [`ApiException.isRetryable`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/errors.dart#L109)
  answers an unknown code from the status actually received (`429` or `>= 500`
  retryable, any other 4xx not); known codes keep the catalog's answer. The
  transport's own retry loop now asks the exception
  ([`transport.dart`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L272)),
  not `code.isRetryable`, so an unknown code on a transient status is retried
  in place as well as by callers. `ApiError` does not gain a status field: the
  only body-only parser is `ApiException`, which already keeps the real one.
  Tests: `transport_test.dart` adds an unknown code on 503 (retried once, then
  a 204 passes) and on 400 (one attempt, thrown with `isRetryable` false).
  Gate: `transport_test.dart` **46 green** (44 before), `dart analyze` clean on
  the package. No wire change, no migration; an app needs the new package.
- S4 (AUD-8-5) — the golden fixtures pinned 9 shapes while every other DTO had
  only self-consistent round-trip tests, which cannot notice both sides of the
  wire moving together: a field renamed in the DTO and its test still passes,
  while the server and an older client disagree.
  **What changed:** [`fixtures_test.dart`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/test/fixtures_test.dart#L154)
  now holds **164 fixtures** (nine unchanged, 155 new): every content type, the
  server and client realtime frames plus an unknown server frame, all top-level
  request/response DTOs of identity, keys, messaging, people, groups, calls,
  media, backup, ops, admin and federation, and the WebSocket close-code map
  written out so renumbering one fails. Each file is generated from its
  constructor (`HELIX_UPDATE_FIXTURES=1`) and re-decoded in the same test, so
  the stored bytes stay the contract. Three completeness tests make a new shape
  fail until it has a fixture:
  [`ContentBody.knownTypes`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L109)
  (additive; the decode switch's 24 types, each checked to reach a real body
  decoder rather than `UnknownBody`), the frame table, and the close codes.
  Deliberately not fixtures: `AccountAddress` (no JSON codec), `Page<T>` (not
  a DTO class), and value types pinned inside their parents. No wire or stored
  change; the nine existing fixture files are byte-identical.
  Gate: `fixtures_test.dart` **167 green** (9 before), full protocol suite
  **281 green**, `dart analyze` and `dart format` clean. No migration; no
  server or app change (both already speak these shapes).
- S5 (AUD-9-1 + S9-1) — the stored-state factories read keys and counters with
  no length or range check: HKDF and HMAC take a key of any length, so a
  damaged `rk`/`cks`/`ck` loaded, encrypted under a chain the peer could never
  derive and committed the advance, while a damaged `dhr` wedged sends forever
  (the record stayed, and a reset could not overwrite it).
  **S9-1:** [`CorruptStateException`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/errors.dart#L30)
  (`requestsSessionReset = true`) is raised only at the local decode boundary:
  `decodeStateJson`/`readState`, `requireVersion`, the key-pair `restore`
  helpers (now via `requireStateLength`), and the state factories, which
  validate every field AUD-9-1 lists - `rk`, `cks`, `ckr`, `dhr`, skipped
  `mk`/`dh`, sender `ck`/`sig_pub`, `remote_dik`/`remote_aik`/`local_dik`/
  `base_key`, retired keys and prekey restores as 32 bytes, and `ns`, `pn`,
  `nr`, `it` as `u32`
  ([`codec.dart`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/codec.dart#L43)).
  The two wire paths that used the local codec now call `readWire`, which
  keeps `MalformedCryptoInputException`: provisioning's `DeviceIdentity`
  and the server-fetched `BackupEnvelope`.
  **AUD-9-1:** [`DbSessionStore.load`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/db_stores.dart#L28)
  catches the new type and drops the record with a compare-and-set
  ([`CryptoDao.deleteSessions(expectedVersion:)`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/crypto_dao.dart#L110))
  - a plain delete could erase a good record another engine just wrote - and
  reports no session, so the send path starts and stores a fresh one.
  [`DbSenderKeyStore`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/sender_key_store.dart#L39)
  drops a damaged own key (the protocol then creates and distributes a new
  one) or a damaged received key (the message is reported unreadable and the
  sender redistributes), instead of failing every group send or read.
  Tests: crypto `session_test.dart` decodes a state with a 16-byte `rk`/`cks`/
  `ckr`/`dhr`, out-of-range and non-integer counters and a missing `rk`, and
  `sender_keys_test.dart` a 16-byte `ck`, a 31-byte `sig_pub` and an `it` past
  `u32`; the unsupported-version expectation moved to the new type. Engine
  `util_test.dart` writes a 16-byte `rk` into alice's stored session and
  asserts the next send rebuilds the record and bob reads both texts.
  Gate: crypto **77 green** (74 before), engine **352 green**, db **140
  green**, `dart analyze` clean on crypto, db, engine and cli. No wire or
  stored-format change (the bytes written stay identical); no migration; an
  app needs the new packages.
- S6 (AUD-9-2) — `DeviceSessions` had two serializations. The crypto one
  (`toJson`/`fromJson`/`encode`/`decode`) wrote one JSON document holding
  `remote`, `active`, `previous[]` and `retired[]`; production
  [`DbSessionStore`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/db_stores.dart#L22)
  wrote six rows instead - slot 0 `{v, retired[], active}`, slots 1-5 one
  `PairwiseSession` each, the remote from the row key - and never called the
  crypto codec, which only crypto tests and the crypto fake used. So a change
  to the stored envelope could be made in the type, proven green by
  `session_test.dart`, and leave the bytes the app writes untouched.
  **Fix:** the slot codec is the package that owns the type's -
  [`DeviceSessions.encodeSlots()` / `decodeSlots(remote, slots, {version})`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/session.dart#L252)
  - `DbSessionStore` encodes and reads through it (its own statics and three
  imports are gone) and the document codec is deleted, with no caller left.
  `decodeSlots` decodes under `readState`/`requireVersion`, so a slot with an
  unknown `v` or a bad field is a `CorruptStateException` and takes S5's
  drop-and-rebuild path; the engine copy had thrown
  `MalformedCryptoInputException` there, which would have wedged every send
  to that device.
  Tests: the crypto fake in [`support.dart`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/test/v2/support.dart#L53)
  now stores `List<Uint8List>` slots and round-trips through the codec, so
  every crypto test pins the bytes production writes; a new
  `session_test.dart` test builds a record with five previous sessions and
  asserts six slots, slot 0's `v`/`retired`/`active` keys, each other slot a
  session of its own, and a byte-identical round trip; the damaged-field test
  writes into slot 0 as the store does. The engine CAS test still pins the
  store (`two_engines_test.dart`), now through `encodeSlots()`.
  Gate: crypto **78 green** (77 before), engine **352 green**, db **140
  green**, `dart analyze` and `dart format` clean on crypto and engine. Stored
  bytes, wire format and schema unchanged; no migration; the app and CLI get
  it from the packages.

## B13 — Local maintenance must survive a large history
**A · ~1–2 days · no schema change**

**Closes:**
- AUD-10-1 — bulk maintenance deletes bind every row id in one statement;
  past SQLite's parameter limit the delete throws and maintenance stops
  rescheduling.
- AUD-10-2 — `HistoryStore.backupableCount` emits `NOT IN ()` for an empty
  exclusion list, which SQLite rejects.
- AUD-10-3 — a thumbnail job converted to a download while a worker holds it is
  marked done by the thumbnail worker; the download never runs.
- AUD-10-4 — `enqueueStandalone` returns an old job for a reused purpose and
  keeps its stale path.
- AUD-12m-1 (P3, appended) — the Storage page and "free up space" count and
  delete the device's copies of *sent* media; re-fetching works only while the
  server keeps the object (30 days), so freeing an old chat makes the app's copy
  of the user's own photos permanently unavailable.
- AUD-12m-2 (P3, appended) — `MediaService.cancel` reads the attachment and the
  job before its transaction; a download that completes in the gap is reset to
  "not downloaded" with its file still on disk (and one orphaned file after the
  next download).
- AUD-12m-3 (P3, appended) — `TransfersService.retryFailed` runs every job's
  retry, including the send path's nested transactions and outbox holds, inside
  one outer write transaction on SQLCipher's single connection.
- AUD-12m-4 (Idea, appended) — three media-kind classifiers
  (`_photoKinds`/`_documentKinds`, `MediaSettings.forKind`, the storage `else`
  branch) already disagree; a future kind is counted but cannot be freed.
- AUD-12n-1 (P3, appended) — `TransferWorker.stop()` is not a barrier: its one
  cancellation sweep can miss a job that `_fill` claimed across it, and the new
  attempt never looks at `_active`, so a job starts after the worker stopped.
- AUD-12n-2 (P3, appended) — once a lease lapses, `due()` makes the in-flight
  job claimable again and `_fill` does not exclude ids it is already running;
  the old heartbeat keeps renewing the new lease (same id, still in-flight), and
  both attempts share the same `up-$jobId`/`dl-$jobId` staging file.
- AUD-12n-3 (P3, appended) — a permanent local I/O error (disk full, a
  read-only path, a permission change) has no classifier and falls to
  `internal`, which retries until the 30-day `maxAge`, while the message's held
  outbox op blocks every later message in that chat.
- AUD-12o-2 (P3, appended) — a failed upload keeps its whole ciphertext in
  `up-<jobId>` for ever: the janitor keeps the staging of any job not `done`,
  and nothing else deletes it except cancelling the message. A full quota or a
  30-day give-up therefore leaves one invisible copy per failed send.
- AUD-12p-1 (P3, appended) — a history offer stays on the receiving device for
  its 7-day `offerTtl`, but the sender deletes the relay objects at 48 h
  (`relayTtl`), so accepting on days 3-7 always ends `expired` and the sender
  no longer knows the transfer existed.
- AUD-12p-2 (P3, appended) — the auto-offer cursor is written *before* `send`
  and every failure is swallowed, so a device that joins while the designated
  sender is offline is never offered history by any device (recovers only if
  another device links or the sender is revoked).
- AUD-12p-3 (P3, appended) — a pause turns the offer into `waiting` with no
  error, which is exactly the shape `_resumeOffers` calls "fresh"; the pause's
  own ledger write wakes that hook, so with `autoAcceptTransfers` on the
  transfer restarts immediately.
- AUD-12p-4 (P3, appended) — `watchOffers` reports zero segments fetched while
  a download runs, and the app's receiving rows read only that stream, so a
  receiving transfer shows no progress (and no "Resume" affordance) until the
  import phase.
- AUD-12q-1 (P2, appended) — a message deleted for me, a cleared chat or a
  deleted chat removes rows and writes no tombstone, so the next restore — or
  the automatic version-conflict catch-up — inserts them back with unread +1.
- AUD-12q-2 (P3, appended) — the archive records nothing about a truncated
  export: `BackupResult.truncated` is write-side only, `RestoreResult` has no
  flag, and the app reads `added` alone, so a capped restore looks complete on
  both ends.
- AUD-12r-2 (P3, appended) — a receive interrupted by a process kill (or by an
  error `translate` does not classify) stays `downloading`/`importing`: nothing
  resumes it, and the only button those stages offer is Pause, which is a no-op
  without a live run.
- AUD-12r-3 (P3, appended) — the sending side of a transfer lives only in a
  non-replaying event stream: the sender never learns the receiver's done or
  declined answer, and after a restart an outstanding offer has no row and
  cannot be cancelled.
- AUD-12r-4 (P3, appended) — the twenty-first unanswered offer is refused by
  `maxOffers` and dropped in silence on both sides.

**Why here:** local-only, but each is a job that silently stops doing its work
for a large history — the class of bug a person notices only when storage fills
or a transfer never completes.

**Structure:** "delete this set" as a statement or a chunked loop (S10-1 in
[10_db.md](file:///J:/Projects/helix/orbit/audit/10_db.md)); a transfer job gets
an immutable identity and a claim token (S10-2); `HistoryStore` moves inside
the DAO/codegen boundary (S10-3). The four 12m findings ride the same seam: the
free-space query gains an `outgoing = 0` condition, `cancel` moves its whole
decision inside the transaction, `retryFailed` drops its outer transaction, and
one kind-group mapping replaces the three classifiers. The three 12n findings
are the same claim token: `_fill` re-checks `_active || _draining` after the
claim and releases what it cannot start (and `stop()` loops until `_running`
is empty); `claim` excludes the ids this worker already runs, and a failed
renewal ends the attempt instead of being swallowed; the classifier gains a
terminal local-I/O outcome, so a full disk fails the message once instead of
holding the chat for 30 days. And the sweep ages out the staging of a *failed*
upload (its plaintext source is still in the media area, so a retry re-encrypts;
a download's staged bytes are kept, since they cost a re-download). The four
12p findings ride the backup transfer's own bookkeeping: the receiving offer
ages out with the relay objects it points at (`min(offerTtl, relayTtl)`), the
auto-offer cursor is written only after `send` returns (with an in-flight guard
taking over the duplicate protection the early write provided), "fresh" means
never started (`segments == null && imported == 0`) with a persisted `paused`
flag, and `IncomingOffer` gains a fetched-segment count that `watchOffers`
reports while downloading. The two 12q findings add one local-only table and
one trailing record: a tombstone table (message id + author, and deleted
conversation ids) written by the three delete paths and consulted by the
importer, never exported; and a final `{'t': 'end', 'truncated': true}` record
that readers already skip as unknown, surfaced through `RestoreResult` and the
recovery page instead of only `added`. The three 12r findings are one state
machine for both directions (S12r-2 in
[12r_transfer_receiver.md](file:///J:/Projects/helix/orbit/audit/12r_transfer_receiver.md)):
`downloading`/`importing` with no live run go back to `waiting` at start-up
(keeping `imported` and the chunks), `translate` learns the transport's other
exceptions so every failure lands in a terminal phase, a failed receive gets
its own answer state instead of `declined`, the outgoing ledger gets the same
`watchOutgoing` view the incoming one has (and seeds the app's rows), and
`recordOffer` distinguishes "duplicate" from "full" so a refused offer can be
reported.

**Verification:** `packages/helix_remote_db/test/` — delete 2,000+ rows through
the maintenance pass; an empty exclusion list counts; a job converted mid-flight
runs once; a reused purpose gets a new row and path. Plus
`packages/helix_remote_engine/test/transfers/` — a sent photo is not freed and
not counted as downloaded; a completion that races `cancel` stays `ready` with
its path; a batch retry leaves the connection free for a concurrent progress
write; every kind the storage page counts in `filesBytes` is freed by
`FreeKind.documents`; a `stop()` that overlaps a claim leaves no running job and
the job is claimable again; a job whose lease lapses while its heartbeat fails
is not started twice; a disk-full write fails the message and its held op at
once, and the next message in the chat sends; a `quotaExceeded` upload aged past
`sweepGrace` loses its `up-<id>` staging while its source stays, and a retry
re-encrypts; a receiving offer older than `relayTtl` is dropped even when
`offerTtl` is longer, and accepting one that is gone says `expired` and removes
the row; an auto-offer whose send fails leaves the cursor behind the new
device and a second `OwnDevicesChanged` sends it; a paused transfer under
`autoAcceptTransfers` stays `waiting` through a maintenance pass and a ledger
tick, and only `acceptOffer` resumes it; `offers()` reports the segments
already fetched while a download is stopped, not zero. And in
`packages/helix_remote_engine/test/backup/` — a message deleted for me, a
cleared chat and a deleted chat stay gone through `restoreFullBackup` and
through a version-conflict `_catchUp`, while a message deleted for everyone on
another device still lands; an export stopped by `maxHistoryBytes` writes the
end record, and `RestoreResult.truncated` (and the page's copy) says so. And
for 12r: a service started over a database holding a `downloading` or
`importing` offer shows it as `waiting` and `acceptOffer` finishes it; a relay
throwing `ResponseTooLargeException` leaves a terminal phase with a named
failure; the sender's row shows Done and Declined after the other device
answers, and a tampered segment reads as "could not be received"; with 20
incoming entries a 21st offer is recorded after evicting a finished one, and a
duplicate still changes nothing.

**Rollout:** app/package only. If a job column is added, drift schema 5 with a
step migration, regenerated dump and codegen (`tool/codegen.dart`, CI
`--check`); the delete tombstones take the same schema step (one table, plus
the migration and dump that go with it).

## B14 — Identity: charge for texts that left, cap devices, name the owner
**S · ~2–3 days · no migration · depends on Q7**

**Closes:**
- AUD-2-1 (P2) — a failed text spends the number's hourly allowance and the
  server's whole daily budget; an SMS outage outlives itself.
- AUD-2-2 (P2) — nothing bounds the devices an account can hold; key bundles,
  fan-out and prekey storage grow without bound.
- AUD-2-3 — `IdentityContext.revokeDevice` accepts an account id and never uses
  it (a cross-account action would look correct at the call site).
- AUD-2-4 — every authenticated request runs an `UPDATE` that almost always
  changes nothing.
- AUD-2-5 — a link long-poll reads the ephemeral store four times a second.
- AUD-2-6 — the one-time-prekey gap marker is set even when no key was handed
  out.
- AUD-2-8 — the verification-token purpose is only enforced when registering.
- AUD-7-1 — a wrong trusted-proxy setting turns the per-address sign-in lock
  into a shared lock on everyone (an unrelated actor can lock every account out
  by failing sign-ins).

**Why here:** 2-1 is an outage multiplier and 2-2 multiplies B2's fan-out;
7-1 is a single config line that turns a per-address defence into a global
denial of service.

**Structure:** charge the budget for texts that left (S2 in
[02_identity_keys.md](file:///J:/Projects/helix/orbit/audit/02_identity_keys.md));
a device registry with a cap owned by identity (S1); identity primitives take
the owner explicitly (S3).

**Verification:** `identity_test.dart` — a provider failure leaves no charge and
no challenge row; the cap refuses with `quota_exceeded`; revoke of a device not
belonging to the account is refused; a verification token for the wrong purpose
is refused. A config test refuses a contradictory trusted-proxy setting at
start-up. `keys_test.dart` — the gap marker is written only when a key was
handed out.

**Rollout:** server-only. No migration (a count under a per-account lock).
`quota_exceeded` is an additive error code; clients treat unknown codes as
non-retryable. The trusted-proxy rule becomes a start-up check — check the
production environment's proxy header setting before deploying.

## B15 — People, reports and the export must be honest about their bounds
**S + W (additive) · ~3 days · people module migration · depends on Q3**

**Closes:**
- AUD-4a-5 — report notes are free text that outlive the account, contradicting
  the "ids only" claim.
- AUD-4a-6 — report intake checks neither the subject nor duplicates, and open
  reports never expire.
- AUD-4a-8 — the account export silently truncates reports filed at 500.
- AUD-4a-2 — account-deletion purge scans the whole contacts table.
- AUD-4a-7 — `openReportsAbout` has no index on `reports.subject`.
- AUD-7-2 — the account export is assembled in memory with one unbounded
  section (the media list).
- AUD-7-3 — cursor paging uses `(@cursor IS NULL OR id < @cursor)`, which no
  index can serve.

**Why here:** a privacy claim the data contradicts (4a-5) and a data-subject
right that silently returns partial data (4a-8, 7-2). The index work is the same
migration.

**Structure:** export sections get a budget and say what was left out (S5 in
[07_ops_admin_compliance.md](file:///J:/Projects/helix/orbit/audit/07_ops_admin_compliance.md));
the purge is a statement, not a scan (with B13's shape).

**Verification:** `people_test.dart` — a report with a missing/unknown subject
or a duplicate is refused; an open report expires; the deletion purge uses the
index (EXPLAIN from B1). Export test — `truncated` and `total` appear exactly
when a section was capped. `ops_admin_test.dart`'s paging covers a
50,000-row account in the B1 EXPLAIN harness.

**Rollout:** people migration (subject index, report expiry, note column
removed or bounded — note that removing a column needs the contract step a
release later). The export gains `truncated`/`total` per section: additive, so
any consumer ignoring them is unaffected.

## B16 — Group data and federation: one writer, one owner
**S · ~2–3 days · groups module migration · depends on B3**

**Closes:**
- AUD-4c-1 (P2) — a member server checks the cached roster version outside any
  row lock, so an older snapshot can overwrite a newer one and re-add a removed
  member to its local cache.
- AUD-4c-4 — an S2S action's `actorDevice` is trusted without checking it
  belongs to the actor.
- AUD-4c-2 — `remote_devices` rows are never cleaned when a group is deleted.
- AUD-4c-3 — `joined_at` is the transaction timestamp and `members()` has no
  tiebreak, so "oldest" is arbitrary.
- AUD-4c-5 — roster syncs are not coalesced and a replayed sync re-delivers its
  event.
- AUD-4c-6 — leaving remote groups depends on a one-shot job that gives up
  silently (the mechanism is B3's; this is the group-side verification).

**Why here:** 4c-1 is a security-adjacent cache race (a removed member can
reappear) and 4c-4 trusts an identity claim from a peer; the rest are the same
store's lifetimes.

**Structure:** federation state gets explicit lifetimes and one reconciliation
(S2 in [04c_groups_data.md](file:///J:/Projects/helix/orbit/audit/04c_groups_data.md)).

**Verification:** `group_federation_test.dart` — a stale-version sync cannot
overwrite a newer cache; an `actorDevice` not owned by the actor is refused; a
replayed sync is idempotent and coalesced. `groups_test.dart` — delete cleans
`remote_devices`; `members()` has a deterministic order; a leaving member
retries to completion.

**Rollout:** groups migration (cleanup FK, deterministic ordering); the S2S
check is stricter but wire-compatible (it refuses what was never valid). No
app change.

## B17 — Sign-in and backup: the copy and the code must agree
**A · ~2–3 days · no migration · depends on Q4, Q5**

**Closes:**
- AUD-15-1 — a national number typed with its trunk zero becomes a different
  E.164 (a person cannot sign in with the number they know).
- AUD-15-2 — the lockout time is read in seconds but the wire carries
  milliseconds.
- AUD-15-3 — a third copy of the legal version, which is never sent.
- AUD-15-4 — "This number already has an account" is unreachable in the path it
  is written for.
- AUD-15-5 — the post-sign-in doc says a take-over asks for the restore step;
  the code does not, and cannot usefully.
- AUD-15-6 — a flow controller writes state after its page is disposed.
- AUD-15-7 — the backup doc says the recovery secret is made by the app and can
  be typed; the code only ever wraps it.
- AUD-15-8 — a transfer's failure cannot be cleared through `copyWith`.
- AUD-12q-3 (P3, appended) — a full backup made under an earlier identity is
  merged into the phone and only then refused as `accountMismatch`; the person
  is told "this backup cannot be opened" about a restore that already happened.

**Why here:** 15-1 is a sign-in failure for everyone who types a local format,
15-2 shows a wrong duration at the moment trust matters, and 15-3/5/7 are
promises the code does not keep. All app-only, one release.

**Structure:** one failure-copy layer (S15-1 in
[15a_features_sign_in.md](file:///J:/Projects/helix/orbit/audit/15a_features_sign_in.md));
numbers assembled through the normaliser (S15-2); page-scoped controllers for
flows that outlive the page (S15-3). Q4's fallback and Q5's cost prompt land in
the restore flow here. 12q-3 is one branch plus copy: the gateway stops
throwing after the merge (the archive's secrets are unused, as its own comment
says) and the page says the backup was made under an earlier key and reports
what was restored.

**Verification:** `phone_numbers_test.dart` — trunk-zero formats, E.164 input
and paste, all with the same result. `sign_in_flow_test.dart` — the lockout
message shows the right unit; the take-over copy matches the flow. Backup tests
— a page disposed mid-flow writes nothing; a failed transfer can be retried; a
recovery restore under a new identity reports the messages it added and names
the key change instead of refusing after the merge. A real-device check for a
national-format number (the OS keyboard and the SMS code are not simulated).
Docs updated in the same change (15-5, 15-7).

**Rollout:** app-only. No server change. If 15-4's copy is removed, the server
message stays as it is.

## B18 — Admin console: never strand the operator or destroy the only code
**A · ~1–2 days · no migration · no server change**

**Closes:**
- AUD-17a-1 — a storage fault at start-up strands the console on the launch
  screen forever.
- AUD-17a-2 — a transient failure at launch makes a still-valid saved session
  unusable until restart.
- AUD-17a-3 — the segmented bar's segments are 44 px, under the 48 px rule the
  console's own tests claim to enforce.
- AUD-17b-1 — resolving a report under the "All" filter can throw `StateError`
  and leave the card open after the server accepted it.
- AUD-17b-2 — the "shown only now" code dialog can be dismissed with the
  Android back gesture, destroying the only copy of the code.
- AUD-17b-3 — the audit trail's kind filter can hide "Load more", so later
  matching events are unreachable.
- AUD-17b-4 — a refresh overlapping a config change can put the old value back
  on the switches.
- AUD-11c-2 — admin sign-out keeps the token when the server call fails, so an
  offline operator stays signed in.

**Why here:** operator-only, but 17b-2 is unrecoverable for the person in front
of it and 17a-1 is a console that cannot be opened. The console is not in the
phone's release path, so it lands independently.

**Structure:** filter the audit trail before paging, not after (proposal in
[17b_admin_console.md](file:///J:/Projects/helix/orbit/audit/17b_admin_console.md)).

**Verification:** the console's widget suite — a storage fault shows an error
page with retry; a saved session survives a failed refresh; the segmented bar is
48 px; the report card closes exactly once; the back gesture is blocked on the
code dialog; "Load more" survives a filter; a failed sign-out clears local
state anyway.

---

# Tier 3 — the app and the CLI on their own device

## B19 — The CLI must obey the client rules
**A · ~1–2 days · no migration, no wire**

**Closes:**
- AUD-13-1 (P2, appended) — the CLI accepts any `http://` server, so the
  password-derived auth key, the bearer access/refresh tokens and the
  registration token cross the network in cleartext. The app refuses the same
  address (`ServerPolicy`), and the crypto doc records HTTPS enforcement as
  closed on that basis; the CLI has no equivalent rule.
- AUD-13-2 (P2, appended) — `helix_v2 send` prints "sent" for a message the
  outbox has already marked `failed` (`blocked`, `expired`, `bad_payload`,
  `unknown_op`), so a blocked recipient reads as a delivered message.
- AUD-13-3 (P3, appended) — `devices revoke` matches a prefix against a device
  list that a fire-and-forget refresh may not have filled, so a fresh home
  answers "no such device" for a device that exists.
- AUD-13-4 (P3, appended) — the first Ctrl-C is swallowed (`ProcessSignal`
  `.first`) and interactive `chat` never observes `interrupted`.
- AUD-13-5 (P3, appended) — `react` only reaches the newest 200 messages and
  the `all` flag that would help is declared but read by nothing.
- AUD-13-6 (P3, appended) — `db.key` is created with the process umask, i.e.
  0644 on POSIX, next to the encrypted database.
- AUD-13-7 (P3, appended) — the end-to-end CLI test's "no unread" assertion is
  a string `contains` against a list of maps, so it can never fail.

**Why here:** this is a new batch rather than an append because no existing
batch owns the CLI: B6's fix site is the engine's op surface and the app's
models, B9's is the API transport, B17's is the app's sign-in flows. Seven
findings share one package and one harness, and two of them are the CLI
telling the person something untrue (that the server is reachable safely, and
that a message went). The CLI is also the client an operator reaches for when
the app is not available, which is why its lies matter more than its size.

**Structure:** one server-address rule in a package every client uses (S13-1
in [13_cli_harness.md](file:///J:/Projects/helix/orbit/audit/13_cli_harness.md))
— `ServerPolicy` moves out of `app/lib/core/engine/` into
`helix_remote_protocol` or `helix_remote_domain`, and the CLI's `_server`
keeps only the precedence of `--server`, `HELIX_SERVER` and `config.json`;
`DeviceService` gets one freshness entry point (`list({fresh})` or
`ensureFresh`) so the CLI cannot read an unrefreshed list (S13-2); the client
harness gains a reopen-across-processes restart so the CLI's file database is
covered by more than one test (S13-3). The status copy comes from all six
`MessageStatus` values, and the key file is created `0600` on POSIX.

**Verification:** `cli_v2_test.dart` — `--server http://host` exits 2 and
`https://host` passes; `chat` returns when `interrupted` completes; a POSIX-only
test asserts the mode of `db.key`. `server/test/client/engine/cli_test.dart` —
a blocked recipient's `send` does not print "sent" and its `--json` says
`failed`; `devices revoke` works in a fresh home with no prior `devices` call;
Alice's chat row after Bob reads is `unread: 0`; 201 messages with a reaction
on the oldest. The app's existing "https is fine, cleartext is not" test keeps
passing after the move.

**Rollout:** the CLI package only. No server change, no schema, no wire. The
shared policy must land in the same commit as the app's import change, or the
app's rule would exist in two places for the length of a release.

## B20 — The app's own gate and lifecycle answer again
**A · ~1–1.5 days · no migration, no wire**

**Closes:**
- AUD-14b-2 (P3, appended) — a call that outlasts the relock time suppresses
  the relock on that resume and nothing re-applies it when the call ends, so
  the app is open after hang-up although the person was away longer than the
  setting. The bypass is a boolean veto with no memory.
- AUD-14b-3 (P3, appended) — the phone's screen lock is checked only when the
  Helix lock is turned on; after it is removed, the app lock can never be
  passed, the screen only says "try again", and the seam that could name the
  cure (`AppLock.deviceSupportsLock`) is called by nothing.
- AUD-14b-4 (P3, appended) — every resume on the sign-in screen awaits
  `runtimeProvider` unguarded, so `NoServerChosen` reaches the zone handler and
  is recorded as a crash each time.

**Why here:** these three are not stranded-account work (B5) and not
transport (B9): they are the app's answers to its own process events — a
resume, a call ending, a credential that disappeared. Each was decided once
and never revisited, which is one habit and one fix shape. 14b-1 is in B5
because the media policy it breaks is the seam B5 already repairs.

**Structure:** S14b-1 in
[14b_core_security.md](file:///J:/Projects/helix/orbit/audit/14b_core_security.md)
— one `covered(enabled, awaySince, callActive, coldStart)` decision called at
every transition (background, resume, call start/end, setting change) instead
of three independent checks; the call-host finish drops the bypass through
that function, not around it. The resume guard is a small try/catch, not a
seam.

**Verification:** `test/app_lock_test.dart` — background, resume past the
threshold with `callInProgress` true, clear it, assert locked; a failed unlock
with `deviceSupportsLock` false keeps the lock and names the phone's screen
lock, with true shows "try again". A lifecycle host test resumes with no
account chosen and asserts nothing was written to a counting anomaly sink.

**Rollout:** app only. No schema, no wire, no server. The lock change is
user-visible only in the missing-credential message.

## B21 — An attachment is what it is, cleaned, or it does not go
**A · ~1 day · no migration, no wire**

**Closes:**
- AUD-14c-1 (P3, appended) — a picked file's kind comes from its extension, so
  an image saved as `.heif`, `.avif`, `.tif` or with no extension is a
  "document": it is sent unchanged, with its EXIF location, time and camera
  model, although the sanitizer exists to remove exactly those.
- AUD-14c-2 (P3, appended) — the profile crop decodes the chosen photo at full
  size and disposes its codec and image only on the success path; a big photo
  on a small phone can throw with the full-size decode still allocated.
- AUD-14c-3 (P3, appended) — one file in a multi-select whose size cannot be
  read (a cloud placeholder) makes `_pick` return `const []`: the whole
  selection silently disappears.
- AUD-14c-4 (Idea, appended) — GIFs are passed through untouched; a Comment or
  XMP application extension can carry text (not coordinates).
- AUD-14d-1 (P3, appended) — the media processor reads the whole picture and
  copies it before checking its 96 MiB decode cap, so a send of a very large
  image holds 2× its size in memory before the cap answers; the cap is meant
  to prevent exactly that spike.

**Why here:** this is a new batch because the app-side attachment path has no
owner in the plan. B7 is the server's media lifecycle (rows, quota, expiry) and
B13 is the engine's local maintenance; both assume the app hands them a file
that is safe to send. The guarantee the person was given — a photo goes only
once its location is gone — is enforced here or nowhere, and 14c-1 is a hole in
it that needs no unusual file: a modern camera's default extension is enough.

**Structure:** S14c-1 in
[14c_core_media.md](file:///J:/Projects/helix/orbit/audit/14c_core_media.md)
— one `AttachmentKind` classifier that reads magic bytes (the sanitizer
already tells JPEG/PNG/WebP/MP4 apart) and uses the extension only as a hint,
called by the picker, the preview and the sanitizer. S14c-2 — one bounded
decode helper used by the profile crop and the fallback re-encode (the engine's
thumbnail path already bounds its decode).

**Verification:** a file-classification test: a JPEG named `IMG_0001`,
`photo.heif` and `photo.avif` are images, and the sanitizer strips the first.
A profile test that a 4000x3000 image comes back as a 256x256 PNG. A picker
test where the middle of three files cannot be stat'ed returns the other two.
The existing `test/media/metadata_test.dart` (15 tests over JPEG/PNG/WebP/MP4
and the three outcomes) keeps passing.

**Rollout:** app only. No schema, no wire, no server. A `.heif` photo that was
sent as a document before the fix is already out; this batch only stops more.

## B22 — A player and a recorder tell the truth about a failure

**A · ~0.5–1 day · no migration, no wire**

**Closes:**
- AUD-14e-1 (P3, appended) — a playback speed the platform refuses is caught
  by `DeviceAudioPlayer.load`'s single `try` as if the file could not be
  opened, so a note that would play at 1x reports "Audio playback is not
  available on this device"; once the speed chip has been used, every later
  note on that player inherits the same refusal.
- AUD-14e-2 (P3, appended) — the recorder discards the plugin's error events
  and its `idle` state, so a capture failure leaves the clock running and the
  composer in a recording state whose stored duration is longer than the audio
  the recipient can play.

**Why here:** no batch owns app-side playback or recording. B21 ends at handing
the engine a file; B13 is the engine's local maintenance and B20 the app's lock
and process glue. Both findings are one shape — a failure from the platform
read as something else — and both are fixed in the adapters, with tests the
existing fakes can drive.

**Structure:** S14e-1 in
[14e_core_audio_voice.md](file:///J:/Projects/helix/orbit/audit/14e_core_audio_voice.md)
— a refused preference (speed, focus, rate) is best effort and never turns a
loaded file into an unavailable one. S14e-2 — a recording has one end,
reached by an explicit stop, a system stop and a capture error alike, so the
clock, the waveform, the file and the composer agree about when it stopped.

**Verification:** `test/media/adapters_test.dart` — a `FakeAudioBackend`
whose `setRate` throws still loads and plays (and a second load after
`setSpeed(2)` still plays); a `FakeRecordBackend` whose state stream adds an
error mid-recording reports idle, stops the clock, and `stop()` returns the
duration only up to the error. `test/media/playback_test.dart` and the
composer's recording tests keep passing; the composer gets one test that a
system-ended recording leaves the recording UI with a sentence.

**Rollout:** app only. No schema, no wire, no server. A voice note already sent
with an inflated duration stays as it is; the fix only stops new ones.

## B23 — The notification tells the truth about what arrived, and cleans up after an account
**A · ~0.5–1 day · no migration, no wire**

**Closes:**
- AUD-14g-1 (P3, appended) — each background wake replaces the account's
  message notification with *that pass's* count, so two pushes with two
  messages each leave "2 new messages" (or "1") over four unread; the running
  app accumulates within one run, so the two paths also disagree.
- AUD-14g-2 (P3, appended) — the message notification is updated with
  `onlyAlertOnce: true`, so the sound and vibration play only for the first
  message after the notification was last cancelled; every later message while
  the app is unopened is silent, although the channels and Settings promise
  sound and vibration.
- AUD-14g-3 (P3, appended) — removing an account wipes its database, key and
  files and leaves its message notification (preview text included, when
  previews are on) and any missed-call entry in the shade; tapping the
  leftover switches to an account that no longer exists and does nothing.
- AUD-14g-4 (P3, appended) — a press on a message notification of the account
  already on screen only brings the app forward: the listener returns for the
  active account and nothing routes, so the press lands on whatever screen was
  open, with the notification already dismissed.
- AUD-14g-5 (P3, appended) — the engine's missed-call notice carries `muted`
  (computed from the chat's mute) exactly as message notices do, and the app's
  only consumer never reads it: a muted chat still posts "Missed call", with
  the caller's name when previews are on.
- AUD-14g-6 (P3, appended) — the missed-call path suppresses only in
  `resumed`, while `appInForeground()` (used by message alerts) treats
  `inactive` — the shade pulled down, a system dialog — as on screen; a call
  that ends as missed while the shade is over the ringing screen posts a
  redundant notification.
- AUD-14g-7 (P3, appended) — `PushTokenSource.prepare` memoises its result,
  including a failure, so one failed Firebase start disables token
  registration and wake-up subscription for the rest of the process; the next
  engine start receives the cached `false` and returns before sending a token.
- AUD-14h-2 (P3, appended) — removing a pack forgets its copy and its channel
  by the string prefix `<id>.`, and ids may contain dots: deleting `a.b` also
  deletes the chosen `a.b.c`'s copy and channel. The choice is deliberately
  kept and `a.b.c` is still installed, so Settings names a ringtone that every
  call now rings around (the phone's own tone), with no line saying so.
- AUD-14h-3 (P3, likely, appended) — a ringtone's copy is published through
  the fixed temporary name `<id><suffix>.part`, and publication is not
  serialised: two publishes of the same ringtone (a double tap on the tile, or
  `update` while the page republishes it) share the temp. One rename then
  fails and reverts a valid choice, or the first rename exposes the target
  while the other writer is still filling it.

**Why here:** no batch owns app-side notifications. B20 is the lock and process
glue, B8 the calls themselves, B21/B22 the attachment and playback adapters,
B13 the engine's local maintenance; the notification layer sits above all of
them and is the one place where "what arrived" is stated to the person. The
seven findings are two habits: a notification whose persistent state (count,
whether it has alerted) is decided by whichever isolate posts next, and
cleanup/destination rules that stop at the account on screen. AUD-14h-2 and
AUD-14h-3 are the same cleanup step one level down: the copy and the channel a
ringtone leaves behind are deleted by `SoundPackActions.remove` alongside the
pack (sound_packs.dart:158-167), so they belong to the batch that already owns
`forgetRingtone`.

**Structure:** S14g-1 in
[14g_push_notifications.md](file:///J:/Projects/helix/orbit/audit/14g_push_notifications.md)
— one owner of an account's notification ids (messages, calls, missed calls)
and one `forgetAccount`, called by both sign-out paths and by
`accountsProvider.remove`; S14g-2 — one foreground predicate
(`appInForeground`) for every "should this raise?" decision; S14g-3 — one
function that posts or updates an account's message notification, given the
pass's messages, owning the cumulative count and the alert-versus-silent
choice, so the background isolate and the running app cannot disagree; S14h-1
in
[14h_sounds_diagnostics.md](file:///J:/Projects/helix/orbit/audit/14h_sounds_diagnostics.md)
— one owner of a ringtone's installation (the copy's exact name and unique
temp, one writer at a time, the channel ids it created, and the only deletion
rule), which is where 14h-2's exact-match cleanup and 14h-3's serialisation
live.

**Verification:** a fake notification plugin that records every `show` and
`cancel`: two wake passes of two and one notices produce "3 new messages" (or a
title without a number) and `onlyAlertOnce` false; removing a non-active
account cancels its message notification (and its call entry); a press while
the active account is set routes to `/home`; a muted missed call posts nothing
and `inactive` is treated as on screen; two `engineRunning` calls after one
failed prepare register the token on the second. For the ringtone half: two
packs `a.b` and `a.b.c`, choose `a.b.c`, remove `a.b`, and assert its copy and
channel are still there and `chosen()` still returns it; two `publish` calls
for one sound started together against a delayed writer leave complete bytes
and both report success. On a real phone, the checklist gains two lines: two
messages in the background make two alerts, and a removed account leaves no
notification behind.

**Rollout:** app only. No schema, no wire, no server. Notifications already in
a shade at update time stay until tapped; the batch covers the ones raised
after the fix, and the removal cleanup runs on the next removal. The ringtone
fix touches only the app's own copy folder and channels.

## B24 — The anomaly log sends what it recorded
**A · ~0.5 day · no migration, no wire**

**Closes:**
- AUD-14h-1 (P3, appended) — every `crash` record is recorded with
  `soon: true`, and `_schedule` answers a `soon` record by cancelling the
  pending send timer and starting a new two-second one; the repeat branch of a
  de-duplicated crash calls it again. An error that recurs faster than every
  two seconds therefore postpones its own report for as long as it recurs: a
  widget that throws in every build emits a crash per frame, the queue fills
  to its 200-entry cap and drops the oldest, and if the person force-stops the
  app the incident is never reported — precisely the incident the log exists
  for. It clears only when the storm pauses for two seconds.

**Why here:** no batch owns `core/diagnostics`. B20 is the app's lock,
network reading and resume; B5 the runtime's lifetime and the stranded-account
repair; the anomaly log sits beside both and is the only way a device's
failures reach the operator. The fix is a scheduler, not a guard on one
`record` call, so it is one seam and one test (a fake clock), not a footnote
in an existing batch.

**Structure:** S14h-2 in
[14h_sounds_diagnostics.md](file:///J:/Projects/helix/orbit/audit/14h_sounds_diagnostics.md)
— the log holds an earliest-due instant that a `soon` record may bring forward
but never push back, and one path from "something was recorded" to "a batch
was attempted".

**Verification:** with a fake clock and a fake sender, a crash every 500 ms for
5 s produces a send by 2.5 s and a queue that never approaches 200; a single
crash still goes within two seconds; slow frames still wait for the 15-minute
report window (no change to `FrameWatch`); the existing masking, repeat,
batch and route-exclusion tests in `test/diagnostics/anomaly_log_test.dart`
still hold.

**Rollout:** app only for the timer fix. Q10 decides the queue's scope: the
fix lands either way, and if the queue is made per server the same change adds
the account/server tag to an entry and filters on flush (an additive payload
field; the route accepts it). Without Q10 the log stays device-global and the
plan records that as the contract. The report's shape and the anomaly route are
otherwise unchanged; the only visible difference is that a crash storm produces
its entry instead of eating it.

## B25 — A chat day is a calendar day, and a snippet cuts a character
**A · ~0.5 day · no migration, no wire**

**Closes:**
- AUD-14i-1 (P3, appended) — `_daysBetween` subtracts two local midnights and
  truncates `.inDays`. Across a spring-forward the previous calendar day is
  23 h away and counts as today, and two days count as yesterday; every label
  built on it (chat list time, the day separator, last-seen, message info, the
  call log and join-request rows) is a day wrong for about a day after the
  transition, and the seven-day branch shifts for a week. Fall-back (25 h)
  truncates correctly, so the defect is one-directional and invisible in a
  zone without DST — which is why no test pins it.
- AUD-14i-2 (P3, appended) — `snippetFor` cuts its twenty characters of
  context with `String.substring` on UTF-16 indices. A surrogate pair
  straddling the cut loses its high half, so the search row begins with a lone
  low surrogate; the highlighted word is still correct. Only the two search
  screens produce snippets.

**Why here:** no batch owns `core/format` or `core/chat`'s presentation
helpers. B23 owns what a notification says, B20 the app's lock and lifecycle,
B6 the engine's action surface. The two findings share a layer and a proof
style (pure functions with an injected "now" and a fixed string), so they are
one small batch rather than footnotes elsewhere.

**Adjacent structure (not required by either finding):** S14i-1 in
[14i_core_chat_people_format.md](file:///J:/Projects/helix/orbit/audit/14i_core_chat_people_format.md)
— `helix_remote_db` mints `direct:<account>` but does not take it apart, and
the prefix is parsed or matched by hand in two app files and five engine
files. Add the inverse next to the minter when the conversation-id code is
next touched; nothing in this batch depends on it.

**Verification:** the DST test needs the process zone to observe DST, so it
runs in the Linux CI job with `TZ=America/New_York` (a message from 2026-03-08
read on 2026-03-09 is "Yesterday", and the separator says so) plus the
southern-hemisphere spring (`TZ=Australia/Sydney`, 2026-10-04 read on
2026-10-05); on the Windows dev host, whose zone has no DST, the same
assertions pass before and after the fix and prove nothing. The snippet test
('😀'×10 + '.needle', query "needle") asserts the first rune of the shown text
is complete and the highlight covers exactly "needle". Existing label
assertions in `chat_logic_test.dart` and `calls/call_log_test.dart` must not
change in a non-DST zone, and `flutter analyze` plus the app suite stay green.

**Rollout:** app only. The labels change only on the day after a spring
transition; the snippet changes only where a cut splits a character.

---

# Tier 4 — decisions and ideas, not scheduled work

| Finding | What it is | Recommendation |
|---|---|---|
| AUD-12h-3 (Idea) | Discovery ignores the salt version, so a server-side salt rotation would silently disable discovery. | Record as a limitation, or add the version as an additive field the next time discovery changes. No batch now. |
| AUD-12j-1 (Idea) | There is no way to stop server wake-ups short of signing out; `PushService.unregister` is dead code with a promise no screen keeps. | Q8. Ship the control, or delete the dead method and record the OS-level-only decision. |
| AUD-14f-1 (Idea) | A `helix://contact/add` link is parsed with a signed payload nothing reads; it opens people search, a leftover of the dropped contact-request design. | Delete the payload codec with the link kind, or wire the payload if contact requests ever return. No batch now. |
| AUD-12l-3 (P3) | The call-metrics pipeline has a route, a client method and a serializer, but nothing ever sends a sample. | Q9. Delete the pipeline (and close AUD-6-1 by removal), or wire the sampler and bound the field first. |
| AUD-12l-4 (P3) | The ICE-restart path is unreachable: nothing calls `restartIce`, the adapter drops the offer it would emit, and the wire has no renegotiation signal. | Q9. Delete the dead path, or add a renegotiation kind to the protocol and handle it in the adapter. |
| AUD-3-13 (Idea) | Every open socket re-authenticates against Postgres every 25 s. | **Declined in B11 S6:** the check is the backstop for a bus hint missed while LISTEN was down, and a cache only widens that window. Batch the check per sweep if scale ever demands it. |

---

# Cross-cutting constraints

**Migration order.** B3 (platform 3) and B4 (platform 4) are independent and
expand-only in their first release; the contract step (dropping the old
constraint) is a release later. B7, B8, B15 and B16 add module migrations that
are independent of each other. Every server migration runs at start or via
`bin/migrate.dart`; the owner deploys with `deploy-helix.ps1 -Tag`, and the
release note names the migration. Agents do not deploy or restart production.

**Order that must not be reversed.**
- If Q2 = advisory: engine tolerance → server stops storing → docs. A server
  that sends a seq-less envelope to a build that cannot parse it turns a
  best-effort notice into a dropped frame, which B12 makes a protocol error.
- B8 and B12: server first, clients after.
- B4's endpoint validation: the production `.env` must hold a valid endpoint
  before that release, or the node refuses to start (by design).
- B14's trusted-proxy check: same — a contradictory setting stops start-up.

**Things that must ship together.** `AUD-1a-3` and `AUD-1a-4` are one
idempotency change; `AUD-1a-1` and the streaming media route are one body-read
change; `AUD-12c-1` and the receipt tests are one line but must not be split
from the apply-path tests; `AUD-16-1` and `AUD-16-6` are one install gate.

**Verification debt this plan creates.** B1's `query_plans_test.dart` is a new
suite that must run in CI with Postgres; B2's "victim mailbox" harness should
become a named helper so later fan-out changes reuse it; B5 and B6 need
fault-injection seams (a DAO that fails on demand) that the engine does not
have today — that is the largest test-infrastructure cost in the plan.

**What this plan cannot fix.** Every sweep area has been read, and the audit
still found no P0. Findings marked `likely` may not reproduce; each batch turns
its own into a failing test first, and a mechanism that does not reproduce is
recorded as such rather than "fixed" blind. The rebuilt plan has no unread
area left to invalidate a batch.

# Not in this plan

Excluded by the role and by the owner's standing decisions, and deliberately
not relitigated:

- The two open DEVIATIONS rulings and the pending-redeploy list (`/u/<~name>`,
  `GET /v1/backups/full/meta`, the three pack routes, `HELIX_PACKS_DIR`).
- The uncommitted `orbit/prototype/css/tokens.css`.
- Known-flaky tests (they are listed in `AGENTS.md` and are not findings).
- Accepted product decisions: screenshots allowed everywhere, English only,
  no iOS, Orbit/Orbit Night themes, no contact requests.
- ADRs: no sweep raised an ADR challenge, so this section is empty. Q4 and Q5
  touch ADR-030's backup format and the crypto header; they are framed as
  product decisions, not as challenges to the ADR.
- `helix_local/`: dormant, read-only, out of scope.

## Appendix — every finding, its severity and its batch

Rebuilt 2026-10-24 from every findings file: 210 ids, each exactly once, each
severity matched to its own file, each assigned to one batch (210 of 210). A
finding filed after this rebuild is appended here and assigned to the batch
that owns the same code path.

| Finding | Sev | Batch | Title |
|---|---|---|---|
| `AUD-18-1` | P2 | B1 | The release gate cannot fail: its steps check `$?` after a scriptblock that ends in `Pop-Location` |
| `AUD-1b-3` | P2 | B1 | The plan's EXPLAIN guardrail for hot queries does not exist |
| `AUD-18-2` | P3 | B1 | A scheduled or manually dispatched CI run verifies only the tip commit's diff, not the tree |
| `AUD-18-3` | P3 | B1 | The dependency register's version check silently skips nine of its rows, while the register says "any table" |
| `AUD-18-4` | P3 | B1 | The lockfile policy says the governance checker covers claims it does not check |
| `AUD-18-5` | P3 | B1 | The performance-budget document's runnable commands name files that do not exist |
| `AUD-4a-1` | P1 | B2 | Block/unblock is an unthrottled stored-envelope fan-out that can flush an offline account's mailbox |
| `AUD-4b-1` | P1 | B2 | An unthrottled roster operation stores a `roster_change` in every member's mailbox; looping it flushes them |
| `AUD-3-1` | P2 | B2 | Ephemeral and urgent fan-out cost two DB round trips per recipient device |
| `AUD-3-3` | P2 | B2 | A presence route outlives its node, so "delivered live" is reported for a device nothing reached |
| `AUD-4b-2` | P2 | B2 | Ephemeral group sends bypass both budgets and fan out to every member device |
| `AUD-3-6` | P3 | B2 | A duplicate send re-charges the budget, re-relays, and is charged before blocks and relay |
| `AUD-3-7` | P3 | B2 | A replayed send loses `blocked_by` |
| `AUD-3-8` | P3 | B2 | The device-list check runs before block filtering |
| `AUD-4a-3` | P3 | B2 | `setContacts` rewrites up to 5,000 rows per call with no per-account limit |
| `AUD-4b-3` | P3 | B2 | A refused or failed group send still burns the sender's stored budget |
| `AUD-4b-4` | P3 | B2 | Group sends have no message-id dedupe, unlike direct sends |
| `AUD-4b-5` | P3 | B2 | `add_members` is bounded only by the request body, and each id costs several queries under the group row lock |
| `AUD-4b-6` | P3 | B2 | A group send authorizes and snapshots the roster outside the delivery transaction |
| `AUD-1b-1` | P1 | B3 | A dead outbox job holds its dedupe key forever and silently suppresses every later one |
| `AUD-1b-2` | P2 | B3 | A periodic job's lease can expire while it is still running |
| `AUD-3-2` | P2 | B3 | A crash between expiry sweep statements inflates `pending` and later trims drop undelivered envelopes early |
| `AUD-2-7` | P3 | B3 | Expired invites and recovery codes have no periodic purge |
| `AUD-3-5` | P3 | B3 | `messaging.expire` is an unbounded `while` loop with no yield or cap |
| `AUD-4a-4` | P3 | B3 | Discovery budget rows are never swept and the refusal names the wrong retry time |
| `AUD-1a-1` | P1 | B4 | A slow client can hold the node's whole body budget forever |
| `AUD-1c-1` | P1 | B4 | Every S3 request is unbounded; one stalled store hangs media requests and accumulates health probes |
| `AUD-1a-2` | P2 | B4 | Path parameters are percent-decoded twice |
| `AUD-1a-3` | P2 | B4 | Concurrent duplicate requests with one Idempotency-Key both run |
| `AUD-1c-2` | P2 | B4 | `LocalObjectStorage.append` is check-then-write with no per-key isolation; concurrent retries corrupt an up... |
| `AUD-1c-3` | P2 | B4 | A malformed `HELIX_S3_ENDPOINT` passes config and fails only at request time |
| `AUD-6-2` | P2 | B4 | Federation reads peer responses with no size cap, and the identity fetch runs before authentication |
| `AUD-8-1` | P2 | B4 | `ContentLimits` covers five fields; every other string and list decodes unbounded |
| `AUD-11a-2` | P3 | B4 | A device POST retried after `internal` can run twice: the idempotent result is stored only for status < 500... |
| `AUD-1a-4` | P3 | B4 | An idempotent replay loses every response header but content-type |
| `AUD-1a-5` | P3 | B4 | The access log is synchronous disk I/O with no per-day size cap |
| `AUD-1b-4` | P3 | B4 | The ephemeral prefix scan cannot use the primary-key index under a non-C collation |
| `AUD-1c-4` | P3 | B4 | `S3ObjectStorage.read` downloads the whole object and slices it in memory |
| `AUD-1c-5` | P3 | B4 | `RecordingPushProvider`, a test double, ships in the production library |
| `AUD-6-6` | P3 | B4 | Inbound S2S bodies are rate-limited per request, never per byte |
| `AUD-12a-1` | P1 | B5 | A session that ends leaves the account in place, and every sign-in path refuses while it is there: the docu... |
| `AUD-12a-2` | P2 | B5 | Device-key re-authentication treats every `ApiException` as "this device is gone", so a 429/5xx during re-a... |
| `AUD-12a-3` | P2 | B5 | Maintenance passes can overlap, and two overlapping replenishments save different private keys under ids th... |
| `AUD-12g-1` | P2 | B5 | The device identity and the session are two commits; between them the engine is "signed in" with no session... |
| `AUD-12g-2` | P2 | B5 | Every new-device flow keeps its generated keys in memory until the server call returns, so a lost response ... |
| `AUD-12h-1` | P2 | B5 | A device that signs in with the password and did not restore a backup has no profile key; publishing from i... |
| `AUD-12a-4` | P3 | B5 | `_startWorkers`/`_stopWorkers` are not serialised: a stop that runs during a start can finish first and lea... |
| `AUD-12a-5` | P3 | B5 | `signOut()` runs the local wipe after three fallible steps outside any `finally`, so a throw leaves the sta... |
| `AUD-12a-6` | P3 | B5 | `start()` ignores the current status and changed flags; the backup timer is unreachable unless `background`... |
| `AUD-12b-2` | P3 | B5 | Sign-out and engine close can hang ~30 s offline behind an inbound retry |
| `AUD-12g-3` | P3 | B5 | A link proposal is spent by the first attempt, including one that failed on the network |
| `AUD-12g-4` | P3 | B5 | A device-list operation reports failure when only its follow-up refresh failed |
| `AUD-12h-2` | P3 | B5 | Clearing a nickname cannot undo the phone-book rename, so the old nickname keeps showing |
| `AUD-12b-1` | P2 | B6 | A failed group rekey is permanent and silent; group state edits then fail for everyone |
| `AUD-12c-1` | P2 | B6 | Every arriving message queues two `delivered` receipts |
| `AUD-12d-1` | P2 | B6 | Lock-order inversion: a peer-key update waits for a device lock inside a transaction, while senders hold th... |
| `AUD-12e-1` | P2 | B6 | A create whose response is lost throws away the only copy of the group key |
| `AUD-12e-2` | P2 | B6 | Group trust (and the keyring) are read-modify-write JSON without a CAS: a confirm can release an unconfirme... |
| `AUD-12f-1` | P2 | B6 | A delete or edit that fails to decrypt is dropped silently, forever |
| `AUD-12i-1` | P2 | B6 | A failed edit/delete/reaction is lost silently; "delete for everyone" is then unrepeatable |
| `AUD-12c-2` | P3 | B6 | The edit and delete windows are measured against a sender-chosen timestamp that is only clamped in the future |
| `AUD-12e-3` | P3 | B6 | The key share after add/approve is derived from the response, so a lost response leaves the new member with... |
| `AUD-12f-2` | P3 | B6 | A stored `typing` envelope is never marked processed, so it is replayed on every reconnect |
| `AUD-12f-3` | P3 | B6 | The first group key to arrive wins over the correct one when the state blob cannot arbitrate |
| `AUD-12i-2` | P3 | B6 | "Delete for me" on a pending message does not cancel it — and is the only deletion offered |
| `AUD-5-1` | P2 | B7 | Deleting an account frees its media only through one best-effort job; persistent media then never expires |
| `AUD-5-2` | P3 | B7 | Deleting or replacing the recovery backup leaves its ciphertext (and 1 GiB of quota) for 90 days |
| `AUD-5-3` | P3 | B7 | A byte-only quota lets one account turn its 4 GiB into millions of rows, and the sweeps that clean them are... |
| `AUD-5-4` | P3 | B7 | Upload quota is a read-then-insert with no serialization, so concurrent creates overshoot it |
| `AUD-5-5` | P3 | B7 | Two concurrent chunk uploads of one object can interleave and leave a corrupt, over-size blob |
| `AUD-5-6` | P3 | B7 | Backup PUTs have no per-route limit, so one account can spend the node's CPU on 64 MiB JSON |
| `AUD-12k-1` | P2 | B8 | Offline catch-up rings the oldest pending offer, not the newest: every newer caller is told "busy" and logg... |
| `AUD-6-1` | P2 | B8 | Call metrics store an unbounded free-text field per row: ~9 GB per account over the retention window, with ... |
| `AUD-12k-2` | P3 | B8 | `release()` finishes the live call outside the call queue, so an engine stop can mislabel the log and race ... |
| `AUD-12l-1` | P3 | B8 | A failed media setup leaks the peer connection (and any initialized renderer), and its ICE callback can fir... |
| `AUD-12l-2` | P3 | B8 | The ICE config says the server enforces relay-only and can drop leaking candidates; call signals are sealed... |
| `AUD-6-3` | P3 | B8 | `PUT /calls/{id}/state` has no policy and fans out to every device of the account |
| `AUD-6-4` | P3 | B8 | A non-offer call signal is delivered to any addressed device; only pending-row writes are party-scoped |
| `AUD-6-5` | P3 | B8 | TURN credentials are capped per device, so one account can mint many one-hour relay credentials |
| `AUD-11a-1` | P2 | B9 | One 30 s deadline covers the whole body, so backup, export and presigned uploads cannot finish on ordinary ... |
| `AUD-11a-3` | P3 | B9 | `isUnauthenticated` is true for `invalid_credentials`, contradicting the transport's own carve-out |
| `AUD-11a-4` | P3 | B9 | A failed session-store write after a refresh re-exposes the rotated-out refresh token, which the server tre... |
| `AUD-11b-1` | P3 | B9 | A refused upgrade can hang or leak: the error body has no deadline and the `HttpClient` is closed without f... |
| `AUD-11b-2` | P3 | B9 | The negotiated WebSocket subprotocol is never checked |
| `AUD-11b-3` | P3 | B9 | `reconnect()` after `dispose()` builds a live socket into closed streams and leaves it running |
| `AUD-11b-4` | P3 | B9 | The silence detector compares wall-clock times; a backward clock step disables it |
| `AUD-11c-1` | P3 | B9 | `accountKeys` is a GET that consumes a one-time prekey, so the transport's automatic retry silently burns o... |
| `AUD-12n-4` | P3 | B9 | A presigned (S3) upload reads the whole ciphertext into memory, with no size cap; OOM becomes a generic retry |
| `AUD-12o-1` | P3 | B9 | The whole-object download cap uses the largest chunk size, so a 64 KiB-chunked object can exceed it and fail permanently |
| `AUD-12r-1` | P1 | B9 | The transfer receive cap uses the max chunk size, so every segment over 64 KiB fails — every history transfer at the default 4 MiB |
| `AUD-16-1` | P2 | B10 | A signed theme pack that parses but cannot be drawn is accepted, and then breaks the next launch |
| `AUD-16-2` | P3 | B10 | `OrbitTokens.lerp` returns the wrong theme at both ends, so every theme change flickers |
| `AUD-16-3` | P3 | B10 | Tokens are keyed by bare name in one flat map, so a document can silently replace a token from another group |
| `AUD-16-4` | P3 | B10 | A field's visible label is not associated with its input, and an inline error is not announced |
| `AUD-16-5` | P3 | B10 | Fixed-height controls clip a label that wraps at large text sizes |
| `AUD-16-6` | P3 | B10 | A theme download reports success for a pack the page then cannot offer, and leaves its bytes behind |
| `AUD-7-4` | P3 | B10 | `GET /v1/packs` rescans and stats the whole folder on every request |
| `AUD-3-10` | P3 | B11 | A failure between registering the socket and `start()` leaves a socket that presence calls online |
| `AUD-3-11` | P3 | B11 | The mailbox backlog gauge scans up to one million rows on every scrape |
| `AUD-3-12` | P3 | B11 | Two near-simultaneous upgrades of one device can close the newest socket |
| `AUD-3-4` | P3 | B11 | The 25 s route-refresh sweep has no in-flight guard and re-authenticates every socket serially |
| `AUD-3-9` | P3 | B11 | Realtime timers use the wall clock, not a monotonic clock |
| `AUD-3-13` | Idea | B11 | Every open socket re-authenticates against Postgres every 25 seconds |
| `AUD-8-2` | P3 | B12 | An unknown conversation kind is a hard decode failure, unlike an unknown body |
| `AUD-8-3` | P3 | B12 | An unknown device-transfer state decodes as `cancelled` |
| `AUD-8-4` | P3 | B12 | An unknown error code is never retryable, against the catalog's own rule |
| `AUD-8-5` | P3 | B12 | The golden fixtures pin 9 shapes; the rest of the wire has only round-trip tests |
| `AUD-9-1` | P3 | B12 | Stored crypto state decodes any-length keys and any counters, so a damaged row either wedges a peer or sile... |
| `AUD-9-2` | P3 | B12 | `DeviceSessions` has two serializations; the one the app stores lives in the engine and the other is dead |
| `AUD-10-1` | P3 | B13 | Bulk maintenance deletes bind every row id in one statement; past SQLite's parameter limit the delete throw... |
| `AUD-10-2` | P3 | B13 | `HistoryStore.backupableCount` emits `NOT IN ()` for an empty exclusion list, which SQLite rejects |
| `AUD-10-3` | P3 | B13 | A thumbnail job converted to a download while a worker holds it is marked done by the thumbnail worker; the... |
| `AUD-10-4` | P3 | B13 | `enqueueStandalone` returns an old job for a reused purpose and keeps its stale path; `purpose` has no uniq... |
| `AUD-12m-1` | P3 | B13 | Storage and "free up space" count and delete sent media, which stops being re-fetchable 30 days after the upload |
| `AUD-12m-2` | P3 | B13 | `cancel` decides from a pre-transaction snapshot: a download that finishes in the gap is reset to "not downloaded" with its file on disk |
| `AUD-12m-3` | P3 | B13 | `retryFailed` retries every failed job, including the send path, inside one write transaction |
| `AUD-12m-4` | Idea | B13 | One media-kind classifier instead of three that already disagree |
| `AUD-12n-1` | P3 | B13 | `stop()` is not a barrier: a job claimed across its cancellation sweep starts after it returns |
| `AUD-12n-2` | P3 | B13 | A lapsed lease lets the worker claim a job it is already running, and the old heartbeat renews the new lease |
| `AUD-12n-3` | P3 | B13 | A permanent local I/O error is retried for 30 days while its held op blocks every later message in the chat |
| `AUD-12o-2` | P3 | B13 | A failed upload keeps its whole ciphertext in staging for ever, and no screen counts it |
| `AUD-12p-1` | P3 | B13 | An offer stays on the receiving device five days after the sender deleted its relay objects |
| `AUD-12p-2` | P3 | B13 | The auto-offer cursor moves before the offer is sent, and every failure is swallowed |
| `AUD-12p-3` | P3 | B13 | A paused transfer restarts itself when auto-accept is on |
| `AUD-12p-4` | P3 | B13 | The offers list reports zero segments fetched while a download runs |
| `AUD-12q-1` | P2 | B13 | Restore and the automatic version-conflict catch-up resurrect messages deleted for me and cleared or deleted chats |
| `AUD-12q-2` | P3 | B13 | The archive records nothing about a truncated export, so a capped restore looks complete |
| `AUD-12r-2` | P3 | B13 | A receive interrupted by a kill sits in `downloading`/`importing` with no resume and no working button |
| `AUD-12r-3` | P3 | B13 | The sender's transfer lives only in memory and never learns the receiver's answer |
| `AUD-12r-4` | P3 | B13 | The twenty-first unanswered offer is refused and dropped in silence |
| `AUD-2-1` | P2 | B14 | A failed text spends the number's hourly allowance and the server's whole daily budget |
| `AUD-2-2` | P2 | B14 | Nothing bounds the number of devices an account can hold |
| `AUD-2-3` | P3 | B14 | `IdentityContext.revokeDevice` accepts an account id and never uses it |
| `AUD-2-4` | P3 | B14 | Every authenticated request runs an UPDATE that almost always changes nothing |
| `AUD-2-5` | P3 | B14 | A link long-poll reads the ephemeral store four times a second |
| `AUD-2-6` | P3 | B14 | The one-time-prekey gap marker is set even when no key was handed out |
| `AUD-2-8` | P3 | B14 | The verification-token purpose is only enforced when registering |
| `AUD-7-1` | P3 | B14 | Wrong trusted-proxy setting turns the per-address sign-in lock into a shared lock on everyone |
| `AUD-4a-2` | P2 | B15 | Account-deletion purge scans the whole contacts table |
| `AUD-4a-5` | P3 | B15 | Report notes are free text that outlive the account, contradicting "ids only" |
| `AUD-4a-6` | P3 | B15 | Report intake checks neither the subject nor duplicates, and open reports never expire |
| `AUD-4a-7` | P3 | B15 | `openReportsAbout` has no index on `reports.subject` |
| `AUD-4a-8` | P3 | B15 | The account export silently truncates reports filed at 500 |
| `AUD-7-2` | P3 | B15 | Account export is assembled in memory with one unbounded section |
| `AUD-7-3` | P3 | B15 | Cursor paging uses `(@cursor IS NULL OR id < @cursor)`, which no index can serve |
| `AUD-4c-1` | P2 | B16 | The roster cache version check is not atomic, so an older snapshot can overwrite a newer one |
| `AUD-4c-2` | P3 | B16 | `remote_devices` rows are never cleaned when a group is deleted |
| `AUD-4c-3` | P3 | B16 | `joined_at` is the transaction timestamp and `members()` has no tiebreak, so "oldest" is arbitrary |
| `AUD-4c-4` | P3 | B16 | An S2S action's `actorDevice` is trusted without checking it belongs to the actor |
| `AUD-4c-5` | P3 | B16 | Roster syncs are not coalesced and a replayed sync re-delivers its event |
| `AUD-4c-6` | P3 | B16 | Leaving remote groups depends on a one-shot job that gives up silently |
| `AUD-15-1` | P3 | B17 | A national number typed with its trunk zero becomes a different E.164 |
| `AUD-15-2` | P3 | B17 | The lockout time is read in seconds, but the wire carries milliseconds |
| `AUD-15-3` | P3 | B17 | A third copy of the legal version, which is never sent |
| `AUD-15-4` | P3 | B17 | "This number already has an account" is unreachable in the code path it is written for |
| `AUD-15-5` | P3 | B17 | The post-sign-in doc says a take-over asks for the restore step; the code does not, and cannot usefully |
| `AUD-15-6` | P3 | B17 | A flow controller writes state after its page has disposed it |
| `AUD-15-7` | P3 | B17 | The backup feature's own doc says the recovery secret is made by the app and can be typed |
| `AUD-15-8` | P3 | B17 | A transfer's failure cannot be cleared through `copyWith` |
| `AUD-12q-3` | P3 | B17 | A full backup made under an earlier identity is merged, then refused as "cannot be opened" |
| `AUD-11c-2` | P3 | B18 | Admin sign-out keeps the token when the server call fails, so an offline operator stays signed in |
| `AUD-17a-1` | P3 | B18 | A storage fault at start-up strands the console on the launch screen forever |
| `AUD-17a-2` | P3 | B18 | A transient failure at launch makes a still-valid saved session unusable until the app restarts |
| `AUD-17a-3` | P3 | B18 | The segmented bar's segments are 44 px tall, under the 48 px rule the console tests claim to enforce |
| `AUD-17b-1` | P3 | B18 | Resolving a report under the "All" filter can throw `StateError` and leave the card open after the server a... |
| `AUD-17b-2` | P3 | B18 | The "shown only now" code dialog can be dismissed with the Android back gesture, destroying the only copy o... |
| `AUD-17b-3` | P3 | B18 | The audit trail's kind filter can hide "Load more", so later matching events are unreachable |
| `AUD-17b-4` | P3 | B18 | A refresh that overlaps a config change can put the old value back on the switches |
| `AUD-12l-3` | P3 | T4 | The call-metrics pipeline has a route, a client method and a serializer, but nothing ever sends a sample |
| `AUD-12l-4` | P3 | T4 | The ICE-restart path is unreachable: nothing calls `restartIce`, the adapter drops the offer it would emit,... |
| `AUD-12h-3` | Idea | T4 | (Idea) Discovery ignores the salt version, so a server-side salt rotation would silently disable discovery |
| `AUD-12j-1` | Idea | T4 | There is no way to stop server wake-ups short of signing out; `PushService.unregister` is dead code with a ... |
| `AUD-13-1` | P2 | B19 | The CLI accepts any `http://` server, so the auth key and bearer tokens travel in cleartext |
| `AUD-13-2` | P2 | B19 | `helix_v2 send` prints "sent" for a message the outbox has already marked failed |
| `AUD-13-3` | P3 | B19 | `devices revoke` matches a prefix against a device list a fire-and-forget refresh may not have filled |
| `AUD-13-4` | P3 | B19 | The first Ctrl-C is swallowed and interactive `chat` cannot be interrupted |
| `AUD-13-5` | P3 | B19 | `react` only reaches the newest 200 messages; the `all` flag is declared but unused |
| `AUD-13-6` | P3 | B19 | `db.key` is created with the process umask (0644 on POSIX) |
| `AUD-13-7` | P3 | B19 | The CLI test's "no unread" assertion is a string `contains` over a list of maps and cannot fail |
| `AUD-14a-1` | P2 | B5 | A setting stream keeps the runtime it was first read on: broken after a signed-out start, the previous account after a switch |
| `AUD-14a-2` | P2 | B5 | An empty or undecodable account list is read as "no accounts" and every secondary account's database and key is deleted |
| `AUD-14a-3` | P3 | B5 | `HelixRuntime.close` skips its remaining steps when one fails, but releases the lease anyway |
| `AUD-14a-4` | P3 | B9 | The app sends its phone model in `x-helix-client`, where the documented value is `<platform>/<app version>` |
| `AUD-14b-1` | P3 | B5 | A VPN on mobile data is classified as Wi-Fi, so "Wi-Fi only" downloads and the backup gate run over mobile data |
| `AUD-14b-2` | P3 | B20 | A call that outlasts the relock time cancels the relock for that return; after hang-up the app stays open |
| `AUD-14b-3` | P3 | B20 | After the phone's screen lock is removed, the app lock can never be passed and the screen does not say why |
| `AUD-14b-4` | P3 | B20 | Every resume on the sign-in screen throws `NoServerChosen` into the crash log |
| `AUD-14c-1` | P3 | B21 | A file is a photo because of its name, so a photo without a known extension is sent with its EXIF intact |
| `AUD-14c-2` | P3 | B21 | The profile crop decodes the photo at full size and leaks the codec and image when the crop fails |
| `AUD-14c-3` | P3 | B21 | One unreadable file in a multi-select discards the whole selection |
| `AUD-14c-4` | Idea | B21 | (Idea) GIFs are always sent untouched, and a GIF can carry text and XMP |
| `AUD-14d-1` | P3 | B21 | The media processor reads and copies the whole picture before checking its 96 MiB cap, so a very large send holds 2x its size in memory |
| `AUD-14d-2` | P3 | B5 | A rename writes a fresh `Name(first:)` into the phone's contact, clearing its middle, family and prefix names |
| `AUD-14e-1` | P3 | B22 | A refused playback speed is caught as a load failure, so a playable voice note reports "audio not available" |
| `AUD-14e-2` | P3 | B22 | A microphone capture failure is swallowed, so the recording clock keeps running and the note is sent longer than its audio |
| `AUD-14f-1` | Idea | T4 | (Idea) A contact-add link is parsed with a signed payload that nothing reads; it opens people search |
| `AUD-14g-1` | P3 | B23 | A later wake-up replaces the message notification with only that pass's count |
| `AUD-14g-2` | P3 | B23 | Every message after the first is posted silently, because the update is `onlyAlertOnce` |
| `AUD-14g-3` | P3 | B23 | Removing an account leaves its notifications in the shade, with preview text |
| `AUD-14g-4` | P3 | B23 | A press on a message notification of the account already open navigates nowhere |
| `AUD-14g-5` | P3 | B23 | A missed call in a muted chat still posts a notification |
| `AUD-14g-6` | P3 | B23 | The missed-call notification treats the app being `inactive` as away |
| `AUD-14g-7` | P3 | B23 | One failed Firebase start disables push for the rest of the process |
| `AUD-14h-2` | P3 | B23 | Deleting one ringtone pack can delete another pack's copy and channel |
| `AUD-14h-3` | P3 | B23 | Two publishes of one ringtone share a temporary file |
| `AUD-14h-1` | P3 | B24 | A repeating crash keeps postponing the batch that would carry it |
| `AUD-14i-1` | P3 | B25 | A chat day is counted in elapsed hours, so the day after a clock change shows yesterday as today |
| `AUD-14i-2` | P3 | B25 | A search snippet can begin inside an emoji |
| `AUD-14j-1` | P3 | B10 | One undecodable theme pack takes every installed pack with it, and cannot be deleted in-app |
| `AUD-14j-2` | P3 | B10 | More themes re-reads up to 64 manifests one at a time on every visit |

**Total: 210 findings** — 7 P1, 39 P2, 158 P3, 6 Idea.

