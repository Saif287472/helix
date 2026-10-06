# calls module

1:1 call signalling (REST_V2.md "calls"). Schema `calls` (`pending_calls`,
`call_metrics`). Group calls are deferred (plan §13).

- **Signals** (`POST /v1/calls/{call_id}/signals`) carry sealed pairwise
  payloads: SDP, ICE, caller name and audio/video live inside them. The
  server sees the call id, the parties and the kind (`offer`, `update`,
  `end`).
  - Online devices get a `call_signal` envelope at once (ephemeral, via
    messaging). Blocked callers reach nobody.
  - An `offer` must address every active device of the callee
    (`device_list_stale` otherwise). Devices that are offline get a
    `pending_calls` row (TTL up to 120 s) and a high-priority `call` push.
    A row is refreshed only by the same caller device (`ON CONFLICT … WHERE`
    the caller matches); anyone else's offer under that call id is not
    stored and pushes nothing.
  - `end` clears the pending rows the sender is in (as caller, or as the
    callee device's account) and pushes `call_ended`, so ringing
    notifications stop. A third party knowing a call id clears nothing.
- **State** (`PUT /v1/calls/{call_id}/state`): answering or declining on
  one device ends the ringing on the account's other devices (an
  ephemeral `call_signal` with `{kind: end, state}`, plus `call_ended`
  pushes for pending ones). Only rows the account is in are cleared.
- **`GET /v1/calls/pending`:** offers this device missed while asleep,
  fetched after a push wake.
- **TURN** (`HELIX_TURN_URLS`, `HELIX_TURN_SECRET`): coturn REST
  credentials. `username = <expiry>:<random id>` (12 random bytes,
  base64url, new on every request) and
  `credential = base64(HMAC-SHA1(secret, username))`, valid one hour.
  coturn checks only the expiry and the HMAC, so the name carries nothing
  about the account or device: the username crosses the network in the clear
  on `turn:` (port 3478), and an on-path observer must not be able to tie
  an address to a person. `HELIX_TURN_URLS` entries must start with `turn:`
  or `turns:` (TLS, port 5349); list both and clients try them in order.
  Limited to 10 per device per hour; 503 `unavailable` if not configured.
- **Metrics:** quality numbers keyed by call id only, kept 90 days.
- **Limits:** 30 offers per account per 10 minutes; every other signal
  (`update`, `end`, ICE) 240 per sending device per minute, on top of the
  per-address limit (federated senders are keyed by qualified account and
  device); 100 metric reports per account per day (at most 9,000 rows per
  account kept).

## Client side

The engine's `CallsService` (`helix_remote_engine`, see its MODULE.md) is the
only client of this module: it seals `CallSignalPayload` (REST_V2.md "calls")
per device, sends an offer to every active device of the callee and everything
else to the one device the call talks to, calls `PUT …/state` when a device
answers or declines, and reads `GET /v1/calls/pending` after a push or a socket
connect. Pending rows are not deleted when read (the TTL or an `end` clears
them), so a client must remember the calls it already rang.

## Federation

Signals to `uuid@domain` go through `CallRelay` before any local device
rings, and they are synchronous (`federation_unavailable` if that server is
down). Signals from other servers enter through `CallsApi.receive`, with
offer limits keyed by the qualified caller. `pending_calls.caller_account`
is `text` since migration 2.
