# Server platform (`lib/src/platform/`)

Infrastructure every module uses through `ModuleContext` (ADR-025/026). No
business logic lives here. Everything is safe to run on several nodes against
one Postgres database.

| Piece | File | Single host now | Scale-out later |
|---|---|---|---|
| Config | `config/server_config.dart`, `env_file.dart` | `HELIX_*` env + `server/.env` | same |
| SQL | `db/db.dart` (`Db`, `Tx`, `Row`), `db/postgres_db.dart` | Postgres pool; every transaction sets `statement_timeout` 15 s and `lock_timeout` 5 s (`Db.tx` overrides, `Duration.zero` for none: migrations only), statements outside one have the driver's `query_timeout` 30 s; `readOnlySnapshot: true` opens `REPEATABLE READ, READ ONLY` (never `SET TRANSACTION` in the body: the timeouts come first) | same (+ replicas) |
| Migrations | `db/migrations.dart`, `platform_migrations.dart` | per-module Dart constants, checksummed, advisory lock | same |
| Schema names | `db/schema_names.dart` | module name = schema | test prefixes |
| Event bus | `bus/event_bus.dart` | `LISTEN/NOTIFY`; the `LISTEN` connection reopens with backoff and then publishes local `platform.resync` | Redis/NATS impl |
| Ephemeral store | `ephemeral/ephemeral_store.dart` | UNLOGGED table, own 4-connection pool; `putAll` parks a whole fan-out with one statement; `scan(prefix)` runs on `ephemeral_key_pattern` (`text_pattern_ops`), which is the only index a `LIKE 'prefix%'` can use | Redis impl |
| Rate limits | `ratelimit/rate_limiter.dart` | UNLOGGED token buckets, one statement; a hit may cost several tokens (`cost:`, charged as the capacity when larger; a charge above what is left takes nothing); swept only once full again (`full_at`, one window after the last hit) | Redis impl |
| Storage budget | `storage/storage_budget.dart` | `HELIX_STORAGE_BUDGET_BYTES` (optional): the size of this server's tables with indexes and TOAST (`pg_total_relation_size` over the catalogue, its own schema prefix only; not `pg_database_size`, which lists every file and took seconds on the shared test database) plus what modules `report` (media objects), measured at most once a minute per node; `check()` throws `quota_exceeded` (`reason: server_storage`) when over it and lets requests through when it cannot measure; gauge `helix_storage_used_bytes`; `close` waits for a measurement in flight | same (S3 bytes reported by media) |
| Outbox + jobs | `jobs/jobs.dart` | `platform.jobs`, `SKIP LOCKED` leases, backoff, dead letters; a handler is given up on after 60 s (`JobRunnerSettings.jobTimeout`, shorter than the 2-minute lease); `enqueueMany` inserts a fan-out with one statement and one wake; `dedupe_key` is unique among `pending` rows only, so a dead job does not spend its key (`jobs_dedupe_live`) | same |
| Periodic jobs | `jobs/jobs.dart` | row-lease, once per interval cluster-wide; a job may declare its worst case (`PeriodicJob.timeout`, else the scheduler's 5 minutes) and is leased for that plus 30 s, so a run that uses its whole timeout is never claimed twice | same |
| Object storage | `blobs/object_storage.dart` | local directory; `list(prefix)` walks it (the media orphan sweep); `append` is serialized per key and returns the file's own length | S3-compatible (SigV4; `list` is ListObjectsV2); every request is bounded (10 s for the headers, then 10 s between two body chunks), a range read asks for a range, and `ping` shares one probe between callers for 5 s |
| Push | `push/push.dart` | FCM HTTP v1, data-only wake-ups | + APNs |
| HTTP | `http/routes.dart`, `pipeline.dart`, `request.dart`, `idempotency.dart`, `websocket_limits.dart` | shelf; auth and route limit before the body, per-node body budget whose read is bounded (10 s between two chunks, 30 s in total, then `request_timeout` 408 and the reservation returned), idempotency claimed before the handler runs (a duplicate is `unavailable`, a lost claim is retaken after 15 min) and answered once with the sealed status, headers and body, WebSocket message cap | same |
| Observability | `observability/log.dart`, `metrics.dart` | JSON logs with redaction (ring buffer + live `lines` stream for the admin console), Prometheus text; `HELIX_LOG_FILE` buffers lines and flushes off the request path, rotates itself daily (UTC) and keeps `HELIX_LOG_KEEP_DAYS`, with `HELIX_LOG_MAX_BYTES_PER_DAY` bounding one flooded day | scrape per node |
| Start-up | `startup.dart` | `retryStartup` (an unreachable database is retried for a minute) and `watchStopFile` (`HELIX_STOP_FILE`, how the Windows task stops the server) | same |
| Modules | `module.dart` | `HelixModule`, `ModuleBase`, `HealthRegistry`; capability interfaces `ProvidesAuthentication`, `ProvidesMaintenance`, `ProvidesAccountExport` | — |

## Rules (enforced by `test/architecture_test.dart` where possible)

- Only `platform/db/` imports the Postgres driver, only `platform/blobs/`
  imports the AWS signer, and only `platform/push/` imports Google auth.
- Transactions start only with `Db.tx`; repositories take a `Tx`/`Session`.
  Side effects after commit use `Tx.afterCommit` (never inside the
  transaction) or the outbox (when they must not be lost). Every after-commit
  action runs; a failing one is logged (`after_commit_failed`) and never
  turns the committed write into an error.
- Anything that waits on the network has a timeout: job handlers, periodic
  jobs, the FCM token refresh (10 s) and every object-storage request
  included. One stalled call must not stop the loop it runs in, and one
  stalled peer must not hold a socket after its caller gave up.
- A config value that cannot work is refused at start-up with its variable
  named — never accepted and discovered per request (an S3 endpoint that is
  not a full `http(s)://host` URL is the case that proved it).
- SQL interpolates only `SchemaNames` (validated identifiers). Values are
  always named parameters with explicit types (`@id:uuid`).
- An `Idempotency-Key` is claimed before its handler runs and answered once:
  a concurrent duplicate gets `unavailable` with a `Retry-After` rather than a
  second side effect, a handler that failed or answered 5xx gives the claim
  back, and only the holder of a claim may write its answer.
- Public routes need a rate limit (`RouteRegistry.add` refuses otherwise),
  and every route must be in the protocol catalog.
- Logs carry ids and counts; secrets are masked by name and by shape
  (`redactFields`, `redactString`). Error logs record exception *types*, not
  messages.
- Never take a second connection from the main pool while holding a
  transaction (`context.db` inside a `tx` body): at pool-size concurrency
  every request waits on the others and the node stalls until the acquire
  timeout. A nested `Db.tx` is safe: it joins the running transaction (a
  zone value) and commits, retries and runs `afterCommit` with it. The
  ephemeral store has its own pool so presence can be read inside send
  transactions; `Presence.online` asks whether a device is reachable in two
  `getAll`s whatever the device count: their routes, then the nodes behind
  them.
- `@name:int4` / `@name:int2` parameters are range-checked before they reach
  the driver (it would wrap them silently) and raise `DbInvalidValue`, which
  the pipeline answers as `invalid_field`.
- Background loops (job runner, periodic scheduler) log a failed pass
  (`jobs_tick_failed`, `periodic_tick_failed`) and retry; an unhandled
  error there would end the process.
- Bus messages are hints, at most 7.9 KB; anything that must arrive goes
  through the outbox.
