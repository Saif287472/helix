# Helix Remote v2 Server - Operability

Status: written in Phase S7 (2026-10-01) from the code on branch
`architecture-v2`. The v2 server is not deployed yet; v1 is still live until
cutover. This document replaces `REMOTE_OPERABILITY_AND_DR.md` for v2 (that
file stays as the v1 reference until Phase X).

Companion: [`V2_SERVER_HANDOFF.md`](V2_SERVER_HANDOFF.md) (what the server is,
the environment variables, start and stop, Caddy, cutover). Module details are
in each module's `MODULE.md`; the platform is in
`server/lib/src/platform/PLATFORM.md`.

Every claim below names the file it was checked against. Paths are relative to
`helix_remote/server/lib/src/` unless they start with `helix_remote/`. Where
something is reasoning rather than something the code or a test shows, it says
so.

SQL in this document is run by the operator, with `psql`, as the `helix` role.
It is not exercised by the test suite. Never paste query output that contains
identifiers into a ticket or chat without checking it first.

## Health and readiness

| Endpoint | Access | Answers |
|---|---|---|
| `GET /v1/health/live` | public, `ops.probe` limit | `{"status":"ok","time":...}` while the process serves requests. |
| `GET /v1/health/ready` | public, `ops.probe` limit | `{"ready":true,"checks":{"database":true,"storage":true}}` with 200, or 503 if any check is false. |

(`modules/ops/module.dart`, `platform/module.dart`.)

- Readiness runs every registered check with a 3-second timeout each. Today
  the checks are `database` (`SELECT 1`) and `storage` (the blob directory
  exists, or `HEAD` on the S3 bucket returns 200). It reports names and
  booleans only.
- Readiness does **not** check push, SMS, TURN, the event bus or the job
  runner. Watch those through logs and metrics (below).
- The `ops.probe` limit is 120 requests at once, refilled at 2 per second,
  per client address. A monitor probing every 10 seconds is far below it.
- Probe from the PC, and from outside, to cover Caddy and DNS:

  ```powershell
  curl.exe http://127.0.0.1:8080/v1/health/ready
  curl.exe https://helix.agiletechbd.com/v1/health/ready
  curl.exe https://helix.agiletechbd.com/v1/server
  ```

- `GET /v1/server` is public and shows name, version (`2.0.0-dev` in
  `version.dart`), registration mode, attachment limit, terms version,
  `federation_domain` (only while federation is on) and the feature flags.

## Metrics

`GET /v1/ops/metrics` returns Prometheus text. (`modules/ops/module.dart`,
`platform/observability/metrics.dart`.)

- **Scraping.** Set `HELIX_METRICS_TOKEN` (32+ characters, secret) and give
  Prometheus `Authorization: Bearer <that token>`
  (`authorization: {credentials: ...}` in the scrape config). The token
  opens this route only and is compared in constant time. Without it, the
  route needs an admin token (`POST /v1/admin/sessions`, 12 hours). (The
  plan said `/metrics`; the code serves `/v1/ops/metrics`.)
- **Each node reports only itself.** Counters live in memory and reset when
  the process restarts. With two nodes, scrape both (through their own
  ports, not through Caddy) and sum them.
- **Only these families exist** (labels are low-cardinality on purpose):

  | Family | Type | Labels | Meaning |
  |---|---|---|---|
  | `helix_http_request_seconds` | histogram | `route` (template, or `unmatched`), `status` (`2xx`, `4xx`, ...) | Request latency. Buckets 5 ms to 10 s. |
  | `helix_jobs_total` | counter | `kind`, `result` (`ok`, `retry`, `dead`) | Outbox jobs finished. |
  | `helix_ws_open` | gauge | none | WebSockets open on this node. |
  | `helix_ws_connections_total` | counter | none | WebSockets opened since start. |
  | `helix_client_crash_reports_total` | counter | none | Opt-in crash reports received. |
  | `helix_jobs_dead` | gauge | none | Dead outbox jobs, cluster-wide (read from the database at scrape time). |
  | `helix_mailbox_backlog` | gauge | none | Undelivered envelopes, cluster-wide (counted up to 1,000,000 at scrape time). |
  | `helix_http_body_bytes_in_flight` | gauge | none | Request body bytes this node is buffering (limit `HELIX_MAX_INFLIGHT_BODY_BYTES`). |

  The two cluster-wide gauges are queried on each scrape (3 s timeout; a
  failed read keeps the last value, `NaN` before the first). Every node
  reports the same value for them, so do not sum them across nodes.
- **Not exported (gaps):** database pool use, rate-limit rejections as a
  counter (they show up as `429` in the histogram's `status` label), push and
  SMS results.
- Useful starting signals, taken from the v1 operability targets and mapped
  to what exists: readiness failing for 2 minutes; `5xx` share of
  `helix_http_request_seconds_count` above 2% for 5 minutes; `429` share above
  20%; any `helix_jobs_total{result="dead"}` increase or `helix_jobs_dead`
  above 0; `helix_mailbox_backlog` growing for an hour; `helix_ws_open` at 0
  during the day.

## Logs

- **Format.** One JSON object per line on **stdout**: `ts`, `level`, `event`,
  then fields. The level is `info` and above (no setting changes this).
  With `HELIX_LOG_FILE` set, the same lines are also appended to that file
  (opened at start; an unwritable path exits with 78). Rotate it with a
  copy-and-truncate tool. (`platform/observability/log.dart`,
  `bin/server.dart`.)
- **Access log.** Every request logs event `http` with `request_id`, `method`,
  `route` (the template, not the URL), `status` and `ms`. It carries no client
  address, no query string and no body.
- **Request ids.** Every response has `x-request-id`. A client may send its own
  (8 to 64 characters of `A-Za-z0-9_-`); otherwise the server makes a UUIDv7.
  Use it to follow one request through the logs.
- **Redaction.** `redactFields` masks by field name (anything containing
  `passw`, `secret`, `token`, `authorization`, `cookie`, `signature`,
  `private`, `auth_key`, `api_key`, `otp`, `phone`, `ciphertext`, `payload`,
  `credential`, `invite`, `recovery`, `verification`, `database_url`, `dsn`;
  names ending in `_id` are kept) and by shape (JWT-like and long opaque
  strings, `Bearer ...`, URL credentials, phone numbers shortened to the last
  two digits). Error logs record the exception type and the first server
  frame, never the message. A test enforces this
  (`test/platform/infra_test.dart`).
- **Events worth searching for:**

  | Event | Meaning |
  |---|---|
  | `server_started`, `server_stopped` | Start and stop, with node id and (on start) the module list. |
  | `unhandled_error` | A 500. Has `request_id`, `error` type and `at`. |
  | `constraint_violation` | A database constraint turned into a 409. |
  | `job_retry`, `job_dead` | A job failed (with `kind`, `job_id`, `attempts`, `error` type). |
  | `periodic_failed` | A housekeeping job failed (`job`, `error`). |
  | `realtime_task_failed` | A WebSocket task failed. |
  | `sms_failed` | SMS gateway refused or was unreachable (`reason`). |
  | `admin_setup`, `admin_seeded`, `admin_seed_ignored`, `admin_sign_in_failed` | Operator account events. |
  | `peer_key_changed` | A federation peer's key changed. |
  | `client_crash` | An opt-in client crash report (redacted). |

- **Live logs for admins.** `GET /v1/admin/logs?limit=200` returns the most
  recent lines (up to 500; each node keeps a ring of the last 500).
  `GET /v1/admin/logs/stream` is a WebSocket that sends every new line as a
  text frame (ping every 30 s). Both need an admin token, both show
  **only the node that answered**, and both carry already-redacted lines.
  With two nodes, use stdout files per node instead.
  (`modules/admin/module.dart`.)
- **Audit log.** Every operator action writes a row in `admin.audit`
  (`GET /v1/admin/audit`, newest first). It is not purged (see "Data growth").

## Maintenance mode

- Turn it on or off with `PATCH /v1/admin/config` and
  `{"maintenance": true}` (Helix Admin app, config screen). It is stored in
  `ops.settings` and audited as `config.update`.
- While on, every request except `/v1/health/*`, `/v1/admin/*` and `/v1/ops/*`
  is answered `503` with error code `maintenance` and `Retry-After: 300`.
  That includes the `/v1/ws` upgrade, `/open` and `/.well-known/*`.
  (`platform/http/pipeline.dart`.)
- WebSockets that are already open are **not** closed by maintenance mode
  (the pipeline only sees HTTP requests; nothing else touches the sockets).
  Background jobs keep running.
- It reaches every node within seconds: the change is published on the bus
  topic `ops.settings`, and each node also re-reads the setting at least every
  30 seconds (`modules/ops/module.dart`).
- For a restart or upgrade you do not need it (you stop the process); it is for
  a restore, a drill, or work done while the server stays up.

## Feature flags

- Flags are an allow list in `modules/ops/api.dart`: `crash_reporting_upload`,
  `minimal_analytics`, `group_calls`. All default to off. Unknown names are
  rejected, so a typo cannot become a feature.
- `GET /v1/admin/feature-flags` lists them. `PUT
  /v1/admin/feature-flags/{name}` with `{"enabled": true}` sets one (audited as
  `flag.set`). Apps see them as `features` in `GET /v1/server`.
- `crash_reporting_upload` gates `POST /v1/telemetry/crash`: while off it
  answers 403. A report becomes one redacted `client_crash` log line and a
  counter. Nothing is stored.
- Flags are stored in `ops.settings` as `flag.<name>`; the cache and bus work
  as for maintenance mode.

## Jobs, the outbox and dead letters

Work that must happen after a commit and must not be lost (push, federation
relays, purges) is written to `platform.jobs` inside the same transaction, and
any node runs it. (`platform/jobs/jobs.dart`, `platform/platform_migrations.dart`.)

- **Claiming.** Each node polls every 2 s and also wakes on the bus topic
  `jobs.wake`. A claim uses `FOR UPDATE SKIP LOCKED` and a 2-minute lease
  (`locked_until`), so a job runs on one node at a time. A job whose node died
  is picked up when the lease ends. Up to 20 jobs per pass.
- **Attempts.** `attempts` goes up when a job is claimed. A job that throws is
  rescheduled with exponential backoff (5 s, doubling, capped at 1 hour) and
  `last_error` holds only the exception type. When `attempts` reaches
  `max_attempts` the row is kept with `status = 'dead'`.
- **A handler that runs longer than the lease** can be claimed again by
  another node. Handlers are written to be idempotent (reasoning, not
  tested for every handler).
- **Jobs left pending forever.** A job whose `kind` has no handler on any
  running node is never claimed. After removing a module, check for these.
- **Job kinds and attempts:**

  | Kind | Purpose | Max attempts |
  |---|---|---|
  | `messaging.push` | Data-only push wake-up (one pending per device) | 5 |
  | `calls.push` | Call push and `call_ended` push | 3 |
  | `federation.relay` | Message relay to a peer that was down | 12 |
  | `groups.sync`, `groups.fanout`, `groups.devices`, `groups.leave` | Group federation work | 12 |
  | `media.purge_account` | Delete a deleted account's media | 8 (default) |

- **Periodic jobs** (each runs once per interval on one node, decided by a
  conditional update of `platform.periodic_jobs`): `platform.sweep_ephemeral`
  (1 min), `platform.sweep_rate_buckets` (10 min), `platform.sweep_idempotency`
  (1 h), `messaging.expire` (10 min), `calls.expire` (5 min),
  `identity.purge_expired` (6 h), `media.expire` (30 min).

### Inspect

```sql
-- Backlog by kind and status (no payloads).
SELECT kind, status, count(*), min(run_at) AS oldest
FROM platform.jobs GROUP BY kind, status ORDER BY kind, status;

-- Dead letters. Do not select payload: it can hold ids and addresses.
SELECT id, kind, attempts, max_attempts, last_error, created_at
FROM platform.jobs WHERE status = 'dead' ORDER BY created_at DESC LIMIT 50;

-- When did each periodic job last run?
SELECT name, last_run_at FROM platform.periodic_jobs ORDER BY name;
```

Also: `helix_jobs_total{result="dead"}` and the log events `job_retry` and
`job_dead`.

### Retry one dead job

After fixing the cause (for example a wrong FCM key):

```sql
UPDATE platform.jobs
SET status = 'pending', attempts = 0, run_at = now(),
    locked_until = NULL, locked_by = NULL
WHERE id = '<job id>' AND status = 'dead';
```

(There is no admin route for this. The columns come from the migration above.)

### Purge

`POST /v1/admin/purge` (admin token) deletes **all** dead jobs and expired
identity rows, and returns counts by kind (`dead_jobs` and the identity
counts). It is audited as `purge`. There is no way to purge only some kinds
through the API; use SQL (`DELETE FROM platform.jobs WHERE status = 'dead' AND
kind = '...'`) for that.

## Rate limits

- **Where.** Limits are token buckets in the UNLOGGED table
  `platform.rate_buckets`, taken in one statement, so every node shares them
  (`platform/ratelimit/rate_limiter.dart`).
- **Layers.**
  1. A global limit on every request, per client address: 600 at once,
     refilled at 10 per second (`platform/http/pipeline.dart`).
  2. A per-route limit declared by the module. Public routes are limited per
     client address, signed-in routes per device, S2S routes per server.
     The route registry refuses a public route without one
     (`platform/http/routes.dart`).
  3. Some limits inside handlers, keyed by account or number (for example 5 SMS
     codes per number per hour).
- **Answer.** `429` with error code `rate_limited` and a `Retry-After` header.
- **Order.** A signed-in route checks the token and the route's limit before
  it reads the request body, so refused requests cost no buffering. Bodies
  that would take the node over `HELIX_MAX_INFLIGHT_BODY_BYTES` get `503
  unavailable` with `Retry-After: 2` (watch `helix_http_body_bytes_in_flight`).
- **Main per-route limits** (all in code, none configurable by environment; to
  change one, edit it and deploy):

  | Policy | Limit |
  |---|---|
  | `ops.probe` | 120 at once, 2 per second |
  | `admin.sign_in` / `admin.setup` / `admin.status` | 10 per minute / 5 per hour / 60 per minute |
  | `identity.otp` (per address) / `identity.otp_phone` (per number) | 10 per hour / 5 per hour, plus a resend gap (`HELIX_OTP_RESEND_SECONDS`) |
  | `identity.verify`, `.invite`, `.password` | 30 per hour each |
  | `identity.register`, `.recovery` | 10 per hour each |
  | `identity.refresh`, `.link_poll` | 600 per hour each |
  | `keys.bundle` / `keys.bundle_target` | 120 / 600 per hour |
  | `messaging.send` (per device) / `messaging.send_account` (per account) | 200 at once, 5 per second / 400 at once, 10 per second |
  | `calls.turn` / `calls.offers` | 10 per hour per device / 30 per 10 minutes per account |
  | `groups.create` / `groups.preview` | 20 per day / 60 per hour |
  | `people.by_name` / `people.reports` | 30 per minute / 20 per hour |
  | `compliance.export` / `compliance.delete` | 5 per day / 5 per hour |
  | `federation.*` | identity 120, keys 600, signals 1200, messages 3000 per minute (keys per target: 30) |

  The full list is every `RateLimitPolicy` in `lib/src` (grep for it). The
  WebSocket upgrade has no policy of its own; only the global limit applies
  (the `4029` close code in the protocol is not used by the server).
- **Keys.** A bucket key is `<policy>:<principal>` where the principal is
  `ip:<address>`, `device:<id>`, `admin:<id>` or `server:<domain>`. The global
  limit's key is `ip:<address>`.
- **Clear a stuck limit** (for example your own address after testing):

  ```sql
  DELETE FROM platform.rate_buckets
  WHERE key = 'ip:<address>' OR key LIKE '%:ip:<address>';
  ```

- Buckets older than an hour are swept every 10 minutes. A Postgres crash
  empties the table (it is UNLOGGED), which only resets limits.

## Backups

What to back up, and how often (suggest: Postgres daily, blobs after each
Postgres dump, secrets once and after every change):

| What | Why | Notes |
|---|---|---|
| PostgreSQL database `helix` | All durable state | `pg_dump`, below |
| Blob store (`HELIX_BLOB_DIR`, or the S3 bucket) | Encrypted attachments, avatars, backups | Copy after the dump; see "Consistency" |
| `server\.env` | Settings and secrets | Store apart from the dumps (see below) |
| Firebase service-account key file, Caddyfile, coturn settings | Rebuild the host | |

**Keep the secrets and the database dump in different places.**
`HELIX_PHONE_PEPPER` exists so a stolen database does not allow testing phone
numbers against stored hashes (`modules/identity/MODULE.md`). A dump stored
next to the pepper loses that protection. A dump also contains the server's
federation signing key (`federation.settings`), password verifier salts and
hashes, undelivered ciphertext, and the discovery salt. Treat dumps as secrets
and encrypt them at rest.

### Postgres dump

```powershell
$pg = 'C:\Program Files\PostgreSQL\17\bin'
& "$pg\pg_dump.exe" --format=custom --no-owner --no-unlogged-table-data `
  -h 127.0.0.1 -U helix -d helix `
  -f "D:\helix-backups\helix-$(Get-Date -Format yyyyMMdd-HHmm).dump"
```

- Give the password through `%APPDATA%\postgresql\pgpass.conf`
  (`127.0.0.1:5432:helix:helix:<password>`), not on the command line.
- `pg_dump` takes a consistent snapshot while the server runs; you do not
  need to stop anything.
- `--no-unlogged-table-data` leaves out the short-lived tables
  (`platform.ephemeral`, `platform.rate_buckets`). They hold sign-in
  challenges, WebSocket routes, presence and rate-limit state, which must not
  come back from the past.
- Schedule it with Windows Task Scheduler. Keep several generations, and keep
  one off the PC.

### Blobs

- Local: copy the directory after the dump finishes, for example
  `robocopy "<blob dir>" "D:\helix-backups\blobs" /E`. (Do not use `/MIR`
  anywhere in this repository's workflows.) Deleted objects stay in the backup
  copy; that costs space only.
- S3: use the store's own versioning or replication.
- **Consistency** (reasoning, not tested): a database row can exist a moment
  before its bytes (an upload in progress), but never the other way round.
  Copying the blobs *after* the dump means every finished row in the dump has
  its object, and any extra objects are harmless orphans.

### Restore

Practice this (see the drill below) before you need it.

1. Stop every node (Ctrl+C).
2. Create an empty database as the Postgres superuser (the `helix` role has
   no CREATEDB):

   ```powershell
   & "$pg\createdb.exe" -h 127.0.0.1 -U postgres -O helix helix_restore
   ```

3. Restore into it as `helix`:

   ```powershell
   & "$pg\pg_restore.exe" --no-owner -h 127.0.0.1 -U helix -d helix_restore "D:\helix-backups\<file>.dump"
   ```

4. Restore the blob directory to the same path the server uses, or point
   `HELIX_BLOB_DIR` at the restored copy.
5. Point `HELIX_DATABASE_URL` at `helix_restore` (or drop `helix` and rename
   `helix_restore` to `helix`).
6. `dart run bin/migrate.dart`. A dump from an older release gets the newer
   migrations; the checksum check proves the schema matches this code.
7. Start the node and check `/v1/health/ready`.

**Going back in time has consequences** (reasoning from the design, not tested):

- Devices revoked after the backup become active again, and accounts deleted
  after it come back. Revoke and delete them again.
- One-time prekeys already handed out can be handed out again.
- Mailbox sequence numbers go back (`messaging.device_seq.last_seq`). A phone
  keeps its own cursor and asks for `seq > cursor` (`messaging/data/mailbox_store.dart`).
  I found no handling in the code or in `REALTIME_V2.md` for a phone whose
  cursor is ahead of the server, so new messages could be skipped by phones
  that had acknowledged beyond the restored numbers. Gaps in sequence numbers
  are allowed (`messaging/MODULE.md`), so raising every counter by a large
  amount (`UPDATE messaging.device_seq SET last_seq = last_seq + 1000000`) is
  an idea to try in a drill. It is **not** a verified procedure. Decide this
  before relying on restores.
- Messages sent after the backup and not yet delivered are lost.

### Restore drill (monthly)

A restored copy must not touch the real world. Do this on a throwaway
database and **not** with the production `.env` as it is:

1. Restore the newest dump into `helix_drill` (steps 2 and 3 above).
2. In `helix_drill`, run `TRUNCATE platform.jobs;` (so no queued push or
   federation relay is sent) and `UPDATE ops.settings SET value = 'false'
   WHERE key IN ('federation_enabled', 'maintenance');`. If a key has no row,
   the environment decides, so also set `HELIX_FEDERATION_ENABLED=false` in the
   drill `.env`.
3. Use a copy of `.env` with a different `HELIX_DATABASE_URL`, `HELIX_PORT`,
   and `HELIX_BLOB_DIR` (an empty or copied directory: `media.expire` deletes
   objects), plus `HELIX_PUSH_PROVIDER=none`, `HELIX_GLOBAL_MODE=false`,
   `HELIX_SMS_PROVIDER=none`.
4. `dart run bin/migrate.dart` should print `Up to date.` (or the newer
   migrations); then start a node and check `/v1/health/ready`.
5. Drop `helix_drill` and delete the copied directory. Note the date and the
   result.

### Point-in-time recovery

Not set up. Postgres can archive its write-ahead log for it, but nothing in
this repository configures that. With a daily dump, the most you can lose is a
day of messages that were not yet delivered.

## Disaster recovery

| Situation | Recovery |
|---|---|
| Server process crashed or the PC rebooted | Start Postgres, coturn, Caddy, the server (`V2_SERVER_HANDOFF.md`, "Start and stop"). State is in Postgres; jobs resume when their leases end. WebSocket routes in the ephemeral store expire within 75 s. |
| Postgres service down | `ready` goes 503 (`database: false`). Start `postgresql-x64-17`. **Then restart every server node** (see "Troubleshooting": the bus connection is not re-opened). |
| Postgres crashed | On restart Postgres empties the UNLOGGED tables itself. That resets rate limits, WebSocket routes, presence, challenges and the federation replay memory. Devices reconnect and refresh their routes. For the 10 minutes after, a captured federation request could be replayed (reasoning from the replay window in `federation/MODULE.md`). |
| Database lost or corrupt | Restore the newest dump (above), then start. |
| Whole PC lost | New PC: install PostgreSQL 17, run `setup_local_postgres.ps1`, restore the dump and blobs, restore `.env` and the Firebase key file, install Caddy and coturn (`deploy/coturn/README.md`), fix the router forwards and firewall rules, then start. DNS points at the router's public address and does not change. |
| `.env` lost, or a secret lost | `HELIX_JWT_KEYS`: make new keys. Phones fail their next access-token check, then refresh (refresh tokens are in the database, not JWTs) and carry on. `HELIX_PHONE_PEPPER`: **not recoverable**; stored phone hashes can no longer be matched. `HELIX_TURN_SECRET`: choose a new one in `.env` and coturn. FCM key: download a new one. Admin password: see "Troubleshooting". |
| Blob store lost | Attachments (kept 30 days), avatars (persistent) and encrypted backups (90 days) are gone. Rows still exist and downloads answer 404. Restore the blobs, or let users re-upload. |
| Federation key lost (database restored empty) | A new key is created at start. Peers that fail a signature re-fetch `/.well-known/helix-server` (at most every 10 minutes per domain), so they recover by themselves. |

## More than one node

Any number of nodes can run against one database. The PC can run two (use the
second to restart without downtime). (`platform/PLATFORM.md`, `server.dart`,
`test/server_test.dart` and `test/platform/shared_state_test.dart` cover
two nodes on one database.)

**Shared through Postgres:**

| State | Where | Effect of sharing |
|---|---|---|
| Event bus | `LISTEN/NOTIFY` on channel `helix_bus` (messages up to 7.9 KB, hints only) | Wake-ups, device revocation, "connected elsewhere", settings changes reach every node. A missed hint only delays work until the next poll or reconnect. |
| Ephemeral store | UNLOGGED `platform.ephemeral` | Sign-in challenges, link polls, WebSocket routes (`rt:route:<device>` = `<node>\|<connection>`, 75 s), presence, federation replay memory. |
| Rate limits | UNLOGGED `platform.rate_buckets` | One bucket per key across nodes. |
| Idempotency | `platform.idempotency` (24 h) | A retry answered by another node replays the stored result. |
| Jobs and periodic jobs | `platform.jobs`, `platform.periodic_jobs` | One node runs each job; each periodic job runs once per interval cluster-wide. |
| Operator settings | `ops.settings` (30 s cache plus bus) | Maintenance, flags, federation switch, server name. |
| Migrations | `platform.schema_migrations` plus an advisory lock | One node migrates. |

**Per node (not shared):**

- The WebSocket connection table. A device's route says which node holds its
  socket; other nodes reach it through the bus.
- Metrics counters, the log ring buffer, the live log stream.
- The environment. **Every node must have the same values** for
  `HELIX_JWT_KEYS`, `HELIX_JWT_ACTIVE_KID`, `HELIX_PHONE_PEPPER`,
  `HELIX_PUBLIC_BASE_URL`, `HELIX_TURN_*`, `HELIX_FCM_*`, `HELIX_SMS_*` and the
  storage settings. Nothing checks this for you.
- Postgres connections: each node uses up to `HELIX_DB_POOL_SIZE` (default
  10) pool connections, a 4-connection pool for the ephemeral store and one
  `LISTEN` connection (`platform/db/postgres_db.dart`). The default
  `max_connections` of 100 allows about six nodes at the default pool size
  before anything else connects. The `LISTEN` connection must go straight to Postgres (a
  transaction-mode connection pooler breaks `LISTEN`).

**Running two nodes on the PC:**

- Same `.env`, but a different `HELIX_PORT` for each (a real environment
  variable overrides `.env`: `$env:HELIX_PORT = "8081"`).
- Local blobs only work if both nodes use the same directory: set
  `HELIX_BLOB_DIR` to one absolute path. With S3 there is nothing to share.
- `HELIX_NODE_ID` is optional (a random id per process) and appears in logs.
  If you set it, keep it unique.
- List both ports in Caddy (`V2_SERVER_HANDOFF.md`, "Caddy").
- After a node dies, its WebSocket routes live up to 75 s. During that time
  the server thinks those devices are online and may skip their push wake-up;
  the devices reconnect (to the other node) and replay their mailbox. The
  push decision reads the route at send time (`modules/messaging/module.dart`).
- A rolling restart (one node at a time, Caddy health checks on) keeps the
  service up. Phones on the stopped node reconnect with backoff
  (`REALTIME_V2.md`).

**Scale-out seams** (`ARCHITECTURE_V2_PLAN.md` §4.6): the bus, ephemeral store
and rate limits are interfaces with Postgres implementations. Moving to Redis or
NATS later is an implementation swap, not a redesign. A home PC cannot serve
millions of users; this section is about two nodes on one host.

## Upgrades and migrations

- **Migrations are Dart constants** per module (`Migration(version, name,
  sql)`), compiled into the server. Each is recorded in
  `platform.schema_migrations` with a SHA-256 checksum of its SQL
  (`platform/db/migrations.dart`).
- **Checksums.** If an applied migration's SQL changed, the server refuses to
  start with `MigrationIntegrityError ... changed after it was applied`.
  Never edit a migration that has run; add a new one.
- **Advisory lock.** The runner takes `pg_advisory_xact_lock(7240001)` and
  applies **all** pending migrations of all modules in one transaction. A
  second node starting at the same moment waits, then finds nothing to do. If
  one migration fails, everything in that run rolls back.
- **Rules: expand, then migrate, then contract.** Never rename or drop in the
  same release that stops using a column. This lets one old node and one new
  node run side by side during a rolling restart. The runner ignores applied
  migrations it does not know, so an old node tolerates a newer schema as long
  as the change was an expansion.
- **There are no down migrations.** Rolling back the code only works if the
  newer schema is still compatible with the older code. Otherwise restore a
  dump.
- **Upgrade steps on the PC:**
  1. Back up (dump, and note the code version).
  2. Update the code (`git` on the working copy). If dependencies changed, run
     `flutter pub get` from `helix_remote/` (the pub workspace).
  3. For one node: stop it (Ctrl+C), `dart run bin/migrate.dart`, start it.
     Downtime is the restart time.
  4. For two nodes: stop node A, `dart run bin/migrate.dart`, start A, wait for
     `ready`, then do the same for node B (Caddy keeps sending requests to the
     other node meanwhile).
  5. Check `ready`, the log for `server_started`, and `job_dead` events.
- Backend changes are deployed by the user restarting the backend. Say so after
  every backend change.

## Data growth

- **Mailbox:** deleted on ack; undelivered rows expire after 30 days
  (`messaging.expire`). The per-device quota is 10,000 undelivered envelopes
  (`quota_exceeded`).
- **Media:** attachments 30 days, backup media 90 days (refreshed by each full
  backup), persistent until deleted; quotas 4 GiB, 1 GiB and 50 MiB per
  account (`media/MODULE.md`). Unfinished uploads are removed after a day.
- **`admin.audit`:** **never purged.** The plan (§4.3) says audit and metrics
  tables are range-partitioned by month with retention jobs. That is not
  built. Growth is small (one row per operator action), but there is no
  retention.
- **`calls.call_metrics`:** 90 days. **`messaging.sends`:** 7 days.
  **`platform.idempotency`:** 24 hours.
- **Dead jobs:** kept until purged.
- **Reports** survive account deletion by design (ids only).
- Check sizes with
  `SELECT schemaname, relname, pg_size_pretty(pg_total_relation_size(relid))
  FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 15;`

## Troubleshooting

**The server will not start.**

- `Invalid configuration:` followed by variable names: fix `.env` (the names
  tell you which). Values are never printed. For problems raised by a module
  you see an unhandled exception with the same text and a stack trace.
- `database is not reachable`: check the `postgresql-x64-17` service, the
  host and port in `HELIX_DATABASE_URL`, the password (percent-encoded) and
  `sslmode`. (The URL is never logged.)
- `MigrationIntegrityError`: the code and the database disagree about an
  applied migration. You are running different code than the database was
  migrated with. Check the code version; do not edit the table.
- Port already in use: another node, or the v1 backend, is on `HELIX_PORT`.
- Another node holds the migration lock: a second start waits for it; it ends
  when that node's migration transaction finishes.

**`/v1/health/ready` is 503.** Read the `checks` object. `database: false`:
Postgres is down or the pool is exhausted. `storage: false`: the blob
directory is missing, or the S3 bucket or credentials are wrong (the check is a
bucket `HEAD`, so the key also needs bucket access).

**Everyone gets `429`.** Probably every request looks like it comes from one
address, so the global per-IP limit is shared. Look at the buckets:

```sql
SELECT key FROM platform.rate_buckets WHERE key LIKE 'ip:%' LIMIT 20;
```

If you only see `ip:127.0.0.1`, the proxy address is not being read: check that
Caddy connects from an address listed in `HELIX_TRUSTED_PROXIES` and sends
`X-Forwarded-For` (`reverse_proxy` does by default; `V2_SERVER_HANDOFF.md`,
"Caddy"). The server takes the rightmost hop that is not a trusted proxy, so
a client cannot dodge limits by writing its own `X-Forwarded-For` or
`X-Real-IP` (the latter is ignored unless `HELIX_TRUST_X_REAL_IP=true`).

**Phones get `503 maintenance`.** Maintenance mode is on. Turn it off from the
admin app (`PATCH /v1/admin/config`, `{"maintenance": false}`).

**Sign-up codes do not arrive.** Look for `sms_failed` and its `reason`:
`invalid_credentials` (key), `invalid_sender`, `invalid_destination`,
`gateway_error`, `unreachable`, `rejected`. If every attempt fails with
`gateway_error` or `rejected` on the first real run, suspect the POST-versus-GET
open item (`V2_SERVER_HANDOFF.md`, "SMS"). Phones see 503 `sms_unavailable`.

**Push wake-ups do not arrive.**
- `HELIX_PUSH_PROVIDER` is `none` (wake-ups are dropped without a log).
- `job_retry` or `job_dead` for `messaging.push` / `calls.push`: wrong project
  id or key, or Google unreachable. Fix, then retry dead jobs (above).
- The device was online at send time (route present), so no push was needed.

**Calls cannot connect.** `GET /v1/calls/turn` answering 503 `unavailable`
means `HELIX_TURN_URLS`/`HELIX_TURN_SECRET` are not set. If credentials are
issued but media fails: coturn is not running, its secret differs, or the
router forwards and firewall rules are missing (`deploy/coturn/README.md`).

**Messages are slow to arrive after Postgres was restarted.** The event bus
holds one dedicated `LISTEN` connection (`platform/db/postgres_db.dart`). If
it drops, the node reopens it with backoff (250 ms doubling to 30 s), listens
on its channels again and publishes a local `platform.resync` so caches that
follow bus hints (ops settings) are dropped. Hints sent while it was down are
lost; jobs still run on their 2-second poll, and a device that missed a wake
gets its mail on the next send or reconnect. A test terminates the `LISTEN`
backend (`pg_terminate_backend`) and checks delivery resumes. No restart of
the nodes is needed.

**A WebSocket closes. What does the code mean?**

| Code | Meaning |
|---|---|
| 4003 | Device revoked or account deleted. The phone must sign out. |
| 4008 | Replaced by a newer connection of the same device (any node). |
| 4010 | No frame from the phone for two heartbeats (50 s). |
| 4400 | Wrong or missing subprotocol (`helix.v1+json`) or a malformed frame. |
| 1001 | The node is shutting down. Reconnect (another node, or after restart). |

A request without a valid token is refused with HTTP 401 before any upgrade.
(`modules/realtime/module.dart`. The `4001`, `4004` and `4029` codes in
`REALTIME_V2.md` are not emitted by the server.)

**An admin is locked out, or the password is lost.** There is no reset tool.
With every node stopped, as the operator:

```sql
-- Locked only: clear the lock.
UPDATE admin.admins SET failed_attempts = 0, locked_until = NULL;

-- Forgotten password: remove the operator, then start the server with
-- HELIX_ADMIN_PASSWORD set (it seeds the first admin), or run setup again.
DELETE FROM admin.admins;
```

Then remove `HELIX_ADMIN_PASSWORD` from `.env`. The audit log keeps the old
admin id. (SQL derived from `modules/admin/data/admin_store.dart`; not covered
by tests.)

**Federation fails.**
- `federation_unavailable` (502): the switch is off, the peer is down, the peer
  is not on `HELIX_FEDERATION_ALLOW`, or it resolves to a private or
  link-local address (`HELIX_FEDERATION_ALLOW_PRIVATE`).
- Signatures refused (401) on inbound requests: clock skew over 5 minutes, or
  a peer that cannot be reached for its identity document. Check the PC's
  clock.
- `peer_key_changed` in the log: a peer rotated its key. Expected after a peer
  restores a new database.
- A failed lookup with nothing cached is not retried for a minute.

**Slow requests.** Look at `helix_http_request_seconds` per `route`. Remember
that every request does at least one Postgres write for the global rate limit
and one for the route limit. A pool of 10 connections is the first ceiling;
add a node before tuning anything else.

**Jobs pile up.** `SELECT kind, status, count(*) FROM platform.jobs GROUP BY 1,
2;`. Many `pending` with old `run_at`: no node is running them (the job runner
stopped, or no handler for that kind). Many `dead`: see "Jobs".

**The disk fills.** Blobs: `HELIX_BLOB_DIR` size against the quotas above.
Database: the size query under "Data growth". Logs: whatever you redirect
stdout to.

## Load and capacity

Phase S7 includes a load harness for authenticated send and receive, with p50
and p95 at 1,000 simulated devices on the PC. Its results and instructions are
recorded with the phase report, not here. The v1 smoke harness described in
`LOAD_TESTING.md` targets the old backend only.

## Review items found while writing this document

- No handling found for a phone cursor ahead of the server after a restore
  (above).
- `admin.audit` has no retention; the plan's monthly partitions and retention
  jobs are not built.
- There is no operator reset for the admin password and no retry route for a
  single dead job.
- Error codes `4001`, `4004` and `4029` are documented for WebSockets but never
  sent; the upgrade has no rate limit of its own.
- The pool size (10) is a constant, not a setting.
