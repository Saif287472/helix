# Helix

Two privacy-focused messengers in one repository.

- **Helix Remote** (`helix_remote/`): an internet messenger with persistent,
  end-to-end encrypted chats, groups, calls and multi-device accounts, for
  Android and Windows. This is the product under active development.
  It talks to **Helix Global** (run by the project owner) or to a personal
  server anyone can run.
- **Helix Local** (`helix_local/`): a LAN-only, ephemeral messenger. Dormant;
  a separate app with its own workspace.

Not externally reviewed: none of the cryptography or the server has had an
independent audit, and the documentation says so wherever it makes a claim
(`helix_remote/docs/product/PRIVACY_CLAIM_MATRIX.md`).

## Helix Remote at a glance

```
helix_remote/
  server/      Dart server (shelf) over PostgreSQL 17, one module per area
  app/         Flutter client (Riverpod, go_router, drift + SQLCipher)
  admin/       Flutter operator console
  packages/    protocol (wire contract), crypto, db, api clients, engine, cli,
               calls, ui, domain, architecture_rules
  deploy/      coturn (TURN relay) for Docker and Windows/WSL
  docs/        architecture, protocol, security, product, operations
  scripts/     verify.ps1 / verify.sh (the full local gate)
```

The architecture, the decisions behind it and the build history are in
[`helix_remote/docs/architecture/ARCHITECTURE_V2_PLAN.md`](helix_remote/docs/architecture/ARCHITECTURE_V2_PLAN.md);
the wire protocol is in [`helix_remote/docs/protocol/v2/`](helix_remote/docs/protocol/v2/README.md).
The previous (v1) implementation is in git history; its last commit is tagged
`v1-final`.

## Quick start

You need the Flutter SDK (version in `.github/workflows/ci.yml`, which also
provides the matching Dart) and, for the server, PostgreSQL 17.

```bash
cd helix_remote
flutter pub get            # one pub workspace for everything
flutter analyze
```

**Run a server** (see [`helix_remote/server/README.md`](helix_remote/server/README.md)
for the one-time database setup):

```bash
cd helix_remote/server
cp .env.example .env       # fill it in
dart run bin/migrate.dart
dart run bin/server.dart
```

**Run the app or the console from source:**

```bash
cd helix_remote/app   && flutter run -d windows     # or a connected phone
cd helix_remote/admin && flutter run -d windows
```

The app opens on the Helix Global sign-in page; a personal server is reached
through the hidden advanced mode (three taps bottom-right, then a fourth) or a
shared link. Building APKs is done by hand, not by scripts or agents.

**Test everything:** `helix_remote/scripts/verify.ps1` (Windows) or
`verify.sh`: format check, drift codegen check, analyze, every package's tests,
the server tests (they need `HELIX_TEST_DATABASE_URL`) and the governance
check. CI runs the same on Linux with a Postgres service.

## Running Helix Global

Operating the server (environment variables, Caddy, coturn, push, SMS, backups,
the cutover checklist): [`helix_remote/docs/operations/V2_SERVER_HANDOFF.md`](helix_remote/docs/operations/V2_SERVER_HANDOFF.md)
and [`V2_OPERABILITY.md`](helix_remote/docs/operations/V2_OPERABILITY.md).

## Working in this repository

[`AGENTS.md`](AGENTS.md) is the reference for people and coding agents: the map,
the product rules (English only, light theme only, screenshots allowed, no
contact requests), the security invariants, and the verification expectations.
`docs/` holds cross-product documents, much of it historical (see the banners).
