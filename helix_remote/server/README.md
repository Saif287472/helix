# helix_remote_server (v2)

This is the Helix Remote v2 server, built to
`../docs/architecture/ARCHITECTURE_V2_PLAN.md` on branch `architecture-v2`.
It runs on PostgreSQL 17, with stateless nodes and one module per area
(ADR-025, ADR-026). Until cutover the live server is `../backend/` (v1); this
package is not deployed.

Status: Phase 0 skeleton. It has the test harness and the architecture rules;
the platform layer arrives in Phase S1.

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
  the report says so. Architecture tests still run.
- **CI** sets `HELIX_REQUIRE_TEST_DATABASE=1` and a Postgres 17 service, so
  there a missing database fails the run.
- **Isolation:** each test gets its own schema through `withTestSchema`
  (`test/support/test_database.dart`), and the schema is dropped afterwards.
- **Passwords:** the connection URL is never printed. Do not log it.
