# helix_remote_server

The Helix Remote server: Helix Global and personal servers run this one
program. It is a stateless Dart (shelf) node over PostgreSQL 17, built from one
module per area (ADR-025, ADR-026; plan of record
[`../docs/architecture/ARCHITECTURE_V2_PLAN.md`](../docs/architecture/ARCHITECTURE_V2_PLAN.md)).
Any node can serve any request: all shared state is in Postgres. It replaced
the v1 SQLite `backend/` at the Phase X cutover.

- **Modules:** `identity`, `keys`, `messaging`, `realtime`, `people`, `media`,
  `backup`, `groups`, `calls`, `federation`, `ops`, `admin`, `compliance`
  (`lib/src/modules/all_modules.dart`). Group calls are not built.
- **Wire contract:** `/v1/...` and the `/v1/ws` WebSocket, defined by
  `../packages/helix_remote_protocol` and `../docs/protocol/v2/`.
- **Needs:** a Dart/Flutter SDK matching `../pubspec.yaml` (the pub workspace
  includes Flutter packages, so run `flutter pub get` in `helix_remote/`) and a
  PostgreSQL 17 database. It does not use SQLite.

## Operating the server

- [`../docs/operations/V2_SERVER_HANDOFF.md`](../docs/operations/V2_SERVER_HANDOFF.md):
  what the server is, start and stop, every environment variable, Caddy,
  coturn, TLS pinning, push, SMS, storage, federation, admin first run, and the
  cutover checklist.
- [`../docs/operations/V2_OPERABILITY.md`](../docs/operations/V2_OPERABILITY.md):
  health, metrics, logs, maintenance mode, feature flags, jobs and dead
  letters, rate limits, backups and restore, disaster recovery, more than one
  node, upgrades, and troubleshooting.

## Layout

```
bin/server.dart          one node: config -> platform -> modules -> HTTP
bin/migrate.dart         apply migrations and exit (a deploy step)
lib/src/platform/        infrastructure (PLATFORM.md): config, Db/Tx, migrations,
                         HTTP pipeline, bus, ephemeral store, rate limits, jobs,
                         object storage, push, logs, metrics
lib/src/kernel/          jwt, crypto helpers, presence: shared by every module
lib/src/modules/<name>/  module.dart, api.dart, http/, application/, domain/,
                         data/, MODULE.md   (ADR-026)
lib/src/modules/all_modules.dart   production module list
lib/src/server.dart      HelixServer: migrate, register, start, stop
tool/load.dart           load harness; tool/setup_local_postgres.ps1
test/                    platform/, per-module tests (modules/), e2e/ (two
                         nodes), client/ (drives the server with the real api,
                         engine and CLI packages), architecture_test.dart
```

## Quick start (a development node)

Create the role and databases once (the script asks for the PostgreSQL
superuser password and for a new `helix` password, and prints neither):

```powershell
cd helix_remote/server/tool
./setup_local_postgres.ps1 -SaveTestUrl
```

`-SaveTestUrl` stores `HELIX_TEST_DATABASE_URL` for your Windows user (open a new
terminal afterwards). Then copy `.env.example` to `.env`, fill it in (the file
is read from the current directory, so always start from `server/`), and:

```bash
dart run bin/migrate.dart   # optional: every node also migrates at start
dart run bin/server.dart
```

The process listens on `HELIX_HOST:HELIX_PORT` (default `127.0.0.1:8080`). It
stops on Ctrl+C, finishing in-flight requests for up to 10 seconds. A bad
setting prints the variable names and exits with 78. To try the apps against
it, enter the address in the app's hidden advanced mode (the Android emulator
reaches this PC at `http://10.0.2.2:8080`; plain `http://` is accepted only in
debug builds and only for such development hosts).

There is no Dockerfile: a personal server is `dart run bin/server.dart` next to
a PostgreSQL instance. `../docker-compose.yml` runs only coturn.

## Tests

```bash
cd helix_remote/server
HELIX_REQUIRE_TEST_DATABASE=1 dart test --concurrency=3
```

- **Without `HELIX_TEST_DATABASE_URL`:** database tests are **skipped**, and
  the report says so. CI sets `HELIX_REQUIRE_TEST_DATABASE=1` and runs a
  Postgres 17 service, so there a missing database fails the run.
- **Isolation:** each test uses a random schema prefix (`t1a2b3c4d_identity`,
  ...), and `dropSchemas` cleans it up. Suites can share one database and run
  in parallel.
- **Two nodes:** a second `HelixServer` on the same prefix acts as another
  node (see `test/server_test.dart`). `test/support/cluster.dart` starts
  such a pair, and `test/e2e/two_node_test.dart` drives clients across it:
  messages, calls, revocation, supersede, groups and jobs.
- **Through the client:** `test/client/` drives the server with
  `helix_remote_api` (`package:helix_remote_api/v2.dart`), the engine and the
  CLI: registration, prekeys, socket delivery and acks, revocation (4003),
  refresh and sign-out, media, backup, calls, groups, recovery and the admin
  console. It is the only place the server package may import the client
  (dev dependencies; `architecture_test.dart`).
- **Passwords:** the connection URL is never printed. Do not log it.

## Load harness

`dart run tool/load.dart --devices 1000 --rate 0.05 --duration 60` boots a
node in-process on the test database, registers the devices through the real
flow and measures send, delivery and ack latency. See
`../docs/operations/LOAD_TESTING.md`.
