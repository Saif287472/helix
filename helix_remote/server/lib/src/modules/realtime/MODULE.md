# realtime module

The WebSocket gateway (REALTIME_V2.md). There is no schema: its state is
in-memory per node, plus routes in the ephemeral store.

## Connection

`GET /v1/ws`: a device access token is required, and subprotocol
`helix.v1+json` (anything else closes with 4400). Suspended accounts may
connect, so they can still read. Client messages are capped at
`maxClientMessageBytes` (64 KiB): `platform/http/websocket_limits.dart`
reads frame headers on the raw socket and destroys it before a larger
payload is buffered (`dart:io` has no limit of its own).
More than 20 upgrades per device in 10
minutes, or client frames beyond a burst of 300 at 30 per second, close
with 4029.

1. **Supersede:** a previous connection for the device on this node is
   closed with 4008. `realtime.connected` on the bus does the same on
   other nodes.
2. **Route:** `rt:route:<device>` = `<node>|<connection>` is stored with a
   75 s TTL and refreshed every 25 s by compare-and-set
   (`EphemeralStore.replace`): a refresh that finds another connection's
   route closes this socket (4008) instead of overwriting it, and closing
   deletes the route only if it is still this connection's (`deleteIf`).
   `Presence` (kernel) reads it, so messaging can choose between socket and
   push.
3. **Hello:** `hello` with `last_seq`, `heartbeat_s: 25` and `window: 100`.
4. **Pump:** stored envelopes after `?after=` are sent oldest first, at
   most 100 un-acked. When the window is full the server first drops
   un-acked seqs below the oldest stored envelope (acked over REST, on any
   node), then sends `wake` if it is still full. Each `ack` deletes through
   messaging and releases credit. The 25 s refresh re-pumps full windows.
5. **Live delivery:** `mailbox.wake` (bus) pumps the device's socket on
   whichever node holds it. `realtime.ephemeral` delivers a parked
   ephemeral envelope once. `platform.resync` (the bus connection came back)
   pumps every socket, so a wake-up missed meanwhile is not lost.
6. **Close:** revocation (`device.revoked` on the bus) closes with 4003.
   Ended sessions (`identity.sessions_ended`, with the cut-off) and the 25 s
   refresh re-check the socket's token through identity's authenticator:
   expired or older than the cut-off closes with 4001, so a socket lives at
   most one access-token lifetime and a fresh sign-in's socket stays.
   Suspension (`identity.account_suspended`, or seen on refresh) closes
   with 4004. Two silent heartbeats close with 4010; shutdown and failed
   delivery close with 4503 (not 1001, which WebSocket libraries refuse).
   Closing always clears the route if it is still this connection's, and
   records `rt:seen:<account>` for presence.

All per-connection work runs through `track`, which logs failures instead
of crashing the socket's zone and lets `stop()` wait for it before the
database closes.
