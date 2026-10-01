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
  - `end` clears pending rows and pushes `call_ended`, so ringing
    notifications stop.
- **State** (`PUT /v1/calls/{call_id}/state`): answering or declining on
  one device ends the ringing on the account's other devices (an
  ephemeral `call_signal` with `{kind: end, state}`, plus `call_ended`
  pushes for pending ones).
- **`GET /v1/calls/pending`:** offers this device missed while asleep,
  fetched after a push wake.
- **TURN** (`HELIX_TURN_URLS`, `HELIX_TURN_SECRET`): coturn REST
  credentials. `username = <expiry>:<account>` and
  `credential = base64(HMAC-SHA1(secret, username))`, valid one hour.
  Limited to 10 per device per hour; 503 `unavailable` if not configured.
- **Metrics:** quality numbers keyed by call id only, kept 90 days.
- **Limits:** 30 offers per account per 10 minutes.
