# 01a — Platform: the HTTP edge

## Overview

Every request passes `HttpPipeline` (request id, client IP, a global per-IP
token bucket, maintenance mode, error mapping, security headers, access log,
latency histogram), then `RouteRegistry.build` resolves the route in
specificity order and wraps it: credentials → route rate limit → body →
idempotency (device routes with an `Idempotency-Key`) → handler. Bodies are
buffered within a route cap and a node-wide `BodyBudget`; WebSocket upgrades
are wrapped in `limitWebSocketFrames`, which parses frame headers on the raw
socket. Logging redacts by field name and by value shape; metrics are
in-process Prometheus text. The edge is deliberately stateless (buckets and
idempotency rows live in Postgres), so any node can serve any request.

## Files read

- `helix_remote/server/lib/src/platform/PLATFORM.md`
- `http/pipeline.dart` (180), `http/routes.dart` (476), `http/request.dart`
  (236), `http/idempotency.dart` (192), `http/websocket_limits.dart` (230)
- `ratelimit/rate_limiter.dart` (157), `observability/log.dart` (278),
  `observability/metrics.dart` (182)
- `lib/src/server.dart` (assembly), `config/server_config.dart:296-375`,
  `modules/ops/share_page.dart` + `ops/module.dart:470-500` (to rule out a
  sink for AUD-1a-2), `packages/helix_remote_protocol/lib/src/routes.dart:76-180`,
  shelf_router 1.1.4 `router.dart`/`router_entry.dart`, shelf_web_socket 2.0.1
  `web_socket_handler.dart`

## Findings

### AUD-1a-1 A slow client can hold the node's whole body budget forever
- **Severity:** P1
- **Confidence:** likely
- **Where:** [routes.dart:340-377](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L340), reservation at [routes.dart:355-357](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L355), read loop at [routes.dart:361-371](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L361), budget default at [routes.dart:169](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L169), configured at [server_config.dart:308-312](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/config/server_config.dart#L308), served with no timeout at [server.dart:79-85](file:///J:/Projects/helix/helix_remote/server/lib/src/server.dart#L79)
- **What:** `_readBody` reserves the declared `Content-Length` from the
  node-wide budget *before* reading, then `await for (final chunk in
  request.read())` has no deadline. Nothing in the server configures a body
  or request timeout (`HttpServer.idleTimeout` only covers keep-alive between
  requests), so a connection that declares a body and sends nothing keeps its
  reservation until the peer disconnects (OS keepalive: hours).
- **Trigger:** one client (no account needed: every `/v1/auth/*` route is
  public with a 256 KiB body cap, `identity_routes.dart:138/190/242`) opens
  ~1,024 connections to `POST /v1/auth/phone/challenges`, each sending only
  `Content-Length: 262144`. The 256 MiB budget is full; every subsequent
  buffered-body request on that node — sign-in, send, upload, backup — is
  answered 503 "the server is busy". The global per-IP limit (600 burst, then
  10/s) still allows >1,024 starts in ~45 s, and the route limit is per
  policy name so several routes can be hit in parallel.
- **Evidence:** the reserve-then-read order and the missing timeout are the
  two lines cited. Checked for a guard: `pipeline.dart` has no timeout
  middleware, `server.dart` passes only `host/port/poweredByHeader`,
  `server_config.dart` has no body/read timeout key, and `platform/http` has
  no other wrapper. Streaming uploads (`streamBody: true`) bypass the budget
  but are not needed for this attack.
- **Impact:** a single unauthenticated attacker can stop all state-changing
  traffic on the node until their sockets die. Multi-node deployment does not
  help: Caddy load-balances onto the stalled node and its 503s are retried.
- **Fix sketch:** read with an idle deadline (`request.read().timeout(const
  Duration(seconds: 15))` per chunk, or an overall body deadline) and release
  the reservation on timeout (`DbInvalidValue`-style mapping to
  `bad_request`/`request_timeout`). Platform only; no schema, no wire change.
  Consider also lowering the anonymous/public body caps.
- **Test that proves it:** a route-level test that opens a request declaring
  a body, sends no bytes, waits past the deadline, and asserts the reservation
  is released (a second request gets 200, not 503).
- **Overlap:** S7 #1 (body budget) in PLATFORM.md:21; the streaming media
  route in `media/module.dart:122` is unaffected.

### AUD-1a-2 Path parameters are percent-decoded twice
- **Severity:** P2
- **Confidence:** confirmed
- **Where:** [routes.dart:242-254](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L242) (`Uri.decodeComponent(request.params[name])`), comment at [request.dart:78](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/request.dart#L78) ("already percent-decoded")
- **What:** shelf_router matches against `request.url.path`, which Dart's
  `Uri` has already percent-decoded (shelf_router 1.1.4 `router.dart:182`),
  so `request.params` values are decoded. The registry decodes them a second
  time, so `%252F` in the URL arrives at a handler as `/`, `%2525` as `%`,
  and a value containing a literal `%` (sent as `%25`) throws and becomes a
  400 "malformed … in the path".
- **Trigger:** `GET /v1/people/by-name/%252F` yields the name `/`;
  `GET /v1/people/by-name/foo%25` is refused as malformed because the second
  decode sees a bare `%`.
- **Evidence:** the shelf_router match line and the decode line. I looked for
  a sink that turns the param into a filesystem path or URL today: the share
  page ignores the server-side param (`ops/module.dart:480-488`,
  `share_page.dart:48-66`), the pack routes take a digest (`ops`), and the
  federation domain is validated the same sweep will check. No exploitable
  sink found now — this is a latent amplifier, not a live traversal.
- **Impact:** names/domains containing `%` cannot be addressed; any future
  handler that joins a path parameter onto a directory (the pack or media
  style of route) or interpolates it into a URL starts from a value that may
  contain `/`, `.` and `..` even after its own "one segment" check.
- **Fix sketch:** drop the `Uri.decodeComponent` and use
  `request.params[name] ?? ''`; adjust the malformed-escape test to expect
  shelf's own 404/400. Server only, no protocol change (one test vector
  changes).
- **Test that proves it:** a route test asserting `param('name')` for
  `%252F` is `%2F`, and that `foo%25` reaches the handler as `foo%`.

### AUD-1a-3 Concurrent duplicate requests with one Idempotency-Key both run
- **Severity:** P2
- **Confidence:** confirmed (mechanism); per-route damage depends on handlers
- **Where:** [routes.dart:434-476](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L434), [idempotency.dart:143-166](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/idempotency.dart#L143) (`ON CONFLICT DO NOTHING`)
- **What:** `_idempotent` does `find`, then runs the handler, then `save`.
  Two requests with the same key that overlap in time both miss `find`, both
  execute the handler, and both insert; the second insert is silently
  dropped, so one side effect is orphaned and its response discarded. The
  sealer's fail-open on an unknown JWT key (documented) re-opens the same
  window after a key rotation.
- **Trigger:** a client (or the engine's retry on a slow response) sends the
  same `POST` twice within the handler's duration — e.g. a create that mints
  a one-time secret.
- **Evidence:** the read-then-write sequence has no claim step; `save`'s
  `DO NOTHING` proves the platform expected the race but only protects the
  stored row, not the side effect. Checked `InMemoryIdempotencyStore`
  (`putIfAbsent`) — same shape.
- **Impact:** duplicate rows for operations the routes treat as one
  (an invite or recovery secret minted twice, a counter incremented twice,
  an SMS/OTP sent twice if a route ever uses idempotency for that). Sends are
  naturally idempotent on `(message_id, device)`, so messaging is safe; the
  rest needs per-route checking (sweeps 2-7).
- **Fix sketch:** acquire before executing: insert a `pending` row
  (`INSERT … ON CONFLICT DO NOTHING RETURNING`), run only if you inserted,
  update it with the response; a concurrent duplicate either waits (short
  poll) or gets `conflict`/`in_progress` with Retry-After. Platform change
  plus one column/state (expand-only migration on `platform.idempotency`).
- **Test that proves it:** a platform test that runs two identical requests
  concurrently against a handler that counts invocations and asserts one
  invocation and two identical responses.
- **Overlap:** the sealer's documented fail-open (`idempotency.dart:39-41`).

### AUD-1a-4 An idempotent replay loses every response header but content-type
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [routes.dart:452-459](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L452), storage at [idempotency.dart:144-166](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/idempotency.dart#L144)
- **What:** only status and body are stored. A replay of a 4xx keeps the
  status but drops `retry-after`, and a replay of a 201 drops any
  location/etag the first response carried; the replay also adds
  `content-type` to routes that answered `204` (which then has a body of
  length 0 — harmless, but the header is now wrong).
- **Trigger:** client retries a rate-limited or 413 request with the same
  key.
- **Evidence:** `StoredResponse` has three fields; the replay constructs a
  `Response` with a hard-coded header map.
- **Impact:** retries back off incorrectly (no Retry-After), and any future
  route that relies on a response header for the next step cannot be retried.
- **Fix sketch:** store the response headers (sealed like the body, or the
  small allow-list `retry-after`, `location`, `etag`) and replay them.
- **Test that proves it:** a platform test that repeats a 429 with the same
  key and asserts `retry-after` survives.
- **Overlap:** none.

### AUD-1a-5 The access log is synchronous disk I/O with no per-day size cap
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [log.dart:154-179](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/observability/log.dart#L154) (`writeStringSync` per line), rotation/retention at [log.dart:145-197](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/observability/log.dart#L145), one line per request at [pipeline.dart:118-124](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/pipeline.dart#L118)
- **What:** every request writes one JSON line to the log file with a
  synchronous write on the event loop, and retention is by day only
  (`HELIX_LOG_KEEP_DAYS`), with no size bound for a single day.
- **Trigger:** a flood (the same one AUD-1a-1 requires, but even legitimate
  load such as a reconnect storm after a network blip) at a few thousand
  requests a second.
- **Evidence:** the sink's synchronous write; the rotation only renames once
  per UTC day. `StdoutSink` is fine; the file sink is the one on the critical
  path because it is in the same `TeeSink` call chain.
- **Impact:** the event loop serializes on disk writes, so throughput drops
  as load rises; a flood can fill the disk (each request line ~200 B at 5k
  req/s ≈ 86 MB/hour). Neither breaks correctness, both degrade the node.
- **Fix sketch:** buffer file writes (line-batched flush) behind the same
  "rotation never splits a line" rule, and add an optional per-day size cap
  that rotates early (the rotator already numbers same-day files).
- **Test that proves it:** a log test with a fake clock/sink asserting a
  size-triggered rotation, and a benchmark asserting the pipeline does not
  call `writeStringSync` per line (or an async flush).
- **Overlap:** AUD-1a-1 (same flood), review H-05.

## Structural proposals

### P1. Make the route table prove it has no shadowing
- **Current shape:** `RouteRegistry.build` sorts by a hand-rolled
  `_specificity` (`literal * 100 - segments`) and relies on `List.sort`
  (unstable) for ties; correctness of matching is a convention about how
  route templates are written.
- **Hazard:** two catalog routes with the same method that both match one URL
  (e.g. `/v1/{a}/x` and `/v1/y/{b}`, or a new route added under an existing
  prefix) are ordered by chance; the loser is silently unreachable, and no
  test notices because each route's own test calls its handler directly.
- **Proposed shape:** compute the order deterministically (specificity, then
  literal count per segment from the left, then path string) and add a
  start-up assertion or `architecture_test` that no two registered routes
  share a method and can match the same path. The catalog is the single
  input.
- **Migration path:** pure function change + one test; no wire or schema
  change. Done in one commit.
- **Risk:** low; a route that today "wins" by accident would start failing
  the new test, which is the point.
- **Size:** 3-4 h.

### P2. One claim-before-execute idempotency in the platform
- **Current shape:** `IdempotencyStore` is `find` + `save`
  (`idempotency.dart:23-29`), so exactly-once is each handler's problem.
- **Hazard:** AUD-1a-3 — duplicate side effects for every route that relies
  on the platform's idempotency; the platform's public promise (REST_V2
  conventions) is stronger than what it delivers.
- **Proposed shape:** `claim(principal, key, hash)` returns
  `stored | claimed | inProgress`; the wrapper runs the handler only on
  `claimed` and records the response; a duplicate either waits briefly for
  the row to complete or gets `conflict` with `retry-after`. Store the
  response headers too (AUD-1a-4) in the same change.
- **Migration path:** expand `platform.idempotency` with a `state` column
  (and `headers`), default `done`; new code writes `pending`; a sweeper
  deletes stale `pending` rows older than the job timeout. Then contract the
  default later if wanted.
- **Risk:** medium — a crashed handler leaves a `pending` row that must
  expire, or the key is stuck; the lease/job timeout pattern already used by
  `jobs` is the model. Timeout must be shorter than the 24 h retention.
- **Size:** 1-1.5 days including tests.

## Coverage gaps

- Not read this sweep: `platform.dart`, `module.dart`, `startup.dart`,
  `bus/`, `ephemeral/`, `db/`, `jobs/`, `blobs/`, `push/`, `storage/`,
  `config/` (all of it except lines 296-375) — sweep 1b.
- The route catalog (`packages/helix_remote_protocol/lib/src/routes.dart`,
  987 lines) was only skimmed for public routes; the shadowing check is a
  test to write, not a manual audit (see proposal P1).
- No tests were run for this sweep; findings are from code reading plus the
  two dependency packages' sources. `flutter analyze`/`dart analyze` not run
  (nothing was changed).
- Did not evaluate per-route `rateLimit` policies (they live in each module),
  nor whether every mutating route is safe under a concurrent duplicate
  (AUD-1a-3) — sweeps 2-7.
- Open question (not a finding): `Log._emit` calls `jsonEncode` on
  caller-supplied values ([log.dart:60-65](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/observability/log.dart#L60));
  a non-encodable value (a `DateTime`, an enum, a `Uint8List`) would throw
  from the log call, including inside the pipeline's catch-all
  ([pipeline.dart:103-108](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/pipeline.dart#L103)).
  Worth grepping module log calls once the modules are read; not filed
  because no call site was found yet.
