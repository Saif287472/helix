# Helix Remote v2 — Realtime

Status: **specified 2026-10-01 (Phase P1), pending user review.** Code:
`packages/helix_remote_protocol/lib/src/realtime.dart`, `envelope.dart`.

## Connection

`GET /v1/ws` with `Authorization: Bearer <access token>` and
`Sec-WebSocket-Protocol: helix.v1+json` (a future binary codec is another
subprotocol name, negotiated alongside). Optional `?after=<seq>`: the last
`seq` this device has processed but may not have acked yet.

- One connection per device. A new one replaces the old one (close
  `4008 superseded`).
- The server's first frame is `hello` (`server_time`, `heartbeat_s`,
  `window`, `last_seq`). The client sends a frame at least every
  `heartbeat_s` seconds (a `ping` when idle).
- A client message (all its fragments) is at most 64 KiB; a larger one
  drops the connection without a close frame (reconnect normally).
- **Close codes:** `4001` unauthorized: the access token expired or the
  session ended (sign-out, refresh-token reuse); refresh, then reconnect.
  `4003` device revoked (stop; sign out locally). `4004` the account was
  suspended while connected (tell the user; a suspended account may
  reconnect, read-only). `4008` superseded. `4010` idle (no frame for two
  heartbeats). `4029` rate limited: too many upgrades (20 per 10 minutes per
  device) or frames (burst 300, 30 per second); back off ≥ 30 s. `4400`
  protocol error. `4503` server going away or could not deliver (reconnect
  with backoff). (WebSocket libraries only let applications send 1000 or
  3000-4999, so v2 uses `4503`, not `1001`.)
- A socket lives as long as its access token: the server re-checks the
  token every 25 s and closes with `4001` once it has expired (15 minutes)
  or predates a session cut-off.
- **Reconnect backoff:** 1 s, doubling to 60 s, with ±20% jitter; reset after
  a connection lasts 60 s.

## Delivery

```
server                                        client
  hello{last_seq:1041, window:100}  ───────▶
  envelope{seq:1037 …} … envelope{seq:1041}  ─▶   (replay of the mailbox after `after`)
                                     ◀───────  ack{seq:1041}         (cumulative)
  envelope{seq:1042 …}             ───────▶       (live, as sends commit)
  envelope{call_signal, no seq}    ───────▶       (ephemeral: never acked)
```

- Stored envelopes go out oldest first, at most `window` un-acked at a time;
  each `ack` returns credit. When the window is full the server stops and
  sends `wake` once more arrives; the client keeps acking (or pages with
  `GET /v1/mailbox`). Acks over REST (`POST /v1/mailbox/ack`) return the
  socket's credit too.
- **Ack only after the envelope is durably processed** (decrypted and
  written in the local database transaction, or quarantined). An ack deletes
  envelopes with `seq ≤ ack` from the server, permanently.
- **Duplicates are possible** (replay after a reconnect before the ack
  landed). Clients de-duplicate by envelope `id` + sender device; `seq` is per
  device and strictly increasing, with gaps.
- Ephemeral envelopes (`call_signal`, and `message` with no `seq` — typing)
  are delivered only to connected devices and never acked.

## Node routing (server side, not visible to clients)

Each node records `device → node` routes in the ephemeral store with a
heartbeat TTL. A node extends and deletes only its own connection's route
(compare-and-set), so a newer connection on another node keeps its route. A send commits mailbox rows, then publishes `device.wake` on
the event bus; the node holding the socket reads the mailbox and pushes.
"Is the device online" is a route lookup, so call delivery and push decisions
work across nodes. Revocation publishes `device.revoked`; the owning node
closes the socket with `4003`. Ending sessions publishes the cut-off; the
owning node re-checks the socket's token and closes it with `4001` only if
the token predates the cut-off. Suspension publishes the account; its
sockets close with `4004`.

## Unknown things

- An unknown server frame type is ignored; if it has a `seq`, it is acked.
- An envelope of unknown `kind` is acked and ignored.
- Unknown fields are ignored.
