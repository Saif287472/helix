# 11a — `helix_remote_api`: transport, auth, errors, retry

## Overview

The transport is the one place that turns the route catalog into HTTP. It is
small and honest about its rules: one attempt for a public POST (a repeated
refresh looks like theft), an `Idempotency-Key` on every unsafe request,
single-flight refresh with a one-shot re-authenticate, a per-attempt deadline
that also covers the response body, and a sealed exception family that never
carries a token or a body. The request budget is enforced by racing an
`AbortableRequest`'s abort trigger, so a client that ignores it still cannot
hold the transport past the deadline.

The main defect is the shape of that deadline: it is a single scalar for every
attempt of every route, applied to the complete body transfer. Every bulk route
in the package (backup push/pull, account export, presigned whole-object
upload) silently inherits 30 s, and their PUT/GET retries restart from byte 0.

## Files read

- `transport/transport.dart` (490), `transport/auth.dart` (218),
  `transport/errors.dart` (236), `transport/retry.dart` (63)
- `helix_api.dart` (130), `lib/v2.dart` (26)
- Cross-checks: `clients/backup_client.dart`, `clients/compliance_client.dart`,
  `clients/media_client.dart:80-209`, `clients/identity_client.dart:60-110`,
  `helix_remote_protocol/lib/src/routes.dart:24-73`,
  `helix_remote_protocol/lib/src/errors.dart:74-85`,
  `server/lib/src/platform/http/routes.dart:215-235, 296-326, 434-473`,
  `server/lib/src/platform/http/idempotency.dart:30-115`,
  `app/lib/core/engine/helix_runtime.dart:150-163`,
  `engine/.../transfers/download_runner.dart:120-160`,
  `engine/.../transfers/transfer_config.dart:10`,
  `test/v2/route_parity_test.dart:1-45`, `test/architecture_test.dart` (86)

## Findings

### AUD-11a-1 One 30 s deadline covers the whole body, so backup, export and presigned uploads cannot finish on ordinary mobile links
- **Severity:** P2
- **Confidence:** confirmed
- **Where:** the deadline is armed before the request and raced against the
  body read — [transport.dart:67](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L67) (default 30 s), [:93-94](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L93) ("until the whole response body has arrived"), [:369-372](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L369), [:394-395](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L394), [:204](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L204);
  callers that never widen it: [backup_client.dart:7](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/backup_client.dart#L7) (32 MiB cap) and [:17](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/backup_client.dart#L17), [:21](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/backup_client.dart#L21), [:30](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/backup_client.dart#L30), [:37](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/backup_client.dart#L37), [compliance_client.dart:12-18](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/compliance_client.dart#L12), [media_client.dart:172-180](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/media_client.dart#L172); the retry that restarts a PUT from scratch — [transport.dart:161-168](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L161), [:207-211](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L207)
- **What:** `_attempt` starts one timer per attempt that aborts the request
  when it expires, and `_readCapped` runs inside that race, so the 30 s limit
  is a total transfer deadline, not an inactivity deadline. A single POST of a
  full/history backup (server blob cap 16 MiB, base64 in JSON ≈ 22 MiB), a GET
  of the same, an account export (32 MiB cap), and a presigned whole-object
  `PUT` all travel as one request through the default deadline. The only
  caller that raises it is the link long-poll
  ([identity_client.dart:85-104](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/identity_client.dart#L85)), which shows the mechanism exists but is not used where payload size is unbounded.
- **Trigger:** a backup or export on a link slower than roughly 6 Mbps for the
  full cap (proportionally lower for larger ones); an S3-backed attachment on
  any link where the ciphertext takes > 30 s.
- **Evidence:** `BackupClient.putFull/full` and `putHistory/history` pass no
  `timeout:` and are annotated with the 32 MiB response cap; the transport
  retries `PUT` and `GET` (`repeatable`, line 164) up to `maxAttempts`, each
  attempt re-sending the whole body and re-arming the 30 s timer. The engine's
  media path avoids this only because its transfer layer slices at 512 KiB
  (`transfer_config.dart:10`), which is why media works and backup does not.
- **Impact:** the full backup (the user-secret recovery path) and history
  backup fail repeatedly on exactly the networks where backups matter; the
  client burns up to three full uploads per attempt cycle, competing for the
  server's body budget; account export cannot be downloaded on a slow link;
  on an S3 backend a mid-sized attachment fails at the transport with no
  retry (external requests are never retried).
- **Fix sketch:** make the transport deadline an inactivity deadline (reset on
  each chunk) or add a per-route "bulk" deadline; the `timeout:` parameter
  already exists, so the minimal fix is to pass a size-derived timeout from
  `BackupClient`, `ComplianceClient.export` and `MediaClient.upload` when the
  target is a presigned URL, and to stop retrying a body that large without a
  resume. Prefer the structural form in S1 so a new bulk route cannot inherit
  30 s by accident.
- **Test that proves it:** a fake streamed response that sends its first byte
  after 28 s and completes after 40 s must succeed for a bulk route and time
  out for a small one; today both throw `NetworkException(timedOut)`.
- **Overlap:** backup and media (sweep 5), the engine backup runner (sweep 12),
  the server body budget (AUD-1a-1), and S3 timeouts (AUD-1c-1) — the opposite
  failure, a client that never gives up.

### AUD-11a-2 A device POST retried after `internal` can run twice: the idempotent result is stored only for status < 500, after the handler committed
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** the client retries any repeatable request whose code is retryable
  — [transport.dart:246-254](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L246), and `internal` is retryable — [protocol errors.dart:75-84](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/errors.dart#L75); the server stores the answer only when `statusCode < 500` and only after
  `run()` returns — [routes.dart:447-473](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L447)
- **What:** `_idempotent` runs the handler (which commits in its own
  transaction), then `readAsString()`s the response and writes the record. If
  either of those steps fails — the record insert hits the same database that
  just committed, or an `afterCommit` side effect throws — the pipeline
  answers 500 without a stored replay. The client sees `internal`, retries the
  same key, `find` returns nothing, and the handler runs a second time.
- **Trigger:** a transient write failure on the idempotency row (or a failed
  after-commit notification) immediately after a successful mutation.
- **Evidence:** the store is written outside the handler transaction
  ([:460-472](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L460)), the 5xx branch returns without saving ([:471-472](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L471)), and the client's retry condition includes `internal`
  ([transport.dart:246-254](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L246)).
- **Impact:** duplicate execution of a device-authenticated POST/PATCH whose
  effects are not naturally de-duplicated (a second invite or link, a repeated
  group change). Narrow trigger, silent when it happens. The concurrent
  variant of the same gap is AUD-1a-3.
- **Fix sketch:** reserve the key before running (insert a `running` row, run,
  then update it), so a retry either replays or resolves the reservation; or
  record the response inside the handler's transaction. The client needs no
  change — its assumption is the documented contract.
- **Test that proves it:** a fake `IdempotencyStore` whose `save` throws once;
  two sends with one key must execute the handler once (today: twice).
- **Overlap:** AUD-1a-3 (concurrent duplicates), after-commit hooks in sweep 1b.

### AUD-11a-3 `isUnauthenticated` is true for `invalid_credentials`, contradicting the transport's own carve-out
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [errors.dart:101-102](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/errors.dart#L101) (`status == 401`) versus the explicit exception in [transport.dart:232-240](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L232); consumers [outbox.dart:231](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L231), [transfer_failure.dart:129](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_failure.dart#L129)
- **What:** the transport deliberately does not refresh or end a session on a
  401 carrying `invalid_credentials` (a wrong password, not a rejected token),
  but the exception's convenience getter still reports it as an authentication
  failure. Engine code branches on that getter to decide "sign in again".
- **Trigger:** any device route that answers a wrong secret with
  `invalid_credentials` and is called by the engine.
- **Evidence:** the two conditions disagree by construction; today the only
  producers are password routes, so the divergence is latent.
- **Impact:** if such a route enters the engine's path, the app would show the
  sign-in screen instead of a wrong-password error. No security change.
- **Fix sketch:** `isUnauthenticated => status == 401 && code != ErrorCode.invalidCredentials`.
- **Test that proves it:** construct both exceptions and assert the getter.
- **Overlap:** engine failure classification (sweep 12).

### AUD-11a-4 A failed session-store write after a refresh re-exposes the rotated-out refresh token, which the server treats as theft
- **Severity:** P3
- **Confidence:** likely
- **Where:** [auth.dart:145-148](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/auth.dart#L145) calls `signedIn`, which writes the store before caching — [auth.dart:100-105](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/auth.dart#L100)
- **What:** a refresh rotates the token pair. `signedIn` persists the new
  session first and only then replaces `_cached`. If the write throws (disk
  full, SQLCipher error), the exception leaves `_refresh` and `_cached` still
  holds the old session, whose refresh token the server has already rotated
  out. The next refresh presents it again, and the server's reuse rule refuses
  the family.
- **Trigger:** a storage error on the single write that follows a successful
  rotation.
- **Evidence:** the ordering is visible in `signedIn`; the refresh token
  rotation and reuse handling are the design recorded on the server side
  (sweep 2), and `_refused` maps the refusal to re-authenticate-or-sign-out
  ([auth.dart:149-169](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/auth.dart#L149)).
- **Impact:** an avoidable forced sign-in (or device re-link) instead of a
  transient error, on a device whose keys are intact. Fails closed.
- **Fix sketch:** make the in-memory session authoritative — set `_cached`
  before the write and treat a failed write as a warning (retry it next time,
  or surface it to the engine's error reporter).
- **Test that proves it:** a `SessionStore` whose `write` throws once; the next
  `refresh` must use the new token, not the old one.
- **Overlap:** refresh rotation (sweep 2), secure storage (sweep 14).

## Structural proposals

**S1 — a deadline per route class, not per attempt.** *Current shape:* one
scalar `timeout` on `HelixTransport`, inherited by every route; bulk clients
are expected to remember to pass a larger one and none do. *Hazard:*
AUD-11a-1, and it will recur with every new bulk route. *Proposed shape:* a
small `Deadline` value in the transport (`total` for normal calls, `idle` for
bulk) plus a set of route defaults derived from the catalog's documented body
caps; `send` picks the idle deadline when the call's `maxResponseBytes` or body
exceeds the normal cap, and the bulk clients may still override it.
*Migration:* expand (add idle mode and a default bulk set; behaviour unchanged
for small routes) → migrate (bulk clients stop relying on the default) →
contract (a test asserts every catalog route with a cap above 4 MiB has a bulk
deadline). *Risk:* low — the normal path keeps the total deadline. *Size:* S
(~80 lines + a test), plus a one-line annotation in the protocol catalog when
sweep 8 gets to it.

**S2 — the in-memory session is authoritative; persistence is best effort.**
*Current shape:* `signedIn` persists then caches, so the cache can lag the
server's rotation state. *Hazard:* AUD-11a-4. *Proposed shape:* cache first,
write afterwards, and expose a `onPersistFailed` callback for the engine to
report/retry; the same ordering for `forget` (clear the cache even if the
store call fails, since a stale persisted session is worse). *Migration:* a
single method change, no schema. *Risk:* low — a crash before the write loses
the new token from disk exactly as today. *Size:* XS.

## Coverage notes

- `url()` builds paths from `route.expand()`, which percent-encodes each
  parameter, then `Uri.replace(path:)`; a test pins that an encoded `%40`
  survives ([transport_test.dart:64](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/test/v2/transport_test.dart#L64)) — no double encoding.
- `send` follows redirects by default, but the only route that redirects
  (media download) opts out and re-requests the `Location` through `external`
  without the bearer ([media_client.dart:107-131](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/media_client.dart#L107)); no other module emits a 3xx (grep).
- `_readCapped` counts streamed bytes as well as `content-length`, so a lying
  length cannot exceed the cap ([transport.dart:421-453](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L421)).
- The refresh route is public, and public POSTs are never retried, so a
  network retry cannot look like refresh-token reuse
  ([transport.dart:164-168](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L164)).
- `external` cannot carry Helix headers or the bearer, is never retried, and
  never follows redirects ([transport.dart:320-357](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L320)).
- The abort race keeps timeout and cancellation effective even for an
  `http.Client` that ignores the abort trigger, and the timer is cancelled on
  every exit ([transport.dart:359-416](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L359)).
- `route_parity_test.dart` drives every non-S2S catalog route through exactly
  one client method; `architecture_test.dart` confines `dart:io` to
  `io_socket.dart` and `package:http` to the transport/facade.
- The admin log socket is per-subscription and closes on cancel
  ([admin_client.dart:199-240](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/admin_client.dart#L199)).
- `MemorySessionStore` is a test double exported for the server's client
  tests; unlike `RecordingPushProvider` it is documented as such and is not a
  production fallback.

## Cross-sweep notes

- The transport retries the streaming upload route (`PUT .../content`,
  `streamBody: true`) although it is outside the server's idempotency store
  ([media/module.dart:122](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/media/module.dart#L122)); that is safe only because the route reconciles offsets (AUD-1c-2 covers the server side of the same route).
- Refresh single-flight is per `DeviceSessionAuth` instance. Two `HelixApi`
  objects (or two isolates) sharing one `SessionStore` would refresh
  concurrently and trip the server's reuse-as-theft rule. Today there is one
  instance in the app ([helix_runtime.dart:150](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L150)) and one in the CLI; sweep 14 must re-check the FCM isolate.
- The server's idempotency gate requires a body and a `DevicePrincipal`
  ([routes.dart:306-321](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L306)), which matches the client's repeatability rule for POST/PATCH/PUT/DELETE.
