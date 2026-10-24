# 01c — Platform: object storage, push, bus, budget, config

## Overview

The I/O edge is deliberately small. Object storage is one interface with a
local directory and an S3 (SigV4, presigned) implementation; modules only ask
it for size, delete, list and presigns, and clients move bytes directly when
the backend presigns. Push is data-only (FCM HTTP v1, token refresh and POST
both bounded, 404 means the token is gone). The event bus is Postgres
`LISTEN/NOTIFY` with a 7.9 KB payload cap and malformed notifications dropped.
The storage budget fails open by design (a measurement error must not stop the
service) and is single-flighted and cached for a minute. Config parses every
`HELIX_*` value once and reports all problems together.

The two hazards below are not in that spirit: the S3 calls have no timeout at
all, and the local `append` primitive is a non-atomic check-then-write that the
media upload route relies on for resumability.

## Files read

- `blobs/object_storage.dart` (340), `push/push.dart` (222),
  `bus/event_bus.dart` (120), `storage/storage_budget.dart` (110)
- `config/server_config.dart` (376), `platform/module.dart` (151)
- Call sites needed to judge impact: `modules/media/module.dart:140-325`,
  `observability/push` callers via `grep`, `db/postgres_db.dart:190-207`
  (LISTEN channel validation), `PLATFORM.md:35-37` (network-timeout rule)

## Findings

### AUD-1c-1 Every S3 request is unbounded; one stalled store hangs media requests and accumulates health probes
- **Severity:** P1
- **Confidence:** likely
- **Where:** [object_storage.dart:240-249](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L240) (`_signed` awaits `_client.send` with no timeout), used by [size:252-259](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L252), [delete:285-292](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L285), [list:306](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L306), [ping:334](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L334); request-path callers [media/module.dart:275](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L275), [:293](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L293), [:359](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L359); rule at [PLATFORM.md:35-37](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/PLATFORM.md#L35)
- **What:** `S3ObjectStorage` sends HEAD/GET/DELETE/LIST requests through a
  plain `http.Client` and never applies a timeout. `PLATFORM.md` says in so
  many words that anything waiting on the network has one. `ping()` is only
  bounded from the outside: `HealthRegistry.run` wraps each check in a 3 s
  `Future.timeout` ([module.dart:26-31](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/module.dart#L26)), but `Future.timeout` does not cancel the
  underlying HTTP request.
- **Trigger:** the S3 endpoint accepts the TCP connection and then stops
  answering (blackholed route, dead load balancer, stalled TLS, throttling
  without a response). No error is raised, so nothing retries or fails over.
- **Evidence:** the only bounds in the class are the health wrapper above and
  `http.Client` defaults; there is no `.timeout(` anywhere in
  `object_storage.dart` (verified by search). The FCM provider in the same
  directory does bound both its token refresh and its POST
  ([push.dart:147](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/push/push.dart#L147), [:183](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/push/push.dart#L183)), so this is an omission, not a style.
- **Impact:** (a) `GET /v1/media/{id}` and `GET /v1/media/{id}/status` await a
  HEAD with no deadline; each stalled store hangs the request (and its socket)
  forever, and repeated client retries multiply it. (b) Each readiness probe
  that times out leaves another HEAD in flight; probes run continuously, so a
  dead store grows an unbounded set of pending requests and sockets on every
  node. (c) the media orphan sweep (a periodic job) blocks on LIST/DELETE until
  the 5-minute job timeout, which then aborts the job but not the HTTP call.
- **Fix sketch:** one `_send(method, uri, {Duration timeout, ...})` in
  `S3ObjectStorage` with a 5-10 s timeout, mapping `TimeoutException` to
  `HttpException`; construct the client with a connection timeout; make
  `ping()` cheap and non-spawning (cached last result with a short TTL, or
  single-flight) so a dead store cannot accumulate probes. Do not put the HEAD
  in the synchronous download path where a presign is available.
- **Test that proves it:** a fake `http.Client` whose `send` never completes;
  `size()` must throw within the configured timeout and `ping()` must return
  false; today the test hangs.
- **Overlap:** media (sweep 5), ops health (sweep 7), the same class of fault
  as AUD-1a-1 (no read deadline) and the FCM fix noted in 1b.

### AUD-1c-2 `LocalObjectStorage.append` is check-then-write with no per-key isolation; concurrent retries corrupt an upload
- **Severity:** P2
- **Confidence:** confirmed
- **Where:** [object_storage.dart:112-128](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L112) (`current != offset` check, then append), call site [media/module.dart:219-252](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L219)
- **What:** `append` reads the file length, compares it with `offset`, then
  opens the file in append mode and writes. Two calls for the same key and
  offset both pass the check before either writes. Each call tracks `written`
  from its own starting offset, so `maxSize` is checked per writer; neither
  sees the other's bytes. The media upload route performs no row lock or
  in-process serialization around the call — it reads the object row
  (`_object`), checks `completed_at`, then appends.
- **Trigger:** two `PUT /v1/media/{id}/content` requests for the same media id
  and `upload-offset` overlapping in time — e.g. a client retry after a
  timeout while the first request is still streaming, or two devices of one
  account retrying the same upload.
- **Evidence:** with declared size 10, two writers at offset 0 each writing 5
  bytes can both return `stored == 10`, the route sets `completed_at`
  ([media/module.dart:253-265](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L253)), and the file holds 20
  bytes. The first 10 bytes can also be an interleaving of two different
  request bodies, so the ciphertext is corrupt even though the row says
  complete.
- **Impact:** a completed media object whose bytes do not decrypt (recipient
  sees a broken attachment; sender has no local error), or a stuck upload
  (status reports 20 bytes for a 10-byte object). Local backend only (S3 does
  not support `append`), i.e. every current deployment. Data-level, not
  cross-account: the route checks `owner_account`.
- **Fix sketch:** serialize per key. The local backend is single-node by
  construction (cluster mode requires S3, `server_config.dart:281-287`), so a
  per-key mutex inside `LocalObjectStorage` plus a final
  `length == written` verification is enough; alternatively make the media
  route hold a short advisory lock for the append. `append` should return the
  file's real length after flush, never its own counter.
- **Test that proves it:** two concurrent `append(key, offset: 0, maxSize: 10)`
  calls whose streams emit 5 bytes each with a delay; assert exactly one gets
  `OffsetMismatch` (or the second fails) and the file length never exceeds 10.
- **Overlap:** media upload path (sweep 5); the same non-atomicity would bite
  any future resumable writer.

### AUD-1c-3 A malformed `HELIX_S3_ENDPOINT` passes config and fails only at request time
- **Severity:** P2
- **Confidence:** confirmed
- **Where:** [server_config.dart:264-275](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/config/server_config.dart#L264) (`Uri.tryParse(require(...))`, `endpoint ?? Uri()`), use at [object_storage.dart:195-208](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L195)
- **What:** the endpoint is required and parsed with `Uri.tryParse`, but a
  parse failure is silently replaced by the empty `Uri()`, and a parse success
  is never checked for scheme or host. `minio:9000` parses as a scheme with no
  host; `storage.example.com` parses as a path. Config validation is supposed
  to report every problem at once and refuse to start.
- **Trigger:** an operator writes `HELIX_S3_ENDPOINT=minio:9000` (a common
  MinIO shorthand) or leaves out `https://`, with `HELIX_BLOB_STORE=s3`.
- **Evidence:** the server starts and passes the cluster/S3 check
  ([server_config.dart:281-287](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/config/server_config.dart#L281)), then every signed request builds a
  relative URI (`base.replace(path: ...)`) and `http.Client.send` throws; media
  create/download/status and the orphan sweep all fail with an opaque error
  rather than one line at start-up.
- **Impact:** a running server that cannot store or serve media or backups,
  discovered on first upload, with an error that does not name the variable.
- **Fix sketch:** validate `endpoint.hasScheme`, scheme is `http`/`https`,
  `endpoint.host.isNotEmpty`, and no userinfo/query/fragment; `problems.add`
  otherwise. Delete the `?? Uri()` fallback.
- **Test that proves it:** `ServerConfig.fromEnv` with
  `HELIX_S3_ENDPOINT=minio:9000` throws `ConfigError` naming the variable;
  today it returns a config.
- **Overlap:** sweep 18 (env table and config tests), sweep 5 (media
  behavior on a broken store).

### AUD-1c-4 `S3ObjectStorage.read` downloads the whole object and slices it in memory
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [object_storage.dart:269-282](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/blobs/object_storage.dart#L269)
- **What:** `read(key, start, endInclusive)` issues a plain GET (no `Range`
  header), buffers `response.bodyBytes`, then `Uint8List.sublistView(bytes,
  start, end)`. The interface promises a byte-range stream; this implementation
  downloads the entire object and allocates it again. If the stored object is
  shorter than the DB-declared size, `sublistView` throws `RangeError` instead
  of a typed storage error.
- **Trigger:** any future server-side reader of an S3 object with a range
  request, or with a truncated object. Not reachable from the current media
  route (it presigns on S3, [media/module.dart:304-307](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L304)); the local
  implementation streams correctly.
- **Impact:** latent. When reached it buffers a whole backup/attachment (up to
  `HELIX_MAX_ATTACHMENT_BYTES`, 100 MB by default) per request, and turns a
  short object into a 500.
- **Fix sketch:** send a `Range: bytes=start-end` header, stream
  `response.stream`, and throw a typed `ObjectMissing`/`ObjectShort` on 404/416.
- **Test that proves it:** a fake client that asserts the `Range` header and
  returns a body longer than the requested window; the returned stream must
  carry only that window and must not buffer the whole body (assert on first
  chunk before the fake finishes).
- **Overlap:** backup/media readers (sweep 5); AUD-1c-1 (same method).

### AUD-1c-5 `RecordingPushProvider`, a test double, ships in the production library
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [push.dart:69-96](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/push/push.dart#L69); used only from [test/support/harness.dart:42](file:///J:/Projects/helix/helix_remote/server/test/support/harness.dart#L42) and [test/support/cluster.dart:104](file:///J:/Projects/helix/helix_remote/server/test/support/cluster.dart#L104)
- **What:** the recording fake (a growable `sent` list, a `gone` set) lives in
  `lib/src/platform` next to the real providers, so production code carries a
  test aid and any module could construct it. `NoPushProvider` is legitimate
  production code; this one is not.
- **Trigger:** none at runtime; it is a placement/ownership issue that makes
  the "platform has no test doubles" boundary fuzzy and invites tests to grow
  behavior into lib.
- **Impact:** none on the wire; maintenance and review clarity only.
- **Fix sketch:** move it to `test/support/` (two import updates) or guard it
  behind a `dev` library; keep `NoPushProvider` where it is.
- **Test that proves it:** an architecture-test import rule that `lib/` does
  not depend on `test/` already holds; the complement (no `Recording*` in lib)
  can be a small search-based assertion.
- **Overlap:** sweep 18 (governance check), sweep 7 (ops tooling).

## Structural proposals

### S1 One bounded, streamed request edge for `S3ObjectStorage`
- **Current shape:** each method calls `_signed`, which builds a request and
  awaits `send` with no timeout; `read` buffers, the rest map errors ad hoc.
- **Hazard:** a stalled store has no deadline anywhere; the same code will
  grow a fourth and fifth call site with the same omission.
- **Proposed shape:** one private `_send` (timeout, range header, status
  mapping, typed errors) returning a streamed `http.StreamedResponse`; `size`,
  `delete`, `list`, `ping` and `read` all go through it, and only `ping` adds a
  cached/single-flight wrapper.
- **Migration path:** expand — add `_send` and a timeout parameter, port
  `size`/`delete`/`list`/`ping`, then `read` (range), then delete `_signed`.
  No schema, no API change.
- **Risk:** low; fake-client tests cover each status and a hanging send.
- **Size:** M (~120 lines + tests).

### S2 Treat `append` as a resumable protocol with isolation, not a byte sink
- **Current shape:** the caller reads the object row, then passes `offset` and
  `maxSize` to a primitive that checks the current length non-atomically and
  appends. The primitive returns its own byte counter.
- **Hazard:** normal retry overlap corrupts or double-sizes an upload, and the
  caller marks it complete on a counter that may not match the file.
- **Proposed shape:** `append` is serialized per key (in-process mutex for the
  single-node local backend) and returns the file's actual length after flush;
  the media route treats a returned length different from `offset + n` as a
  conflict. If a second node ever needs the local backend, this must become a
  DB advisory lock or an explicitly S3-only path.
- **Migration path:** expand — add the mutex and the final length check,
  keep the signature; migrate callers to use the returned length; contract —
  document `append` as serialized and non-concurrent in the interface
  docstring.
- **Risk:** low for local; the cluster rule (S3 only) is already enforced.
- **Size:** S (mutex + verify) / M with the media-side check.

## Coverage gaps and notes

- Verified sound: FCM token refresh 10 s and POST 15 s, 404 -> `PushTokenGone`,
  other status -> `PushFailed('http_N')`; bus payload cap 7,900 bytes and
  channel-name validation (`postgres_db.dart:190-196` rejects a prefix that
  would overflow 63 bytes, so no silent truncation); `StorageBudget` fail-open
  and single-flight; `HealthRegistry` reporting a timed-out check as false.
- Not audited here: media/backup consumers of blobs (sweep 5); how the
  readiness registry is populated and exposed (sweep 7); the generated env
  table and its drift check (sweep 18); S3 signing correctness against a real
  store (only config parsing is tested — `test/platform/infra_test.dart`).
- One open question is not raised: whether the media orphan sweep should bound
  `list` by page as it deletes (it consumes the stream while deleting, which
  is fine for both backends today).
