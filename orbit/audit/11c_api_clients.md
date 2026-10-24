# 11c — `helix_remote_api`: typed REST clients

## Overview

Twelve thin clients over one transport, one method per catalog route, with the
DTOs doing the validation. The shape is uniform and the naming matches
`REST_V2.md`. Two details stand out as deliberate: `GroupsClient.sendMessage`
takes an `idempotencyKey` override because a re-encrypted body after
`device_list_stale` must not collide with the stored answer to the first body,
and `MessagingClient.send` uses the message id as the key so a retried send is
never delivered twice. `Operations` keeps pack bytes opaque — the format is
understood only by `checkOrbitPack`.

The transport decides retryability from the HTTP method, and that assumption
breaks for the one GET with side effects (`accountKeys` consumes a one-time
prekey). The admin console's sign-out also loses its local half when the
network call fails.

## Files read

- All twelve clients: `identity` (203), `groups` (144), `people` (71), `keys`
  (43), `messaging` (37), `calls` (38), `ops` (101), `admin` (251),
  `federation` (14); `backup` (65), `media` (210) and `compliance` (37) were
  read for 11a.
- Cross-checks: `helix_remote_engine/.../messaging/sender.dart:30-80,
  120-160`, `outbox.dart:100-160, 340-430`, server
  `keys/module.dart:252-322`, `platform/http/pipeline.dart:60-112`,
  `platform/http/routes.dart:296-326`.

## Findings

### AUD-11c-1 `accountKeys` is a GET that consumes a one-time prekey, so the transport's automatic retry silently burns one and returns a bundle without an OTK
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [keys_client.dart:32-42](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/keys_client.dart#L32) calls a GET — [routes.dart:278-283](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/routes.dart#L278); the transport repeats every GET on no response — [transport.dart:161-168](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L161), [:207-211](file:///J:/Projects/helix/helix_remote_api/lib/src/v2/transport/transport.dart#L207); the server takes an OTK per call, guarded only by an hourly gap marker — [keys/module.dart:286-295](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/keys/module.dart#L286)
- **What:** fetching a recipient's bundles has a side effect: each device
  gives the requester one one-time prekey (at most one per hour per device,
  the gap marker). The transport treats GET as safe to repeat, so a response
  lost to a timeout is re-requested with the same parameters. The first call
  consumed and discarded the OTK; the retry sees the gap marker and returns
  the signed prekey alone. The caller gets a 200 and starts a session with no
  one-time prekey.
- **Trigger:** a mobile network timeout after the server has answered the
  first bundle request — routine on a slow or flapping link.
- **Evidence:** the gap marker is `putIfAbsent('keys:otk:$requester:$device')`
  before `takeOneTime`, so the second call within the hour takes nothing; the
  transport's `repeatable` depends only on the method and access
  ([transport.dart:164-168](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L164)).
- **Impact:** one prekey is burned per lost bundle response per target device,
  and the session it was meant to strengthen is initiated without an OTK
  (standard X3DH allows this, so messages still flow — the loss is forward
  secrecy for that session, plus an accelerated path to `prekeys_low` under
  bad networks).
- **Fix sketch:** state retry safety per route instead of deriving it from the
  method (S1): `accountKeys` is a "run once" GET; the transport sends it once
  and lets the caller decide. A server-side replay cache keyed by
  `(requester, target, device)` for a few seconds would also make the GET
  genuinely idempotent.
- **Test that proves it:** a fake server counts `takeOneTime` calls; a
  transport timeout on the first answer must not produce a second bundle
  request (today it does, and the second bundle has `oneTimePrekey == null`).
- **Overlap:** AUD-2-6 (gap marker set before the take), keys directory (sweep
  2), the transport's retry rule (11a), the engine peer fetch (sweep 12).

### AUD-11c-2 Admin sign-out keeps the token when the server call fails, so an offline operator stays signed in
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [admin_client.dart:50-55](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/admin_client.dart#L50)
- **What:** `signOut()` awaits the server route and only then calls
  `auth.forget()`. If the request throws (offline, 5xx, a proxy error), the
  admin token stays in `AdminTokenAuth`, and since admin tokens are not
  refreshed and last 12 hours, the console remains authenticated in memory
  after the operator asked to end the session.
- **Trigger:** signing out of the operator console while the server is
  unreachable or erroring.
- **Evidence:** no `try`/`finally`; `auth.forget()` is the second statement;
  the token expiry is 12 hours (class doc), so the window is long.
- **Impact:** on a shared or kiosk console, a sign-out that looks like it
  failed leaves a working admin session; the operator's next click still has
  full operator rights. The server session is correctly left alive, so the
  remedy is only local.
- **Fix sketch:** `try { await _t.empty(...); } finally { auth.forget(); }` —
  the server call is best effort; forgetting is not. The same reasoning that
  makes `DeviceSessionAuth.forget()` unconditional.
- **Test that proves it:** a transport whose route throws `NetworkException`;
  after `signOut()` the auth must hold no session.
- **Overlap:** admin console (sweep 17), `DeviceSessionAuth.forget` semantics
  (11a).

## Structural proposals

**S1 — the catalog states retry safety; the transport stops guessing from the
method.** *Current shape:* `repeatable = !unsafe || PUT || DELETE ||
device access` ([transport.dart:161-168](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L161)); HTTP semantics are a good default but not a
contract, and `accountKeys` is a counter-example. *Hazard:* AUD-11c-1, and
any future consuming GET (a `HEAD` that reserves, a `GET` that mints). *
*Proposed shape:* an optional `RetrySafety { byMethod (default), never,
idempotent }` field on `ApiRoute`, set deliberately for the exceptions; the
transport consults it, and a route-parity test asserts every route is
classified. *Migration:* expand (field defaults to `byMethod`; behaviour
unchanged) → migrate (`accountKeys` set to `never`, plus any other consuming
reads found in sweeps 3-10) → contract (the parity test requires an explicit
value for routes whose handler is documented to mutate, which the route
catalog can tag). *Risk:* low; the default preserves today's behaviour.
*Size:* S (catalog field + transport branch + one test).

## Coverage notes

- The route-parity test drives every non-S2S route through exactly one client
  method, so a method that silently targets the wrong route cannot pass.
- `GroupsClient.sendMessage`'s key override and `MessagingClient.send`'s
  message-id key are the two places the caller can influence idempotency; the
  engine always passes an explicit key (outbox `idempotencyKey`, sender
  `requestId`), so the pairwise path never relies on the transport's random
  key.
- The pairwise stale-list retry is safe despite reusing `request.id`: a thrown
  `ApiError` leaves `_idempotent` without saving (the pipeline maps it outside
  the idempotency wrapper, `pipeline.dart:82-109`), so the re-encrypted body
  is not compared against the earlier 409. Returned 4xx bodies (relayed group
  errors) *are* stored, which is what the group client's doc warns about.
- `OpsClient.ready` accepts 503 as a normal answer; `packManifest`/`packFile`
  cap their reads at the format's own limits (64 KiB / 8 MiB); `assetLinks`
  parses a raw list and maps a non-list body to `MalformedResponseException`.
- `AdminClient` validates that its transport carries `AdminTokenAuth`, keeps
  the token on setup/sign-in/password change, and its live log stream closes
  its socket on cancel (with the race where a cancel during connect closes the
  just-opened socket).
- `IdentityClient.pollLink` extends the per-attempt deadline by the requested
  wait; it is the only client that uses the `timeout:` override, which is why
  AUD-11a-1 matters elsewhere.
- `PeopleClient.findByName` and `OpsClient.sharePage` put user-chosen values
  in path segments; `route.expand` percent-encodes them, so neither can alter
  the path.

## Cross-sweep notes

- `AdminClient.logStream` is a second WebSocket implementation (admin
  audience): it has no heartbeat, no reconnect and swallows socket errors
  (`onError: (_) {}`), unlike `RealtimeClient`. A node deploy ends the stream
  as a normal `onDone`, so the console must resubscribe; sweep 17 should check
  that it does.
- An admin log socket authenticated at upgrade keeps receiving logs after the
  12-hour admin token expires; the server does not re-check the token on an
  open socket. That is a server-session-lifetime question for sweep 7, not a
  client defect.
- `IdentityClient.inviteSelfIssue()` is an anonymous POST that mints a
  single-use invite; a lost response leaves the invite alive but unseen. The
  transport deliberately never retries public POSTs, so this is inherent to
  the route rather than fixable in the client.
