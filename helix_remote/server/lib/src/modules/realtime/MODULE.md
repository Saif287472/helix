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
with 4029. The frame bucket and the idle timer run on a monotonic uptime
(`platform/clock.dart`), so a wall-clock step (NTP, a manual change) closes
no socket (AUD-3-9); `hello`'s `server_time` is still wall-clock time.

1. **Supersede:** a previous connection for the device on this node is
   closed with 4008. Accepts for one device run one at a time (a per-device
   turn), so the map write, the route and that close happen in accept
   order. `realtime.connected` on the bus closes the socket on other nodes
   only when the route there no longer names it: delivery can lag, and a
   hint for an older connection must not close a newer socket (AUD-3-12).
2. **Route:** `rt:route:<device>` = `<node>|<connection>` is stored with a
   75 s TTL and refreshed every 25 s by compare-and-set
   (`EphemeralStore.replace`): a refresh that finds another connection's
   route closes this socket (4008) instead of overwriting it, and closing
   deletes the route only if it is still this connection's (`deleteIf`).
   The sweep is single-flight: a tick that fires while the previous pass is
   still awaiting the store and the authenticator is skipped and counted
   (`helix_ws_refresh_skipped_total`), so a stalled pass cannot overlap the
   next (AUD-3-4).
   `Presence` (kernel) reads it, so messaging can choose between socket and
   push.
   A route alone is not reachability: it is what a crash leaves behind. So
   each node also renews `rt:node:<node>` (20 s TTL, every 5 s) and
   `Presence` counts a device online only while both keys are present
   (AUD-3-3). A node that dies where it stood stops "holding" its devices
   after 20 s rather than 75, and the conservative direction is a push;
   `stop()` deletes its own key once the sockets have drained.
3. **Hello:** `hello` with `last_seq`, `heartbeat_s: 25` and `window: 100`.
4. **Pump:** stored envelopes after `?after=` are sent oldest first, at
   most 100 un-acked. When the window is full the server first drops
   un-acked seqs below the oldest stored envelope (acked over REST, on any
   node), then sends `wake` if it is still full. Each `ack` deletes through
   messaging and releases credit. The 25 s refresh re-pumps full windows.
5. **Live delivery:** `mailbox.wake` (bus, a chunk of devices) pumps those
   sockets on whichever node holds them. `realtime.ephemeral` (`{r: ref,
   d: [devices]}`) names the devices a parked envelope waits for; each
   socket takes its own value, so it is delivered once. `platform.resync`
   (the bus connection came back)
   pumps every socket, so a wake-up missed meanwhile is not lost.
6. **Close:** revocation (`device.revoked` on the bus) closes with 4003.
   Ended sessions (`identity.sessions_ended`, with the cut-off) and the 25 s
   refresh re-check the socket's token through identity's authenticator:
   expired or older than the cut-off closes with 4001, so a socket lives at
   most one access-token lifetime and a fresh sign-in's socket stays. That
   check is deliberately not cached: it is the backstop for an invalidation
   whose bus hint was missed while the LISTEN connection was down (AUD-3-13,
   declined). Should the sweep's cost ever matter, batch the check per sweep;
   a cache only moves the revocation window.
   Suspension (`identity.account_suspended`, or seen on refresh) closes
   with 4004. Two silent heartbeats close with 4010; shutdown and failed
   delivery close with 4503 (not 1001, which WebSocket libraries refuse).
   A connection that was registered but failed to start (the route save, the
   `realtime.connected` publish or the first mailbox read threw) is closed
   with 4503 too, so presence does not keep it online until the idle
   timeout (AUD-3-10); its route is deleted and its map entry removed.
   Closing always clears the route if it is still this connection's, and
   records `rt:seen:<account>` for presence.

All per-connection work runs through `track`, which logs failures instead
of crashing the socket's zone and lets `stop()` wait for it before the
database closes.
