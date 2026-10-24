# Sweep 7 — ops, admin, compliance (packs, `HELIX_PACKS_DIR`, admin authz)

Read (2026-10-23, ~2,266 lines plus cross-checks): `server/lib/src/modules/
ops/{module.dart (552), api.dart (44), pack_host.dart (199), open_page.dart
(70), share_page.dart (70), MODULE.md}`, `admin/{module.dart (787), MODULE.md,
data/admin_store.dart (311), domain/local_address.dart (37),
domain/password_hash.dart (88)}`, `compliance/{module.dart (108), MODULE.md}`,
the admin/ops/compliance rows of `packages/helix_remote_protocol/lib/src/
routes.dart` (788-945), `kernel/jwt.dart` (105), the maintenance gate in
`platform/http/pipeline.dart` (67-75, 140-170), `platform/config/
server_config.dart` (354-355), and the export/paging implementations the two
modules call (`identity/data/admin_store.dart` 184-245, `people/module.dart`
187-215 & 690-706, `media/module.dart` 50-70, `groups/module.dart` 110-135),
plus `tool/theme_pack_tool.dart`'s publish path.

## What is sound

- **Admin authz is route-level and two-keyed.** Every `/v1/admin/*` route is
  `access: _adm` in the catalog ([routes.dart:788-945](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/routes.dart#L788));
  the pipeline resolves admin access only through `authenticator.admin`
  ([routes.dart:419-428](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L419)).
  Admin and device tokens cannot cross: `HmacJwt.verify` pins `iss`, `aud`,
  `typ`, `exp` and `ims` ([jwt.dart:77-89](file:///J:/Projects/helix/helix_remote/server/lib/src/kernel/jwt.dart#L77)),
  and the admin module signs `audience helix.admin, type admin`
  ([admin/module.dart:229-242](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L229)).
- **Sign-in guessing is counted in SQL before the hash runs**, with the
  admin row `FOR UPDATE` and one insert-or-update per address
  ([admin_store.dart:148-197](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/data/admin_store.dart#L148)),
  so parallel requests get no extra guesses; a success clears both counters,
  quiet addresses are purged after two days. First-run creation takes a table
  lock ([admin_store.dart:116-136](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/data/admin_store.dart#L116)),
  so two concurrent setups cannot both win.
- **Argon2id runs in its own isolate**, parameters stored per hash, and the
  env knob can only lower cost in dev mode
  ([password_hash.dart:110-121 in admin/module.dart](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L110),
  [password_hash.dart:71-87](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/domain/password_hash.dart#L71)).
- Every mutating admin action writes its audit row **in the same
  transaction** as the change (`_suspend`, `_ban`, `_deleteAccount`,
  `_revokeDevice`, `_recoveryCode`, invites, reports, config, flags, purge);
  reasons pass through `redactString`, and codes/tokens/passwords are never
  audited ([admin/module.dart:404-428](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L404)).
- **Log streams do not outlive a session**: the token is re-verified every
  60 s and at once on sign-out/password change, then closed 4001; inbound
  frames are capped at 1 KiB ([admin/module.dart:721-753](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L721)).
- **Maintenance mode is a pipeline-level 503** for everything except
  `v1/health`, `v1/ops`, `v1/admin` ([pipeline.dart:67-75](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/pipeline.dart#L67),
  [:140-143](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/pipeline.dart#L140)),
  so the console can always turn it off; a change also drops every node's
  cache via the bus and the 30 s expiry ([ops/module.dart:227-237](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/module.dart#L227)).
- **Pack hosting never parses a manifest**; slugs, revisions and digests are
  each checked against their own grammar and the joined path is checked to
  stay inside the root ([pack_host.dart:116-138](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/pack_host.dart#L116)).
  The publish tool writes bytes (`writeAsBytesSync`), so it cannot leave a
  symlink in the host folder ([theme_pack_tool.dart:457-466](file:///J:/Projects/helix/helix_remote/tool/theme_pack_tool.dart#L457)).
- **The two landing pages are static documents**: the code/name comes from
  `location.hash`/`location.pathname`, is written with `textContent`, and is
  served with `frame-ancestors 'none'`, `X-Frame-Options: DENY` and no
  form action ([open_page.dart:44-66](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/open_page.dart#L44),
  [share_page.dart:45-66](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/share_page.dart#L45),
  [ops/module.dart:483-497](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/module.dart#L483)).
  `/u/<name>` cannot be a name oracle: it never looks the name up.
- Crash/anomaly telemetry caps count, key shape, field count and every value
  before it becomes one log line; nothing is stored
  ([ops/module.dart:367-433](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/module.dart#L367)).
- The metrics token is constant-time compared and opens nothing else
  ([ops/module.dart:435-443](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/module.dart#L435)).
- Deletion needs a body confirmation **and** a fresh ownership proof
  (auth key, phone verification or device signature), then runs identity's
  full delete in one transaction
  ([compliance/module.dart:85-107](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/compliance/module.dart#L85)).

## Findings

### AUD-7-1 Wrong trusted-proxy setting turns the per-address sign-in lock into a shared lock on everyone

**Severity:** P3
**Confidence:** confirmed (code path), config-dependent (trigger)
**Where:** [admin/module.dart:306-317](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L306), [local_address.dart:13-14](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/domain/local_address.dart#L13), [pipeline.dart:151-170](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/pipeline.dart#L151), [server_config.dart:354-355](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/config/server_config.dart#L354), [admin_store.dart:158-196](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/data/admin_store.dart#L158)
**What:** `_signIn` keys both the lockout and the limiter on `q.clientIp`,
which is the rightmost `X-Forwarded-For` hop after the trusted-proxy rules —
the raw peer when the proxy is not listed. `isLocalNetworkAddress` then also
exempts that address from the global cap. `MODULE.md` says "only the
per-address lock applies" in that case, but the per-address row is now *the
proxy's* address, so it is one bucket shared by every client on the internet.
**Trigger:** `HELIX_TRUSTED_PROXIES` omits the proxy (default is
`127.0.0.1,::1`; a proxy on another LAN host, a container network, or a
second hop in front of Caddy), with the admin API reachable from outside the
LAN.
**Evidence:** `_clientIp` returns `peer` when `!trustedProxies.contains(peer)`
([pipeline.dart:156](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/pipeline.dart#L156));
`reserveAttempt` inserts `sign_in_failures (ip text PRIMARY KEY)` keyed on
that value; `_signIn` passes `global: isLocalNetworkAddress(q.clientIp) ?
null : globalLockAfter` ([admin/module.dart:314](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L314)).
With the proxy's address loopback/private, `global` is null and the row is
shared.
**Impact:** any five failed sign-ins from anywhere lock the operator's own
sign-ins (`password_locked`, `Retry-After`) for 15 minutes; each further
failure after expiry doubles the next lock up to 24 hours, because the
`failed_attempts` count survives the lock expiry
([admin_store.dart:166-180](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/data/admin_store.dart#L166)).
Recovery is `bin/admin_tool.dart reset-password` (clears the rows) or a DB
edit. The hardened Caddyfile limiting `/v1/admin` to the LAN reduces, but
does not close, the path (the operator would then also be "the LAN").
**Fix sketch:** server only. Either (a) key the per-address lock on the
forwarded address *and* make the shared bucket detectable — e.g. warn/refuse
at start-up when `globalMode` and `trustedProxies` does not cover the
listener's expected proxy; or (b) make the per-address lock only apply when
the address is not a trusted proxy, and let trusted-proxy traffic fall back
to the global cap. (b) needs `q.clientIp` to say whether it was forwarded;
`HttpContextKeys` would carry a flag.
**Test that proves it:** a server test that sends five failures with
`HELIX_TRUSTED_PROXIES` unset and checks that the sixth attempt returns
`password_locked`; then the same with the proxy listed and a different
`X-Forwarded-For` per attempt, expecting 401s not `password_locked`.
**Overlap:** none. The doc line in `admin/MODULE.md`
([37-38](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/MODULE.md#L37))
promises a narrower consequence than the code has.

### AUD-7-2 Account export is assembled in memory with one unbounded section

**Severity:** P3
**Confidence:** confirmed
**Where:** [compliance/module.dart:61-83](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/compliance/module.dart#L61), [media/module.dart:50-70](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L50)
**What:** `_export` collects every module's section into one map and then
`jsonEncode`s the whole document into a single string. Every other exporter
caps itself (identity: 500 security events
[identity/data/admin_store.dart:195-199](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/data/admin_store.dart#L195);
people: 500 reports
[people/module.dart:204-207](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L204)),
but media selects **every** `media.objects` row for the owner with no `LIMIT`.
**Trigger:** an account with many small uploads (the 4 GiB quota is
byte-based, so a million 1-byte attachments cost 1 MB of quota — the same
cause as AUD-5-3); media routes have no route rate limit
([media/module.dart:118-126](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L118)).
**Evidence:** `SELECT id, kind, size, ... FROM objects WHERE owner_account =
@a ORDER BY id` with no limit ([media/module.dart:52-56](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L52));
`Response.ok(jsonEncode(...))` ([compliance/module.dart:70-77](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/compliance/module.dart#L70)).
**Impact:** peak memory is the row set plus the encoded string (roughly 2-3×
the JSON); one export from an abusive account can push a node into GC
pressure or OOM, taking every request on it down with it. Export is allowed
while suspended (`allowSuspended: true`), so suspension does not stop it.
**Fix sketch:** server only; no wire change. Give `ProvidesAccountExport` a
declared row/byte budget (or a `limit` parameter) and truncate the media
section with a count, matching what identity/people already do; optionally
stream the document (`Response` from a `Stream` of a few sections at a time)
so the whole JSON is never one string.
**Test that proves it:** a server test that inserts N media rows for an
account, exports, and asserts the media section is capped and reports a
`truncated`/`total` count (needs the decision in `99_OPEN_QUESTIONS.md` Q3).
**Overlap:** AUD-5-3 (byte-only media quota), AUD-5-1 (export does not touch
blobs, so it is not a storage leak, only size).

### AUD-7-3 Cursor paging uses `(@cursor IS NULL OR id < @cursor)`, which no index can serve

**Severity:** P3
**Confidence:** likely (plan hazard; not measured — no EXPLAIN run)
**Where:** [admin_store.dart:288-293](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/data/admin_store.dart#L288), [identity/data/admin_store.dart:71](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/data/admin_store.dart#L71), [identity/data/admin_store.dart:130](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/data/admin_store.dart#L130), [people/module.dart:698](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L698)
**What:** The four paged admin queries express "newest first, after the
cursor" as `WHERE (@cursor:uuid IS NULL OR id < @cursor:uuid) ORDER BY id
DESC LIMIT n`. A `Param` is not folded to a constant at plan time, so the
`OR` makes the predicate a filter: the planner cannot walk the `id` primary
key backwards and stop at `n` rows. It scans and sorts, or at best
bitmap-scans the whole time range.
**Trigger:** `/v1/admin/audit`, `/v1/admin/accounts`, `/v1/admin/invites`,
`/v1/admin/reports` with a cursor, once the tables are large (the audit table
keeps a full year at 365-day retention
([admin/module.dart:72](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/admin/module.dart#L72))).
**Evidence:** the predicate at each site above; the retention job that keeps
the table growing (`admin.purge_audit` only deletes at one year); the plan's
own EXPLAIN hot-path tests were never written (AUD-1b-3).
**Impact:** each page costs O(table) instead of O(limit): admin pages get
slow as history grows, and the audit page is the one an operator opens
during an incident. Admin-only traffic, so availability impact only.
**Fix sketch:** server only. Split into two statements chosen in Dart
(`cursor == null ? ORDER BY id DESC LIMIT n : WHERE id < @cursor ORDER BY id
DESC LIMIT n`), the same shape the other page queries use; or write it as
`id < COALESCE(@cursor, 'ffffffff-...')` so the predicate is a plain range.
Add the missing EXPLAIN tests for these four queries.
**Test that proves it:** a test that runs `EXPLAIN (FORMAT JSON)` for the
statement with a cursor and asserts an `Index Scan Backward` / `Index Only
Scan` on the primary key (skipped without Postgres, as the suite already
does).
**Overlap:** AUD-1b-3 (missing EXPLAIN tests) — this is the first concrete
query that needs one.

### AUD-7-4 `GET /v1/packs` rescans and stats the whole folder on every request

**Severity:** P3
**Confidence:** confirmed
**Where:** [ops/module.dart:302-315](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/module.dart#L302), [pack_host.dart:51-104](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/pack_host.dart#L51)
**What:** Listing the gallery opens every pack directory, every revision
directory, and stats every file twice (`length()` and `lastModified()`), on
every call, with no cache. Nothing bounds the number of packs, revisions or
files in the folder and nothing bounds the work per request.
**Trigger:** a pack folder with many revisions or files (the tool publishes
every revision it is asked to; files are content-addressed and retained per
revision), opened by many clients — the limit is 1/s per IP, so N addresses
multiply the work.
**Evidence:** `list()` returns `packs` built from `_measure` per revision
([pack_host.dart:51-74](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/pack_host.dart#L51));
`_measure` iterates `files.list` with two `await entry.length()` /
`lastModified()` per entry ([pack_host.dart:88-96](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/pack_host.dart#L88)).
**Impact:** latency and event-loop churn proportional to the folder, on a
public route; a slow/spinning disk makes the gallery (and concurrent pack
downloads that share the isolate) slow, though not incorrect.
**Fix sketch:** server only. Cache the list keyed on the root folder's mtime
(invalidate when `manifest.json` mtimes change), or have `publish` write a
`index.json` the host reads; keep the same caps and the same 404/413
answers. Both leave the wire format unchanged.
**Test that proves it:** a test that calls `list()` twice around a file
change and asserts one folder walk (a counting `Directory` fake), or a
benchmark with a synthetic 5,000-file folder.
**Overlap:** none. This is the one place the "the list is the folder" design
([ops/MODULE.md:105-110](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/MODULE.md#L105))
meets request handling.

## Structural proposals

### S5 — Export sections need a budget, not a convention

**Current shape:** `ProvidesAccountExport` returns `Object?`; compliance
concatenates the sections and encodes them. Identity, people and groups cap
their queries; media does not. Nothing in the interface can enforce a cap.
**Hazard:** AUD-7-2 — the one section that forgot is the one whose row count
is attacker-controlled. The next module with account data can repeat it
silently.
**Proposed shape:** the interface returns a small envelope
(`ExportSection { Object? data; int total; bool truncated }`) or takes a
`rowLimit`; compliance enforces and reports truncation, and can stream
sections.
**Migration:** expand (interface gains the budget, all seven exporters
implement it, wire gains an optional `truncated` flag on a section) →
migrate (release app-side expectation that a section is an array/map) →
contract (drop the unbounded path). The export is already versioned by its
`exportedAt`/section map, so a client that ignores the flag still works.
**Risk:** low; export is rarely used and has no consumers that depend on
completeness beyond a human reading it. **Size:** ~50 lines in compliance,
~20 per exporter, plus one test.

### S6 — The pack host needs an index, not a directory walk

**Current shape:** three public routes answer from the filesystem; the list
walks it per request; reads stat then stream a file.
**Hazard:** AUD-7-4 — page cost is proportional to folder size, and a future
"many revisions" pack tool (the tool already keeps every revision) makes the
gallery the most expensive public route.
**Proposed shape:** `PackHost` keeps a cached index (`id → revision →
{manifestBytes, totalBytes, updatedAt}`) built once and invalidated on a
root mtime change, and `_read` uses the index for existence (still opening
the file for the stream). `publish` can write the same index file for
crash-free start-up.
**Migration:** internal only; no wire or schema change. Ship the cache
behind the existing routes, keep the 404/413 semantics
([pack_host.dart:164-177](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/ops/pack_host.dart#L164)).
**Risk:** a stale index would advertise a removed file (404 on read) or miss
a new one until mtime changes; the publish tool writes into a staging dir
and renames, so mtime changes atomically. **Size:** ~80 lines plus a
folder-fake test.

## Coverage gaps

- The Flutter operator console (`helix_remote/admin/`) is sweep 17; this
  sweep only judged the API it talks to.
- `admin/test/` and `test/client/admin_console_v2_test.dart` were not read;
  no test run was needed for these findings (no EXPLAIN, so AUD-7-3 is
  "likely", not measured).
- `identity.admin.*` (accounts/ban/suspend/revoke/purge) was observed only
  where admin calls it — its queries are sweep 2's.
- The pack tool was read only for its publish write path (symlinks), not
  audited.
- `HELIX_PACKS_DIR` semantics and the three pack routes' redeploy status are
  accepted (pending-redeploy list) and not relitigated.
