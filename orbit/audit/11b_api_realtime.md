# 11b — `helix_remote_api`: realtime client

## Overview

The realtime client is the most carefully built part of the package: a
broadcast `envelopes` stream with cumulative acks, replay from a persisted
cursor, a restored-server reset judged by the cursor actually sent, a skippable
sequence set for unknown kinds, heartbeat by silence, and an explicit policy
for every close code (4001 refresh-and-open, 4003 terminal, 4004/4008 park,
4029 rate-limit floor, 4400 reported). `io_socket.dart` does the upgrade by
hand so an HTTP refusal arrives with its v2 error code instead of a generic
`WebSocketException`, and it checks `Sec-WebSocket-Accept`.

The gaps are at the edges of that handshake and around the hand-built
lifecycle: nothing bounds the body of a refused upgrade, the negotiated
subprotocol is not checked, `reconnect()` has no disposed guard, and the
silence detector runs on wall-clock time.

## Files read

- `realtime/realtime_client.dart` (597), `realtime/io_socket.dart` (115),
  `realtime/socket.dart` (52), `realtime/socket_stub.dart` (11)
- `test/v2/realtime_client_test.dart` (test names, 491) to see what is
  already pinned, and `server/lib/src/platform/http/websocket_limits.dart:1-80`
  for the upgrade wrapper the client faces.

## Findings

### AUD-11b-1 A refused upgrade can hang or leak: the error body has no deadline and the `HttpClient` is closed without force
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [io_socket.dart:21-22](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/io_socket.dart#L21) (connect timeout only), [:44](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/io_socket.dart#L44) (30 s for headers), [:46](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/io_socket.dart#L46) (unbounded body read), [:74-76](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/io_socket.dart#L74) (`close()` without `force`); the caller has no deadline around the connect — [realtime_client.dart:289-305](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L289)
- **What:** when the upgrade is refused, `_readCapped` consumes the error
  body with no timeout: a server that sends a 401 header line and then stalls
  the body holds `_open` in `connecting` indefinitely, with no retry timer
  armed. When the 30 s header timeout does fire, `Future.timeout` does not
  cancel the request, and `HttpClient.close()` with `force: false` leaves the
  active connection open — every retry leaves one more pending request and
  socket behind.
- **Trigger:** a proxy or node that accepts the TCP connection, answers (or
  does not answer) the upgrade, and never finishes the body — a hung server
  rather than a down one.
- **Evidence:** no `.timeout(` wraps the body read; `close()` is called with
  the default arguments; the client's state machine only moves on `_retry`,
  which nothing calls while `_connect` is awaiting.
- **Impact:** the device stops receiving messages but never reports a problem
  (state stays `connecting`); sockets and requests accumulate while the
  condition lasts; only a user-visible `reconnect()` (app resume) breaks it.
- **Fix sketch:** wrap the body read in the same 30 s deadline (or cancel the
  stream on timeout), and close the client with `force: true` in the
  `finally` — the upgraded socket is already detached, so the live WebSocket
  is unaffected. Optionally put a deadline on `_connect` itself in the
  realtime client so no factory can stall the state machine.
- **Test that proves it:** a fake refused-upgrade response whose body stalls;
  `connectPlatformSocket` must throw within the deadline (today it hangs), and
  the fake client must be closed forcibly.
- **Overlap:** the server's upgrade path and WS frame cap (sweep 1a/3), and
  the same "no deadline on a network call" class as AUD-1c-1.

### AUD-11b-2 The negotiated WebSocket subprotocol is never checked
- **Severity:** P3
- **Confidence:** likely
- **Where:** [io_socket.dart:65-72](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/io_socket.dart#L65) (the response protocol is read and passed through), offered at [realtime_client.dart:293-298](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L293)
- **What:** the handshake validates `Sec-WebSocket-Accept` but accepts any
  (or no) `Sec-WebSocket-Protocol` in the response. The RFC requires the
  server's choice to be one the client offered; a server or intermediary that
  drops or rewrites it still gets a connection that the client then speaks
  JSON over.
- **Trigger:** a proxy that strips the response header, or a server deployed
  with a different protocol string.
- **Evidence:** `protocol` is forwarded to `WebSocket.fromUpgradedSocket`
  without comparison to `realtimeSubprotocolJson`; every other handshake
  property is checked.
- **Impact:** protocol confusion instead of a clean, diagnosable failure; the
  first JSON frame might be answered with a 4400, which is then reported as a
  generic protocol error.
- **Fix sketch:** after the 101, require
  `protocol == realtimeSubprotocolJson`, else destroy the socket and throw
  `WebSocketException`.
- **Test that proves it:** a fake 101 response with a wrong/absent protocol
  header must raise, not connect.
- **Overlap:** realtime protocol spec (sweep 8), server upgrade (sweep 3).

### AUD-11b-3 `reconnect()` after `dispose()` builds a live socket into closed streams and leaves it running
- **Severity:** P3
- **Confidence:** likely
- **Where:** [realtime_client.dart:239-243](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L239) (`reconnect` has no disposed guard; `start` does, at [:226-228](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L226)), unguarded adds at [:506](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L506), [:511](file:///J:/Projects/helix/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L511), [:521](file:///J:/Projects/helix/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L521), [:530](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L530)
- **What:** `dispose()` closes the four controllers but leaves the object
  usable in every other respect. A later `reconnect()` (the app-resume call)
  sets `_running` and opens a real socket. `_emit` is guarded against closed
  controllers, but `_envelopes.add`, `_wakes.add` and `_errors.add` are not,
  and `_onText` runs inside a stream callback: the first frame after dispose
  throws `StateError: Cannot add to a closed stream` into the zone, the
  heartbeat timer keeps firing, and the socket is never closed.
- **Trigger:** an app-lifecycle resume (or a retry scheduled by the engine)
  that calls `reconnect()` after the runtime was disposed during sign-out.
- **Evidence:** `start` checks `_states.isClosed`, `reconnect` and `_open` do
  not; only `_emit` guards its controller.
- **Impact:** an unhandled asynchronous error plus a live WebSocket and timer
  after the app believes realtime is closed; in tests it fails the test that
  disposed the client.
- **Fix sketch:** make `reconnect()` throw the same `StateError` as `start`,
  and set a `_disposed` flag that `_open` checks before installing a socket;
  guard the three `add` calls with `isClosed` as `_emit` does.
- **Test that proves it:** dispose, then `reconnect()`; it must throw and no
  factory call may happen.
- **Overlap:** engine/app lifecycle (sweep 12/14).

### AUD-11b-4 The silence detector compares wall-clock times; a backward clock step disables it
- **Severity:** P3
- **Confidence:** likely
- **Where:** [realtime_client.dart:197-199](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L197) (`DateTime` timestamps), [:578-588](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L578) (`now.difference(...) > _heartbeat * 2 + idleGrace`), clock at [:175](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L175)
- **What:** `_lastHeard`, `_lastSent` and `_connectedAt` come from
  `DateTime.now`, which is not monotonic. If the system clock steps backwards
  (NTP correction, user change) while a connection is half-open, the
  difference stays negative and the dead-connection check can be suppressed
  until the clock catches up. A forward step of two heartbeats kills a healthy
  connection.
- **Trigger:** a clock adjustment during a dead-air network (half-open TCP,
  no FIN/RST).
- **Evidence:** all heartbeat arithmetic uses the injected wall clock; only
  `ReconnectPolicy` and `_connectedAt` use it too, so the same applies to the
  "reset backoff after 60 s" rule.
- **Impact:** no reconnect (and so no message delivery) for as long as the
  clock is behind; or a spurious reconnect after a forward step. Low
  frequency, self-healing once the clock is monotonic again.
- **Fix sketch:** use a monotonic source (`Stopwatch` or `clock` package's
  `Stopwatch`-backed instant) for elapsed-time decisions, keeping the injected
  clock only for tests; or clamp negative differences to zero and treat a
  large forward jump as "unknown".
- **Test that proves it:** inject a clock that steps back 10 minutes after a
  connection; the silence detector must still fire on schedule.
- **Overlap:** app clock/TLS handling (sweep 14); the server's own time source
  (sweep 1a).

## Structural proposals

**S1 — one connection lifecycle state machine in the client, not two.** The
client already tracks `_running`, `_generation`, `_retryTimer`, `_socket` and
`_subscription` by hand. Every finding above is an edge of that hand-built
machine (a connect that never returns, a reconnect after dispose, a timer left
armed). *Proposed shape:* keep the public API, but make `_open` run under a
single `_Connection` object that owns its socket, subscription, heartbeat
timer and deadline, and is disposed exactly once; `_retry`/`_abandon` replace
the object rather than mutating fields. *Migration:* internal refactor, no
wire change; the 28 realtime tests are the safety net. *Risk:* low (behaviour
is already pinned by tests). *Size:* M (~-80/+120 lines).

## Coverage notes

- The tests pin ack cumulativity, replay at/below the cursor, duplicate
  suppression, unknown kinds skipped in order, restored-server reset, cursor
  moved during connect, acks made while disconnected, heartbeat/drop, every
  close code, backoff reset and jitter.
- `_skip` only acks a sequence once every lower outstanding stored envelope is
  acked, so a skipped unknown kind cannot hide a gap
  ([realtime_client.dart:533-551](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L533)).
- `io_socket.dart` verifies `Sec-WebSocket-Accept` against the SHA-1 of the
  nonce and the fixed GUID, sets `followRedirects = false`, and reads at most
  64 KiB of a refusal body.
- On web, `defaultSocketFactory` is the stub that throws `UnsupportedError`;
  the factory can be injected. Any other connect error (including that one) is
  retried with backoff, so a missing factory on a web build would look like an
  unreachable server rather than a clear configuration error — worth a log
  line when the admin console is audited (sweep 17).
- `_url()` switches `https`→`wss` and keeps the base path prefix; the cursor
  is captured there, before the connect, so the restored-server reset compares
  against the cursor the server actually received.
- Envelope delivery is not bounded in the client, but the server's window and
  the cumulative ack bound in-flight stored envelopes; ephemeral frames
  (`seq == null`) bypass the cursor by design.

## Cross-sweep notes

- `RealtimeClient` reuses `DeviceSessionAuth` single-flight refresh on 4001
  ([realtime_client.dart:391-411](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L391)), so a REST call and a socket 4001 at the same moment share one rotation — the right shape for the server's reuse-as-theft rule (sweep 2).
- The 4008 "superseded" path deliberately does not fight the newer
  connection; the app must call `reconnect()` on resume, which sweep 14 should
  confirm is wired.
