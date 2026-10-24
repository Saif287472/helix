# Sweep 4a — people module

People owns profiles (ciphertext), display names, privacy audiences, blocks,
contacts, contact discovery, `~name` lookup, presence, read budgets and
reports. Schema `people`; everything below is that module plus the call sites
that make its invariants real (messaging's block policy and delivery, admin's
report count, the route table).

Findings: **P1 1, P2 1, P3 6**. The P1 is new in kind: a *server-generated
stored envelope* triggered by an unthrottled user action.

## Files read

| File | Lines |
|---|---|
| `helix_remote/server/lib/src/modules/people/MODULE.md` | 65 |
| `helix_remote/server/lib/src/modules/people/api.dart` | 41 |
| `helix_remote/server/lib/src/modules/people/module.dart` | 780 |
| Cross-checks: `messaging/module.dart` (deliver/trim), `messaging/data/mailbox_store.dart` (quota/trim), `messaging/api.dart` (Delivery), `platform/http/{pipeline,routes}.dart`, `admin/module.dart` (report count), `protocol` people DTOs + `json.dart`, groups `mayAddToGroup` call sites, `test/modules/people_test.dart` titles | ~450 |

Not read this turn: groups (4b), federation delivery of blocks, app UI for
blocks/reports, identity's discovery-index rebuild (sweep 2, other agent).

## What is sound

Worth recording so the fixes below do not disturb it:

- Discovery budget increment and the over-budget check are in one
  transaction, so a refused call consumes nothing
  ([module.dart:278](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L278)).
- Profile writes are guarded by `version < excluded.version` in the upsert, so
  two devices cannot regress a profile
  ([module.dart:414](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L414)).
- Block checks are applied consistently to discovery, name lookup and presence
  ([module.dart:311](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L311),
  [module.dart:452](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L452)).
- Read limits refund the distinct-target token when the token limit refuses the
  read ([module.dart:377](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L377)).
- `mayAddToGroup` is only reached with local ids; the callers guard remote
  addresses before the `_uuid` cast
  ([groups/module.dart:484](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L484),
  [groups/federation.dart:318](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L318)).

---

### AUD-4a-1 Block/unblock is an unthrottled stored-envelope fan-out that can flush an offline account's mailbox

**Severity:** P1
**Confidence:** confirmed
**Where:** [people/module.dart:506](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L506) (`_block`), [people/module.dart:522](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L522) (`_unblock`), [people/module.dart:539](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L539) (`_tellBlocked`), routes [people/module.dart:173](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L173); [messaging/module.dart:578](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L578) (`deliver` + `trim`), [mailbox_store.dart:20](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L20) (quota), [mailbox_store.dart:107](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L107) (`trim`); global limiter only, [pipeline.dart:23](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/pipeline.dart#L23).

**What:** Every block or unblock that actually changes a row calls
`_tellBlocked`, which stores a `block_change` envelope for **every active
device of the target** ([people/module.dart:546-555](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L546)).
`messaging.deliver` allocates a mailbox row per device and, once that device's
`pending` exceeds the 10,000-envelope quota, deletes its **oldest** rows
([messaging/module.dart:591-593](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L591),
[mailbox_store.dart:107-131](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L107)).
Neither block nor unblock has a per-route `rateLimit`
([people/module.dart:173-175](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L173);
the registry applies a limiter only when one is set,
[routes.dart:230-240](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L230)),
so the only bound is the global 10 requests/second per IP. Each request writes
one `blocks` row and fans out one envelope per target device; alternating block
and unblock makes both directions fire forever. The routes are also
`allowSuspended: true`, so a suspended account can still do it.

**Trigger:** Sign in as any account, learn the victim's account UUID (e.g.
`~name` lookup, a past chat, a group member list), then alternate
`PUT/DELETE /v1/people/blocks/<id>` at ~10 req/s while the victim's devices are
offline. With one device the victim's 10,000-row quota fills in ~17 minutes;
with five devices, ~3½ minutes.

**Evidence:** `_block` inserts, then `_tellBlocked` → `deliver` →
`MailboxStore.allocate` counts the row as pending and returns `over`;
`deliver` then calls `trim`, whose `DELETE ... ORDER BY seq LIMIT n` removes
the oldest undelivered envelopes
([mailbox_store.dart:118-126](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L118)).
`Delivery.urgent` defaults to false
([messaging/api.dart:50](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/api.dart#L50)),
so no push is sent, but the rows are stored and count toward the quota all the
same. Nothing in `deliver` treats server-generated kinds differently
([messaging/module.dart:563-612](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L563)).
The module's own test only checks that blocking stops messages; no test
delivers into a full mailbox.

**Impact:** Silent, permanent loss of the victim's oldest undelivered
envelopes — messages, group updates, and parked call signals — because the
quota trims them. The victim's 30-day mailbox retention becomes "until anyone
with your id decides to flap a block", and the loss is invisible to the
recipient (the sender still has the message). Anything that reaches
`deliver` with no sender-side budget is a lever on another account's storage.
Secondary effect: the victim's client shows a stream of block/unblock events.

**Fix sketch:**
- Best: stop storing `block_change`. It is advisory ("so their chat says so
  before they type" — [people/module.dart:535-537](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L535)),
  and an offline device learns the state from the next send's `blocked_by`
  anyway. Deliver it to online sockets only (the realtime bus / ephemeral
  path). Wire: same envelope kind, but it must tolerate a seq-less server
  frame; verify the engine's handling before switching.
- Keep it stored, but make it idempotent and bounded: notify at most once per
  (blocker, target, state) per window (6 h) — a `blocks.notified_at` column
  or an ephemeral marker — plus a per-account rate limit on block/unblock
  (e.g. 60/hour). This removes the flap without changing delivery semantics.
- Minimum partial fix: charge the fan-out through `chargeStored` against the
  blocker's stored-envelope budget, so a flapper runs out of budget. Note the
  attack still works until the budget is exhausted; caps should be small.

**Test that proves it:** Fill a victim device's mailbox to quota−1, queue one
ordinary message, then block/unblock N times. Assert the ordinary message is
still fetched (today it is trimmed away). A simpler guard: assert the second
block change for the same pair inside the window writes no envelope.

**Overlap:** AUD-3-1 (fan-out is O(devices) round trips), AUD-3-2 (a crash
between trim and pending accounting), AUD-1b-1 (dropped pushes are a different
side of the same "server-generated traffic has no budget" problem). Structural
proposal S1.

---

### AUD-4a-2 Account-deletion purge scans the whole contacts table

**Severity:** P2
**Confidence:** confirmed
**Where:** schema [people/module.dart:140-144](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L140), purge [people/module.dart:257-260](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L257); blocks has its index at [people/module.dart:139](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L139).

**What:** `_purge` deletes contacts with
`DELETE FROM people.contacts WHERE account_id = @a OR contact = @a`. The only
index is the primary key `(account_id, contact)`; there is no index on
`contact`, so the second branch forces a sequential scan of the **entire**
`contacts` table inside the account-deletion transaction. Blocks has exactly
this index (`blocks_blocked`, line 139); contacts was never given one.

**Trigger:** Delete any account once the server's contacts table is large.
Each account may upload up to 5,000 entries
([module.dart:595](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L595)),
so 10,000 active accounts can hold 50 M rows.

**Evidence:** The schema at lines 140-144 defines only the composite primary
key; the purge at 257-260 uses `contact` alone. PostgreSQL can bitmap-OR two
indexes but cannot use `(account_id, contact)` for a `contact`-only predicate
(the leading column is absent).

**Impact:** Account deletion is a privacy guarantee and runs as one
transaction with the identity hooks; at scale the scan can exceed the
statement/transaction timeout, so the deletion fails or holds locks while every
other purge waits. Cost grows with total users, not with the deleted account.

**Fix sketch:** New people migration adding
`CREATE INDEX contacts_contact ON people.contacts (contact);`. If the runner
wraps migrations in a transaction, a plain build blocks writes on a large
table: build it in a low-traffic window or add a non-transactional
`CONCURRENTLY` path to the runner (expand → migrate). Schema only; no wire or
app change. Add a small test that every purge predicate has a supporting
index, so the next cross-account table cannot repeat this.

**Test that proves it:** `EXPLAIN (ANALYZE)` the purge statement on a seeded
table shows `Seq Scan on contacts` before and an index/bitmap scan after.

**Overlap:** AUD-4a-3 (the same table is rewritten with no limit), and the
account-deletion fan-out across modules (sweep 1b/2).

---

### AUD-4a-3 `setContacts` rewrites up to 5,000 rows per call with no per-account limit

**Severity:** P3
**Confidence:** confirmed
**Where:** route [people/module.dart:178](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L178), handler [people/module.dart:592-614](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L592).

**What:** Each call deletes every row for the account and re-inserts up to
5,000 in one transaction, and the route has no `rateLimit`; only the global
10/s per IP applies. The body cap is 512 KiB, so a full list fits.

**Trigger:** A client (or a retry loop / phone-book sync on every launch) with
a large address book calls the endpoint repeatedly.

**Evidence:** [module.dart:602-612](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L602)
shows the delete-all/insert-all pair; the registration at line 178 passes no
policy, and [routes.dart:230-240](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L230)
applies none when it is absent.

**Impact:** 10 k row writes per call, up to 10 calls/s from one IP: WAL and
lock load on a table that is already the target of the unindexed
account-deletion scan (AUD-4a-2). An otherwise idle personal server can be made
to work at full write speed by one signed-in client.

**Fix sketch:** Add a per-account policy (e.g. 12/hour) to the route; diff
instead of replace (`DELETE ... WHERE contact <> ALL(@ids)` plus
`INSERT ... ON CONFLICT DO NOTHING`) so a no-op sync writes nothing. No wire
change.

**Test that proves it:** Post the same list twice; assert the second call
issues no row writes, and that the N+1st call within the window is 429.

**Overlap:** AUD-4a-2.

---

### AUD-4a-4 Discovery budget rows are never swept and the refusal names the wrong retry time

**Severity:** P3
**Confidence:** confirmed
**Where:** table [people/module.dart:145-150](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L145),
increment/refusal [people/module.dart:278-294](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L278), retry hint [people/module.dart:290](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L290),
periodic jobs [people/module.dart:68-78](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L68) (reports only).

**What:** `discovery_budget` keeps one row per account per day and nothing
deletes past days except account deletion. The budget is daily
(`current_date`), but an over-budget response says `retryAfter: 1 hour`, so a
well-behaved client retries hourly all day and is refused each time. Each
refused attempt still runs the upsert and then rolls back, leaving a dead
tuple.

**Trigger:** Any server where discovery is used daily; a client that honours
`retry_after`.

**Evidence:** The only `PeriodicJob` is `people.purge_reports`
([module.dart:71-78](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L71));
`_purge` removes the table only for deleted accounts
([module.dart:243-248](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L243)).

**Impact:** Unbounded growth at one row per discovering account per day (small
rows, but no ceiling: 1 M daily users = 365 M rows a year), and pointless
retry traffic rooted in a misleading hint.

**Fix sketch:** Daily job deleting `day < current_date - 2`; compute
`retryAfter` as the interval to the next UTC midnight (cap it). Additive wire
behaviour only (`retry_after` already exists; the app should accept hours).

**Test that proves it:** Seed yesterday's rows, run the job, assert they are
gone; assert `retry_after` is within 24 h of the next boundary.

**Overlap:** None.

---

### AUD-4a-5 Report notes are free text that outlive the account, contradicting "ids only"

**Severity:** P3
**Confidence:** confirmed
**Where:** schema [people/module.dart:151-160](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L151),
comment [people/module.dart:184-186](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L184),
intake [people/module.dart:616-640](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L616),
export [people/module.dart:228-238](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L228);
claim [MODULE.md:53-58](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/MODULE.md#L53);
test [people_test.dart:330-341](file:///J:/Projects/helix/helix_remote/server/test/modules/people_test.dart#L330).

**What:** `_report` stores the client's `note` (≤ 500 chars), and reports are
deliberately not purged on account deletion — so free text written by a
deleted account survives. `MODULE.md` and the code comment say reports are
"ids only" and "store no message content", and the test titled "reports are
stored without content" posts `note: 'sends links'`. The note is also absent
from the account export's `reports_filed`.

**Trigger:** File a report with a note, then delete the reporter's account. An
open report has no retention limit at all.

**Evidence:** `INSERT ... (id, reporter, subject, category, note)` at
[module.dart:630-639](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L630);
`_purge` never names `reports` ([module.dart:242-261](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L242));
the export selects every column except `note`
([module.dart:233-237](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L233)).
The app sends a user-entered string
([contact_info_screen.dart:140](file:///J:/Projects/helix/helix_remote/app/lib/features/people/presentation/contact_info_screen.dart#L140)).

**Impact:** A documented privacy invariant ("no content") is false, and a
user can paste message content into a note that then outlives their account.
Compliance/export is incomplete for the reporter.

**Fix sketch:** Decide the product line. Either drop `note` from the wire and
schema (contract migration), or keep it and fix the docs, retention and export:
mention free-text notes in `MODULE.md`/metadata docs, include the note in the
export, and bound open reports by age (see AUD-4a-6). If notes stay, a
"contains no message content" warning in the app is cheap.

**Test that proves it:** File a report with a note, delete the reporter, assert
the note is gone (or the docs claim is updated and the export contains it).

**Overlap:** AUD-4a-6.

---

### AUD-4a-6 Report intake checks neither the subject nor duplicates, and open reports never expire

**Severity:** P3
**Confidence:** confirmed
**Where:** [people/module.dart:616-640](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L616), retention job [people/module.dart:68-78](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L68).

**What:** `_report` validates only UUID syntax: it accepts reports about
nonexistent accounts and about oneself, has no dedupe key and no daily cap
(20/hour with no total). The purge job deletes only reports with a
`resolved_at`, so **open** reports accumulate forever.

**Trigger:** A signed-in account reports the same UUID repeatedly (480/day,
unbounded in aggregate).

**Evidence:** [module.dart:625-628](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L625)
checks `Uuid.isValid` and note length only; the schema has no unique
constraint ([module.dart:151-160](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L151));
the job deletes `WHERE resolved_at < now() - …`
([module.dart:72-77](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L72)).

**Impact:** The operator queue and `reports` table grow without bound; the
per-account count shown in the admin console counts duplicates, and reports
about ids that never existed cannot be acted on. Purely operational (no direct
data exposure), but it is the input to the operator workload.

**Fix sketch:** Check the subject exists and is not the reporter (via the
identity facade); add a partial unique index on
`(reporter, subject, category) WHERE status = 'open'` and treat a duplicate as
the existing report; add a daily cap; auto-close open reports older than N days
(e.g. 90) with an operator-visible reason. Schema + one migration; API stays
`201` (return the existing id) or `409`.

**Test that proves it:** A second identical report creates no new row;
reporting an unknown UUID is rejected.

**Overlap:** AUD-4a-5, AUD-4a-7.

---

### AUD-4a-7 `openReportsAbout` has no index on `reports.subject`

**Severity:** P3
**Confidence:** confirmed
**Where:** [people/module.dart:761-768](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L761); caller [admin/module.dart:465](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L465); schema [people/module.dart:151-160](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L151).

**What:** `WHERE subject = @a:uuid AND status = 'open'`; the only index is
`reports_open (created_at) WHERE status = 'open'`, which does not cover
`subject`. Every view of an account in the admin console is a sequential scan
of `reports`.

**Trigger:** Admin opens an account page once the reports table is large
(made easy by AUD-4a-6).

**Evidence:** Schema lines 151-160, query line 764.

**Impact:** The operator console degrades linearly with the whole table, not
with the account's reports. Small today, unbounded by design.

**Fix sketch:** `CREATE INDEX reports_by_subject ON people.reports (subject) WHERE status = 'open';`
in a new migration. If the table is already big, build concurrently (same
runner caveat as AUD-4a-2).

**Test that proves it:** `EXPLAIN` on the query before/after.

**Overlap:** AUD-4a-6.

---

### AUD-4a-8 The account export silently truncates reports filed at 500

**Severity:** P3
**Confidence:** confirmed
**Where:** [people/module.dart:200-203](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L200) and [people/module.dart:228-238](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L228).

**What:** `SELECT ... ORDER BY id DESC LIMIT 500` with no count and no
`truncated` marker; the export presents the list as complete.

**Trigger:** An account with more than 500 reports (reachable at 20/hour).

**Evidence:** The `LIMIT 500` at line 202; `reports_filed` is the only output.

**Impact:** A data export that is silently incomplete — the user cannot tell.

**Fix sketch:** Return a total and a `truncated` flag, or paginate; additive
JSON fields. No wire break.

**Test that proves it:** Seed 501 reports, assert the flag/total.

**Overlap:** AUD-4a-6.

---

## Structural proposal

### S1 — Server-generated stored envelopes need one budgeted path

**Current shape.** `MessagingApi.deliver` is open to every module and always
stores a row per recipient device and trims that device's oldest envelopes when
over quota ([messaging/module.dart:563-612](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L563),
[mailbox_store.dart:107-131](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L107)).
The caller decides kind and urgency; nothing charges the *sender* or bounds the
rate at which a module-generated signal can enter another account's mailbox.
`people._tellBlocked` is the live example (AUD-4a-1); identity's device/prekey
signals and groups' membership relays use the same door.

**Hazard.** A cheap, unthrottled user action becomes a write into someone
else's quota-limited storage, and the recipient's oldest real messages are the
casualty. Each new server-generated kind re-opens the question with a fresh
call site rather than a policy.

**Proposed shape.** One `notify(...)` entry point in messaging that (a)
classifies a kind as *advisory* (may be ephemeral, best-effort) or *required*
(must store, e.g. `device_list_change`), (b) enforces per-sender and
per-(sender, recipient) rate/dedupe rules, and (c) charges or refuses when a
recipient is at quota instead of trimming silently. `deliver` stays for
user messages; server signals go through `notify`.

**Migration path.** Add the classification and limits inside messaging and
route existing server-generated sends through it (expand). Move `block_change`
to advisory/ephemeral after checking the engine accepts seq-less frames
(migrate). No wire change; no schema change unless a dedupe table is chosen
(one small migration). Keep `device_list_change` stored throughout.

**Risk.** Ephemeral delivery is lost for offline devices; that is acceptable
for block state (learned on next send) but not for device-list changes, so the
classification must be deliberate. Rate limits on signals must not delay a
genuine block notification past the first send.

**Rough size.** ~250 lines in messaging (policy table, dedupe, notify), call
sites in people/identity/groups, one optional migration, tests per kind.

## Coverage gaps

- Groups, invites and membership fan-out: sweep 4b.
- Federation: blocks for `uuid@domain` are stored and consulted, but no test
  or trace of a remote sender reaching `blockedBy` was verified end to end.
- The app's block/unblock UI and its handling of repeated `block_change`
  frames were not read.
- `identity.setPhoneDiscoverable` rebuild cost: sweep 2 (other agent).
- No server tests were run (no database URL used); findings here are from
  schema and code paths, and the missing indexes are direct schema facts.
