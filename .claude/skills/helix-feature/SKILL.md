---
name: helix-feature
description: End-to-end checklist for changing Helix Remote — a feature, fix, refinement or UI/UX change that touches the server, the wire protocol, the engine, the Flutter app, the admin app or the shared packages. Use for any non-trivial Helix Remote work, before writing code.
---

# Helix Remote change checklist

Read `AGENTS.md` first (repo map, rules, known test failures). This skill is
the order of work; AGENTS.md is the reference. The architecture is v2; its
rules are in `helix_remote/docs/architecture/ARCHITECTURE_V2_PLAN.md`, and
boundaries are enforced by each package's `test/architecture_test.dart`.

## 1. Before coding

- Find the layer(s) the change touches. Use the map in AGENTS.md rather than
  scanning directories; skip `build/`, `.dart_tool/`, `docs/codebase/`.
- Read the doc next to the code you change: a server module's `MODULE.md`
  (`helix_remote/server/lib/src/modules/<name>/`), `PLATFORM.md` for
  infrastructure, a package's `MODULE.md`, an app feature's `FEATURE.md`.
- A product decision you cannot settle from the code or the user's words:
  ask (AskUserQuestion) before building. Planning-only requests: plan, don't
  implement.
- A change to the target architecture needs an ADR and a user-approved plan
  change-log entry; do not slip one in.

## 2. Wire contract (`packages/helix_remote_protocol`)

Everything that crosses the network is defined here first: route in the
catalog (`lib/src/routes.dart`, with its module, access and, for public
routes, a rate-limit policy name), DTOs in `lib/src/modules/<module>.dart`,
error codes, frames, content types. Update `docs/protocol/v2/REST_V2.md` (a
test checks the catalog and the doc agree). Golden fixtures in
`contracts/v2/fixtures/` change only deliberately
(`HELIX_UPDATE_FIXTURES=1 dart test` in the protocol package). New message
kinds go **inside** the encrypted content (`CONTENT_V2.md`), not as server
routes, unless the server must route on them.

## 3. Server (`helix_remote/server`)

- Put the change in the module that owns the data (`modules/<name>/`):
  `http/` handlers map DTOs, `application/` holds use cases and starts
  transactions, `data/` holds the SQL (nowhere else), `domain/` holds rules.
  Other modules are reached only through their `api.dart` or the event bus.
- New table or column: a new numbered `Migration` in that module (never edit a
  migration that has run; expand, migrate, contract). Postgres types:
  `timestamptz`, `bytea`, UUIDv7 ids.
- New **public** route (no session): `r.public(...)` with a rate-limit policy;
  update the public-route snapshot test deliberately. Sessions are minted only
  by `SessionIssuer.issue`. Delivery uses the exact active device list.
- Update the module's `MODULE.md` (routes, tables, jobs, invariants).
- Test against a real Postgres: `server/test/modules/<name>_test.dart` with the
  harness in `server/test/support/`. A route a client uses also gets a test in
  `server/test/client/`.
- Env or config the user must add: tell them the exact line; update the table
  in `docs/operations/V2_SERVER_HANDOFF.md` and `server/.env.example`.

## 4. Clients

- API: add the method to the module's client in `packages/helix_remote_api`
  (`lib/src/v2/clients/<module>_client.dart`); the route-parity test fails
  until there is exactly one method per route.
- Engine (`packages/helix_remote_engine`): the behaviour (sessions, pipelines,
  features) is pure Dart, tested without Flutter. Local data goes through
  `helix_remote_db` (drift: schema change = step migration + schema dump +
  `dart run tool/codegen.dart`, committed generated code).
- App (`helix_remote/app`): a feature is `features/<name>/application`
  (Riverpod Notifiers and StreamProviders) plus `presentation` (stateless
  widgets that import only their own feature, `shared/`, `helix_remote_ui` and
  `helix_remote_domain`). Wiring lives in `core/`. Every list is a StreamProvider
  over an engine watch query.
- UI rules the test suite enforces:
  - Plain English string literals. There is no localization layer - never
    add ARB files or a translation.
  - No `Color(0x…)` / `Colors.x` in `app/lib` (except `Colors.transparent`):
    use `Theme.of(context).colorScheme` or a token in `packages/helix_remote_ui`.
  - Every `IconButton` has a `tooltip:` (also in `admin/lib`).
  - Tap targets >= 48 px; sign-in pages use `HelixThemes.signIn()`.
  - Screenshots are allowed everywhere; never add capture blocking.
- Admin console: `admin/lib/src/features/<feature>` over `HelixAdminApi`.

## 5. Verify (use the `helix-verify` skill)

Analyze + the affected suites, compare failures against the known list in
AGENTS.md, and fix anything new you caused.

## 6. Report to the user

- What changed, in plain words; files grouped by layer.
- Test results with real numbers; pre-existing failures named as such.
- **Whether a new APK is needed** (any `app/` or `admin/` change) - never
  build it unless asked.
- **Whether the server must be restarted, and whether `bin/migrate.dart` is
  needed** (any `server/` change) - the user restarts it; never stop or
  restart the live server yourself.
- Env/config the user must add (e.g. to `helix_remote/server/.env`) - tell
  them the line; never edit live config or state.
- Update docs that describe what you changed (module `.md`, `helix_remote/docs`,
  the protocol docs for any wire change).
