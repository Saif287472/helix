# Server platform (`lib/src/platform/`)

Infrastructure every module uses through `ModuleContext` (ADR-025/026). No
business logic lives here. Everything is safe to run on several nodes against
one Postgres database.

| Piece | File | Single host now | Scale-out later |
|---|---|---|---|
| Config | `config/server_config.dart`, `env_file.dart` | `HELIX_*` env + `server/.env` | same |
| SQL | `db/db.dart` (`Db`, `Tx`, `Row`), `db/postgres_db.dart` | Postgres pool | same (+ replicas) |
| Migrations | `db/migrations.dart`, `platform_migrations.dart` | per-module Dart constants, checksummed, advisory lock | same |
| Schema names | `db/schema_names.dart` | module name = schema | test prefixes |
| Event bus | `bus/event_bus.dart` | `LISTEN/NOTIFY`; the `LISTEN` connection reopens with backoff and then publishes local `platform.resync` | Redis/NATS impl |
| Ephemeral store | `ephemeral/ephemeral_store.dart` | UNLOGGED table, own 4-connection pool | Redis impl |
| Rate limits | `ratelimit/rate_limiter.dart` | UNLOGGED token buckets, one statement | Redis impl |
| Outbox + jobs | `jobs/jobs.dart` | `platform.jobs`, `SKIP LOCKED` leases, backoff, dead letters | same |
| Periodic jobs | `jobs/jobs.dart` | row-lease, once per interval cluster-wide | same |
| Object storage | `blobs/object_storage.dart` | local directory | S3-compatible (SigV4) |
| Push | `push/push.dart` | FCM HTTP v1, data-only wake-ups | + APNs |
| HTTP | `http/routes.dart`, `pipeline.dart`, `request.dart`, `idempotency.dart`, `websocket_limits.dart` | shelf; auth and route limit before the body, per-node body budget, sealed idempotency rows, WebSocket message cap | same |
| Observability | `observability/log.dart`, `metrics.dart` | JSON logs with redaction (ring buffer + live `lines` stream for the admin console), Prometheus text | scrape per node |
| Modules | `module.dart` | `HelixModule`, `ModuleBase`, `HealthRegistry`; capability interfaces `ProvidesAuthentication`, `ProvidesMaintenance`, `ProvidesAccountExport` | — |

## Rules (enforced by `test/architecture_test.dart` where possible)

- Only `platform/db/` imports the Postgres driver, only `platform/blobs/`
  imports the AWS signer, and only `platform/push/` imports Google auth.
- Transactions start only with `Db.tx`; repositories take a `Tx`/`Session`.
  Side effects after commit use `Tx.afterCommit` (never inside the
  transaction) or the outbox (when they must not be lost).
- SQL interpolates only `SchemaNames` (validated identifiers). Values are
  always named parameters with explicit types (`@id:uuid`).
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
  transactions; `Presence.online` reads many devices in one `getAll`.
- `@name:int4` / `@name:int2` parameters are range-checked before they reach
  the driver (it would wrap them silently) and raise `DbInvalidValue`, which
  the pipeline answers as `invalid_field`.
- Background loops (job runner, periodic scheduler) log a failed pass
  (`jobs_tick_failed`, `periodic_tick_failed`) and retry; an unhandled
  error there would end the process.
- Bus messages are hints, at most 7.9 KB; anything that must arrive goes
  through the outbox.
