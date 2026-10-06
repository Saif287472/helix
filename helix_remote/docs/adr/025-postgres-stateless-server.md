# ADR 025: PostgreSQL and stateless server nodes (v2 server)

Status: accepted (2026-09-30) · Supersedes the storage and topology parts of
ADR-019 for the v2 server. ADR-019 still describes the live v1 `backend/`
until cutover (plan Phase X).

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§4).

## Context

The v1 backend runs on one SQLite connection with a fully synchronous API
(~660 call sites). Its correctness depends on that: sequence numbers are
allocated read-then-write, and 16 repository methods issue their own `BEGIN`.
In-process state (WebSocket registry, ~10 rate limiters, login challenges, the
S2S replay map, an outbox without leases) means a second process would
double-send pushes, reject valid logins and miss sockets. Helix Remote must be
able to serve millions of users, which needs more than one server process and
a database that supports concurrent writers.

## Decision

- The v2 server (`helix_remote/server/`) uses **PostgreSQL 17** through
  `package:postgres` v3 with a connection pool. SQLite is not used by the
  server, including in tests: tests run against a real Postgres
  (`HELIX_TEST_DATABASE_URL`, a fresh schema per test file).
- The database API is **async** throughout. Writes go through one
  `Db.tx(...)` entry point. Repositories never open transactions.
- Server nodes are **stateless**. Durable state lives in Postgres. Short-lived
  state (presence, WebSocket routes, login challenges, replay caches, rate
  buckets) lives in an `EphemeralStore`. Nodes coordinate through an
  `EventBus` and a transactional outbox with leases (`FOR UPDATE SKIP
  LOCKED`).
- Every scale-out component sits behind an interface. The single-host
  implementation (Postgres `LISTEN/NOTIFY`, `UNLOGGED` tables, local
  filesystem blobs) ships first. The scale-out implementation (Redis/NATS,
  S3-compatible storage) is a configuration switch, not an architecture change.
- IDs are UUIDv7. Payloads are `bytea`. Times are `timestamptz`.
- Migrations are per-module numbered SQL files. They are checksummed, run
  under an advisory lock, and follow expand → migrate → contract.

## Consequences

- Personal servers need Postgres too, shipped as `docker compose` (server +
  Postgres). This is accepted.
- The PC deployment runs Postgres natively, as a Windows service. The user
  owns its credentials; agents never handle them.
- The code scales horizontally. Serving millions of users still needs hosted
  infrastructure, and that is a deployment change.
- Documentation may call Postgres *implemented* only once the v2 server is
  live after cutover, with tests linked (ADR-019's evidence rule still
  applies).
