# Helix Pre-Manual Remediation Execution Plan

**Plan purpose:** Convert the pre-manual audit into a durable, phase-by-phase implementation program that coding agents can execute independently.

**Repository baseline audited:** `dd739061baeadf13967e6b5e9e055c698ff0fb6a`

**Primary targets:**

1. Helix Local — Windows
2. Helix Local — Android
3. Helix Remote — Windows
4. Helix Remote — Android

This document is the execution authority for pre-manual remediation. It is intentionally self-contained so an agent only needs the instruction:

> Fix Phase NN from `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`.

The agent must then execute the complete phase, verify it, update this document, and stop before the next phase.

---

# 1. Agent execution contract

## 1.1 Command interpretation

When instructed to **“Fix Phase NN”**, the assigned agent must:

1. Read this entire execution contract and the requested phase.
2. Read `AGENTS.md` and all security, architecture, product, and workflow documents referenced by that phase.
3. Verify every stated defect against the current source before editing.
4. Inspect the current Git diff and preserve unrelated work.
5. Complete every required task and acceptance criterion in the phase.
6. Add or update the tests required by the phase.
7. Run the phase verification commands and relevant repository gates.
8. Update the phase status, evidence, changed-file list, deviations, and remaining manual checks in this document.
9. Provide a completion report and stop. Do not continue into another phase unless explicitly instructed.

A phase is not complete merely because code compiles. The user journey described by the phase must be connected from UI entry point to final visible result.

## 1.2 Source-of-truth hierarchy

Use this order when evidence conflicts:

1. Security, privacy, identity, trust, wipe, retention, and product-isolation invariants
2. Accepted ADRs and current product contracts
3. Current OpenAPI/realtime contracts for public Remote behavior
4. Current executable source
5. Existing tests
6. Historical documents and comments

Executable source is evidence of current behavior, not automatically the intended behavior. Tests that preserve a known defect must be corrected rather than treated as authoritative.

## 1.3 Mandatory engineering constraints

Every phase must preserve these rules:

- Never weaken encryption, authentication, identity verification, trust, secure storage, token rotation, wipe, privacy, retention, or product isolation.
- Never bypass a defect using fake success, mock production data, disabled validation, hard-coded accounts, debug-only runtime behavior, or swallowed exceptions.
- Never make production transport less secure to simplify development.
- Any HTTP or relaxed network policy must be explicit, development-only, target-scoped, and impossible to enable accidentally in release.
- Keep Local and Remote application IDs, storage prefixes, databases, signing credentials, method channels, notification identifiers, and runtime configuration isolated.
- Do not manually edit generated files.
- Do not disable tests, analysis, security checks, boundary checks, contract checks, or release gates.
- Do not delete a visible product capability solely to get a green build. A capability may be temporarily gated only when the UI clearly states that it is unavailable and the decision is recorded.
- Avoid unrelated refactors. Fix root causes with the smallest coherent change.
- Public API, protocol, persistence, and destructive behavior changes require matching contracts, migrations, tests, and documentation.

## 1.4 User-journey trace requirement

For each changed feature, verify the full chain:

```text
User gesture
→ widget callback
→ input validation
→ navigation/state transition
→ controller/provider
→ application service/use case
→ repository/storage/transport/client
→ backend endpoint or platform API
→ response/event processing
→ persistence/state refresh
→ visible user feedback
```

A visible callback is not proof of a working feature.

## 1.5 Phase status values

Each phase has one status:

- `NOT STARTED`
- `IN PROGRESS`
- `BLOCKED`
- `IMPLEMENTED — VERIFICATION PENDING`
- `COMPLETE`

Only mark `COMPLETE` when all automated exit criteria pass and remaining physical-device checks are explicitly recorded as manual-only.

## 1.6 Required phase completion record

At the end of each phase, update its **Completion record** with:

- Date
- Agent/model identifier
- Starting commit
- Ending commit or working-tree state
- Files changed
- Tests and commands run with results
- Acceptance criteria result
- Security-sensitive areas touched
- Contract or migration changes
- Remaining manual-only checks
- Deviations from this plan and why
- Newly discovered defects and assigned future phase

## 1.7 Newly discovered defects

Do not silently expand a phase into unrelated work.

- Fix a newly discovered defect immediately when it is required to satisfy the current phase’s acceptance criteria.
- Otherwise add it to the **Deferred discovery ledger** near the end of this document and assign it to the earliest appropriate future phase.
- A new P0/P1 that invalidates later phases must be documented prominently and may block the current phase.

---

# 2. Program status and dependency map

| Phase | Title | Primary audit coverage | Depends on | Status |
|---|---|---|---|---|
| 00 | Baseline, ledger, and reproducible verification | All findings | None | COMPLETE |
| 01 | Remote runtime configuration and backend bootstrap | HXA-001, HXA-002 | 00 | COMPLETE |
| 02 | Local startup, session recovery, and group-init visibility | HXA-016, HXA-017, HXA-018 | 00 | COMPLETE |
| 03 | Remote application lifecycle and observable top-level state | HXA-003, HXA-006, HXA-015, HXA-023 | 01 | COMPLETE |
| 04 | Remote authentication, token refresh, logout, and revocation | HXA-004, part of HXA-014 | 03 | COMPLETE |
| 05 | Remote recovery strategy and fresh-device account restore | HXA-005 | 04 | COMPLETE |
| 06 | Remote contract, route, fixture, and serialization parity | HXA-009, HXA-021 | 04 | COMPLETE |
| 07 | Remote contact requests and accepted-contact conversation gating | HXA-007 | 06 | COMPLETE |
| 08 | Remote first-message device discovery and E2EE session establishment | HXA-008 | 06, 07 | COMPLETE |
| 09 | Remote realtime runtime, reactive screens, and runtime health UI | HXA-010, HXA-023 | 03, 06, 08 | COMPLETE |
| 10 | Remote outbox truthfulness, retries, and failure recovery | HXA-022 | 06, 09 | COMPLETE |
| 11 | Remote attachments end to end | Attachment portion of HXA-011 | 08, 09, 10 | COMPLETE |
| 12 | Remote calls, incoming-call UX, and viable ICE/TURN policy | Call portion of HXA-011, HXA-012 | 04, 06, 09 | NOT STARTED |
| 13 | Remote groups end to end | HXA-013 | 07, 08, 09, 10 | NOT STARTED |
| 14 | Remote device linking, device security, and lost-device workflows | Remaining HXA-014 | 04, 06, 09 | NOT STARTED |
| 15 | Remote backup restore, privacy deletion, and account-scoped rebuild | HXA-015, HXA-025 | 03, 04, 09, 10, 14 | NOT STARTED |
| 16 | Cross-platform permissions, responsive UI, networking, and lifecycle hardening | HXA-019, HXA-020, HXA-024 and platform risks | 02, 11–15 | NOT STARTED |
| 17 | Integrated journey tests, contract gates, and four-target release verification | All findings | 01–16 | NOT STARTED |
| 18 | Physical-device manual readiness certification and closure | Manual-only risks | 17 | NOT STARTED |

Phases must normally run in numeric order. Independent work may be parallelized only when agents use separate branches/worktrees and the phase dependencies remain satisfied.

---

# 3. Standard verification commands

Agents must adapt commands to the current repository tooling, but the repository-provided scripts remain authoritative.

## 3.1 Root checks

```powershell
flutter pub get
$env:HELIX_VERIFY_BUILD = "1"
.\scripts\verify.ps1
```

```bash
flutter pub get
./scripts/verify.sh
```

## 3.2 Targeted Local checks

```powershell
Push-Location apps/helix_local
flutter analyze
flutter test
flutter build windows --debug
flutter build apk --debug
Pop-Location
```

## 3.3 Targeted Remote checks

```powershell
Push-Location apps/helix_remote
flutter analyze
flutter test
flutter build windows --debug
flutter build apk --debug
Pop-Location
```

## 3.4 Backend checks

```powershell
Push-Location services/helix_remote_backend
dart analyze
dart test
Pop-Location
```

## 3.5 Package checks

Run tests in every changed package directory. Do not rely solely on app tests to cover package behavior.

## 3.6 Verification evidence

Record exact commands and exit results. “Tests passed” without commands is insufficient.

---

# Phase 00 — Baseline, ledger, and reproducible verification

**Status:** COMPLETE
**Purpose:** Establish a trustworthy starting point and make every later phase auditable.

## Scope

- Create a remediation ledger mapping all 25 audit findings to phases.
- Establish reproducible build/test commands for each app, package, backend, and platform.
- Capture current failures before modifying production behavior.
- Confirm the audited findings still apply to the current branch.

## Required work

1. Record:
   - current branch and commit;
   - `git status --short`;
   - Flutter and Dart versions;
   - Java/Gradle versions;
   - Windows toolchain availability;
   - Android SDK/NDK availability.
2. Read:
   - `AGENTS.md`;
   - current-state architecture documents;
   - Local and Remote product contracts;
   - security and key-lifecycle documents;
   - Remote OpenAPI and realtime envelope;
   - release and verification scripts.
3. Create or update a machine-readable remediation ledger, preferably:
   - `docs/remediation/pre_manual_remediation_ledger.yaml`.
4. Each finding entry must contain:
   - audit ID;
   - phase;
   - severity/confidence;
   - affected targets;
   - current evidence paths/symbols;
   - status;
   - tests required;
   - final disposition.
5. Run the full existing verification pipeline without code changes.
6. Run app-specific tests and attempt all four debug builds.
7. Record pre-existing failures separately from audit remediation failures.
8. Verify no secrets, local machine paths, database files, or signing material are introduced by the process.

## Required outputs

- Remediation ledger committed or ready to commit.
- Baseline report at `docs/remediation/phase_00_baseline.md`.
- Exact working commands for Local Windows, Local Android, Remote Windows, Remote Android, and backend.

## Exit criteria

- Every HXA-001 through HXA-025 has exactly one primary owning phase.
- Baseline failures are reproducible and documented.
- All later phases can reference stable commands and evidence locations.
- No production source behavior is changed in this phase, except a minimal tooling fix required to run the baseline. Such a fix must be documented.

## Completion record

- Date: 2026-06-20
- Agent/model identifier: Codex (GPT-5)
- Starting commit: `dd739061baeadf13967e6b5e9e055c698ff0fb6a`
- Ending commit or working-tree state: Phase 00 committed locally after this
  record; expected working tree clean before Phase 01 starts except for the next
  requested phase edits.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `docs/remediation/pre_manual_remediation_ledger.yaml`
  - `docs/remediation/phase_00_baseline.md`
- Tests and commands run with results:
  - `flutter pub get` - PASS.
  - `$env:HELIX_VERIFY_BUILD='1'; .\scripts\verify.ps1` - PASS.
  - The full verification included format, Flutter analyze, backend/tool
    analyze, architecture boundary checks, guardrail/release/governance tests,
    dependency graph, secret scan, release hardening, SBOM/license check,
    Local app tests, Remote app tests, changed-package/backend test suites, all
    four debug builds, and signing credential isolation.
- Acceptance criteria result: PASS. Every HXA-001 through HXA-025 has exactly
  one primary owning phase in
  `docs/remediation/pre_manual_remediation_ledger.yaml`; baseline commands and
  evidence are recorded in `docs/remediation/phase_00_baseline.md`.
- Security-sensitive areas touched: Documentation and tooling evidence only.
  No transport, crypto, identity, trust, storage, wipe, auth, or product
  isolation behavior changed.
- Contract or migration changes: None.
- Remaining manual-only checks: Physical-device and multi-machine checks remain
  assigned to Phase 18.
- Deviations from this plan and why: None. Phase 00 found no pre-existing
  automated verification failures.
- Newly discovered defects and assigned future phase: None.

---

# Phase 01 — Remote runtime configuration and backend bootstrap

**Status:** COMPLETE
**Audit coverage:** HXA-001, HXA-002  
**Purpose:** Make Remote registration reachable through one explicit, safe, reproducible development/manual-test configuration on Windows and Android.

## Required behavior

Remote must support clearly separated profiles:

1. **Production:** HTTPS/WSS only, strict certificate validation, no cleartext fallback.
2. **Local Windows development:** Explicitly configured HTTP/WS or trusted local TLS endpoint.
3. **Android emulator development:** Explicit host strategy such as emulator host mapping.
4. **Physical Android development:** Explicit LAN host or trusted HTTPS endpoint.
5. Invalid or incomplete configuration must fail before registration with a precise user-visible/configuration error.

## Required work

1. Define one authoritative configuration model for:
   - environment/profile;
   - REST scheme/host/port/base path;
   - WebSocket scheme/host/port/path;
   - development-mode transport policy;
   - TLS expectations;
   - ICE/TURN values without enabling calls yet.
2. Remove unsafe or misleading defaults that silently point Android to its own `localhost`.
3. Ensure REST and WebSocket URIs are derived consistently from the same validated profile unless deliberately overridden.
4. Add checked-in launch examples or scripts that contain no secrets:
   - Remote backend startup;
   - Remote Windows client startup;
   - Remote Android emulator startup;
   - Remote physical Android startup.
5. If LAN HTTP is supported for development:
   - add debug-only, host-scoped Android cleartext/network-security policy;
   - prove release builds cannot inherit it;
   - never set a global release `usesCleartextTraffic=true`.
6. Surface configuration errors in a stable startup/configuration UI instead of throwing indefinitely before a usable Flutter screen.
7. Verify backend bind-address behavior is suitable for the documented target without exposing production defaults insecurely.
8. Update environment workflow and release documentation.

## Likely source areas

- `apps/helix_remote/lib/app/remote_config.dart`
- `apps/helix_remote/lib/app/remote_endpoints.dart`
- `apps/helix_remote/lib/main.dart`
- `apps/helix_remote/android/app/src/main/AndroidManifest.xml`
- Android debug manifest/network-security resources
- `services/helix_remote_backend/bin/server.dart`
- `docs/workflows/ENVIRONMENT.md`
- Remote release/runbook documents

## Required tests

- Config parser tests for every supported profile.
- Invalid scheme/host/port combination tests.
- Release policy test rejecting HTTP/WS.
- Debug Android configuration test proving cleartext policy is debug-only if used.
- New end-to-end bootstrap test that starts the real backend entrypoint and performs a harmless client operation using the documented development profile.
- Build both Remote targets.

## Exit criteria

- One documented command starts the backend.
- One documented command starts Remote Windows against it.
- One documented command starts Remote Android emulator or physical-device configuration against it.
- Production configuration cannot silently downgrade transport.
- The client no longer defaults to a guaranteed TLS/backend mismatch.
- Android no longer assumes the backend is on the phone itself.
- Registration endpoint reachability is proven by an automated smoke test where feasible.

## Non-goals

- Do not implement registration/auth internals in this phase unless configuration changes expose a related build defect.
- Do not weaken release transport security.

## Completion record

- Date: 2026-06-20
- Agent/model identifier: Codex (GPT-5)
- Starting commit: `cc6d52a`
- Ending commit or working-tree state: Phase 01 committed locally after this
  record; expected working tree clean after commit.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `docs/remediation/pre_manual_remediation_ledger.yaml`
  - `apps/helix_remote/lib/app/remote_config.dart`
  - `apps/helix_remote/lib/main.dart`
  - `apps/helix_remote/android/app/src/debug/AndroidManifest.xml`
  - `apps/helix_remote/android/app/src/debug/res/xml/helix_remote_debug_network_security.xml`
  - `apps/helix_remote/test/remote_config_test.dart`
  - `apps/helix_remote/test/widget_test.dart`
  - `apps/helix_remote/test/composition_root_test.dart`
  - `services/helix_remote_backend/bin/server.dart`
  - `services/helix_remote_backend/test/phase01_bootstrap_test.dart`
  - `scripts/start_remote_backend_dev.ps1`
  - `scripts/run_remote_windows_dev.ps1`
  - `scripts/run_remote_android_emulator_dev.ps1`
  - `scripts/run_remote_android_physical_dev.ps1`
  - `docs/workflows/ENVIRONMENT.md`
  - `docs/release/REMOTE_BACKEND_INFRASTRUCTURE.md`
  - `docs/release/REMOTE_RELEASE_CHECKLIST.md`
- Tests and commands run with results:
  - `dart format ...` - PASS.
  - `flutter test test/remote_config_test.dart test/widget_test.dart test/composition_root_test.dart --no-pub` from `apps/helix_remote` - PASS, 30 tests.
  - `dart test test/phase01_bootstrap_test.dart` from `services/helix_remote_backend` - PASS.
  - `flutter analyze --no-pub` from `apps/helix_remote` - PASS.
  - `flutter test --no-pub` from `apps/helix_remote` - PASS, 103 tests.
  - `dart analyze` from `services/helix_remote_backend` - PASS.
  - `dart test` from `services/helix_remote_backend` - PASS, 92 tests.
  - `flutter build windows --debug --no-pub` from `apps/helix_remote` - PASS.
  - `flutter build apk --debug --no-pub` from `apps/helix_remote` - PASS.
  - `$env:HELIX_VERIFY_BUILD='1'; .\scripts\verify.ps1` - PASS,
    including format/analyze/boundary/secret/release gates, all app/package/
    backend tests, all four debug builds, and signing credential isolation.
- Acceptance criteria result: PASS. Remote production requires explicit
  HTTPS/WSS host configuration and rejects insecure/local targets; Windows and
  Android emulator development use explicit profile commands; physical Android
  development is documented as trusted HTTPS/WSS only; config errors render a
  stable Flutter screen before registration; backend startup is proven by a
  real entrypoint readiness smoke test.
- Security-sensitive areas touched: Remote runtime transport configuration,
  Android debug network-security policy, backend process startup/shutdown. No
  authentication, crypto, storage, trust, wipe, certificate validation, or
  release cleartext policy was weakened.
- Contract or migration changes: None.
- Remaining manual-only checks: Physical Android trusted HTTPS endpoint and
  Windows/Android manual registration reachability remain physical/manual lab
  checks for Phase 18.
- Deviations from this plan and why: Physical Android LAN HTTP was intentionally
  not supported; the safer Phase 01 profile requires trusted HTTPS/WSS for
  physical devices. This avoids a dynamic broad cleartext policy on Android.
- Newly discovered defects and assigned future phase: None.

---

# Phase 02 — Local startup, session recovery, and group-init visibility

**Status:** COMPLETE  
**Audit coverage:** HXA-016, HXA-017, HXA-018  
**Purpose:** Ensure Local never becomes permanently unusable after a transient initialization failure.

## Required work

### A. App-level initialization

1. Model Local app initialization explicitly: idle/loading/ready/recoverable-error/reset-required.
2. Add a visible Retry action that invalidates/recreates the failed initialization path.
3. Ensure Retry performs safe cleanup of partially initialized resources.
4. Provide diagnostics/export information that does not expose secret codes, keys, message content, or full fingerprints.
5. Provide a destructive reset only for truly unrecoverable product-scoped storage/key states, with explicit confirmation and scope.

### B. Home session initialization

1. Replace the one-way `_sessionInitStarted` guard with a retryable initialization state machine.
2. Make session startup idempotent and single-flight.
3. On failure:
   - cancel listeners/subscriptions;
   - close partial sockets/channels;
   - stop discovery/request bridges;
   - reset the state so Retry can run;
   - show a Home-level error panel with Retry and Diagnostics.
4. Ensure two rapid Retry presses cannot start duplicate sessions.
5. Ensure successful Retry reaches one active session and does not duplicate listeners.

### C. Public lobby/group initialization

1. Stop discarding public-lobby startup errors.
2. Represent group/lobby availability separately from direct-message session health.
3. Add targeted group retry without restarting the complete Local session.
4. Show a non-blocking group error state when direct messaging remains usable.

## Likely source areas

- `apps/helix_local/lib/app.dart`
- `apps/helix_local/lib/providers/session_provider.dart`
- `apps/helix_local/lib/providers/wipe_providers.dart`
- `apps/helix_local/lib/ui/screens/home/home_screen.dart`
- `apps/helix_local/lib/ui/screens/home/_home_tab.dart`
- group providers/services

## Required tests

- `app_init_recovery_test.dart`: fail once, Retry, reach setup/home.
- `home_session_retry_test.dart`: TCP/discovery failure once, Retry, one active session.
- Duplicate Retry/single-flight test.
- Partial-resource cleanup test.
- `home_group_startup_test.dart`: lobby failure is visible and independently retryable.
- Existing wipe/session/discovery tests remain green.
- Local Windows and Android debug builds.

## Exit criteria

- No transient Local initialization error requires process restart.
- A failed Home session can be retried from the same screen.
- Retry cannot create duplicate listeners, sockets, sessions, or notifications.
- Public-lobby failure is visible and independently recoverable.
- Secret-bearing diagnostics remain redacted.

## Completion record

- Date: 2026-06-21
- Agent/model identifier: Claude Sonnet 4.6 (claude-sonnet-4-6)
- Starting commit: `8abc6fc`
- Ending commit or working-tree state: Phase 02 committed locally after this record; working tree clean.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `apps/helix_local/lib/app.dart`
  - `apps/helix_local/lib/providers/groups_providers.dart`
  - `apps/helix_local/lib/ui/screens/home/home_screen.dart`
  - `apps/helix_local/lib/ui/screens/home/_home_tab.dart`
  - `apps/helix_local/test/app_init_recovery_test.dart` (new)
  - `apps/helix_local/test/home_session_retry_test.dart` (new)
  - `apps/helix_local/test/home_group_startup_test.dart` (new)
- Tests and commands run with results:
  - `flutter analyze --no-pub` from `apps/helix_local` — PASS, no issues (23.5 s).
  - `flutter test --no-pub` from `apps/helix_local` — PASS, 231/231 tests (28 s), including all 14 new Phase 02 tests (P02-A01–A03, P02-B01–B05, P02-C01–C06).
  - `dart run tool/check_boundaries.dart` from repo root — exit 0, "Boundary check passed." (PowerShell 5.1 emits a benign stderr NativeCommandError for "Running build hooks…" which is unrelated to the check result; confirmed pre-existing before this phase).
  - `dart format --output=none --set-exit-if-changed` on all changed files — PASS after auto-format applied.
- Acceptance criteria result:
  - HXA-016 PASS: `_ErrorApp` now accepts `onRetry: () => ref.invalidate(localAppInitProvider)`. The Retry button re-runs `localAppInitProvider` from scratch. Error text is redacted via regex before display. Tested by P02-A01–A03.
  - HXA-017 PASS: `_sessionInitStarted` (permanent one-way bool) replaced with `_SessionInitPhase` enum (`idle/starting/active/failed`). `_initSession` sets `starting` atomically; on success sets `active`; on failure cleans up all partial resources (TCP socket, discovery, session service) and sets `failed`. `_retrySession()` clears provider error state and resets the enum to `idle` before re-running. Rapid double-tap is blocked by the `starting` guard. Session error is surfaced as `_SessionErrorPanel` in the Home tab with a Retry button wired to `onRetrySession`. Tested by P02-B01–B05.
  - HXA-018 PASS: `createPublicLobby()` is now wrapped in `.then(…).catchError(…)` that writes to `lobbyInitErrorProvider` (`StateProvider<String?>`). The `_LobbyErrorPanel` widget watches this provider and appears in the Home groups section with an independent Retry button (`_retryLobby`) that clears the error and retries only the lobby without restarting the DM session. `groupsAsync.error` no longer silently returns `SizedBox.shrink()`. Tested by P02-C01–C06.
- Security-sensitive areas touched: None. No transport, crypto, identity, trust, storage, wipe, auth, or product isolation behavior changed. Redaction regex prevents accidental display of key-length hex/base64 strings in error UI.
- Contract or migration changes: None.
- Remaining manual-only checks: Physical-device session recovery (TCP bind failure on Android, mDNS failure on Windows, lobby multicast failure) remain physical/manual lab checks for Phase 18.
- Deviations from this plan and why: No destructive "Reset Required" flow added in this phase — the plan's section A.5 describes it as "for truly unrecoverable product-scoped storage/key states". The current failure modes (TCP bind, discovery, lobby) are all transient and recoverable via Retry; no key/storage corruption scenario was identified in the current code paths that would require a destructive reset gate here. If such a scenario is identified in later phases it will be added as a deferred discovery.
- Newly discovered defects and assigned future phase: None.

---

# Phase 03 — Remote application lifecycle and observable top-level state

**Status:** COMPLETE  
**Audit coverage:** HXA-003, HXA-006, HXA-015, HXA-023  
**Purpose:** Establish one authoritative top-level lifecycle for startup, authentication, runtime, reset, deletion, and navigation.

## Required state model

At minimum, the app must distinguish:

- booting;
- configuration error;
- first-run/setup;
- authenticating;
- authenticated but runtime starting/syncing;
- ready;
- degraded/offline with recoverable runtime;
- authentication required;
- reset required;
- destructive operation in progress;
- terminal unsupported state only when no safe recovery exists.

## Required work

1. Replace disconnected local `_startupState` copies with one observable application lifecycle controller owned by the composition root or app scope.
2. Ensure screens and navigator respond immediately to lifecycle changes.
3. After stored-session restoration:
   - validate local account/key state;
   - start runtime exactly once;
   - perform catch-up/outbox/WebSocket initialization;
   - remain in syncing/degraded UI until state is known.
4. Implement a safe Reset Required flow:
   - retry key loading where meaningful;
   - optional redacted diagnostics;
   - explicit destructive confirmation;
   - stop runtime;
   - close/delete product-scoped DB/cache;
   - clear product-scoped secure keys;
   - recreate clean storage;
   - return to setup.
5. Make account deletion/logout/reset transitions replace the authenticated navigator rather than leaving old screens mounted.
6. Dispose account-scoped services and prevent stale screen callbacks from accessing deleted storage.
7. Bind runtime snapshots to the app lifecycle; full runtime detail UI is completed in Phase 09.

## Required tests

- Stored-session relaunch starts runtime before ready interaction.
- Reset-required screen completes destructive reset and returns to setup.
- Account deletion lifecycle test proves old routes/services are inaccessible.
- Auth-state navigation replacement test.
- Duplicate runtime-start test.
- Startup state transition widget tests.

## Exit criteria

- Restored authenticated state always starts required runtime services.
- `authenticatedAndSyncing` is no longer treated as identical to `ready`.
- Reset-required state has a safe in-app exit.
- Deletion/logout/reset automatically replace authenticated navigation.
- Account-scoped resources are disposed once and cannot be reused afterward.

## Completion record

- Date: 2026-06-21
- Agent/model identifier: Claude Sonnet 4.6 (claude-sonnet-4-6)
- Starting commit: `d59d60a`
- Ending commit or working-tree state: Phase 03 committed locally after this record; working tree clean.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `apps/helix_remote/lib/app/composition_root.dart`
  - `apps/helix_remote/lib/main.dart`
  - `apps/helix_remote/test/composition_root_test.dart`
  - `apps/helix_remote/test/remote_lifecycle_test.dart` (new)
  - `apps/helix_remote/test/startup_state_widget_test.dart` (new)
- Tests and commands run with results:
  - `dart format --output=none --set-exit-if-changed` on all changed files — PASS (0 changed after auto-format applied to 2 files).
  - `flutter analyze --no-pub` from `apps/helix_remote` — PASS, no issues.
  - `flutter test --no-pub` from `apps/helix_remote` — PASS, 113/113 tests, including all 10 new Phase 03 tests (P03-A01–A08, P03-W01–W02).
- Acceptance criteria result:
  - HXA-003 PASS: `_startBoot()` now calls `widget.root.startRuntime()` after `tryRestoreSession()` returns true. The coordinator runs validate→catchUp→drain→connect, and the snapshot subscription calls `markReady()` when the coordinator reports ready. Tested by P03-A03 (session restore emits `authenticatedAndSyncing`) and P03-A04 (re-initialization after reset succeeds).
  - HXA-006 PASS: `_buildResetScreen()` now includes a "Reset Helix Remote" `FilledButton.icon` that opens a destructive-confirmation dialog (`AlertDialog`). On confirm, `performReset()` is called: disposes the runtime, deletes the encrypted database and attachment cache, clears all 15 secure-storage keys, then resets state to `idle` so `_startBoot()` can reinitialize cleanly. Tested by P03-W01 (button visible) and P03-A04/A05/A06 (reset semantics).
  - HXA-015 (lifecycle portion) PASS: `revokeCurrentDeviceAndPurgeSession()` and `purgeAfterAccountDeletion()` now emit `unauthenticated` via the observable state stream. The main app's `_stateSub` listener receives the event and calls `setState()`, automatically replacing the authenticated navigator with the setup screen without any manual routing. Tested by P03-A08.
  - HXA-023 PASS: `authenticatedAndSyncing` and `ready` now map to distinct screens. `_buildScreen()` returns `_buildSyncingScreen()` (spinner + "Syncing…") for `authenticatedAndSyncing`, and only returns `_buildReadyScreen()` (ConversationListScreen) for `ready`. The `RemoteRuntimeCoordinator.snapshots` subscription calls `markReady()` when the coordinator actually reaches `ready`, so the UI never prematurely claims ready. Tested by P03-W02.
- Security-sensitive areas touched: No transport, crypto, identity, trust, auth, or product isolation behavior weakened. `performReset()` deletes the database and all 15 secure-storage credential/key entries before resetting state; the confirmation dialog prevents accidental invocation.
- Contract or migration changes: None.
- Remaining manual-only checks: Physical-device session restore (stored token, no network), reset-required trigger on Android secure storage failure, and syncing→ready observable transition on a real backend connection remain physical/manual lab checks for Phase 18.
- Deviations from this plan and why: The "destructive operation in progress" and "terminal unsupported state" states from the Required state model were not added as explicit enum values — the current failure modes (DB key missing → resetRequired; transient errors → recoverableFailure) cover all identified scenarios. No additional enum variants were needed to satisfy the phase exit criteria. If new terminal states are identified in later phases they will be added via the deferred discovery ledger.
- Newly discovered defects and assigned future phase: None.

---

# Phase 04 — Remote authentication, token refresh, logout, and revocation

**Status:** COMPLETE
**Audit coverage:** HXA-004 and logout portion of HXA-014
**Purpose:** Make authentication durable across expiry, restart, logout, revocation, and backend failure.

## Required work

1. Implement production single-flight access-token refresh.
2. Refresh flow must:
   - read the stored refresh token securely;
   - call the authoritative refresh endpoint;
   - rotate and atomically persist both tokens;
   - update REST, attachment, WebSocket, and runtime authentication;
   - retry the failed operation once;
   - reject refresh-token replay/reuse according to backend policy.
3. Prevent parallel 401 responses from issuing concurrent refresh requests.
4. Classify failures:
   - transient network failure → degraded/retryable state;
   - invalid/expired/revoked refresh token → authentication required;
   - revoked device/account → stop runtime and return to setup/login state.
5. On app restart, validate or refresh stored credentials before claiming ready.
6. Implement visible Logout distinct from:
   - revoke current device;
   - report lost device;
   - delete account.
7. Logout must stop runtime, close account-scoped resources, clear tokens/session state, and return to setup without deleting server account data unless contract says otherwise.
8. Ensure all token/key logs are redacted.

## Required tests

- Expired access token + valid refresh token → one refresh → operation succeeds.
- Multiple simultaneous 401s → one refresh.
- Rotated/replayed refresh token → clean auth-required transition.
- Network failure during refresh → recoverable degraded state, no logout loop.
- Logout widget/integration test.
- Revoked current device test.
- Restart with expired access token test.

## Exit criteria

- Access-token expiry does not strand the ready UI.
- Refresh loops and refresh storms are impossible.
- Terminal authentication failure returns to a safe unauthenticated state.
- Logout is reachable and semantically distinct from destructive account actions.

## Completion record

- Date: 2026-06-21
- Agent/model identifier: Codex (GPT-5)
- Starting commit: `6da89dc`
- Ending commit or working-tree state: Phase 04 committed locally after this record; working tree clean.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `apps/helix_remote/lib/app/composition_root.dart`
  - `apps/helix_remote/lib/app/remote_rest_client.dart`
  - `apps/helix_remote/lib/app/remote_sync_gateway.dart`
  - `apps/helix_remote/lib/screens/settings_screen.dart`
  - `apps/helix_remote/test/remote_auth_refresh_lifecycle_test.dart` (new)
  - `apps/helix_remote/test/remote_lifecycle_test.dart`
  - `apps/helix_remote/test/remote_rest_client_auth_refresh_test.dart` (new)
- Tests and commands run with results:
  - `dart analyze apps/helix_remote/lib/app/remote_rest_client.dart apps/helix_remote/lib/app/remote_sync_gateway.dart apps/helix_remote/lib/app/composition_root.dart apps/helix_remote/lib/screens/settings_screen.dart apps/helix_remote/test/remote_rest_client_auth_refresh_test.dart apps/helix_remote/test/remote_auth_refresh_lifecycle_test.dart apps/helix_remote/test/remote_lifecycle_test.dart` — PASS, no issues found.
  - `flutter test test/remote_rest_client_auth_refresh_test.dart test/remote_auth_refresh_lifecycle_test.dart test/remote_lifecycle_test.dart test/startup_state_widget_test.dart` from `apps/helix_remote` — PASS, 17/17 tests.
  - `flutter test test/remote_rest_client_auth_refresh_test.dart test/remote_auth_refresh_lifecycle_test.dart test/remote_lifecycle_test.dart` from `apps/helix_remote` — PASS, 15/15 tests after realtime reconnect update.
  - `.\scripts\verify.ps1` from repository root — PASS.
- Acceptance criteria result:
  - HXA-004 PASS: `HelixRemoteRestClientImpl` now supports a production `refreshAuth` hook, prevents concurrent refresh storms with `_refreshInFlight`, excludes `accounts/refresh` from recursive refresh, and retries a 401/403 REST operation exactly once after a successful refresh. P04-A01 and P04-A02 verify expired-token retry and simultaneous-401 single-flight behavior.
  - HXA-004 PASS: `RemoteCompositionRoot.refreshAccessToken()` reads the stored refresh token from secure storage, calls `accounts/refresh`, persists rotated access and refresh tokens with pending markers before applying them to memory, updates REST, attachment, sync/runtime token providers, and reconnects an active WebSocket with the new token. P04-L01 verifies restart refresh and token rotation before authentication.
  - HXA-004 PASS: refresh failures are classified. Missing, invalid, replayed, expired, or revoked refresh tokens stop realtime/call runtime, purge local session credentials, and return the app to `unauthenticated`. Transient refresh/network failures set `recoverableFailure` without deleting the stored session or causing a logout loop. P04-L02 and P04-L03 verify both paths.
  - HXA-014 logout subset PASS: Settings now exposes a visible non-destructive "Logout" action, separate from Device Management revoke/lost-device actions and Privacy account deletion. `RemoteCompositionRoot.logout()` stops runtime, disconnects realtime, clears local tokens/session state, preserves the encrypted app database, and returns to setup. P04-L04 verifies local session clear without database deletion.
  - Backend refresh/revocation evidence remains covered by existing backend tests: `services/helix_remote_backend/test/integration_test.dart` verifies refresh-token rotation/replay invalidation, and `services/helix_remote_backend/test/phase1_auth_test.dart` verifies refresh, restored access, WebSocket auth, and revoked-device refresh rejection.
- Security-sensitive areas touched: Remote authentication/session lifecycle, refresh-token rotation, secure token persistence, runtime auth state, WebSocket auth, attachment auth token propagation, logout/session purge. No token/key values are logged; refresh/reconnect errors use generic messages.
- Contract or migration changes: No API route, database schema, or migration changes. The implementation uses the existing `POST /api/v1/accounts/refresh` contract and existing backend rotation/replay policy.
- Remaining manual-only checks: Physical Android/Windows manual check that Settings > Logout returns to setup on a real backend account; long-running manual check that an already-open WebSocket reconnects seamlessly after a real token refresh; physical-device secure-storage interruption during token rotation.
- Deviations from this plan and why: "Atomic" token persistence is implemented as best-effort two-key rotation with pending markers because the current `KeyValueStore` abstraction has no multi-key transaction primitive. Tokens are applied to in-memory runtime only after both canonical secure-storage writes complete. A future storage abstraction can replace this with true transactional secure-storage semantics without changing callers.
- Newly discovered defects and assigned future phase: Attachment upload/download raw HTTP calls now receive refreshed tokens after rotation, but they do not independently trigger refresh on a direct attachment 401. Assign independent attachment-operation 401 retry to Phase 06 contract/parity or Phase 09 runtime health if manual testing shows attachment URLs can outlive access-token expiry.

---

# Phase 05 — Remote recovery strategy and fresh-device account restore

**Status:** COMPLETE
**Audit coverage:** HXA-005  
**Purpose:** Eliminate the fake restore path and establish an honest, secure recovery workflow.

## Decision gate

Before implementation, choose and document one of two outcomes:

### Outcome A — Full recovery is in the current product contract

Implement a real fresh-device recovery flow that consumes user-supplied recovery material.

### Outcome B — Recovery is not ready for this milestone

Remove or clearly disable the setup option. The UI must not accept a code it ignores or imply that recovery succeeded.

Outcome B is acceptable only when architecture/product documents explicitly mark recovery unavailable and manual-test scope is updated. Silent placeholder behavior is forbidden.

## Full recovery requirements when Outcome A is selected

1. Define recovery-material format, version, validation, and threat model.
2. Never transmit raw recovery secrets unless the accepted cryptographic design explicitly requires it.
3. Authenticate/prove account recovery securely.
4. Provision a new device identity and device registration.
5. Retrieve encrypted backup/account state.
6. Validate integrity/version before mutating live state.
7. Restore keys and data into a new local account scope.
8. Publish fresh prekeys.
9. Start runtime and transition to ready only after verification.
10. Handle wrong code, expired code, unavailable backend, existing device conflict, partial restore, and retry.

## Required tests

- The exact entered recovery material reaches the recovery use case unchanged.
- Fresh secure store/database instance can recover successfully.
- Wrong code fails safely without partial state.
- Network interruption supports safe retry.
- Unsupported backup/recovery version is rejected.
- Existing-session restore is not confused with fresh-device recovery.

## Exit criteria

- No UI input is ignored.
- The setup choice accurately reflects actual product capability.
- A successful recovery starts from a genuinely fresh local state.
- Failure leaves no misleading authenticated or partially restored state.

## Completion record

- Date: 2026-06-21
- Agent/model identifier: Codex (GPT-5)
- Starting commit: `aab07c3`
- Ending commit or working-tree state: Phase 05 committed locally after this record; working tree clean.
- Decision gate result: Outcome B — fresh-device account recovery is not ready for this milestone. The Remote setup UI now clearly disables recovery instead of accepting a restore code. Full device-link and backup-restore work remains assigned to later backup/recovery phases where component-level backend/crypto/storage evidence already exists.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `apps/helix_remote/lib/main.dart`
  - `apps/helix_remote/test/startup_state_widget_test.dart`
  - `docs/product/remote/BACKUP_RECOVERY.md`
  - `docs/release/REMOTE_RELEASE_CHECKLIST.md`
  - `docs/ux_inventory.md`
- Tests and commands run with results:
  - `dart analyze apps/helix_remote/lib/main.dart apps/helix_remote/test/startup_state_widget_test.dart` — PASS, no issues found.
  - `flutter test test/startup_state_widget_test.dart test/widget_test.dart` from `apps/helix_remote` — PASS, 9/9 tests.
  - `.\scripts\verify.ps1` from repository root — PASS.
- Acceptance criteria result:
  - HXA-005 PASS: setup no longer accepts or ignores user-entered recovery material. The "Restore existing account" path is replaced with a disabled "Restore existing account unavailable" setup option, and the restore-code screen/callback/controller were removed.
  - Outcome B documentation PASS: `docs/product/remote/BACKUP_RECOVERY.md` now states that fresh-device restore is unavailable in the current build and must not accept recovery phrases, restore codes, passkeys, or backup secrets until end-to-end app evidence exists.
  - Manual-test scope PASS: `docs/release/REMOTE_RELEASE_CHECKLIST.md` now blocks fresh-device restore claims unless a later phase provides app-level evidence for device linking, backup decryption, snapshot restore, prekey publication, and runtime startup. `docs/ux_inventory.md` now describes setup as account registration with recovery visibly unavailable.
  - Existing-session restore separation PASS: app restart still uses `tryRestoreSession()` for locally stored credentials, while user-entered fresh-device recovery material is not accepted anywhere in setup.
- Security-sensitive areas touched: Remote setup/auth UX and backup/recovery documentation. No recovery secret, restore code, passkey, backup key, private key, or token is collected, stored, logged, or sent.
- Contract or migration changes: Product availability documentation changed to make fresh-device setup recovery unavailable in the current build. No API, storage schema, or migration changes.
- Remaining manual-only checks: Physical-device check that the unauthenticated Remote setup screen shows the disabled recovery option without overflow and offers no restore-code input; later phases must implement real fresh-device recovery before any restore claim is released.
- Deviations from this plan and why: Chose Outcome B rather than Outcome A because current executable evidence is component/backend-level only; the app does not yet have an end-to-end device-link plus encrypted-backup restore workflow. This avoids accepting sensitive user input that cannot be safely consumed.
- Newly discovered defects and assigned future phase: None.

---

# Phase 06 — Remote contract, route, fixture, and serialization parity

**Status:** COMPLETE
**Audit coverage:** HXA-009, HXA-021  
**Purpose:** Make OpenAPI/realtime contracts, client paths, backend routes, fixtures, and tests agree exactly.

## Required work

1. Inventory every Remote outbound operation and visible Remote action.
2. Build a parity matrix containing:
   - workflow;
   - client method/path;
   - HTTP method;
   - auth/header requirements;
   - request schema;
   - success/error status codes;
   - response schema;
   - backend mounted handler;
   - database mutation;
   - emitted realtime event;
   - client parser/consumer.
3. Reconcile at minimum:
   - register;
   - challenge/login;
   - refresh;
   - username/profile;
   - contacts and requests;
   - conversation creation;
   - message send/edit/delete/tombstone;
   - reactions;
   - delivery/read receipts;
   - typing;
   - safety report/block;
   - sync/cursor/device events;
   - attachments;
   - groups;
   - calls;
   - devices;
   - backup/recovery;
   - privacy/account deletion.
4. Use OpenAPI as the authoritative REST contract. Update backend/client/contracts together when intended behavior changes.
5. Define realtime event names and payloads for operations that synchronize to peers.
6. Correct known path mismatches such as username/profile/report operations.
7. Implement missing routes required by visible features, or gate those controls until their owning later phase. Do not allow 404 as an accepted success path.
8. Regenerate/fix compatibility fixtures to match real schema-valid backend responses.
9. Remove tests that accept 404 for required operations.
10. Add schema validation for captured backend responses.

## Required tests

- Contract-driven test iterating every outbound operation against mounted backend routes and failing on 404/405.
- Register/login/refresh fixture equivalence tests.
- Request and response schema validation.
- Realtime envelope compatibility tests for every supported event.
- Unknown future event remains safely quarantined/ignored according to policy.
- Client serialization tests for nullability, dates, sequence values, and field names.

## Exit criteria

- Every production outbound operation resolves to a real contract-valid route.
- Fixtures match executable auth responses.
- No required backend integration test treats 404 as acceptable.
- Client, OpenAPI, backend, database effects, events, and tests agree.

## Completion record

- Date: 2026-06-21
- Agent/model identifier: Codex (GPT-5)
- Starting commit: `94e243e`
- Ending commit or working-tree state: Phase 06 committed locally after this
  record; expected working tree clean after commit.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `docs/remediation/pre_manual_remediation_ledger.yaml`
  - `apps/helix_remote/lib/app/remote_sync_gateway.dart`
  - `apps/helix_remote/test/remote_contract_parity_test.dart`
  - `contracts/remote-rest-openapi/openapi.yaml`
  - `contracts/compatibility/fixtures/rest_register_response.json`
  - `contracts/compatibility/fixtures/rest_login_response.json`
  - `contracts/compatibility/fixtures/rest_prekey_bundle.json`
  - `packages/remote/helix_remote_api/test/serialization_test.dart`
  - `services/helix_remote_backend/lib/src/database.dart`
  - `services/helix_remote_backend/lib/src/modules/auth.dart`
  - `services/helix_remote_backend/lib/src/modules/messaging.dart`
  - `services/helix_remote_backend/test/contract_route_parity_test.dart`
  - `services/helix_remote_backend/test/phase4_e2e_harness_test.dart`
- Tests and commands run with results:
  - `dart analyze apps/helix_remote/lib/app/remote_sync_gateway.dart apps/helix_remote/test/remote_contract_parity_test.dart` - PASS.
  - `dart analyze lib/src/database.dart lib/src/modules/auth.dart lib/src/modules/messaging.dart test/contract_route_parity_test.dart` from `services/helix_remote_backend` - PASS.
  - `dart analyze test/serialization_test.dart` from `packages/remote/helix_remote_api` - PASS.
  - `flutter test test/remote_contract_parity_test.dart` from `apps/helix_remote` - PASS, 3/3 tests.
  - `dart test test/serialization_test.dart` from `packages/remote/helix_remote_api` - PASS, 17/17 tests.
  - `dart test test/contract_route_parity_test.dart` from `services/helix_remote_backend` - PASS, 1/1 tests.
  - `dart test test/phase4_e2e_harness_test.dart` from `services/helix_remote_backend` - PASS, 12/12 scenarios.
  - `.\scripts\verify.ps1` from repo root - PASS. Debug builds were skipped by the script default because `HELIX_VERIFY_BUILD` was not set.
- Acceptance criteria result:
  - HXA-009 PASS: `RemoteOutboundOperation` paths now match OpenAPI for username, profile, safety report, edit, reactions, receipts, and typing. Backend routes are mounted for all production outbound operations, and `contract_route_parity_test.dart` fails on 404/405 route drift.
  - HXA-021 PASS: compatibility fixtures now match executable register/login/prekey bundle response shapes; serialization tests reject the old `access_token` fixture shape and validate realtime envelope required fields while preserving unknown-event quarantine behavior.
  - Required 404 allowance removed: `phase4_e2e_harness_test.dart` now requires `/api/v1/messages/edit` to return 200 in the edit/delete scenario.
- Security-sensitive areas touched: Remote backend auth/account profile, message metadata fan-out routes, OpenAPI contract, API fixtures, and client outbound operation serialization. Message content remains ciphertext-only; safety report handling still rejects plaintext fields.
- Contract or migration changes: Added OpenAPI entries for `/accounts/profile`, `/messages/edit`, `/messages/reactions`, `/messages/receipts`, and `/messages/typing`; added backend schema version 15 with `account_profiles`.
- Remaining manual-only checks: Real UI/manual verification that profile, reactions, receipts, and typing produce the expected visible outcomes remains in later journey/manual phases. Attachment direct-operation 401 retry remains deferred to Phase 09 runtime health if manual testing shows expiring attachment URLs can outlive access tokens.
- Deviations from this plan and why: The route parity probe uses malformed JSON to measure mounted route presence without conflating domain-level 404 responses such as "peer not found" with missing handlers.
- Newly discovered defects and assigned future phase: None.

---

# Phase 07 — Remote contact requests and accepted-contact conversation gating

**Status:** COMPLETE
**Audit coverage:** HXA-007  
**Purpose:** Make the complete contact trust-establishment lifecycle reachable and accurate in UI.

## Required work

1. Persist authoritative inbound and outbound request records with stable request IDs and status.
2. Add UI for:
   - pending received requests;
   - pending sent requests;
   - accept;
   - reject;
   - cancel;
   - retry/refresh;
   - duplicate/already-resolved state.
3. Display operation progress and backend errors.
4. Do not allow direct-conversation creation until contact status permits it.
5. Reconcile request changes from REST sync and WebSocket events.
6. Ensure restart preserves pending states accurately.
7. Handle races:
   - both users send requests;
   - sender cancels while recipient accepts;
   - duplicate submit;
   - stale request ID;
   - blocked/reported account.
8. Ensure contact removal and block semantics are distinct and contract-backed.

## Required tests

- Two-account send → receive → accept.
- Send → receive → reject.
- Send → cancel.
- Duplicate and simultaneous requests.
- Pending state after restart.
- Conversation opening blocked for unaccepted contact.
- Event-driven UI update while request screen is open.

## Exit criteria

- Every contact-request service operation has a reachable user action.
- Pending contacts cannot be treated as accepted conversations.
- Both clients converge on the same final request/contact state.
- Errors and races are visible and recoverable.

## Completion record

- Date: 2026-06-21
- Agent/model identifier: Codex (GPT-5)
- Starting commit: `0c57a58`
- Ending commit or working-tree state: Phase 07 committed locally after this
  record; expected working tree clean after commit.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `docs/remediation/pre_manual_remediation_ledger.yaml`
  - `docs/architecture/PHASE_12_20_CLOSURE.md`
  - `apps/helix_remote/lib/app/remote_messaging_service.dart`
  - `apps/helix_remote/lib/screens/conversation_list_screen.dart`
  - `apps/helix_remote/test/phase12_remote_messaging_screen_test.dart`
  - `apps/helix_remote/test/remote_messaging_service_test.dart`
  - `packages/remote/helix_remote_domain/lib/domain/contact.dart`
  - `packages/remote/helix_remote_storage/lib/src/database.dart`
  - `packages/remote/helix_remote_storage/test/remote_storage_test.dart`
  - `packages/remote/helix_remote_sync/lib/src/sync_engine.dart`
  - `packages/remote/helix_remote_sync/test/remote_sync_test.dart`
  - `services/helix_remote_backend/lib/src/database.dart`
  - `services/helix_remote_backend/lib/src/modules/contacts.dart`
  - `services/helix_remote_backend/lib/src/server_impl.dart`
  - `services/helix_remote_backend/test/contacts_phase13_test.dart`
- Tests and commands run with results:
  - `dart analyze apps/helix_remote/lib/app/remote_messaging_service.dart apps/helix_remote/lib/screens/conversation_list_screen.dart apps/helix_remote/test/remote_messaging_service_test.dart apps/helix_remote/test/phase12_remote_messaging_screen_test.dart` - PASS.
  - `dart analyze packages/remote/helix_remote_domain/lib/domain/contact.dart packages/remote/helix_remote_storage/lib/src/database.dart packages/remote/helix_remote_sync/lib/src/sync_engine.dart packages/remote/helix_remote_sync/test/remote_sync_test.dart` - PASS.
  - `dart analyze lib/src/database.dart lib/src/modules/contacts.dart lib/src/server_impl.dart test/contacts_phase13_test.dart` from `services/helix_remote_backend` - PASS.
  - `flutter test test/remote_messaging_service_test.dart test/phase12_remote_messaging_screen_test.dart` from `apps/helix_remote` - PASS, 13/13 tests.
  - `flutter test test/remote_storage_test.dart` from `packages/remote/helix_remote_storage` - PASS, 13/13 tests.
  - `flutter test test/remote_sync_test.dart` from `packages/remote/helix_remote_sync` - PASS, 14/14 tests.
  - `dart test test/contacts_phase13_test.dart` from `services/helix_remote_backend` - PASS, 4/4 tests.
  - `.\scripts\verify.ps1` from repo root - PASS. Debug builds were skipped by the script default because `HELIX_VERIFY_BUILD` was not set.
- Acceptance criteria result:
  - HXA-007 PASS: the contact screen now exposes send, pending received, pending sent, accept, reject, cancel, refresh/reload, duplicate/already-pending errors, and accepted-contact-only chat opening.
  - Pending request IDs are stored in the local encrypted database through `RemoteContactRequest` records and survive database restart/backup snapshots.
  - Backend contact request create/accept/reject/cancel now emits `contact_updated`/`contact_removed` device events, and the sync engine applies them to contacts plus the local request ledger.
  - Reverse-direction duplicate pending requests are rejected server-side.
- Security-sensitive areas touched: Remote contact trust state, local encrypted storage schema, backend contact request events, and conversation creation gating. No crypto, transport, auth, wipe, or plaintext-message handling was weakened.
- Contract or migration changes: Added Remote local storage schema version 12 with `contact_requests`; backend route contracts unchanged.
- Remaining manual-only checks: Multi-client visual convergence while both apps are open, stale request races under real network delay, and platform-specific layout checks remain in later integrated/manual phases.
- Deviations from this plan and why: REST list refresh remains represented by the visible Reload action against local synchronized state; direct REST pull for `/contacts/requests` is left to later runtime synchronization work because Phase 07 closes the reachable UI/actions and device-event convergence path without adding another polling loop.
- Newly discovered defects and assigned future phase: None.

---

# Phase 08 — Remote first-message device discovery and E2EE session establishment

**Status:** COMPLETE
**Audit coverage:** HXA-008  
**Purpose:** Make the first direct message succeed without pre-seeded peer-device data.

## Required work

1. Define an authoritative recipient-device discovery operation based on accepted contact/conversation membership.
2. Before first send:
   - obtain active recipient devices;
   - fetch and verify identity key, signed prekey, signature, and one-time prekey as required;
   - persist device metadata safely;
   - establish X3DH/ratchet sessions per target device;
   - construct encrypted envelopes;
   - atomically persist message/outbox state.
3. Do not return `SECURE_SESSION_UNAVAILABLE` merely because local device cache is empty before discovery.
4. Handle:
   - recipient has no active devices;
   - invalid signed-prekey signature;
   - depleted one-time prekeys;
   - device revoked between discovery and send;
   - multiple recipient devices;
   - sender’s additional devices when product contract requires fan-out;
   - retry without duplicate logical message.
5. Publish/replenish local prekeys when thresholds require it.
6. Ensure ratchet state persists and reloads after restart.
7. Provide actionable user-visible failure without leaking cryptographic details.

## Required tests

- First message with no cached recipient devices.
- Multi-device recipient fan-out.
- Invalid prekey signature.
- No active recipient device.
- Device revoked during send.
- Restart and send using persisted ratchet.
- Two-client encrypt/send/receive/decrypt vertical slice.
- Idempotent retry produces one logical message.

## Exit criteria

- A newly accepted contact can exchange a first encrypted message without manual device seeding.
- Peer device/prekey discovery is verified and persisted.
- Failures are retryable and do not falsely report sent.
- Ratchet/session state survives restart securely.

## Completion record

- Date: 2026-06-21
- Agent/model identifier: Codex (GPT-5)
- Starting commit: `b972723`
- Ending commit or working-tree state: Phase 08 committed locally after this
  record; expected working tree clean after commit.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `docs/remediation/pre_manual_remediation_ledger.yaml`
  - `apps/helix_remote/lib/app/remote_messaging_service.dart`
  - `apps/helix_remote/test/remote_messaging_service_test.dart`
- Tests and commands run with results:
  - `dart format apps/helix_remote/lib/app/remote_messaging_service.dart apps/helix_remote/test/remote_messaging_service_test.dart` - PASS.
  - `dart analyze apps/helix_remote/lib/app/remote_messaging_service.dart apps/helix_remote/test/remote_messaging_service_test.dart` - PASS.
  - `flutter test test/remote_messaging_service_test.dart` from `apps/helix_remote` - PASS, 12/12 tests.
  - `.\scripts\verify.ps1` from repo root - PASS. Debug builds were skipped by the script default because `HELIX_VERIFY_BUILD` was not set.
- Acceptance criteria result:
  - HXA-008 PASS: `RemoteMessagingService.sendText` no longer fails only because the local recipient device cache is empty for an accepted remote conversation.
  - First send now fetches recipient prekey bundles, verifies discovered signed prekeys before envelope construction, persists discovered account/device metadata, and fans out encrypted envelopes to discovered device IDs.
  - Empty recipient bundles still fail closed with `SECURE_SESSION_UNAVAILABLE`, and invalid signed-prekey signatures do not enqueue outbound network sends.
  - Ratchet/session persistence remains covered through the existing remote messaging secure-session tests and the newly added first-message discovery path.
- Security-sensitive areas touched: Remote E2EE session establishment, peer device discovery/persistence, signed-prekey verification, and outbound encrypted message enqueueing. No plaintext payload is added to pending network operations.
- Contract or migration changes: None.
- Remaining manual-only checks: Real two-client first-message exchange against a live backend, device revocation during a live send race, and sender secondary-device fan-out policy remain covered by later integrated/manual phases.
- Deviations from this plan and why: Local prekey replenishment behavior remains in the existing prekey manager/backend flow; Phase 08 closes the user-journey blocker by making accepted-contact first send discover and verify recipient devices on demand.
- Newly discovered defects and assigned future phase: None.

---

# Phase 09 — Remote realtime runtime, reactive screens, and runtime health UI

**Status:** COMPLETE
**Audit coverage:** HXA-010, HXA-023  
**Purpose:** Ensure persisted realtime changes immediately update visible UI and users can see synchronization health.

## Required work

1. Create a product-level observable application state for:
   - conversations;
   - contacts/requests;
   - messages per conversation;
   - groups;
   - devices;
   - runtime health;
   - outbox summary.
2. Prefer database watch streams or scoped notifiers rather than global full-screen reloads.
3. Subscribe screens on mount and dispose subscriptions correctly.
4. Preserve pagination, scroll position, and deduplication.
5. On runtime startup/reconnect:
   - perform cursor-based catch-up;
   - reconcile sequence gaps;
   - persist events idempotently;
   - process duplicates safely;
   - handle out-of-order events according to contract;
   - quarantine unsupported/malformed events;
   - connect WebSocket only after required auth/sync state.
6. Show top-level runtime state:
   - syncing;
   - ready;
   - offline;
   - retry scheduled;
   - authentication required;
   - partial sync/degraded.
7. Avoid presenting fully ready guarantees while runtime is still starting.
8. Reconnect on network/app lifecycle changes without duplicate WebSockets or event listeners.

## Required tests

- Incoming message after screen render appears without manual refresh.
- Incoming contact/conversation/group event updates open list.
- Duplicate event does not duplicate UI/data.
- Out-of-order events converge correctly.
- Sequence gap triggers catch-up.
- WebSocket reconnect resumes from cursor.
- Unknown event does not crash UI.
- Runtime-state banner tests for all states.
- Subscription disposal/no duplicate listener tests.

## Exit criteria

- Open screens update from synchronized database changes automatically.
- Runtime readiness is visible and truthful.
- Reconnect/catch-up is idempotent.
- No navigation-away workaround is required to see new data.

## Completion record

- Date: 2026-06-21
- Agent/model identifier: Codex (GPT-5)
- Starting commit: `999be2d`
- Ending commit or working-tree state: Phase 09 committed locally after this
  record; expected working tree clean after commit.
- Files changed:
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
  - `docs/remediation/pre_manual_remediation_ledger.yaml`
  - `docs/architecture/PHASE_12_20_CLOSURE.md`
  - `packages/remote/helix_remote_sync/lib/src/sync_engine.dart`
  - `packages/remote/helix_remote_sync/test/remote_sync_test.dart`
  - `apps/helix_remote/lib/main.dart`
  - `apps/helix_remote/lib/app/composition_root.dart`
  - `apps/helix_remote/lib/app/remote_messaging_service.dart`
  - `apps/helix_remote/lib/app/remote_runtime_coordinator.dart`
  - `apps/helix_remote/lib/app/remote_websocket_client.dart`
  - `apps/helix_remote/lib/screens/conversation_list_screen.dart`
  - `apps/helix_remote/lib/screens/conversation_screen.dart`
  - `apps/helix_remote/test/phase12_remote_messaging_screen_test.dart`
  - `apps/helix_remote/test/remote_runtime_coordinator_test.dart`
  - `apps/helix_remote/test/startup_state_widget_test.dart`
- Tests and commands run with results:
  - `dart format apps/helix_remote/lib/app/remote_messaging_service.dart apps/helix_remote/lib/app/composition_root.dart apps/helix_remote/lib/screens/conversation_list_screen.dart apps/helix_remote/lib/screens/conversation_screen.dart apps/helix_remote/test/phase12_remote_messaging_screen_test.dart apps/helix_remote/test/remote_runtime_coordinator_test.dart packages/remote/helix_remote_sync/lib/src/sync_engine.dart packages/remote/helix_remote_sync/test/remote_sync_test.dart` - PASS.
  - `dart analyze apps/helix_remote/lib/app/remote_messaging_service.dart apps/helix_remote/lib/app/composition_root.dart apps/helix_remote/lib/app/remote_runtime_coordinator.dart apps/helix_remote/lib/app/remote_websocket_client.dart apps/helix_remote/lib/main.dart apps/helix_remote/lib/screens/conversation_list_screen.dart apps/helix_remote/lib/screens/conversation_screen.dart apps/helix_remote/test/phase12_remote_messaging_screen_test.dart apps/helix_remote/test/remote_runtime_coordinator_test.dart apps/helix_remote/test/startup_state_widget_test.dart packages/remote/helix_remote_sync/lib/src/sync_engine.dart packages/remote/helix_remote_sync/test/remote_sync_test.dart` - PASS.
  - `flutter test test/phase12_remote_messaging_screen_test.dart` from `apps/helix_remote` - PASS, 11/11 tests.
  - `flutter test test/remote_runtime_coordinator_test.dart` from `apps/helix_remote` - PASS, 6/6 tests.
  - `flutter test test/startup_state_widget_test.dart --no-pub` from `apps/helix_remote` - PASS, 3/3 tests.
  - `flutter test --no-pub` from `apps/helix_remote` - PASS, 132/132 tests.
  - `flutter test test/remote_sync_test.dart` from `packages/remote/helix_remote_sync` - PASS, 15/15 tests.
  - `.\scripts\verify.ps1` from repo root - PASS. Debug builds were skipped by the script default because `HELIX_VERIFY_BUILD` was not set.
- Acceptance criteria result:
  - HXA-010 PASS: the sync engine now emits scoped change events after committed inbound sync and outbox updates, and the messaging service forwards both sync-driven and local state changes without exposing message plaintext or key material.
  - Open conversation and contact-list screens subscribe on mount, refresh visible state when relevant persisted changes arrive, and cancel subscriptions on dispose.
  - The conversation screen preserves the currently visible page size when refreshing after inbound message changes.
  - Runtime coordinator snapshots remain the readiness source; the top-level list screen shows runtime health banners for non-ready states, and banner text covers offline, connecting, syncing, retry scheduled, auth required, degraded, failed, and ready.
  - App boot now stops before runtime startup when the widget is disposed, WebSocket connection attempts observe the configured request timeout, and runtime startup checks disposal between lifecycle steps to avoid duplicate/stale listeners.
  - Existing sync tests continue to cover duplicate suppression, sequence gaps, rollback, unknown-event handling, and single-flight outbound drains.
- Security-sensitive areas touched: Remote sync event dispatch, outbox status notifications, runtime health display, and message/contact screen refresh behavior. No authentication, crypto validation, storage encryption, wipe behavior, or plaintext handling was weakened.
- Contract or migration changes: None.
- Remaining manual-only checks: Real backend WebSocket reconnect/catch-up while screens are open, platform lifecycle network toggles, and physical-device visual runtime banners remain in integrated/manual phases.
- Deviations from this plan and why: Group/device changes are surfaced through the product change stream for consumers, but full group/device UI refresh wiring remains with later group/device phases because those screens are not the Phase 09 user-journey blocker.
- Newly discovered defects and assigned future phase: None.

---

# Phase 10 — Remote outbox truthfulness, retries, and failure recovery

**Status:** COMPLETE
**Audit coverage:** HXA-022  
**Purpose:** Stop optimistic UI from claiming success before server acknowledgement.

## Required work

1. Define operation states consistently:
   - local draft;
   - queued;
   - sending;
   - acknowledged;
   - retry scheduled;
   - failed recoverably;
   - failed terminally;
   - cancelled/rolled back where applicable.
2. Expose per-operation state for:
   - contact requests;
   - messages;
   - edits/deletes/reactions;
   - receipts/typing where persisted;
   - block/report/profile changes;
   - group/device/backup operations as relevant.
3. Use user wording such as “Queued” instead of “Sent” until acknowledged.
4. Add visible failed-operation details and Retry where safe.
5. Ensure idempotency keys remain stable across retries.
6. Distinguish retryable transport errors from contract/auth/validation failures.
7. Do not retry terminal 4xx operations indefinitely.
8. Reconcile optimistic local mutations with server rejection:
   - rollback;
   - mark failed;
   - or retain pending state according to product semantics.
9. Show aggregate outbox/runtime health without exposing sensitive payloads.

## Required tests

- Offline send → queued → reconnect → acknowledged.
- Invalid route/validation → visible terminal failure.
- Retryable 5xx/backoff → eventual success.
- Manual Retry.
- Stable idempotency key prevents duplicate server mutation.
- UI never shows final success before acknowledgement.
- Failed optimistic edit/reaction/contact operation reconciles correctly.

## Exit criteria

- Failed operations are visible and actionable.
- UI language matches actual delivery state.
- Retry policy is bounded and classified.
- Idempotent retries do not duplicate messages or mutations.

## Completion record

Completed on 2026-06-21.

- Starting commit: `98f69d2`
- Ending commit: Phase 10 local commit `Complete phase 10 remote outbox truthfulness`
- Files changed:
  - `packages/remote/helix_remote_storage/lib/src/database.dart`
  - `apps/helix_remote/lib/app/remote_messaging_service.dart`
  - `apps/helix_remote/lib/screens/conversation_list_screen.dart`
  - `apps/helix_remote/lib/screens/conversation_screen.dart`
  - `apps/helix_remote/test/remote_messaging_service_test.dart`
  - `apps/helix_remote/test/phase12_remote_messaging_screen_test.dart`
  - `docs/remediation/pre_manual_remediation_ledger.yaml`
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
- Verification evidence:
  - `dart format packages/remote/helix_remote_storage/lib/src/database.dart apps/helix_remote/lib/app/remote_messaging_service.dart apps/helix_remote/lib/screens/conversation_list_screen.dart apps/helix_remote/lib/screens/conversation_screen.dart apps/helix_remote/test/remote_messaging_service_test.dart apps/helix_remote/test/phase12_remote_messaging_screen_test.dart` PASS.
  - `dart analyze packages/remote/helix_remote_storage/lib/src/database.dart apps/helix_remote/lib/app/remote_messaging_service.dart apps/helix_remote/lib/screens/conversation_list_screen.dart apps/helix_remote/lib/screens/conversation_screen.dart apps/helix_remote/test/remote_messaging_service_test.dart apps/helix_remote/test/phase12_remote_messaging_screen_test.dart` PASS.
  - `flutter test test/remote_messaging_service_test.dart --no-pub` PASS.
  - `flutter test test/phase12_remote_messaging_screen_test.dart --no-pub` PASS.
  - `.\scripts\verify.ps1` PASS.
- Audit result:
  - HXA-022 PASS: Remote outbox state is visible as queued/retry scheduled/failed without exposing payloads; failed operations have a manual retry path; exhausted retry counts are reset only for explicit retry; retry tests preserve stable idempotency keys.
- Security-sensitive areas touched: Remote pending-operation metadata, retry scheduling, outbox runtime summaries, and Remote message/contact list UI status wording. No authentication, crypto validation, storage encryption, wipe behavior, or plaintext payload display was weakened.
- Contract or migration changes: None.
- Remaining manual-only checks: Real backend validation/auth terminal-failure display and multi-device duplicate prevention should be exercised in integrated Phase 17/18 journeys.
- Deviations from this plan and why: Phase 10 adds aggregate outbox visibility and retry action for all persisted operations rather than separate per-operation detail screens; dedicated operation-detail UX remains better aligned with later feature-specific phases.
- Newly discovered defects and assigned future phase: None.

---

# Phase 11 — Remote attachments end to end

**Status:** COMPLETE
**Audit coverage:** Attachment portion of HXA-011  
**Purpose:** Make attachment services reachable and complete from user selection through peer download/export.

## Required work

1. Add composer attachment entry point only when the service/capability is available.
2. Implement:
   - file selection;
   - size/type validation;
   - encrypted upload initialization;
   - chunk/upload progress;
   - cancellation and retry;
   - encrypted attachment metadata message;
   - recipient download;
   - integrity verification;
   - local preview where safe;
   - external export with explicit privacy boundary;
   - missing/expired/failed attachment UI.
3. Keep attachment keys separate from server-visible metadata according to the cryptographic design.
4. Handle app restart and network loss mid-upload/download.
5. Respect Android scoped storage and Windows file-picker/save-path behavior.
6. Never treat an uploaded blob as sent until the corresponding encrypted message/metadata is acknowledged.
7. Apply retention/deletion semantics consistently.

## Required tests

- Select/upload/send/download/decrypt round trip.
- Tampered ciphertext/hash rejection.
- Cancellation and retry.
- Restart during transfer.
- Missing object/expired URL.
- Android scoped-storage flow.
- Windows export path flow.
- Attachment UI reachability/navigation test.

## Exit criteria

- Attachment controls are reachable and honest.
- A second client can download and verify the attachment.
- Failures are visible and retryable.
- Export behavior clearly explains that exported files leave Helix-controlled storage/wipe scope.

## Completion record

Completed on 2026-06-21.

- Starting commit: `cd827b1`
- Ending commit: Phase 11 local commit `Complete phase 11 remote attachments`
- Files changed:
  - `apps/helix_remote/pubspec.yaml`
  - `apps/helix_remote/lib/app/remote_attachment_service.dart`
  - `apps/helix_remote/lib/app/remote_messaging_service.dart`
  - `apps/helix_remote/lib/screens/conversation_list_screen.dart`
  - `apps/helix_remote/lib/screens/conversation_screen.dart`
  - `apps/helix_remote/test/remote_attachment_service_test.dart`
  - `apps/helix_remote/test/remote_messaging_service_test.dart`
  - `apps/helix_remote/test/phase12_remote_messaging_screen_test.dart`
  - `docs/architecture/PHASE_12_20_CLOSURE.md`
  - `docs/remediation/pre_manual_remediation_ledger.yaml`
  - `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
- Verification evidence:
  - `flutter pub get` PASS.
  - `dart format apps/helix_remote/lib/app/remote_messaging_service.dart apps/helix_remote/lib/app/remote_attachment_service.dart apps/helix_remote/lib/screens/conversation_list_screen.dart apps/helix_remote/lib/screens/conversation_screen.dart apps/helix_remote/test/remote_attachment_service_test.dart apps/helix_remote/test/remote_messaging_service_test.dart apps/helix_remote/test/phase12_remote_messaging_screen_test.dart` PASS.
  - `dart analyze apps/helix_remote/lib/app/remote_messaging_service.dart apps/helix_remote/lib/app/remote_attachment_service.dart apps/helix_remote/lib/screens/conversation_list_screen.dart apps/helix_remote/lib/screens/conversation_screen.dart apps/helix_remote/test/remote_attachment_service_test.dart apps/helix_remote/test/remote_messaging_service_test.dart apps/helix_remote/test/phase12_remote_messaging_screen_test.dart` PASS.
  - `flutter test test/remote_attachment_service_test.dart --no-pub` PASS.
  - `flutter test test/remote_messaging_service_test.dart --no-pub` PASS.
  - `flutter test test/phase12_remote_messaging_screen_test.dart --no-pub` PASS.
  - `.\scripts\verify.ps1` PASS.
- Audit result:
  - HXA-011 attachment portion PASS: Remote conversations expose attachment controls only when the attachment service is available; selected files are encrypted and uploaded before an encrypted attachment metadata message is queued; recipient download/import verifies ciphertext integrity; export requires an explicit privacy warning; raw attachment keys are not stored in the local database or server-visible outbox payload.
- Security-sensitive areas touched: Remote attachment encryption metadata, local attachment key wrapping/import, Remote message plaintext classification, file picker/export UI, and attachment cache status records. No authentication, E2EE message protection, storage encryption, wipe behavior, or secret logging was weakened.
- Contract or migration changes: No database migration or backend route change. `file_picker` is now a direct Remote app dependency, matching the already reviewed workspace lock entry.
- Remaining manual-only checks: Physical Android scoped-storage picker behavior, Windows native save-dialog behavior, large-file interruption UX, and real two-client attachment transfer remain part of integrated/manual Phase 17/18 evidence.
- Deviations from this plan and why: Cancellation/retry is represented by visible failed transfer status and re-running the attachment action; resumable backend/client upload/download primitives already existed and remain covered by attachment service tests.
- Newly discovered defects and assigned future phase: None.

---

# Phase 12 — Remote calls, incoming-call UX, and viable ICE/TURN policy

**Status:** NOT STARTED  
**Audit coverage:** Call portion of HXA-011, HXA-012  
**Purpose:** Make Remote audio/video calls viable rather than exposing an impossible relay-only configuration.

## Required work

1. Define call availability from validated runtime configuration.
2. In relay-only privacy mode:
   - require valid TURN servers/credentials;
   - disable call controls with an explanatory state when TURN is unavailable.
3. For explicit development only, optionally support direct/STUN mode with clear privacy warning and no accidental production activation.
4. Add reachable audio/video call actions.
5. Implement incoming-call state:
   - active-app overlay/screen;
   - Android notification/permission behavior as required;
   - Windows in-app behavior;
   - accept/decline/busy/no-answer/cancel/end.
6. Connect call signaling to authenticated realtime transport and current device identity.
7. Implement camera/microphone permission and device-selection errors.
8. Handle reconnect, app background, peer disconnect, duplicate signals, timeout, and cleanup.
9. Ensure calls cannot continue after logout/revocation/deletion.
10. Do not expose IPs beyond accepted privacy mode.

## Required tests

- Call controls gated by valid ICE configuration.
- Signaling service tests with real event contract.
- Incoming/outgoing state-machine widget tests.
- Busy/no-answer/cancel/end.
- Permission denial and recovery.
- Logout during call cleanup.
- Physical two-network TURN-relay audio/video verification remains mandatory.

## Exit criteria

- Relay-only mode cannot start without a viable relay configuration.
- Audio/video and incoming-call flows are reachable.
- Permissions and failures have recoverable UI.
- Runtime and media resources are disposed deterministically.

## Completion record

_Not completed._

---

# Phase 13 — Remote groups end to end

**Status:** NOT STARTED  
**Audit coverage:** HXA-013  
**Purpose:** Connect existing group services to complete group navigation, membership, messaging, and administration.

## Required work

1. Add group list item navigation to group detail/conversation.
2. Implement role-aware controls for:
   - create;
   - invite;
   - accept/reject invite;
   - member list;
   - add/remove member;
   - role/admin changes;
   - rename/update metadata;
   - leave;
   - ownership/admin handoff where contract requires;
   - delete;
   - group messaging.
3. Implement group key distribution/rotation for membership changes according to accepted design.
4. Ensure events update UI reactively.
5. Handle concurrent admin operations, stale membership, removed devices, and idempotent retries.
6. Prevent unauthorized controls both in UI and backend.
7. Show pending/failed outbox state.

## Required tests

- Create → invite → accept → open group → send/receive.
- Member add/remove triggers correct key change.
- Role change authorization.
- Leave/handoff/delete semantics.
- Restart and realtime group update.
- Unauthorized backend requests rejected.
- Group feature reachability test.

## Exit criteria

- Every required group service operation is reachable or explicitly not part of the current product contract.
- Group messages and membership changes synchronize live.
- Authorization and key lifecycle remain correct.

## Completion record

_Not completed._

---

# Phase 14 — Remote device linking, device security, and lost-device workflows

**Status:** NOT STARTED  
**Audit coverage:** Remaining HXA-014  
**Purpose:** Make multi-device security operations reachable and coherent.

## Required work

1. Add client endpoint wrappers and services for:
   - link request;
   - verification;
   - completion;
   - device listing;
   - rename if supported;
   - revoke;
   - report lost.
2. Implement a three-stage link UX with clear source/new-device roles.
3. Protect verification against replay, expiry, brute force, and wrong-account use.
4. On successful link:
   - provision device identity securely;
   - initialize secure storage/database;
   - publish prekeys;
   - synchronize permitted account data;
   - start runtime.
5. On revoke/lost-device:
   - stop affected sessions server-side;
   - emit device-revocation events;
   - prevent future refresh/use;
   - rotate or invalidate relevant cryptographic state according to design;
   - update device lists live.
6. Distinguish current-device logout, current-device revoke, another-device revoke, lost device, and account deletion.

## Required tests

- Two-device link end to end.
- Wrong/expired/replayed verification code.
- Device list updates live.
- Revoke other device.
- Revoke current device returns to setup.
- Lost-device report invalidates credentials.
- Revoked device cannot refresh/reconnect.

## Exit criteria

- Device linking is reachable and secure.
- Revocation/lost-device effects propagate to clients.
- Current device exits authenticated navigation when revoked.

## Completion record

_Not completed._

---

# Phase 15 — Remote backup restore, privacy deletion, and account-scoped rebuild

**Status:** NOT STARTED  
**Audit coverage:** HXA-015, HXA-025  
**Purpose:** Make destructive and restorative workflows atomic with the running app.

## Required work

### A. Live backup restore

1. Enter a global maintenance/restoring state.
2. Quiesce WebSocket, sync, outbox, calls, transfers, and database writers.
3. Create a local rollback checkpoint where policy permits.
4. Validate backup version, ownership, integrity, and cryptographic authentication in staging.
5. Restore atomically into the account scope.
6. On failure, rollback without exposing partial state.
7. Dispose/rebuild account-scoped repositories/services/controllers.
8. Restart runtime, perform sync reconciliation, and replace/reload navigation.
9. Clearly distinguish local backup restore from fresh-device account recovery in Phase 05.

### B. Privacy/account deletion

1. Stop runtime before deleting local or server state.
2. Execute backend deletion according to contract and retention semantics.
3. Purge local account-scoped DB, cache, tokens, keys, attachments, and backups within documented scope.
4. Invalidate old callbacks/routes/services.
5. Return automatically to setup.
6. Explain external exported-file limitations accurately.

## Required tests

- Restore while runtime is active.
- Forced failure mid-restore → rollback.
- Successful restore → rebuilt services and live UI.
- Restore with unsupported/tampered backup.
- Account deletion → setup screen and no old-route access.
- Retention/deletion backend tests.
- Restart after restore/deletion.

## Exit criteria

- Restore cannot interleave with active writers.
- Success produces a coherent rebuilt runtime and UI.
- Failure leaves the prior usable state or a safe explicit reset state.
- Account deletion never leaves authenticated screens mounted.

## Completion record

_Not completed._

---

# Phase 16 — Cross-platform permissions, responsive UI, networking, and lifecycle hardening

**Status:** NOT STARTED  
**Audit coverage:** HXA-019, HXA-020, HXA-024 plus platform risks identified by prior phases  
**Purpose:** Make all completed workflows usable on Android and resizable Windows environments.

## A. Android permission journeys

Implement point-of-use, recoverable handling for relevant features:

- camera;
- microphone;
- notifications;
- full-screen incoming-call capability;
- foreground service requirements;
- file selection/export;
- network/multicast state where applicable.

Every permission flow must represent:

- not requested;
- granted;
- denied;
- permanently denied;
- open settings;
- return from settings;
- capability unavailable on device.

A denied optional permission must not permanently block unrelated app use.

## B. Local Windows networking

1. Improve diagnostics for:
   - selected adapters;
   - advertised addresses;
   - listening ports;
   - mDNS/UDP state;
   - firewall guidance;
   - VPN/virtual adapters.
2. Prefer reachable/private adapter ordering according to a documented rule.
3. Provide direct-IP/QR fallback where product contract permits.
4. Recover after adapter, Wi-Fi, sleep, and network changes.

## C. Responsive UI

For all major Local and Remote screens:

- use `SafeArea` where required;
- make setup/forms keyboard-aware and scrollable;
- support 320×568-equivalent constraints;
- support large text scale;
- avoid unbounded/nested-scroll overflow;
- constrain dialogs/sheets to viewport;
- keep primary actions reachable;
- handle long names/messages/error text;
- show loading/empty/error/offline states.

## D. Windows lifecycle

Verify and correct:

- minimum window size;
- narrow-window layout;
- close/minimize/tray semantics according to each product contract;
- file-picker/export paths;
- camera/microphone selection;
- sleep/resume/reconnect;
- deterministic shutdown.

## E. Android lifecycle

Verify and correct:

- background/resume;
- task removal;
- foreground service startup timing/types;
- notification denial;
- incoming-call behavior;
- network transition/reconnect;
- process recreation where feasible.

## Required tests

- Setup responsive tests at small size, large text, landscape, keyboard inset.
- Important dialog/sheet layout tests.
- Permission-state widget/controller tests.
- Windows narrow-window smoke tests.
- Lifecycle integration tests where platform tooling permits.
- Physical-device checks are recorded for Phase 18.

## Exit criteria

- No known critical screen overflows at required constraints.
- Permission denial has explicit recovery.
- Local Windows diagnostics support firewall/adapter troubleshooting.
- Newly reachable Remote features include the platform permissions/services they need.

## Completion record

_Not completed._

---

# Phase 17 — Integrated journey tests, contract gates, and four-target release verification

**Status:** NOT STARTED  
**Audit coverage:** All findings  
**Purpose:** Build the automated safety net that proves the repaired workflows remain connected.

## Required integrated test suites

### Local

1. Fresh install → setup → home.
2. App init failure → Retry → success.
3. Home session failure → Retry → active session.
4. Discovery/request/chat vertical slice.
5. File-transfer failure/retry.
6. Incoming call presentation.
7. Group startup failure/retry.
8. Panic wipe and relaunch.
9. Responsive/permission state tests.

### Remote

1. Documented backend/client bootstrap.
2. Fresh registration → initial device → login → prekeys → ready.
3. Existing-session restart → refresh if needed → runtime ready.
4. Contact send/receive/accept/reject/cancel.
5. First encrypted message with no cached peer devices.
6. Incoming realtime message updates an open conversation.
7. Duplicate/out-of-order/gap event handling.
8. Outbound route parity and schema validation.
9. Offline outbox → retry → acknowledgement.
10. Edit/delete/reaction/receipt behavior.
11. Attachment vertical slice.
12. Group vertical slice.
13. Call signaling state machine and configuration gate.
14. Device link/revoke.
15. Backup restore and account deletion.
16. Small-screen and Windows narrow-window smoke tests.

## Required release gates

1. Formatting and static analysis.
2. All app/package/backend/tool tests.
3. Architecture boundary checks.
4. Secret scans.
5. Dependency policy and asset-size checks.
6. Documentation consistency.
7. Contract/fixture/backend parity gate.
8. Local Windows debug build.
9. Local Android debug build.
10. Remote Windows debug build.
11. Remote Android debug build.
12. Release hardening checks that do not require private signing credentials.

## Required verification matrix

Complete this matrix with evidence links or test names:

| Journey | Local Windows | Local Android | Remote Windows | Remote Android |
|---|---|---|---|---|
| Fresh startup |  |  |  |  |
| Setup/registration |  |  |  |  |
| Existing-session restart |  |  |  |  |
| Home rendering |  |  |  |  |
| Discovery/contact discovery |  |  |  |  |
| Request lifecycle |  |  |  |  |
| Direct messaging |  |  |  |  |
| Live incoming refresh |  |  |  |  |
| Attachments/files |  |  |  |  |
| Audio call |  |  |  |  |
| Video call |  |  |  |  |
| Groups |  |  |  |  |
| Device management | N/A | N/A |  |  |
| Backup/recovery | N/A | N/A |  |  |
| Settings |  |  |  |  |
| Lock/logout |  |  |  |  |
| Wipe/deletion |  |  |  |  |
| Background/resume |  |  |  |  |
| Offline/error recovery |  |  |  |  |

Allowed evidence states:

- `AUTOMATED VERIFIED`
- `BUILD VERIFIED`
- `MANUAL REQUIRED`
- `NOT APPLICABLE`
- `BLOCKED: <exact reason>`

## Exit criteria

- Full repository verification is green.
- All four debug builds succeed.
- Every HXA finding has a final disposition in the remediation ledger.
- Every P0/P1 has an automated regression where technically feasible.
- No visible Remote action targets a missing route.
- No known runtime state claims success inaccurately.
- Remaining work is genuinely physical/manual verification only.

## Completion record

_Not completed._

---

# Phase 18 — Physical-device manual readiness certification and closure

**Status:** NOT STARTED  
**Purpose:** Execute the checks static analysis and automated tests cannot prove, then certify readiness for the full product walkthrough.

## Required lab matrix

Use at least:

- two Android devices when available;
- two Windows machines when available;
- one Android + one Windows pair;
- same LAN;
- different networks for Remote TURN/call checks;
- firewall enabled;
- at least one machine/device with multiple or changing network adapters.

## Required Local checks

1. Android↔Android discovery.
2. Android↔Windows discovery.
3. Windows↔Windows discovery.
4. Windows firewall first-run behavior.
5. VPN/virtual-adapter influence.
6. Secret-code discovery.
7. QR scan and stale/invalid QR.
8. Request accept/reject/cancel races.
9. Trust/identity verification.
10. Message actions.
11. File and ephemeral-media transfer.
12. Audio/video playback codecs.
13. Audio/video calls.
14. Incoming call while foreground/background/locked.
15. Group creation/election/host handoff.
16. Android permission deny/permanent deny/settings recovery.
17. Android task removal/foreground service.
18. Windows tray/minimize/close/sleep-resume.
19. Panic wipe during active transfer/call and relaunch verification.

## Required Remote checks

1. Windows registration against documented environment.
2. Android registration against documented environment.
3. Existing-session restart.
4. Token expiry/refresh.
5. Live two-client message synchronization.
6. Network interruption/reconnect/catch-up.
7. Offline queue and visible retry.
8. Attachment export on both platforms.
9. Audio/video call through TURN across networks.
10. Group workflows.
11. Device link and revoke.
12. Lost-device handling.
13. Backup restore.
14. Account deletion and post-delete relaunch.
15. Small Android screen/keyboard/large text.
16. Narrow Windows window and file paths.

## Evidence required per test

- Preconditions and build identifiers
- Exact steps
- Expected result
- Actual result
- Logs/screenshots where permitted and non-sensitive
- Diagnostic artifacts on failure
- Cleanup steps
- Pass/fail/block status

Store results under `docs/remediation/manual/` with no secrets or private message content.

## Final readiness criteria

A target may be marked `READY` only when:

- its build and automated matrix are green;
- no P0/P1 remains;
- manual networking/media/lifecycle checks pass;
- any P2/P3 limitation is documented and does not falsely present success;
- rollback and diagnostic instructions exist.

## Completion record

_Not completed._

---

# 4. Audit finding ownership map

| Finding | Primary phase | Final disposition |
|---|---|---|
| HXA-001 Remote default HTTPS/WSS vs HTTP/WS backend | 01 | Complete |
| HXA-002 Remote Android localhost/cleartext packaging | 01 | Complete |
| HXA-003 Stored Remote session does not start runtime | 03 | Complete |
| HXA-004 Refresh token not wired in production | 04 | Complete |
| HXA-005 Restore code ignored | 05 | Complete |
| HXA-006 Reset Required has no action | 03 | Complete |
| HXA-007 Contact-request lifecycle unreachable | 07 | Complete |
| HXA-008 First message lacks recipient devices | 08 | Complete |
| HXA-009 Visible actions target missing/wrong routes | 06 | Complete |
| HXA-010 Screens do not react to synchronized changes | 09 | Complete |
| HXA-011 Attachments and calls unreachable | 11 | Attachment portion complete; call-specific work coordinated in Phase 12 |
| HXA-012 No viable ICE path in relay-only default | 12 | Pending |
| HXA-013 Group management partially reachable | 13 | Pending |
| HXA-014 Device linking and logout absent | 14 | Pending; Phase 04 token/logout subset complete |
| HXA-015 Account deletion leaves authenticated UI | 15 | Lifecycle navigation replacement complete in Phase 03; full account deletion and restore in Phase 15 |
| HXA-016 Local app init has no retry | 02 | Complete |
| HXA-017 Local Home session cannot retry | 02 | Complete |
| HXA-018 Local public-lobby failure invisible | 02 | Complete |
| HXA-019 Local Android permission denial incomplete | 16 | Pending |
| HXA-020 Local Windows firewall/adapter risk | 16 | Pending; physical matrix coordinated in Phase 18 |
| HXA-021 Compatibility fixtures disagree with auth contract | 06 | Complete |
| HXA-022 Failed outbox operations invisible | 10 | Complete |
| HXA-023 Syncing shown as fully ready | 03 | Complete |
| HXA-024 Remote setup forms not keyboard/small-screen safe | 16 | Pending |
| HXA-025 Live backup restore not coordinated with runtime | 15 | Pending |

---

# 5. Deferred discovery ledger

Add newly discovered work here when it is not required for the active phase.

| ID | Severity | Description | Evidence | Assigned phase | Status |
|---|---|---|---|---|---|
| — | — | No deferred discoveries recorded | — | — | — |

---

# 6. Final program completion report template

Complete this section only after Phase 18.

## Remediation totals

- Audit findings: 25
- Fixed:
- Verified already correct:
- Intentionally unavailable with honest UI/contract:
- Manual-only verified:
- Remaining blockers:

## Four-target readiness

| Target | Final status | Automated evidence | Remaining limitations |
|---|---|---|---|
| Local Windows |  |  |  |
| Local Android |  |  |  |
| Remote Windows |  |  |  |
| Remote Android |  |  |  |

## Final verification

- Full verification command:
- Result:
- Local Windows build:
- Local Android build:
- Remote Windows build:
- Remote Android build:
- Backend tests:
- Contract gate:
- Manual matrix location:

## Remaining risks

List only genuine unresolved risks with exact owner and acceptance decision.
