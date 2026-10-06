# Load testing

Status: updated at Phase X. The v1 smoke harness (`backend/tool/load_smoke.dart`) was deleted
with the v1 backend; the harness below is the only one. Record the emitted request counts,
concurrency, failures, p50 and p95 in the release evidence, and increase the load until the p95
budget or the error-rate budget fails.

## Server (`server/`, Phase S7)

`server/tool/load.dart` boots one v2 node **in-process** (all modules, the
Postgres platform, the production rate limits) on `127.0.0.1` with an
OS-assigned port. It uses the test database `HELIX_TEST_DATABASE_URL`, and the
tool refuses any database whose name does not contain `test`. Every run gets a
fresh schema prefix (`ld…_`), which is dropped at the end. The tool then:

1. **Provisions** N devices, one account each, through the real Helix Global
   flow: phone challenge, verify, then register with an AIK-certified
   device, DSK proof, signed prekey and one-time prekeys. This is not a fast
   path. The recording SMS provider (dev mode only) hands the codes to the
   workers in memory, and they are never printed.
2. **Opens** one authenticated WebSocket per device (`helix.v1+json`) and
   waits for `hello`.
3. **Sends** for warm-up + duration. Each device sends Poisson arrivals at
   `--rate` (open loop) to a random peer (`POST /v1/messages`, addressed to
   all of the peer's devices). A `--group-share` of sends instead go to the
   device's group of `--group-size` (`POST /v1/groups/{id}/messages` with the
   `membersDigest` device digest). Payloads are random bytes sized like real
   sealed messages (160-byte padding buckets plus about 100 bytes of
   overhead; `--payload-bytes` fixes the size). Each payload starts with a run
   tag and the send time.
4. **Receives** on the sockets and acks every envelope there. An
   `--ack-sample` share is also acked over REST to time acks, because socket
   acks have no reply.

The simulated devices run in worker isolates started with
`Isolate.spawnUri`, each with its own heap, so client garbage collection
never pauses the server isolate. Each simulated device sends `X-Forwarded-For:
10.x.y.z`. The node trusts loopback as its proxy, so as behind Caddy every
device gets its own per-IP rate-limit buckets. **No limits are overridden.**
Server log lines are formatted and redacted as in production, then counted
instead of written, and warnings and errors are reported by event and code
location.

The report measures:

- **REST send latency:** request issued to response read.
- **Delivery:** the send was issued to the recipient socket receiving the
  envelope, using the send time inside the payload.
- **REST ack latency.**
- **Connect time:** until `hello`.
- **Registration**, per call.
- **Event-loop lag** of the server isolate and of the workers. Low lag means
  that isolate was not the bottleneck.
- **Server-side mean time per route**, from `/metrics`.
- **Errors**, by route and code.
- **Process CPU.**

`deliveries_expected` counts only sends whose response arrived. Sends the
client gave up on (30 s timeout) can still commit and be delivered, so
"received" can exceed "expected" under overload.

```bash
cd helix_remote/server
dart run tool/load.dart --help
dart run tool/load.dart --devices 1000 --rate 0.05 --duration 60 --json load.json
```

Defaults are `--devices 1000 --rate 0.2 --warmup 5 --duration 60 --drain 15
--group-share 0.1 --group-size 8 --ack-sample 0.05 --one-time-prekeys 20`,
with workers set to half the cores. Access tokens are not refreshed, so a run
must stay under 13 minutes. `test/load/load_smoke_test.dart` runs 20 devices
for 5 s so the tool cannot rot.

### Results 2026-10-01 (PC, 1 node, 1,000 devices)

- **Machine:** Intel i5-7400, 4 cores / 4 threads, 16 GB RAM, Windows 11 Pro
  26200, Dart 3.12.2, PostgreSQL 17.9 (Windows service, default config:
  `shared_buffers` 128 MB, `synchronous_commit` on).
- **The machine was shared.** The user's browser and another agent's test run
  were active; total CPU was 18-36% just before the runs.
- **Run setup:**
  - Postgres round trips measured about 5 ms for `SELECT 1` and 13-36 ms per
    commit on this machine.
  - Two worker isolates, 1,000 sockets.
  - Groups: 125 groups of 8, 10% of sends.
  - Provisioning: 1,000 registrations in 67 s (~15/s), 125 groups in 6 s,
    1,000 sockets in 9 s.

**Sustainable rate: `--rate 0.05`, 50 sends/s offered, 80 deliveries/s.**
No errors, 4,776 of 4,776 deliveries, no duplicates or reconnects.

| Metric | count | p50 ms | p95 ms | p99 ms | max ms |
|---|---|---|---|---|---|
| REST send 1:1 | 2,690 | 18.0 | 319.9 | 646.4 | 1,041.9 |
| REST send group (8) | 298 | 24.1 | 408.5 | 616.6 | 1,041.4 |
| Delivery 1:1 (send -> socket) | 2,690 | 18.1 | 351.2 | 690.9 | 1,082.1 |
| Delivery group (send -> socket) | 2,086 | 29.9 | 439.2 | 636.7 | 1,076.1 |
| REST ack (sampled) | 240 | 13.9 | 118.4 | 239.6 | 593.9 |
| WS connect (to hello) | 1,000 | 506.2 | 1,059.6 | 1,134.6 | 1,143.1 |
| Registration (3 calls) | 1,000 | 919.2 | 1,351.3 | 2,789.4 | 3,891.6 |

Server-side means: send 55 ms, group send 68 ms, ack 27 ms. Server loop lag
p95 was 13.6 ms and the process used 0.68 cores.

**Overload: default `--rate 0.2`, 200 sends/s offered.** The node completed
about 83 sends/s (server-side mean 6.2 s), and the rest queued for the
database pool:

- 9,279 sends hit the client's 30 s timeout, and 301 sampled REST acks did
  too.
- Delivery p50/p95 was 35/55 s.
- Server loop lag p95 was 9.9 ms, and the process used 1.31 cores.
- The server logged 235 `unhandled_error` lines (`PgException`/`StateError`
  in `PostgresDb.notify`, `PostgresDb.tx` and `_query`). These are probably
  the requests still queued at shutdown, but that was not confirmed.

**Bottleneck: the database pool, not the Dart isolate.** Server CPU and loop
lag stay low while requests queue. One send costs about 12 round trips:

- the per-IP limit
- the auth lookup
- the replay check
- the device check
- blocks
- the send transaction (sequence, insert, presence, push), and its commit
- `NOTIFY`
- the socket's mailbox fetch
- the ack transaction

All of these run over a hard-coded 10-connection pool, with millisecond round
trips and fsync'd commits on this PC. That puts the ceiling at about 80
sends/s. To raise it:

- make the pool size configurable;
- batch round trips on the send path (presence is read once per device);
- tune Postgres (`shared_buffers`, WAL on a fast disk).

### Bugs the harness found

Fixed in S7, with tests in `test/platform/resilience_test.dart`:

- **The node deadlocked at about 10 concurrent sends.** Messaging `deliver`
  reads presence (the ephemeral store) inside the send transaction. On the
  shared pool, every in-flight send held one connection while waiting for a
  second, so everything stalled until the 15 s acquire timeout. This showed
  at 20–40 devices. The fix gives the ephemeral store its own 4-connection
  pool (`platform.dart`; rule added to `PLATFORM.md`).
- **A failed job-runner or periodic-scheduler pass ended the process.**
  `unawaited(tick())` let a pool timeout escape as an unhandled error. The
  fix logs `jobs_tick_failed` / `periodic_tick_failed` and retries on the next
  poll.

Open:

- **Close code 1001 cannot be sent.** `RealtimeCloseCode.goingAway` (1001) is
  rejected by `web_socket_channel` on the server side, which accepts only 1000
  or 3000-4999. As a result:
  - `_Connection.close` throws when a delivery fails, which leaves the
    connection marked closed but still routed: the device looks online and
    gets nothing.
  - `RealtimeModule.stop()` throws on shutdown while sockets are open.
  - `admin` has the same problem with `close(1001)`.

  Fixing it needs a protocol decision: a 4xxx code for "going away" in
  REALTIME_V2.md.
- **Nested `Db.tx` takes a second pool connection.** `PostgresDb.tx` takes a
  new pool connection when called inside a transaction; the plan says nested
  calls reuse the outer one. Any such nesting can deadlock the same way, so
  it needs an audit.
