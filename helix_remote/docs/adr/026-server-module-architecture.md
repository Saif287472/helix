# ADR 026: Server module architecture (v2)

Status: accepted (2026-09-30). Refines ADR-010 (modular monolith).

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§4.1–§4.2, §4.7).

## Context

The v1 backend calls itself modular, but `BackendDatabase` is one class, with
every `*_repository.dart` an extension on it. Any module can call any
repository method. `OperabilityModule` receives almost everything. Public
routes are an `endsWith` chain inside `_authMiddleware`. Adding a feature
means editing shared files.

## Decision

- The server is a list of `HelixModule`s. Each module declares its name (also
  its Postgres schema), migrations, routes, bus subscriptions and jobs.
- Module layout: `module.dart`, `api.dart` (the only file other modules may
  import), `http/`, `application/` (use cases; transactions start here),
  `domain/`, `data/` (SQL, this module's schema only), `migrations/`,
  `MODULE.md`.
- Shared code lives in `platform/` (infrastructure, no business logic) and
  `kernel/` (ids, errors, auth context, paging, idempotency, event base types).
- **No cross-schema joins and no cross-schema foreign keys.** Cross-module
  effects use `api.dart` facades (synchronous) or domain events (asynchronous).
  Account deletion is an event every module handles.
- **Public routes are declared explicitly** with `routes.public(path, handler,
  rateLimit: ...)`, where the rate-limit policy is required. A snapshot test of
  the public-route list makes every addition a deliberate reviewed diff. This
  replaces the v1 `_authMiddleware` list, and keeps the invariant in
  AGENTS.md.
- **Sessions are minted in exactly one place** (`identity` module,
  `issueDeviceSession`). An architecture test forbids JWT signing elsewhere.

## Consequences

- A new feature is a new module. Core files do not change.
- Modules can later be deployed separately if needed, because nothing shares
  tables.
- Some work is duplicated deliberately. For example, `people` keeps its own
  projection of account display data, updated by events, instead of joining
  `identity.accounts`.
