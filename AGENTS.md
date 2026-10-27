# Agent Instructions

Helix is two privacy-focused messengers in one repo. **Helix Remote**
(internet, persistent, end-to-end encrypted) is the product under active
development; **Helix Local** (LAN-only, ephemeral) is dormant. Unless the
user says otherwise, work means Helix Remote.

For any non-trivial Helix Remote change, use the project skills:
`helix-feature` (order of work across server → API → engine → app → tests →
report) and `helix-verify` (analyze, test, separate new failures from known
ones).

**Never change anything under `helix_local/`** - it is a separate app.

## Architecture (v2, live since the Phase X cutover)

Helix Remote runs on the architecture in
`helix_remote/docs/architecture/ARCHITECTURE_V2_PLAN.md` (the plan of record;
its tracker, section 11, is the history of how it was built): a stateless
Dart server over PostgreSQL 17 with one module per area, a pure-Dart protocol
package shared by every client, a pure-Dart engine over a drift + SQLCipher
local database, and a Flutter app on Riverpod and go_router. The v1 code
(SQLite backend, `helix_remote_storage`, `_sync`, `_groups`, the v1 REST client
and crypto) was deleted at cutover; it lives in git history, and the last v1
commit is tagged `v1-final`.

- Changing the target architecture (plan sections 3-6) needs a new ADR in
  `helix_remote/docs/adr/` and a user-approved change-log entry (section 12).
- Boundaries are enforced by tests, not convention: the server's
  `test/architecture_test.dart` and every package's `test/architecture_test.dart`
  (rules in `packages/helix_remote_architecture_rules`, a test-only package).
  A new package must be added to `v2PackageDependencies` in the same change.
- The wire contract is `packages/helix_remote_protocol` plus
  `helix_remote/docs/protocol/v2/` (the truth for REST, realtime, content,
  crypto and metadata). Golden fixtures in `helix_remote/contracts/v2/fixtures/`
  change only deliberately (`HELIX_UPDATE_FIXTURES=1 dart test` in the
  protocol package).
- `flutter pub get` regenerates the plugin registrant files under
  `app/windows/flutter` and `admin/{linux,macos,windows}`, and git often lists
  them as modified with no content change - `git checkout --` them before
  committing. When a plugin is added or removed, the content does change
  (`git diff --ignore-cr-at-eol` shows it): commit the regenerated files with
  that change.

## Repository map

Two separate Dart/Flutter workspaces; there is no root `pubspec.yaml`.

```
helix_remote/                pub workspace (run commands from here)
  server/                    Dart shelf server (Helix Global and personal servers)
    bin/server.dart          one node: reads server/.env, migrates, serves
    bin/migrate.dart         apply migrations and exit (deploy step)
    lib/src/platform/        infrastructure, no business logic (PLATFORM.md):
                             config, Postgres Db/Tx and migration runner, HTTP
                             pipeline, event bus, ephemeral store, rate limits,
                             jobs/outbox, object storage, push, logs, metrics
    lib/src/kernel/          types every module may use (jwt, crypto, presence)
    lib/src/modules/<name>/  one module per area: identity, keys, messaging,
                             realtime, people, media, backup, groups, calls,
                             federation, ops, admin, compliance; each has
                             module.dart and a MODULE.md (routes, tables, jobs,
                             invariants), and all but realtime an api.dart (the
                             only file other modules may import); the larger
                             ones split into http/, application/, domain/,
                             data/ (identity has all four)
    test/                    per-module + platform + e2e (two nodes) + client/
                             (drives the server with the real api/engine/cli)
    tool/                    load harness, local Postgres setup script
  app/                       Flutter client (Android, Windows)
    lib/main.dart            zones, error reporting, FCM handler, router
    lib/core/                wiring only: engine/ (HelixRuntime, providers),
                             router/, links/, platform/, lifecycle/, security/,
                             notifications/, push/, people/, calls/
    lib/features/<feature>/  application/ (Riverpod) + presentation/ (widgets);
                             sign_in, home, chats, conversation, people, calls,
                             groups, settings, devices, backup, profile
    lib/shared/widgets/      cross-feature widgets on orbit_ui
    test/                    widget + unit tests; test/support/ shared fakes
  admin/                     Flutter operator console on the admin API
  packages/helix_remote_protocol  wire DTOs, route catalog, frames, content types
  packages/helix_remote_crypto    X3DH, Double Ratchet, Sender Keys, backup crypto
  packages/helix_remote_db        drift + SQLCipher local database (generated
                                  code is committed: tool/codegen.dart --check)
  packages/helix_remote_api       typed REST + WebSocket clients (lib/v2.dart)
  packages/helix_remote_engine    pure-Dart messaging engine (sessions, inbound/
                                  outbound pipelines, groups, calls, transfers)
  packages/helix_remote_cli       headless client on the engine (helix_v2)
  packages/helix_remote_calls     WebRTC wrapper (Flutter)
  packages/helix_remote_ui        the old look, kept for the operator console
                                  (tokens, `HelixThemes.console()`, two widgets)
  packages/orbit_ui               the Orbit design system and every Orbit screen
                                  (orbit/PORT_PLAN.md; models in, actions out)
  packages/helix_remote_domain    shared value types (legal documents only today)
  packages/helix_remote_architecture_rules  test-only import-rule helpers
  contracts/v2/fixtures/     golden wire fixtures
  deploy/coturn/             TURN relay (Docker and Windows/WSL1 start script)
  deploy/windows/            the PC's backup task, restore drill and hardened
                             Caddyfile (the user installs and runs them)
  docs/                      Remote docs (architecture, protocol, security, product)
  scripts/verify.ps1|.sh     full local gate; coverage.sh the coverage ratchet
  tool/                      governance check, performance-budget check, SBOM
helix_local/                 Helix Local workspace (app, packages, docs) - dormant
docs/                        cross-product docs; much of it historical (see banners)
.github/workflows/ci.yml     CI (Remote jobs run in helix_remote/, Postgres 17 service)
```

Schema versions: the server has numbered migrations **per module**
(`modules/<name>/` and `platform/platform_migrations.dart`), checksummed and
recorded in `platform.schema_migrations`; never edit one that has run, add a
new one (expand, migrate, contract). The app's local database is schema **7**
(`schemaVersion` in `packages/helix_remote_db/lib/src/database.dart`); a change
needs a step migration, a regenerated schema dump and generated code
(`dart run tool/codegen.dart` in the package; CI runs `--check`), plus the
tests that assert it.

## Read before working in an area

- A server module you touch: its `MODULE.md` next to the code, and
  `server/lib/src/platform/PLATFORM.md` for infrastructure.
- Auth, devices, sessions: `server/lib/src/modules/identity/MODULE.md`,
  `helix_remote/docs/protocol/v2/` and
  `helix_remote/docs/protocol/F1_MULTI_DEVICE_TRUST_DESIGN.md` (historical for
  mechanics, still the design record for trust).
- Backup / recovery / history: `helix_remote/docs/product/BACKUP_RECOVERY.md`,
  `helix_remote/docs/protocol/F2_BACKUP_RECOVERY_TRANSFER_DESIGN.md`.
- Security and privacy claims: `helix_remote/docs/product/THREAT_MODEL.md`,
  `PRIVACY_CLAIM_MATRIX.md`, `METADATA_INVENTORY.md`,
  `helix_remote/docs/protocol/v2/METADATA_V2.md` and
  `helix_remote/docs/security/remote_cryptographic_design_review.md`.
- Deployment and env vars: `helix_remote/docs/operations/V2_SERVER_HANDOFF.md`
  (the env table is generated from the code), `V2_OPERABILITY.md`.
- Dependencies: `docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md`,
  `DEPENDENCY_RISK_REGISTER.md` (CI enforces both).
- Files never to read or print: `docs/security/FORBIDDEN_FILES.md`
  (includes `helix_remote/server/.env` and keystores).

Docs marked "Status: historical" or "Scope: Helix Local" are context, not
instructions. `docs/codebase/` is a gitignored code dump - never read it.

## Product rules

- **English only.** UI text is plain English string literals. There is no
  localization layer (ARB/gen-l10n and Bengali were removed on 2026-09-28) -
  never add one back.
- **Themes.** The app draws the Orbit theme chosen on You > Appearance (a
  device setting, kept across sign-outs): Orbit or Orbit Night today, more as
  downloadable packs later. Colours come from the theme (`OrbitTokens`,
  `Theme.of(context)`); no `Color(0x…)`/`Colors.x` in `app/lib`
  (`product_rules_test`), and no second dark or high-contrast theme. (Until
  2026-10-20 the app was light theme only.)
- **Screenshots are allowed everywhere.** No FLAG_SECURE, no Windows display
  affinity, no per-screen capture blocking (removed 2026-09-30 - people need
  to screenshot chats; `product_rules_test`, and the governance check). Never
  add it back.
- Every `IconButton` has a `tooltip:`; tap targets are at least 48 px
  (`product_rules_test`, `accessibility_test`, which also checks the sign-in
  page).
- **No contact requests.** Anyone can message or call anyone who has not
  blocked them (WhatsApp-style); there is no Contacts tab. People are shown
  by phone-book name, then nickname, then number, then `~Helix name`
  (`app/lib/core/people/people_names.dart`, the one naming source). Renaming
  someone writes the name to the phone's contacts too. Search for people lives
  in the Chats and Calls tabs (`features/people/`). Home is three swipeable
  tabs: Chats, Calls, Settings.
- Sign-in always opens on the simple Helix Global page. Personal servers are
  behind the hidden advanced mode (3 taps bottom-right, 2 s apart, reveal it;
  a 4th opens it) or a shared link `https://helix.agiletechbd.com/open#HLX-…`.
  There is no host-your-own-server guide in the app.
- TLS pinning is **off by default** (`app/lib/core/platform/tls_pinning.dart`);
  it applies only when a build passes `--dart-define=HELIX_GLOBAL_PINS=...`.

## Security invariants

- Never weaken authentication, encryption, signature/transcript checks or
  trust decisions to make something work.
- Never log or print passwords, tokens, keys, message content, recovery or
  invite codes, or full phone numbers (server logs go through the redacting
  logger; a test enforces it).
- The password never leaves the device; only the HKDF-derived auth key is
  sent. Sessions are minted only by `issueDeviceSession` (identity module; an
  architecture test pins the single mint point). Message delivery uses the
  recipient's *active* devices and the exact device list (a stale list is a 409
  `device_list_stale`); revoked devices get nothing.
- A new public route is declared deliberately with `r.public(...)`, which
  requires a rate-limit policy; the public-route snapshot test fails until the
  new route is an intentional diff. Modules import only another module's
  `api.dart`. A module's SQL lives in its own files (`module.dart`,
  `application/` or `data/`), names only its own schema, and is never in its
  `api.dart` or in `kernel/` (`test/architecture_test.dart`).
- Crypto code changes need test vectors and a note in
  `docs/security/remote_cryptographic_design_review.md`. The crypto has had
  no external review, and the docs keep saying so.

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
  in front of the server, against the PostgreSQL 17 service
  `postgresql-x64-17` (role `helix`, database `helix`), with local object
  storage and coturn in WSL1 (`deploy/coturn/windows/start-turn.ps1`). The
  process model chosen on 2026-10-14 (review batch 9): a compiled release in
  `J:\Projects\Servers\helix_server\helix` (`bin\helix-server.exe`, its own
  `.env`), run at boot by the scheduled task "Helix Server"
  (`deploy/windows/`, README "Running production"). Until the user has moved
  it there, production is still `dart run bin/server.dart` in
  `helix_remote/server`. Either way it is live production - **never stop or
  restart it**, and never run the deploy, install or release scripts.
- Deploying = the user tags a commit, builds it (`release-helix.ps1 -Tag`)
  and switches to it (`deploy-helix.ps1 -Tag`: graceful stop, swap, migrate,
  start, ready check); the old console way is a restart (`bin/migrate.dart`
  first if the change adds a migration; every node also migrates at start).
  After server changes, say so, and say which migration or `.env` line is
  new (and that the production `.env` is the one in the production folder).
- Never hand-edit live state (the production database, `server/.env`); tell
  the user the exact line to add instead. Agents never handle Postgres
  passwords; the test database URL is the Windows user variable
  `HELIX_TEST_DATABASE_URL` (never print or log it).

## Verification expectations

- Run `flutter analyze` / `dart analyze` and the relevant test suites before
  reporting work as done (see the `helix-verify` skill). From `helix_remote/`:
  `flutter analyze` (whole workspace), `dart analyze server tool`, then each
  package's `flutter test` (the full gate is `scripts/verify.ps1` / `.sh`,
  which also runs the codegen check and the governance check).
- Server tests need Postgres: set `HELIX_TEST_DATABASE_URL` and run
  `HELIX_REQUIRE_TEST_DATABASE=1 dart test --concurrency=3` in `server/`.
  Without the URL, database tests are skipped (the report says so); CI sets
  the require flag and runs a Postgres 17 service, so there they fail instead.
- Distinguish pre-existing failures from ones you introduced. Confirm by
  stashing changes and re-running, rather than assuming.
- Do not commit unexplained binary or asset changes (e.g. `logo.png` changing
  during a build). Flag them and let the user decide.

### Known pre-existing test failures

None as of 2026-10-25, after batch B12's full gate (server 524 tests on
Postgres at `--concurrency=3`, 520 green and the other four timing-sensitive
(see below); app 1044, engine 352, orbit_ui 245, api 217, admin 205, db 140,
protocol 289, crypto 78, rules 20, `helix_remote_ui` 7 (the console kit, after
its goldens left), cli 13, calls 5, domain 61; `dart analyze server tool` clean,
the format check and the governance check pass; `flutter analyze` clean apart
from whichever files another agent session has in flight). The two failures the
2026-10-20 note listed - the api route-parity table lacking `setPhoneNumber`
and `setOwnName`, and engine `calls_test.dart` "a caller the callee blocked is
told at once" - were fixed on the `orbit-ui` branch, which is now merged.

Some server tests are timing-sensitive and can fail while the machine is busy
with other test runs (they pass alone; rerun them alone before calling a failure
real): `test/platform/hardening_db_test.dart` ("sends are limited per device and
per account"), `test/client/engine/calls_test.dart` ("two callee devices
ring, one answers..."), and, seen 2026-10-09/10 under the full suite (a pool
connection not acquired, or the 30 s test timeout), `devices_test.dart`
("changing the password needs the current one..."), `messaging_test.dart`
("two engines talking at once..."), `recovery_test.dart` ("a full
recovery-code redeem...") and `cli_test.dart` ("two CLI homes exchange
messages..."): the client's password hashing runs in the server's isolate
there. `devices_test.dart` has also failed once when run alone (2026-10-14; it
failed the same way before any review batch) and passed on the next runs. Seen
2026-10-23 under the full suite at `--concurrency=3`, and green when each was
run alone: `test/client/engine/calls_test.dart` ("hang-up from either side, and
a decline") and `test/client/engine/security_test.dart` ("signed prekeys
rotate when due"). Do not run Flutter analysis or tests alongside the server suite.
The two timing budgets in `app/test/performance_budget_test.dart` can likewise
flake under load. Seen 2026-10-24 during batch B2, each green when rerun alone:
`test/modules/messaging_test.dart` ("a send that only reaches people who
blocked you pays nothing" - the token bucket refills under it during a
`--concurrency=3` run), `test/client/engine/messaging_test.dart` ("two engines
talking at once never corrupt a session" - proved pre-existing by reverting the
step's source files and rerunning at `c04bc84`: same shape, different position),
and the engine two-server group test in `test/client/engine/groups_test.dart`
(fails inside a multi-file run, passes alone in 6 s). Seen again 2026-10-24 in
the push-observability gate, each green when rerun alone: the same
`test/modules/messaging_test.dart` send, `test/modules/availability_test.dart`
("a spent stored budget refuses group sends") and
`test/client/engine/security_test.dart` ("a texted account needs a fresh phone
verification"). Seen 2026-10-25 in the B4 S5 gate, each green when rerun alone:
`test/modules/messaging_test.dart` ("every wake-up says what became of it" - the
`no_token` push line is not in the log yet) and the same `messaging_test.dart`
send again. Seen 2026-10-25 in the B4 S6 gate, green when rerun alone in 3 s:
`test/modules/groups_test.dart` ("a member removed while a send is in flight
receives nothing" - the send answered 409 `the sender is still a member` over
its 200). When another agent session is editing the server while a suite
runs, whole files can also fail to *load* on a compile error that is already
gone by the time the report is read - re-`dart analyze` the file before treating
a load failure as a result. On the app side,
`test/media/voice_composer_test.dart` ("holding and letting go sends the note
and deletes the file") failed once in a full `flutter test` on 2026-10-25 and
passed alone in 10 s; the rest of that app run (1024 tests) was green. Seen
2026-10-25 in a full app run (1050 green), and green when rerun alone:
`test/settings/theme_packs_test.dart` ("a full folder is read a few manifests
at a time, never more" - it counts concurrent reads, which load skews). Seen
2026-10-25 in the B11 gate, each green when rerun alone: `calls_test.dart`
("non-offer signals are limited per sending device", 3 s) and
`hardening_db_test.dart` ("stored idempotent responses are sealed and still
replay", 18 s). Seen 2026-10-25 in the B12 gate (520 of 524 green), each green
when rerun alone: `test/client/engine/devices_test.dart` ("changing the password
needs the current one, and the new one signs in on another device", 10 s),
`test/modules/federation_test.dart` ("remote key fetches count against the
account's limit", 21 s), the same `hardening_db_test.dart` send limit (12 s) and
the same `test/modules/messaging_test.dart` blocked-send case - which there also
failed twice as its whole file, and was green in 5 s when run by name with
nothing else on the machine, so the refill of its own token bucket is the cause
rather than anything in the file. Seen 2026-10-25 in the B13 S6 gate, and no
longer only under load: `test/client/engine/messaging_test.dart` ("two engines
talking at once never corrupt a session") failed 4 of 4 runs **alone** at the
step's code and 2 of 3 alone in a clean worktree at `f43f7a1` (before any B13
S2-S6 change), always the same shape - one device's own outgoing rows out of
order (`a8` before `a7`) when 25 sends start at once, never an undecryptable
row. It is the order check, not the session check, that fails.

Add any failure you confirm is pre-existing here, with the date.

## Working on Windows

- The shell is Git Bash. Every command prints an `ng completion` warning from
  the user's profile - ignore it.
- Heredocs containing apostrophes or `\n` break easily: write multi-line
  patches as a Python script in the scratchpad and run it.
- `tar` needs `--force-local` for `C:` paths.
- Run `dart format` only on files you changed.
- Never `robocopy /MIR` Flutter directories (it follows `.plugin_symlinks`
  into the pub cache and empties packages).
- Use a short-path worktree for big work (`git worktree add J:/wt/<name> <branch>`):
  deep `.dart_tool` paths hit the Windows path-length limit.

## Committing

- The user has asked for commits to include all uncommitted work. Stage
  deliberately and review `git status` first, since builds can leave stray
  modifications behind.
- Commit only when asked.
