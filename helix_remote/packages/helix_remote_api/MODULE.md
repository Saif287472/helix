# Package: helix_remote_api

Status: current. Holds two APIs side by side until the app moves to v2:

- **v1** (`lib/api.dart`, `lib/api/`): the REST interface and envelope
  parser the live v1 app uses. Unchanged on `architecture-v2` and deleted
  with the rest of v1 (Phase A1 / X).
- **v2** (`lib/v2.dart`, `lib/src/v2/`): the typed REST and WebSocket
  clients for the v2 server (ARCHITECTURE_V2_PLAN.md §6.1, ADR-027), built
  in Phase C3a. Everything below the v1 section is about v2.

## v1

Package-level counterpart to the backend module docs, from the
[structural upgrade plan](../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A4). Public surface `lib/api.dart`; used by the v1 app, CLI and
`helix_remote_sync`; depends on `helix_remote_domain` and `meta`.

- Error bodies are `{error, code, details?}` with `code` from
  `RemoteErrorCode`. Branch on `code`, not on the message, and do not infer
  the code from the HTTP status.

## v2: who may depend on it, and on what

- **Users:** `helix_remote_engine` (C3b), the CLI, the admin console (AD).
  The app's presentation layer never imports it (plan §6.4).
- **Depends on:** `helix_remote_protocol` (routes, DTOs, frames, error
  codes; the single source of truth for paths and payloads), `http`,
  `crypto` (the WebSocket accept check) and `meta`. Not
  `helix_remote_domain`, not the v1 files (`test/architecture_test.dart`).
- **Pure Dart.** `dart:io` appears only in `realtime/io_socket.dart`, behind
  a conditional import, so the web build of the admin console compiles.
  `package:http` appears only in the transport and the facades. No other
  client package may use HTTP or WebSockets (plan §8).

## v2: layout

```
lib/v2.dart                     public library
lib/src/v2/
  transport/transport.dart      HelixTransport, ApiResponse
  transport/auth.dart           AuthProvider, DeviceSessionAuth, AdminTokenAuth,
                                SessionStore, MemorySessionStore
  transport/errors.dart         HelixApiException (sealed) and its cases
  transport/retry.dart          RetryPolicy, CancellationToken
  clients/<module>_client.dart  one class per server module
  realtime/realtime_client.dart RealtimeClient, RealtimeState, ReconnectPolicy
  realtime/socket.dart          RealtimeSocket, RealtimeSocketFactory
  realtime/io_socket.dart       dart:io socket (manual upgrade, see below)
  helix_api.dart                HelixApi (device), HelixAdminApi (console)
```

## v2: clients

One class per server module; each method is one catalog route, takes and
returns protocol DTOs, and keeps no state. `route_parity_test.dart` checks
that every non-S2S route in `Routes.all` is sent by exactly one method, in
the client of the route's module, and that no S2S route appears.

| Class | Routes |
|---|---|
| `IdentityClient` | phone codes, invites, register, password and device-key sign-in, QR links, refresh, recovery, sign-out, account, password, `~name`, security events, devices, revoke, link approval, push tokens |
| `KeysClient` | signed prekey, one-time prekeys, status, account bundles (`?device=`) |
| `MessagingClient` | send (message id = idempotency key), mailbox, ack |
| `PeopleClient` | discovery salt and matching, `~name` lookup, profiles, presence, blocks, privacy, contacts, reports |
| `GroupsClient` | create, list, get, delete, state, settings, members, roles, bans, invite links, join, join requests, **group send** (the route belongs to `groups`) |
| `CallsClient` | TURN, signals, state, pending offers, metrics |
| `MediaClient` | create upload, `PUT` chunk, `HEAD` status, ranged download, delete; `upload()` (resumable or one presigned `PUT`) |
| `BackupClient` | history and full backups (`GET` returns null when there is none) |
| `OpsClient` | live, ready (503 is an answer), server info, legal, crash report, asset links, `/open` |
| `ComplianceClient` | export, delete account |
| `FederationClient` | `/.well-known/helix-server` (the only public federation route) |
| `AdminClient` | every admin route, the log stream (WebSocket) and `GET /v1/ops/metrics` (an `ops` route that needs the admin audience) |
| `RealtimeClient` | `GET /v1/ws` |

`HelixApi(baseUrl, sessions)` wires the device clients to one transport and
a `DeviceSessionAuth`; `HelixAdminApi(baseUrl)` the admin client to an
`AdminTokenAuth`.

## v2: transport rules

- **Tokens per audience.** A transport holds one `AuthProvider`: device or
  admin. A device transport refuses admin routes (`StateError`) and vice
  versa; S2S routes are refused outright. Public routes never carry a
  token, except the link poll's own bearer.
- **Refresh.** `DeviceSessionAuth` refreshes ahead of expiry (30 s) and on a
  401, once for all concurrent requests (single flight). A refused refresh
  (401 or 403) gives the engine's `reauthenticate` (device-key
  sign-in) one chance, then clears the session and throws
  `SignedOutException(refreshRejected)`, also published on `signedOut`. A
  refresh with no answer throws that error and keeps the session. Admin
  tokens are never refreshed: a 401 is `SignedOutException(sessionEnded)`.
  A 401 with `invalid_credentials` is a wrong password in the request (the admin
  password change), not a rejected token: it is thrown as an `ApiException`, with no
  refresh and the admin session kept.
- **Idempotency.** Every unsafe request carries an `Idempotency-Key`; sends
  use the message id. `GroupsClient.sendMessage` takes an optional
  `idempotencyKey`: a retry whose ciphertext differs (after
  `device_list_stale`) needs its own key, because the server answers a
  repeated key with another body `idempotency_conflict`, and stores a 4xx
  answer relayed from a group's home server under the key.
- **Retries** only for requests safe to repeat: `GET`/`HEAD`/`PUT`/`DELETE`
  and device `POST`/`PATCH` (the server replays their key). Public `POST`s
  are never repeated (a repeated refresh is token reuse and revokes the
  device). Retried on no response and on retryable codes except
  `password_locked`, waiting `Retry-After` (header, else body) up to 30 s,
  else 0.5 s doubling to 8 s with jitter, 3 attempts.
- **Errors.** `HelixApiException` is sealed: `ApiException` (every
  `ErrorCode`, unknown codes keep their status, non-v2 bodies map by status
  class; `staleDevices`, `lockedUntil`, `retryAfter`, `requestId`),
  `SignedOutException`, `NetworkException` (`timedOut`),
  `RequestCancelledException`, `MalformedResponseException` (field path).
- **No logging.** The package logs nothing. No exception's `toString`
  contains a token, a header value or a body (tested).
- **Media.** Redirects from the download route and presigned upload URLs
  go through `HelixTransport.external`: no bearer, no Helix headers, no
  redirects followed.

## v2: realtime rules (REALTIME_V2.md)

- Subprotocol `realtimeSubprotocolJson` from the protocol package
  (currently `helix.v1+json`), `Authorization` header, `?after=<cursor>`.
- The `dart:io` socket performs the upgrade itself so a refused upgrade
  keeps its HTTP status and error code (`RealtimeUpgradeException`):
  `WebSocket.connect` reports 401 and 403 the same way.
- `envelopes` (broadcast; listen before `start`), `ack(seq)` (cumulative,
  after the envelope is durably processed), `outstanding` vs `window`,
  `wakes`. Replays at or below the cursor are dropped; unknown frames and
  envelope kinds with a `seq` are acked in order, never surfaced. The
  cursor's ack is re-sent after every `hello`.
- Ping after 60% of `heartbeat_s` without sending; a server silent for two
  heartbeats plus 5 s is dropped and reconnected.
- Close codes: 4001 refresh, then reconnect at once (a second 4001 right
  after backs off); 4003 `revoked`, stop; 4004 `suspended`, wait for
  `reconnect()`; 4008 `superseded`, wait for `reconnect()`; 4029 at least
  30 s; 4400 reported on `protocolErrors`, then backoff; 4010, 4503 and
  drops back off 1 s doubling to 60 s, ±20%, reset after 60 s connected.
  Upgrade 401 = 4001, 403 `account_suspended` = 4004, other 403 = revoked,
  429 = at least 30 s or `Retry-After`.

## Tests

- `test/v2/transport_test.dart`, `realtime_client_test.dart` (fake HTTP
  client, fake sockets, `fake_async`), `route_parity_test.dart`,
  `test/architecture_test.dart`.
- Integration tests against a real server live in
  `server/test/client/api_v2_test.dart`: this package may not depend on
  the server, so the server's tests (allowed to import this package only
  under `test/client/`) drive it instead.

## Response size caps (review pass 2026-10-05)

`HelixTransport.send/call/external` take `maxResponseBytes` (default
`defaultMaxResponseBytes`, 4 MiB). The body is cut off as soon as it is longer
(by `content-length` up front, or counted while it streams in) with
`ResponseTooLargeException`; it is never retried. Backups and the account
export pass 32 MiB; `MediaClient.download` takes `maxBytes` (the caller passes
what the pointer's declared size allows; the default is the 4 GiB quota). A
ranged download must be answered with the range: a full body where an offset
was asked, or more bytes than the range holds, is `RangeNotHonoredException`
(the first range, from byte 0, may be answered with the whole object within
the cap). `ComplianceClient.deleteAccount` takes `currentAuthKey`,
`verificationToken` or `deviceProof` (see `DeleteAccountRequest`).
