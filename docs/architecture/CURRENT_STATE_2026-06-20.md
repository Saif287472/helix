# Current State Evidence Ledger - 2026-06-20

This ledger is the Phase 0 evidence baseline for the enterprise improvement
cycle. It classifies executable behavior only. A class, package, or checklist
entry is not counted as implemented unless the app wiring path and tests prove
it.

## Classification Key

| Status | Meaning |
|---|---|
| Verified | Production wiring and tests prove the behavior. |
| Component-only | Code and tests exist, but app wiring or an end-to-end path is missing. |
| Defective | Code exists but has a confirmed correctness, security, privacy, or data-loss defect. |
| Missing | No meaningful implementation or test exists. |
| External gate | Requires external infrastructure, signing, store validation, or independent review. |

## Local Product

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Product shell and app namespace | Verified | `apps/helix_local/android/app/build.gradle.kts`; `tool/phase20_release_governance_test.dart` | Uses `com.helix.local` and product-scoped release signing inputs. |
| Local package boundary isolation | Verified | `docs/architecture/module_boundaries.json`; `tool/check_boundaries.dart`; `tool/boundary_test.dart` | Local app must not import `packages/remote/**`. |
| LAN identity/session contracts | Verified | `packages/local/helix_local_domain`; `docs/workflows/IDENTITY_SESSION.md`; Local tests under `apps/helix_local/test` | Local identity remains install-scoped and Local-classified. |
| LAN protocol fixtures | Verified | `packages/local/helix_local_protocol`; `scripts/verify.ps1`; protocol tests | Protocol fixture checks are in the verification pipeline. |
| Local crypto primitives | Verified | `packages/local/helix_local_crypto`; `packages/local/helix_local_transport` tests | Local crypto is product-specific and must not be reused by Remote without review. |
| Secure LAN transport | Verified | `packages/local/helix_local_transport`; `apps/helix_local/test/phase7_test.dart` | Boundary and test coverage exist; future decomposition is Phase 7 work. |
| mDNS LAN discovery | Verified | `packages/local/helix_local_discovery`; `docs/workflows/DISCOVERY.md`; Local app tests | Android re-enable behavior still has Phase 7 repair work but the LAN-only discovery path exists. |
| Ephemeral messaging and storage policy | Verified | `packages/local/helix_local_messaging`; `packages/local/helix_local_storage/test`; `docs/workflows/STORAGE_WIPE.md` | Local message content is RAM-only by product contract; storage tests cover scoped persistent data. |
| Panic wipe and scoped deletion | Verified | Local wipe/storage tests; `docs/release/LOCAL_PRIVACY_VERIFICATION_CHECKLIST.md` | Wipe behavior is security-sensitive and must stay product-scoped. |
| Local calls and file transfer | Verified | `packages/local/helix_local_calls`; `packages/local/helix_local_transfer`; workflow docs | LAN-only behavior exists with Local signaling; no Remote reuse. |
| Local provider/composition simplification | Component-only | `apps/helix_local/lib/providers/app_providers.dart`; `apps/helix_local/lib/app/local_composition_root.dart` | Phase 7 will consolidate construction ownership and remove static fallbacks. |

## Remote Client

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Product shell and app namespace | Verified | `apps/helix_remote/android/app/build.gradle.kts`; `tool/phase20_release_governance_test.dart` | Uses `com.helix.remote` and product-scoped signing inputs. |
| Remote package boundary isolation | Verified | `docs/architecture/module_boundaries.json`; `tool/check_boundaries.dart`; `tool/boundary_test.dart` | Remote app and packages must not import Local packages. |
| Remote UI data model | Defective | `apps/helix_remote/lib/main.dart`; `docs/architecture/PHASE_12_20_CLOSURE.md` | UI remains an in-memory demo and does not call Remote services for auth, messaging, sync, backup, or privacy flows. |
| Remote composition root | Component-only | `apps/helix_remote/lib/app/composition_root.dart`; `apps/helix_remote/test` | Wires storage/key/sync basics, but concrete REST, realtime, messaging, attachments, calls, groups, backup, and privacy services are incomplete or disconnected. |
| Account registration/login | Defective | `apps/helix_remote/lib/app/composition_root.dart`; `services/helix_remote_backend/lib/src/modules/auth.dart`; `HELIX_ENTERPRISE_IMPROVEMENT_MASTER_PLAN.md` R-001/R-002 | Key roles and device identifiers are inconsistent; Phase 1 owns this fix. |
| Remote REST DTOs and compatibility fixtures | Component-only | `packages/remote/helix_remote_api`; `contracts/compatibility`; API tests | DTO tests exist, but contract generation and route-level parity are incomplete. |
| WebSocket transport | Defective | `apps/helix_remote/lib/app/remote_config.dart`; backend WebSocket route | Client path/scheme and query-token behavior are inconsistent with backend safety goals. |
| Remote persistent storage | Component-only | `packages/remote/helix_remote_storage/lib/src/database.dart`; `packages/remote/helix_remote_storage/test/remote_storage_test.dart` | P2-01 verifies SQLCipher-backed local DB encryption, wrong-key failure, binary marker absence, plaintext migration, and rollback. UI/service use remains broader Remote wiring work. |
| Remote sync/outbox | Component-only | `packages/remote/helix_remote_sync`; sync tests | Sync engine exists, but lifecycle/reconnect driving and atomic batch guarantees are incomplete. |
| Remote crypto sessions and E2EE messaging | Defective | `packages/remote/helix_remote_crypto`; `apps/helix_remote/lib/app/remote_messaging_service.dart`; crypto tests | X3DH/ratchet pieces exist, but key roles, fail-closed policy, persisted sessions, and full Double Ratchet behavior are not proven. |
| Remote attachments | Defective | `apps/helix_remote/lib/app/remote_attachment_service.dart`; backend attachment tests | Upload/download components exist; raw key fallback and cache semantics need Phase 5 repair. |
| Remote backup | Defective | `apps/helix_remote/lib/screens/backup_screen.dart` | Declared encryption does not protect the uploaded snapshot. |
| Remote privacy/account deletion | Component-only | `services/helix_remote_backend/test/privacy_compliance_test.dart`; Remote app privacy screen | Backend purge path has tests; app-side local cleanup/wiring remains incomplete. |
| Remote calls | Component-only | `packages/remote/helix_remote_calls`; `apps/helix_remote/lib/app/composition_root.dart` | Service package exists, but concrete engine/lifecycle is not production-wired. |
| Remote groups | Defective | `packages/remote/helix_remote_groups`; group tests | Deterministic fallback key behavior and sync endpoint mapping require repair before use. |

## Remote Backend

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Backend language/runtime | Verified | `services/helix_remote_backend/pubspec.yaml`; `docs/adr/019-dart-shelf-backend-authoritative.md` | Dart/Shelf modular monolith is authoritative for this cycle. |
| Modular HTTP routing | Component-only | `services/helix_remote_backend/lib/src/server_impl.dart`; backend tests | Routes and modules exist; production config, migration, and contract parity remain Phase 1+ work. |
| Auth/session backend | Defective | `services/helix_remote_backend/lib/src/modules/auth.dart`; auth tests | Backend currently verifies the registered device key as a signing key; key-role split is Phase 1. |
| Messaging backend | Component-only | `services/helix_remote_backend/lib/src/modules/messaging.dart`; backend tests | Message endpoints exist; transactional outbox atomicity and realtime consistency need repair. |
| Contacts/privacy/presence backend | Component-only | backend modules and tests; `docs/architecture/PHASE_12_20_CLOSURE.md` | Backend behavior is tested in isolation but not wired through the app. |
| Attachment backend | Component-only | `services/helix_remote_backend/lib/src/modules/attachments.dart`; backend tests | Local filesystem/storage path exists; object storage is target-state only. |
| Backup/privacy backend | Component-only | privacy compliance tests | Server-visible export/deletion behavior exists; client flow is disconnected. |
| Production PostgreSQL/Redis/S3/metrics | Missing | `docs/architecture/remote_backend_architecture.md`; `docs/adr/019-dart-shelf-backend-authoritative.md` | These are target-state ideas, not implemented infrastructure. |
| External crypto/security review | External gate | `docs/security/EXTERNAL_SECURITY_REVIEW_GATE.md`; `docs/security/REMOTE_SECURITY_AND_COMPLIANCE.md` | Strong production security claims remain blocked. |

## Tooling And Guardrails

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Monorepo secret scan | Verified | `tool/check_secrets.dart`; `tool/secret_scan_test.dart` | Defaults cover `.github`, `apps`, `packages`, `services`, `contracts`, `tool`, `scripts`, docs, and root configs. |
| Boundary and dependency package discovery | Verified | `tool/check_boundaries.dart`; `tool/dep_graph.dart`; `tool/boundary_test.dart` | Package resolution comes from root workspace pubspecs and fails unclassified packages. |
| Strict analyzer baseline | Verified | `analysis_options.yaml`; `apps/helix_remote/analysis_options.yaml` | Remote app inherits the root strict baseline. |
| Dependency pinning and lockfile policy | Verified | workspace `pubspec.yaml` files; `docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md`; `tool/dependency_policy_test.dart` | Direct `any` dependencies are banned; EOL/prerelease lockfile risks are documented. |
| Documentation consistency | Verified | `docs/adr/019-dart-shelf-backend-authoritative.md`; `tool/documentation_consistency_test.dart` | Stale Go/Chi and SQLCipher claims are guarded by tests. |
| CI consolidation | Verified | `.github/workflows/ci.yml`; `scripts/verify.ps1`; `scripts/verify.sh`; release/governance tests | One CI workflow owns checks; duplicate workflow removed. |
| Risk-based coverage reporting | Component-only | `docs/quality/RISK_BASED_COVERAGE.md`; `tool/risk_coverage_test.dart` | Phase 0 establishes the reporting gate and scenario inventory; later phases add deeper branch artifacts for repaired modules. |

## Phase 0 Exit Notes

- No Remote feature work was started in this phase.
- The evidence baseline deliberately marks several Remote paths defective or
  component-only despite existing classes and isolated tests.
- PostgreSQL, Redis, S3, SQLCipher, production observability, staging, signing,
  and external security review remain future or external gates unless executable
  evidence is added in later phases.
