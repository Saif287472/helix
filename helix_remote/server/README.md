# helix_remote_server (v2)

This is the Helix Remote v2 server, built to
`../docs/architecture/ARCHITECTURE_V2_PLAN.md` on branch `architecture-v2`.
It runs on PostgreSQL 17, with stateless nodes and one module per area
(ADR-025, ADR-026). Until cutover the live server is `../backend/` (v1); this
package is not deployed.

- **Status:** Phase S1 is done. The platform layer is in place (see
  `lib/src/platform/PLATFORM.md`). The only module so far is `ops` (health).
- **Next:** Phase S2, the `identity` and `keys` modules.

## Operating the server

- [`../docs/operations/V2_SERVER_HANDOFF.md`](../docs/operations/V2_SERVER_HANDOFF.md):
  what the server is, start and stop, every environment variable, Caddy,
  coturn, push, SMS, storage, federation, admin first run, and the draft
  cutover checklist.
- [`../docs/operations/V2_OPERABILITY.md`](../docs/operations/V2_OPERABILITY.md):
  health, metrics, logs, maintenance mode, feature flags, jobs and dead
  letters, rate limits, backups and restore, disaster recovery, more than one
  node, upgrades, and troubleshooting.

## Layout

```
bin/server.dart          one node: config -> platform -> modules -> HTTP
bin/migrate.dart         apply migrations and exit
lib/src/platform/        infrastructure (PLATFORM.md)
lib/src/modules/<name>/  module.dart, api.dart, http/, application/, domain/,
                         data/, MODULE.md   (ADR-026)
lib/src/modules/all_modules.dart   production module list
lib/src/server.dart      HelixServer: migrate, register, start, stop
test/                    platform/, per-module tests, e2e/, client/,
                         architecture_test.dart
```

## Running a node locally

Copy `.env.example` to `.env`, fill it in, then:

```bash
dart run bin/server.dart
```

The process listens on `HELIX_HOST:HELIX_PORT`. It stops on Ctrl+C,
finishing in-flight requests for up to 10 seconds.

## Local database (one-time)

PostgreSQL 17 runs on the PC as the `postgresql-x64-17` Windows service.
Create the role and databases yourself. The script asks for the PostgreSQL
superuser password and for a new `helix` password, and prints neither:

```powershell
cd helix_remote/server/tool
./setup_local_postgres.ps1 -SaveTestUrl
```

`-SaveTestUrl` stores `HELIX_TEST_DATABASE_URL` for your Windows user.
Open a new terminal afterwards.

## Tests

```bash
cd helix_remote/server
dart test
```

- **Without `HELIX_TEST_DATABASE_URL`:** database tests are **skipped**, and
  the report says so. CI sets `HELIX_REQUIRE_TEST_DATABASE=1` and runs a
  Postgres 17 service, so there a missing database fails the run.
- **Isolation:** each test uses a random schema prefix (`t1a2b3c4d_identity`,
  …), and `dropSchemas` cleans it up. Suites can share one database and run
  in parallel.
- **Two nodes:** a second `HelixServer` on the same prefix acts as another
  node (see `test/server_test.dart`). `test/support/cluster.dart` starts
  such a pair, and `test/e2e/two_node_test.dart` drives clients across it:
  messages, calls, revocation, supersede, groups and jobs.
- **Through the v2 client:** `test/client/` drives the server with
  `helix_remote_api` (`package:helix_remote_api/v2.dart`): registration,
  prekeys, socket delivery and acks, revocation (4003), refresh and
  sign-out, media, and the admin console. It is the only place the server
  package may import the client (dev dependency; `architecture_test.dart`).
- **Passwords:** the connection URL is never printed. Do not log it.

## Load harness

`dart run tool/load.dart --devices 1000 --rate 0.05 --duration 60` boots a
node in-process on the test database, registers the devices through the real
flow and measures send, delivery and ack latency. See
`../docs/operations/LOAD_TESTING.md` ("v2 server").
