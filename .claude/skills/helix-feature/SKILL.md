---
name: helix-feature
description: End-to-end checklist for changing Helix Remote — a feature, fix, refinement or UI/UX change that touches the backend, the REST API, the Flutter app, the admin app or the shared packages. Use for any non-trivial Helix Remote work, before writing code.
---

# Helix Remote change checklist

Read `AGENTS.md` first (repo map, rules, known test failures). This skill is
the order of work; AGENTS.md is the reference.

## 1. Before coding

- Find the layer(s) the change touches. Use the map in AGENTS.md rather than
  scanning directories; skip `build/`, `.dart_tool/`, `docs/codebase/`.
- Read the module doc next to the code you change
  (`helix_remote/backend/lib/src/modules/*.module.md`, `auth/MODULE.md`).
- A product decision you cannot settle from the code or the user's words:
  ask (AskUserQuestion) before building. Planning-only requests: plan, don't
  implement.

## 2. Backend (`helix_remote/backend`)

- Handlers live in `lib/src/modules/<module>.dart` or its `part` files
  (`modules/auth/*.dart`, `groups/`, `calls/`). Errors: throw `AppError`
  (`lib/src/app_error.dart`) with a `RemoteErrorCode` when the client must
  tell cases apart.
- New table/column: append `if (version < N) { ...; PRAGMA user_version = N }`
  in `lib/src/database/migrations.dart`, add repository methods in
  `lib/src/database/*_repository.dart` (`part of '../database.dart'`), then
  bump every test that asserts the schema version (grep `user_version` and
  the old number in `backend/test`).
- New **public** route (no session): add it to `_authMiddleware`'s exemption
  list in `lib/src/server_impl.dart`. Rate-limit public lookups
  (`lookupRateLimiter`).
- Sessions are minted only by `_issueDeviceSession` (auth.dart). Delivery
  paths use `getActiveDevices`, never `getDevices`.
- Update the module's `.md` route table.
- Test with a real server: `BackendServer.create(sqliteDb:
  sqlite3.openInMemory(), ...)` + `HttpClient` (see
  `test/recovery_lookup_otp_test.dart`, `_RecordingSmsProvider` for SMS).

## 3. API contract

- Add or change the method in
  `helix_remote/packages/helix_remote_api/lib/api/rest_client.dart`.
- Implement it in `helix_remote/app/lib/app/remote_rest_client.dart`.
- Add a default to `helix_remote/app/test/support/group_call_rest_stubs.dart`
  — a dozen test fakes mix it in. A changed signature must also be changed
  in every fake that overrides it (grep the method name under `app/test`).

## 4. App (`helix_remote/app`)

- Composition root: `lib/app/composition_root.dart` + `composition_root/*.dart`
  parts (mixins on `RemoteCompositionRootBase`). Messaging:
  `lib/app/remote_messaging_service.dart` + `remote_messaging_service/*.dart`.
- Local DB change: `packages/helix_remote_storage/lib/src/database/migrations.dart`
  (`latestSchemaVersion`) and the tests asserting it.
- UI rules the test suite enforces:
  - Plain English string literals. There is no localization layer — never
    add ARB files, `HelixLocalizations` or a translation.
  - No `Color(0x…)` / `Colors.x` in `app/lib` (except `Colors.transparent`):
    use `Theme.of(context).colorScheme` or a token in
    `packages/helix_remote_ui/lib/helix_remote_ui.dart`.
  - Every `IconButton` has a `tooltip:` (also in `admin/lib`).
  - Tap targets ≥ 48 px; sign-in pages use `HelixThemes.signIn()`.
- Sign-in flow: `lib/screens/setup/` — `state/onboarding_notifier.dart`
  (logic), `setup_screen.dart` (pages), `setup_choices.dart` (results the host
  completes in `lib/app/bootstrap.dart`).

## 5. Verify (use the `helix-verify` skill)

Analyze + the affected suites, compare failures against the known list in
AGENTS.md, and fix anything new you caused.

## 6. Report to the user

- What changed, in plain words; files grouped by layer.
- Test results with real numbers; pre-existing failures named as such.
- **Whether a new APK is needed** (any `app/` or `admin/` change) — never
  build it unless asked.
- **Whether the backend must be restarted** (any `backend/` change) — the
  user restarts it; never stop or restart the live server yourself.
- Env/config the user must add (e.g. to `helix_remote/backend/.env`) — tell
  them the line; never edit live config or state.
- Update docs that describe what you changed (module `.md`, `helix_remote/docs`).
