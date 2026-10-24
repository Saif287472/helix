# Sweep 5 — backup + media

Scope: `server/lib/src/modules/backup/{module.dart,MODULE.md}`,
`server/lib/src/modules/media/{module.dart,api.dart,MODULE.md}`, the blob
layer they sit on (`platform/blobs/object_storage.dart`), the storage-budget
hook and the route catalog entries. Cross-checks: identity account deletion,
job timeout/attempt defaults, protocol `modules/backup.dart`,
`docs/product/BACKUP_RECOVERY.md`, `docs/protocol/v2/REST_V2.md`, and
`server/test/modules/media_backup_test.dart`.

Files read: backup 268 + media 481 + media/api 12 + object_storage 340 +
docs 65 + routes 130 + cross-check slices (~120) ≈ 1,420 lines.

## What is sound

- Ownership is checked on every mutating media route with 404 (not 403), and
  the download route is deliberately open to any signed-in device because ids
  are random and content is client-encrypted (media/module.dart:203-209,
  268-274, 352-358).
- Declared size is enforced twice: the streamed upload stops at `maxSize`
  (object_storage.dart:110-118, media/module.dart:236-252) and a presigned PUT
  signs `content-length` (object_storage.dart:246-251), so the store refuses a
  different size.
- Expiry is applied at read time as well as by the sweep, so an expired object
  is a 404 even before housekeeping runs (media/module.dart:194-198, test
  media_backup_test.dart:202-217).
- `Range` parsing never 500s: an unparseable header is ignored (full 200) and
  an unsatisfiable one is 416 (media/module.dart:329-350, test 142-153).
- Blob-before-row deletion in both the sweep and the account purge keeps the
  row for a retry instead of forgetting the file (media/module.dart:366-419).
- Blob keys are server-chosen, grammar-checked and path-escape-checked, and
  the orphan sweep has a one-day grace so an upload whose row is being written
  is never deleted (object_storage.dart:80-90, 144-160; media/module.dart:37,
  424-460).
- Backup: forbidden fields are refused at any depth and JSON depth/node limits
  run before decoding; version monotonicity is one SQL statement; the
  server-wide budget is checked before the write; the history row is deleted
  in the same transaction as an identity-key change (backup/module.dart:22-32,
  95-98, 125-144, 168-225).
- `FullBackup.meta` answers 200 `{exists:false}` and never 404 (backup
  module.dart:248-259) — the client can tell "no backup" from "no route".

## Findings

### AUD-5-1 Deleting an account frees its media only through one best-effort job; persistent media then never expires

**Severity:** P2
**Confidence:** likely
**Where:** [media/module.dart:18](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L18)
(the only cleanup: an outbox job enqueued from `onAccountDeleted`),
[media/module.dart:391](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L391)
(`_purgeAccount` reads **every** row for the account in one query, then deletes
blob+row one by one, throwing once if any blob failed),
[media/module.dart:45](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L45)
(`persistent` retention is `null`, so those rows never age out),
[media/module.dart:82](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L82)
(no FK from `media.objects.owner_account` to accounts),
[identity/module.dart:216](/J:/Projects/helix/helix_remote/server/lib/src/modules/identity/module.dart#L216)
(the hook runs, then only `identity.accounts` is deleted),
[jobs.dart:27](/J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart#L27)
(default 8 attempts) and
[jobs.dart:271](/J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart#L271)
(5-minute job timeout).
**What:** Account deletion has exactly one path that removes media bytes: the
`media.purge_account` outbox job. The job is not idempotent-by-reconcile (it
only looks at the payload's account id), loads the account's whole row set into
memory before it starts deleting, and every row costs one blob delete. If the
store is slow (AUD-1c-1: no request timeout), if the job hits the 5-minute
budget, or if it exhausts its 8 attempts, it dead-letters (AUD-1b-1).
**Trigger:** delete an account holding many small objects, or any account
while object storage is slow/unreachable for the retry window.
**Evidence:** the purge job is the sole hook (media/module.dart:18-21);
nothing else in the schema ties objects to a live account — `owner_account` is
a bare `uuid` (82-97) — and `persistent` objects have `expires_at = NULL` and
no retention (45-49), so neither `media.expire` (370-387) nor the weekly orphan
sweep (424-460) can reach them: the rows still exist, so the blobs are not
orphans. A dead job's dedupe key also blocks a re-enqueue (AUD-1b-1).
**Impact:** encrypted avatar/group-picture blobs and their rows survive the
account forever, against the deletion promise in `media/MODULE.md:30-36`, and
keep consuming the owner's former quota and the server-wide budget. The DB row
set also stays visible to admin export/storage metrics with no owner.
**Fix sketch:** no wire change. Add a periodic, batched, cursor-resumable
`media.reconcile` (see S3) that deletes rows whose `owner_account` has no
`identity.accounts` row (blob first), and make `_purgeAccount` itself batched
(keyset over `id`, commit per chunk) so a big account cannot time out.
**Test that proves it:** delete an account with N persistent objects, mark the
purge job dead (or make `_blobs.delete` throw), run the reconcile/drain, and
assert no rows remain and the store has no blobs.
**Overlap:** AUD-1b-1 (dead dedupe key), AUD-1c-1 (no S3 timeout), AUD-1b-2
(periodic lease), S3 below.

### AUD-5-2 Deleting or replacing the recovery backup leaves its ciphertext (and 1 GiB of quota) for 90 days

**Severity:** P3
**Confidence:** confirmed
**Where:** [backup/module.dart:261](/J:/Projects/helix/helix_remote/server/lib/src/modules/backup/module.dart#L261)
(`_deleteFull` deletes only the row),
[backup/module.dart:222](/J:/Projects/helix/helix_remote/server/lib/src/modules/backup/module.dart#L222)
(a higher-version PUT extends only the ids it lists),
[media/module.dart:476](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L476)
(`extendBackupMedia` sets `now() + 90 days`),
[media/module.dart:45](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L45)
(backup retention).
**What:** `backup`-kind media exist only to be referenced by the full backup's
`media_ids`, but nothing deletes them when that reference goes away. The
`DELETE` route removes the row; a new full backup extends the ids it names but
silently leaves the previous backup's ids on their old 90-day clock. The
ciphertext therefore stays downloadable by any signed-in device that still
holds the ids and keeps occupying the account's 1 GiB `backup` quota.
**Trigger:** Settings > Backup > delete the recovery backup, or re-create it
after the media set changed; then try to upload new backup media.
**Evidence:** `_deleteFull` is a single `DELETE FROM full_backups`
(261-267); `extendBackupMedia` is the *only* writer of backup-media expiry
beyond creation (media/module.dart:469-480); the retention default is 90 days
(45-49). Nothing ever shortens `expires_at`.
**Impact:** "delete my recovery backup" does not delete the recovery material's
ciphertext, and the freed space is not freed — a later backup can fail with
`quota_exceeded` even though the account (as the UI sees it) has no backup.
Privacy impact is limited by the ids being secret and the blobs encrypted, but
the retention and quota behaviour contradict what a delete implies.
**Fix sketch:** no wire change. In `_deleteFull`, delete the referenced
`backup`-kind objects (blob first, then row; enqueue a job if the caller must
not block) inside the same flow; on `_putFull`, set `expires_at = now()` for
the account's `backup` objects whose id is not in the new `media_ids` (a
`NOT id = ANY(...)` update), or let S3's reconcile collect unreferenced ones.
**Test that proves it:** put a full backup with media, `DELETE` it, assert the
objects rows are gone, the download is 404, and a new upload of the same size
succeeds at quota.
**Overlap:** S3.

### AUD-5-3 A byte-only quota lets one account turn its 4 GiB into millions of rows, and the sweeps that clean them are per-object and time-boxed

**Severity:** P3
**Confidence:** confirmed
**Where:** [media/module.dart:147](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L147)
(quota is `sum(size)` per kind; no row count),
[media/module.dart:135](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L135)
(only `size <= 0` is refused, so a 1-byte object is legal),
[media/module.dart:370](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L370)
(`_expire` deletes 500 rows per query but loops unbounded, one blob delete per
row),
[media/module.dart:391](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L391)
(purge reads all rows at once),
[jobs.dart:271](/J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart#L271)
(5-minute job timeout).
**What:** The per-account quota counts bytes, never objects. The smallest legal
object is 1 byte, so a 4 GiB attachment quota is up to ~4.3 billion rows; at
the global 10 req/s per IP that is still ~860k rows/day, and each row costs a
DB row plus an index entry (and the small blob) while contributing 1 byte of
"quota". Cleanup is one blob delete per object, inside a 5-minute job; the
account purge materialises the full row list before deleting.
**Trigger:** an authenticated account creates and completes 1-byte attachments
(one `POST /v1/media`, one 1-byte `PUT` each) and keeps doing it; 30 days later
`media.expire` must delete them all, and a later account deletion must purge
them.
**Evidence:** quota arithmetic at 147-171; `req.size <= 0` is the only floor
(135); schema has no count constraint (82-97); the sweep's unit of work is
`_deleteObject` (408-419) per row, and the job has a 5-minute budget; the
purge queries every row into a `List` before the first delete (391-397).
**Impact:** cheap database bloat that the storage budget only notices after
the fact (`StorageBudget` measures table size), slow/failing housekeeping and
purge jobs, and — through AUD-5-1 — media that survives an account deletion
because its purge job could not finish.
**Fix sketch:** server only. Add a per-account object cap to `_create` (e.g.
`count(*)` with the kind, or a cheap `LIMIT cap+1` probe) and/or a minimum
size; batch `_expire` and `_purgeAccount` with a keyset cursor and a time
budget so a run always commits progress.
**Test that proves it:** create `cap + 1` tiny objects and assert the last
`POST` is `quota_exceeded`; make the sweep's delete slow and assert it stops
before the job timeout with the cursor persisted.
**Overlap:** AUD-5-1, AUD-1c-1 (each blob delete is an untimed store call).

### AUD-5-4 Upload quota is a read-then-insert with no serialization, so concurrent creates overshoot it

**Severity:** P3
**Confidence:** confirmed
**Where:** [media/module.dart:147](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L147)
(`SELECT sum(size)` then `INSERT` in the same transaction, no lock and no
`FOR UPDATE`; the sum is over existing rows only),
[media/module.dart:139](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L139)
(the server-wide check reads a measurement cached for a minute,
storage_budget.dart:63-75).
**What:** Under READ COMMITTED two concurrent `POST /v1/media` requests both
see the pre-insert sum and both insert, so one account can reserve up to
`concurrency × max size` beyond its quota in a single burst (and beyond the
server budget, which is deliberately cached). Abandoned reservations then hold
that space for a day (`_expire` deletes incomplete objects after 1 day,
media/module.dart:376).
**Trigger:** fire N creates of the largest attachment size at once; or one
device creates an upload and never sends the bytes.
**Evidence:** the only guard is the sum read at 147-152; the insert at 158-170
does not re-check; there is no advisory lock, row lock or counter column, and
`StorageBudget.used()` caches for `refreshEvery` (1 minute).
**Impact:** bounded overrun of both the per-account quota and the server-wide
budget, i.e. a short window in which the disk can be pushed past its limit by
one authenticated account. Not unbounded, but the quota is the last line
before the budget, and the budget is intentionally stale.
**Fix sketch:** server only, no wire change. Serialise per account (e.g.
`SELECT ... FROM identity.accounts WHERE id = ... FOR UPDATE` is cross-module
SQL, so instead maintain a `media.account_usage` counter row updated with
`UPDATE ... SET bytes = bytes + @n WHERE ... AND bytes + @n <= @q RETURNING`),
or accept the race and document that the quota is advisory.
**Test that proves it:** issue two creates concurrently at a quota boundary and
assert the second is refused (a deterministic version can use a barrier inside
the transaction).
**Overlap:** AUD-5-3 (both are quota-enforcement gaps), 1c storage budget.

### AUD-5-5 Two concurrent chunk uploads of one object can interleave and leave a corrupt, over-size blob

**Severity:** P3
**Confidence:** likely
**Where:** [object_storage.dart:103](/J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L103)
(`append` reads the file length, compares to `offset`, then reopens in append
mode — no lock between the check and the writes),
[object_storage.dart:110](/J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L110)
(each request tracks `written` from its own `current`),
[media/module.dart:253](/J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L253)
(`completed_at` is set when a request's own `stored == size`).
**What:** Both requests read `current == 0`, both pass the offset check, and
both append. Each enforces `maxSize` against its own counter, so the file can
reach twice the declared size; one of them can still see `stored == size` and
mark the object complete. A later download serves `size` bytes of a blob that
is the interleaving of two writers. A retry storm from one device (network
flap, two app instances) is enough; no attacker is required.
**Trigger:** two `PUT /v1/media/{id}/content` calls for the same object with
the same `Upload-Offset`, concurrently.
**Evidence:** the sequence at 103-118 is `exists()` → `length()` → `open(append)`
with no lock; `written` (110) is per-request state, so the `> maxSize` check
never sees the other request's bytes; the completion decision is made in the
handler from the request's own return value (media/module.dart:253-257).
**Impact:** owner-only corruption of an object that was already declared
complete — the recipient may store a truncated/garbled attachment and the
owner has no way to tell. Requires concurrency on one upload id, so it is a
durability bug rather than a cross-account issue.
**Fix sketch:** server only. Make `append` take an exclusive advisory file
lock (or a per-object in-process lock plus an expected-size check before
`completed_at` is set), and set `completed_at` only when `_blobs.size(key) ==
size` after the write.
**Test that proves it:** two concurrent `append` calls at offset 0 on a 2 MiB
object; assert final size == declared, or that exactly one call returns
`OffsetMismatch`.
**Overlap:** none.

### AUD-5-6 Backup PUTs have no per-route limit, so one account can spend the node's CPU on 64 MiB JSON

**Severity:** P3
**Confidence:** confirmed
**Where:** [backup/module.dart:100](/J:/Projects/helix/helix_remote/server/lib/src/modules/backup/module.dart#L100)
(`routes()` registers no `rateLimit`; only public routes are forced to have
one, platform/http/routes.dart:119-121),
[backup/module.dart:183](/J:/Projects/helix/helix_remote/server/lib/src/modules/backup/module.dart#L183)
(`_putFull` scans the body, decodes it, then `jsonEncode`s it again),
[backup/module.dart:125](/J:/Projects/helix/helix_remote/server/lib/src/modules/backup/module.dart#L125)
(`_putHistory`, 16 MiB body),
[pipeline.dart:23](/J:/Projects/helix/helix_remote/server/lib/src/platform/http/pipeline.dart#L23)
(the only limiter is 600 burst / 10 per s per IP).
**What:** Every other heavy authenticated write in this repo has a per-principal
policy; the two backup `PUT`s have none. Each request buffers up to 64 MiB
(body budget), scans it byte by byte (`checkJsonShape`), decodes it, walks it
for forbidden keys, and re-encodes the envelope into a parameter — roughly
three copies of the body in memory and full JSON parsing of it. At the global
rate one account can keep the node parsing JSON continuously, and a full-page
`jsonb` rewrite per request churns WAL/TOAST.
**Trigger:** an authenticated account loops `PUT /v1/backups/full` with a large
envelope (or an account whose device is compromised/buggy).
**Evidence:** route registration at 100-123 has no `rateLimit` argument; the
limiter is only applied when a registration supplies a policy
(platform/http/routes.dart:231-236); the three-pass body handling is at
183-215 (`q.json(...)` inside `checkJsonShape` + `decode`,
`_carriesSecret`, `jsonEncode`).
**Impact:** a single authenticated principal can occupy the node's CPU and
memory bandwidth, degrading every other API on that node (the body budget
caps bytes in flight, not work per second). Self-inflicted storage churn is
bounded by one row per account.
**Fix sketch:** server only. Add a per-principal `rateLimit` to both routes
(e.g. 6/min for the full backup, 12/min for the history) and/or make
`checkJsonShape` + `jsonEncode` unnecessary by storing the body text directly
(the envelope is opaque; `jsonb` is not needed to read it back).
**Test that proves it:** the public-route snapshot already pins policies; add
a test that the last of 10 rapid full-backup PUTs gets `rate_limited`.
**Overlap:** AUD-1a-1 (body budget), sweep 3 send limits.

## Structural proposal

### S3 The media lifecycle has no single owner and no reconciliation

**Current shape:** an object's life is decided by five independent mechanisms —
`expires_at` written at create (media/module.dart:146-170), `completed_at` +
a one-day rule (376), the weekly orphan sweep (424-460), the one-shot account
purge job (18-21, 391-404), and backup-driven `extendBackupMedia`
(469-480). Rows and blobs are two stores with no shared transaction, and
nothing ever compares the set of rows to the set of live accounts or to the
set of blobs.
**Hazard:** every failure mode of that split is silent and permanent for
`persistent` media: a dead purge job (AUD-5-1), a timed-out sweep (AUD-5-3), or
a row whose blob is gone (download 500s, quota held). There is no place to add
an object-count cap or a "backup was deleted" rule without touching each
mechanism separately.
**Proposed shape:** one periodic `media.reconcile` (weekly, capped at ~5
minutes, keyset-resumable, dry-run counter first) that: (a) deletes rows whose
`owner_account` is absent from `identity.accounts` (through `IdentityApi`, not
SQL), blob first; (b) enforces a per-account object cap; (c) reports drift
between `List`/`size` and rows. Keep `expires_at` as the primary retention
rule; reconcile is the backstop, not a replacement. The account purge stays
for prompt deletion but becomes batched and simply runs the same reconcile for
one account.
**Migration path:** expand: add the periodic job and the cap check (with the
cap set above current per-account counts, or off by default). Migrate: run in
dry-run for a while, compare counts. Contract: turn the cap on, remove the
purge job's non-batched path. No schema change needed; `objects_owner` already
covers the scans.
**Risk:** a reconcile bug can delete live media — mitigate with the dry-run
period, the account-existence check restricted to `IdentityApi`, and the
one-day blob grace.
**Rough size:** ~150 lines in media + a small `IdentityApi` lookup (already
exposed via `identity.account`) + 4 tests.

## Coverage gaps / not measured

- S3 object storage was not exercised live (no server started, no credentials);
  every S3 path was read only. AUD-1c-1 covers its missing timeouts.
- Device-to-device transfer (`transfer_jobs`) is engine-side; server sees only
  ordinary media uploads. Covered in sweep 12/15, not here.
- Backup merge/retry semantics after a 409 are client behaviour (engine/app,
  sweeps 12/15); the server side of version monotonicity is sound.
- No concurrency test exists for media quota or chunked upload; both races
  (AUD-5-4, AUD-5-5) are read from the code, not observed.
