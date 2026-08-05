# Module: calls

Status: current. Follows the template in `../messaging.module.md`; see the
[structural upgrade plan](../../../../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
for why these docs exist.

## Purpose

1:1 WebRTC calling: issuing TURN relay credentials, routing signaling frames
(offer / answer / ICE candidate / hangup) between devices, and the
pending-call queue that lets a closed app be woken by push and then find out
what it was woken for.

Group calls are a separate module (`../group_calls.dart`) — this one is
strictly caller-to-callee.

## Owned files

Split from a single 1403-line file (plan item A3) into `part` files holding
mixins, the same mechanism `../auth/` and `../groups/` use.

| File | Lines | Holds |
|---|---|---|
| `../calls.dart` | ~336 | Routes, TURN credential issuing, shared small helpers |
| `signaling.dart` | ~425 | `_routeSignal`, `_routeOffer`, `_routeSessionSignal` |
| `delivery.dart` | ~260 | Device fan-out, answered-elsewhere, push wake |
| `pending.dart` | ~160 | The pending-call queue |
| `federation.dart` | ~115 | Cross-server signal proxying, both directions |
| `validation.dart` | ~100 | Frame parsing, size bounds, rate-limit windows |
| `push_tokens.dart` | ~85 | Device push-token registration |
| `support.dart` | ~75 | `_WindowCounter`, `_ParseResult`, `_ParsedCallSignal` |

## Route table

Mounted at `/api/v1/calls` by `server_impl.dart`. Every route requires a
valid session.

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET | `/turn-credentials` | `_handleTurnCredentials` | Short-lived HMAC credentials, 1h validity. 10/hour per account *and* per device. 503 when TURN is unconfigured. |
| POST | `/signal` | `_handleSignal` | The REST signaling entry point. The WebSocket path reaches the same `_routeSignal`. |
| GET | `/pending` | `_handlePendingCalls` | 30/minute per device. |
| POST | `/pending/<callId>/accept` | `_handleAcceptPending` | Notifies sibling devices they lost the race. |
| POST | `/pending/<callId>/decline` | `_handleDeclinePending` | |
| POST | `/pending/<callId>/cancel` | `_handleCancelPending` | Caller-side cancel. |
| POST | `/pending/<callId>/expire` | `_handleExpirePending` | |
| POST | `/push-token` | `_handleRegisterPushToken` | `token_type` must be `FCM` or `APNS`; token capped at 4096 chars. |
| DELETE | `/push-token` | `_handleDeregisterPushToken` | |
| POST | `/metrics` | `_handleCallMetrics` | Client-reported call quality metrics. |

`receiveFederatedSignal` is not a route — it is what `S2SModule` calls when
a peer server proxies a signal to us, and it converges on the same routing
logic as the REST and WebSocket entry points.

## Error codes this module throws

The [`AppError`](../../app_error.dart) shape. `.unauthorized` / `.forbidden`
for missing sessions, `.badRequest` for malformed frames, `.notFound` for an
unknown pending call, `.tooManyRequests` for every rate limit, and
`.serviceUnavailable` when TURN is not configured. Two responses attach
structured context through `AppError.withDetails` rather than putting extra
keys beside `error`: the TURN 503 reports `turn_configured`, and the TURN
429 reports which of the account or device quota was hit.

## Dependencies

- `BackendDatabase` (`../../database.dart`) — call sessions, pending calls,
  push tokens, TURN credential issue log.
- `WebSocketRelay` (`../../websocket.dart`) — delivery to online devices.
- `PushProvider` (`../../push_provider.dart`) — waking a device with no live
  socket. Defaults to `NoopPushProvider`, so an unconfigured deployment
  degrades to online-only calling rather than failing.
- `FederationClient?` (`../../federation.dart`) — optional; without it,
  calls to external accounts cannot be placed.
- `turnSecret` / `turnUrl` — shared with the coturn deployment. See
  `deploy/coturn/README.md`: if the secret drifts between backend and relay,
  calls fail with a 401 **from the relay** that never appears in the
  backend's own logs.

## Gotchas

- **The validation bounds are abuse limits, not tidiness.** `_maxSdpLength`
  (64 KB) and `_maxCandidateLength` (4 KB) cap what a peer can push through
  the relay; the per-account, per-device and per-IP windows cap how fast.
  They are in their own file so they can be audited as a set.
- **`_maxConcurrentCallsPerAccount` is 1.** A second offer while a call is
  live is rejected, not queued.
- **A pending call's TTL is 45s** (`_pendingCallTtlMs`). Expiry is swept
  lazily on read, not by a timer — a stale row exists until something looks
  at it.
- **`CallsModule.resolveTurnUrls` is deliberately strict**: it accepts only
  `turn:` and `turns:` schemes and drops anything else. A typo'd
  `https://...` entry silently produces no usable URL, which is why the
  handler reports 503 rather than issuing credentials that cannot work.
  `operability.dart` calls the same function so the admin console's TURN
  status reflects what the call path would actually accept.
- **Push-token pruning is driven by exception type.** A
  `FcmTokenNotFoundException` from the provider means "this token is dead" —
  the call path deletes it, and the outbox worker completes the event rather
  than retrying. Both branches depend on that specific type, which is why it
  stays a distinct class even though it is now an `AppError` subtype.
- **The 1:1 call lifecycle is described by `RemoteCallSessionStatus`** in
  `helix_remote_domain` (plan item A6). `active <-> reconnecting` cycles for
  ICE restarts; every other ending is terminal and a retry is a new call.
