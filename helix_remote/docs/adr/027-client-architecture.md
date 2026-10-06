# ADR 027: Client architecture — drift, pure-Dart engine, Riverpod feature modules

Status: accepted (2026-09-30).

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§6).

## Context

In v1:
- The app stores messages as ciphertext inside SQLCipher and decrypts them on
  every read.
- All SQLite calls are synchronous on the UI isolate.
- There are no reactive queries; the UI re-fetches on broad change events and
  pages with OFFSET.
- 59 of 252 storage methods are unused.
- `RemoteMessagingService` and `RemoteCompositionRoot` are god objects split
  into mixins.
- Screens reach into `messagingService.db` and the REST client directly.
- Messaging logic depends on Flutter, so the FCM background isolate and the
  CLI cannot reuse it.

## Decision

- **`helix_remote_db`:** drift over `sqlite3` with the SQLCipher hook. It is
  opened with `NativeDatabase.createInBackground`, so there is never a DB call
  on the UI isolate. It depends on neither Flutter nor the UI.
- **Decrypt once:**
  - Messages are decrypted on arrival into structured rows (body, kind,
    reply, reactions, receipts, attachments, FTS5).
  - SQLCipher is the at-rest protection, as `PRODUCT_CONTRACT.md` and
    `PRIVACY_POLICY.md` already state.
  - Conversation summary columns (last message, unread and mention counts)
    are written in the same transaction as the message.
- **`helix_remote_engine`:** pure Dart. It holds the session manager, inbound
  and outbound pipelines, transfer queue, and feature services. It runs in
  the app, in the FCM background isolate, in the CLI and in tests.
- **`helix_remote_api`:** typed REST and WebSocket clients, one client per
  server module. The REST implementation moves out of `app/`.
- **`helix_remote_protocol`:** wire DTOs, frames, content types and error
  codes, shared with the server (ADR-028).
- **App:**
  - `core/` (providers, go_router with deep links, lifecycle, notifications,
    push, app lock).
  - `features/<feature>/{application,presentation}`.
  - Riverpod for dependency wiring and UI state. Every list is a
    `StreamProvider` over a drift watch query.
  - Presentation may not import db, api, crypto or engine. A test enforces
    this.
- **Code generation** (drift): generated files are committed. CI fails if
  they are stale.
- **Retired at cutover:** `helix_remote_storage`, `helix_remote_sync` and
  `helix_remote_groups`. The groups logic moves into the engine.

## Consequences

- New dependencies (`drift`, `drift_dev`, `build_runner`, `flutter_riverpod`,
  `go_router`) are recorded in `docs/dependencies/DEPENDENCY_RISK_REGISTER.md`
  and added in the phase that first uses each one.
- The product rules in AGENTS.md are unchanged. English literals, light theme
  only, tokens, tooltips, 48 px targets and screenshots-allowed keep their
  tests.
- The local schema starts again at version 1 (clean slate, D2). From the first
  v2 release onward, every schema change needs a drift migration test.
