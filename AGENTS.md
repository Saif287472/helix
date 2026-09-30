# Agent Instructions

Helix is two privacy-focused messengers in one repo. **Helix Remote**
(internet, persistent, end-to-end encrypted) is the product under active
development; **Helix Local** (LAN-only, ephemeral) is dormant. Unless the
user says otherwise, work means Helix Remote.

For any non-trivial Helix Remote change, use the project skills:
`helix-feature` (order of work across backend → API → app → tests → report)
and `helix-verify` (analyze, test, separate new failures from known ones).

## Repository map

Two separate Dart/Flutter workspaces; there is no root `pubspec.yaml`.

```
helix_remote/                pub workspace (run commands from here)
  app/                       Flutter client (Android, Windows)
    lib/main.dart            entry; parts: app/bootstrap.dart (which server,
                             sign-in hand-off, links), app/remote_app_shell.dart
    lib/app/composition_root.dart + composition_root/*.dart
                             the app's wiring; parts are mixins: session,
                             registration, password_auth, history_backup,
                             runtime, lifecycle, contacts_sync, ...
    lib/app/remote_messaging_service.dart + remote_messaging_service/*.dart
                             encryption, sending, decryption, history, backup
    lib/app/remote_rest_client.dart   REST implementation
    lib/app/deep_link.dart, link_channel.dart   helix:// and https://…/open links
    lib/screens/setup/       sign-in: state/onboarding_notifier.dart (logic),
                             setup_screen.dart (pages), setup_choices.dart
    lib/screens/, lib/widgets/, lib/presentation/   UI
    test/                    widget + unit tests; test/support/ shared fakes
  admin/                     Flutter operator console (users, invites, recovery codes)
  backend/                   Dart shelf server (Helix Global and personal servers)
    bin/server.dart          entry; reads backend/.env
    lib/src/server_impl.dart router, middleware, public-route list (_authMiddleware)
    lib/src/modules/         one module per area + parts (auth/, groups/, calls/);
                             each has a MODULE.md / *.module.md contract
    lib/src/database.dart + database/*_repository.dart, database/migrations.dart
  packages/helix_remote_api       REST client interface (rest_client.dart)
  packages/helix_remote_storage   local SQLCipher DB, migrations (latestSchemaVersion)
  packages/helix_remote_sync      sync engine / outbox
  packages/helix_remote_crypto    X3DH, double ratchet, prekeys, backup crypto
  packages/helix_remote_ui        design tokens + components (HelixColorTokens,
                                  HelixStatusColors, HelixSpace, HelixThemes)
  packages/helix_remote_{domain,calls,groups,cli}
  contracts/                 OpenAPI + realtime contracts (behind the code; see docs)
  docs/                      Remote docs (architecture, protocol, security, product)
  scripts/verify.ps1|.sh     full local gate
helix_local/                 Helix Local workspace (app, packages, docs) - dormant
docs/                        cross-product docs; much of it historical (see banners)
.github/workflows/ci.yml     CI (Remote jobs run in helix_remote/)
```

Schema versions: backend SQLite `PRAGMA user_version` **48**; app local DB
**32**. Bump with a migration block and update the tests that assert them.

## Read before working in an area

- Backend module you touch: its `MODULE.md` / `*.module.md` next to the code.
- Auth, devices, sessions: `helix_remote/backend/lib/src/modules/auth/MODULE.md`,
  `helix_remote/docs/protocol/F1_MULTI_DEVICE_TRUST_DESIGN.md`.
- Backup / recovery / history: `helix_remote/docs/product/BACKUP_RECOVERY.md`,
  `helix_remote/docs/protocol/F2_BACKUP_RECOVERY_TRANSFER_DESIGN.md`.
- Security and privacy claims: `helix_remote/docs/product/THREAT_MODEL.md`,
  `PRIVACY_CLAIM_MATRIX.md`, `METADATA_INVENTORY.md`,
  `helix_remote/docs/security/remote_cryptographic_design_review.md`.
- Deployment and env vars: `helix-remote-server-handoff.md`,
  `helix_remote/docs/operations/REMOTE_OPERABILITY_AND_DR.md`.
- Dependencies: `docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md`,
  `DEPENDENCY_RISK_REGISTER.md` (CI enforces both).
- Files never to read or print: `docs/security/FORBIDDEN_FILES.md`
  (includes `helix_remote/backend/.env` and keystores).

Docs marked "Status: historical" or "Scope: Helix Local" are context, not
instructions. `docs/codebase/` is a gitignored code dump - never read it.

## Product rules

- **English only.** UI text is plain English string literals. There is no
  localization layer (ARB/gen-l10n and Bengali were removed on 2026-09-28) -
  never add one back.
- **Light theme only.** Colours come from `Theme.of(context).colorScheme` or
  tokens in `helix_remote_ui`; no `Color(0x…)`/`Colors.x` in `app/lib`
  (`phase5_design_tokens_test`). Sign-in pages use `HelixThemes.signIn()`
  (the app icon's blue).
- **Screenshots are allowed everywhere.** No FLAG_SECURE, no Windows display
  affinity, no per-screen capture blocking (removed 2026-09-30 - people need
  to screenshot chats; `screenshots_allowed_test`). Never add it back.
- Every `IconButton` has a `tooltip:`; tap targets are at least 48 px
  (`phase7_accessibility_test`, which also checks the sign-in page).
- **No contact requests.** Anyone can message or call anyone who has not
  blocked them (WhatsApp-style); there is no Contacts tab. People are shown
  by phone-book name, then nickname, then number, then `~Helix name`
  (`remote_messaging_service/people.dart`). Renaming someone writes the name
  to the phone's contacts too. Search for people lives in the Chats and
  Calls tabs (`screens/people/`). Home is three swipeable tabs: Chats,
  Calls, Settings.
- Sign-in always opens on the simple Helix Global page. Personal servers are
  behind the hidden advanced mode (3 taps bottom-right, 2 s apart, reveal it;
  a 4th opens it) or a shared link `https://helix.agiletechbd.com/open#HLX-…`.
  There is no host-your-own-server guide in the app.

## Security invariants

- Never weaken authentication, encryption, signature/transcript checks or
  trust decisions to make something work.
- Never log or print passwords, tokens, keys, message content, recovery or
  invite codes, or full phone numbers.
- The password never leaves the device; only the HKDF-derived auth key is
  sent. Sessions are minted only by `_issueDeviceSession`. Message delivery
  uses `getActiveDevices` (revoked devices get nothing).
- A new public route must be added deliberately to `_authMiddleware`'s list
  and rate-limited if it looks anything up.

## Build artifacts

**Do not build debug APKs unless explicitly asked.** The user builds and
installs them manually on a physical device.

When app or admin code changes, do **not** run `flutter build apk`. Instead,
finish the work, run analysis and tests, and then tell the user plainly whether
a new APK is needed for them to test the change. Wait for them to ask before
building.

This applies to both `helix_remote/app` and `helix_remote/admin`.

## Deployment

- Helix Global runs on the user's PC: Caddy (`J:\Projects\Servers\helix_server`)
  in front of `dart run bin/server.dart` in `helix_remote/backend`, coturn in
  WSL1. That process is live production - **never stop or restart it**.
- Deploying = the user restarts the backend. After backend changes, say so.
- Never hand-edit live state (the production database, `backend/.env`); tell
  the user the exact line to add instead.

## Verification expectations

- Run `flutter analyze` / `dart analyze` and the relevant test suites before
  reporting work as done (see the `helix-verify` skill).
- Distinguish pre-existing failures from ones you introduced. Confirm by
  stashing changes and re-running, rather than assuming.
- Do not commit unexplained binary or asset changes (e.g. `logo.png` changing
  during a build). Flag them and let the user decide.

### Known pre-existing test failures

None as of 2026-09-30 (app 486, backend 577, admin 109, api 46, storage 25,
sync 13, calls 73 - all passing). Add any failure you confirm is pre-existing here,
with the date.

## Working on Windows

- The shell is Git Bash. Every command prints an `ng completion` warning from
  the user's profile - ignore it.
- Heredocs containing apostrophes or `\n` break easily: write multi-line
  patches as a Python script in the scratchpad and run it.
- `tar` needs `--force-local` for `C:` paths.
- `dart test` in `helix_remote/backend` fails with `PathAccessException` on
  `.dart_tool/lib/sqlcipher.dll` while the live server runs from this
  checkout (it holds the DLL). Run backend tests in a short-path worktree
  (`git worktree add --detach J:/wt/<name> HEAD`, apply the diff, copy
  untracked files, `flutter pub get`), then remove it.
- Run `dart format` only on files you changed; the tree is not uniformly
  formatted with the current formatter.
- Never `robocopy /MIR` Flutter directories (it follows `.plugin_symlinks`
  into the pub cache and empties packages).

## Committing

- The user has asked for commits to include all uncommitted work. Stage
  deliberately and review `git status` first, since builds can leave stray
  modifications behind.
- Commit only when asked.
