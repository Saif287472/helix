# realtime module

The WebSocket gateway (REALTIME_V2.md). There is no schema: its state is
in-memory per node, plus routes in the ephemeral store.

## Connection

`GET /v1/ws`: a device access token is required, and subprotocol
`helix.v1+json` (anything else closes with 4400). Suspended accounts may
connect, so they can still read.

1. **Supersede:** a previous connection for the device on this node is
   closed with 4008. `realtime.connected` on the bus does the same on
   other nodes.
2. **Route:** `rt:route:<device>` = `<node>|<connection>` is stored with a
   75 s TTL and refreshed every 25 s. `Presence` (kernel) reads it, so
   messaging can choose between socket and push.
3. **Hello:** `hello` with `last_seq`, `heartbeat_s: 25` and `window: 100`.
4. **Pump:** stored envelopes after `?after=` are sent oldest first, at
   most 100 un-acked. When the window is full the server sends `wake`.
   Each `ack` deletes through messaging and releases credit.
5. **Live delivery:** `mailbox.wake` (bus) pumps the device's socket on
   whichever node holds it. `realtime.ephemeral` delivers a parked
   ephemeral envelope once.
6. **Close:** revocation (`device.revoked` on the bus) closes with 4003.
   Two silent heartbeats close with 4010; shutdown closes with 1001.
   Closing clears the route if it is still this connection's, and records
   `rt:seen:<account>` for presence.

All per-connection work runs through `track`, which logs failures instead
of crashing the socket's zone and lets `stop()` wait for it before the
database closes.
