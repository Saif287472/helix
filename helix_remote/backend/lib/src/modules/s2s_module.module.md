# Module: s2s_module

Status: current. Follows the template in `messaging.module.md`.

## Purpose

The server-to-server surface: everything one Helix server exposes to
*another* Helix server rather than to a client. Prekey bundle lookup,
message proxying, conversation event relay, group state sync and action
proxying, and federated call signaling.

Milestones 3 (1:1 federation), 4 (group federation) and 5 (call
federation) all land here.

## Owned files

- `s2s_module.dart` - `S2SModule`, its Shelf router, and every handler.

## Route table

Mounted at `/api/v1/s2s` by `server_impl.dart`. **None of these routes uses
the session middleware** - `_authMiddleware` skips any path containing
`/s2s/`. They are authenticated instead by `_s2sAuthMiddleware`, which
verifies the peer's signature against its registered server public key and
puts the caller's server id in `request.context['s2s_sender_id']`.

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET | `/prekeys/bundle` | `_prekeysBundleHandler` | Peer fetching one of our accounts' bundles on behalf of its user. |
| POST | `/messages/proxy` | `_messagesProxyHandler` | One envelope for one local device. |
| POST | `/messages/proxy-batch` | `_messagesProxyBatchHandler` | Many envelopes in one signed request. A bad envelope fails alone, not the batch. |
| POST | `/conversations/event-relay-batch` | `_eventRelayBatchHandler` | Receipts, typing, reactions - account-addressed, fanned out to devices here. |
| POST | `/groups/sync` | `_groupsSyncHandler` | Home server pushing a roster snapshot. Only the group's own home server may call it. |
| GET | `/groups/state` | `_groupsStateHandler` | Peer pulling current group state from us as home. |
| POST | `/groups/action` | `_groupsActionHandler` | Participant server proxying its admin's action to us as home. |
| POST | `/groups/epoch-key/deliver-batch` | `_groupsEpochKeyDeliverBatchHandler` | Wrapped Sender Keys for our local member devices. |
| POST | `/calls/signal` | `_callsSignalHandler` | Milestone 5.1 federated WebRTC signaling. |

## Error codes this module throws

The [`AppError`](../app_error.dart) shape. `.badRequest` for missing fields,
`.unauthorized` for a peer overreaching its authority (pushing sync for a
group it does not host, proxying an action for an account outside its own
domain), `.conflict` when we are not the home server for the group in
question, `.notFound`, and `.serviceUnavailable` when group or call
federation is not wired up on this deployment.

## Dependencies

- `BackendDatabase` (`../database.dart`) - all persistence.
- `MessageRelay` (`messaging.dart`) - delivering a proxied envelope onward
  to a local device's socket.
- `GroupsModule?` / `CallsModule?` - optional back-references. When null,
  the corresponding routes report `serviceUnavailable` rather than half
  applying an action.
- `FederationClient` (`../federation.dart`) - for the outbound direction.

## Gotchas

- **These handlers answer another server, not a user.** A caught exception
  is logged and the peer gets the generic 500 body; the detail is
  deliberately not interpolated into the response the way it used to be.
- **`_groupsSyncHandler` checks `home_server_id == s2s_sender_id`.** Without
  it, any authenticated peer could rewrite any group's roster. This is the
  single most security-load-bearing check in the module.
- **`_groupsActionHandler` additionally checks the acting account's domain
  against the sender's**, so a server may only proxy actions for its own
  local users. Defense in depth on top of the signature check.
- **Account ids cross the boundary qualified (`user@domain`) and are
  localized on arrival** by `_localAccountId`. Forgetting that is how a
  local lookup silently misses.
- **`_applyProxiedMessage` returns a result map rather than throwing**, so
  the batch endpoint can report per-envelope outcomes. Only the
  single-envelope route turns a failed result into an `AppError`.
