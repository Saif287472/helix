# Phase 9–11 Closure and Repair Audit

**Date:** 2026-06-19  
**Auditor:** Closure pass (automated + manual code inspection)  
**Branch:** master, commit after Phase 6

---

## Methodology

Every classification below is based on **executable code inspection** and **test evidence**, not on Markdown documents or checkbox state. The master plan is amended separately to match this audit.

Classification key:

| Status | Meaning |
|---|---|
| **VERIFIED COMPLETE** | Production implementation exists, tests prove behavior, CI would catch regressions |
| **PARTIALLY IMPLEMENTED** | Code exists but is incomplete, missing critical paths, or not proven by negative tests |
| **PLACEHOLDER** | Interface or stub only; no meaningful implementation |
| **UNVERIFIED** | Code exists but no tests prove the claimed behavior |
| **BLOCKED** | Cannot be completed without an external dependency, human reviewer, or infrastructure not yet available |
| **NOT STARTED** | No code or test file exists |

---

## Phase 9 — Remote Cryptographic and Identity Security Gate

### 9.1 Design and Protocol Selection

| ID | Item | Status | Evidence | Risk | Required Repair |
|---|---|---|---|---|---|
| P9-001 | Cryptographic design review | **VERIFIED COMPLETE** | `docs/security/remote_cryptographic_design_review.md` (9 KB, covers X3DH, DR, groups, attachments, backups) | Low | None |
| P9-002 | Evaluate mature maintained implementations | **PARTIALLY IMPLEMENTED** | `docs/adr/012-remote-e2ee-protocol-selection.md` records `cryptography` Dart package; no formal comparison of alternatives; no libsignal binding evaluated | Medium | Update ADR to confirm platform availability of `cryptography` v6+; note absence of reviewed DR library |
| P9-003 | X3DH session establishment — implementation | **PARTIALLY IMPLEMENTED** | `packages/remote/helix_remote_crypto/lib/src/x3dh.dart` implements DH math correctly; **signed prekey signature verification is completely absent** from `initiateSession()`; no `bobSignedPrekeySignature` parameter exists | **CRITICAL** | Add Ed25519 signature verification before DH computation; add negative tests |
| P9-004 | Per-message ratchet — implementation | **PARTIALLY IMPLEMENTED** | `packages/remote/helix_remote_crypto/lib/src/double_ratchet.dart` implements a symmetric KDF chain only; **no DH ratchet**, no root key evolution, no ratchet key headers, no out-of-order support, no skipped-key storage, no replay detection; **state advances before authentication on decrypt** (CRITICAL) | **CRITICAL** | Fix decrypt-before-auth immediately; BLOCK full DR until reviewed Dart implementation exists |
| P9-005 | Offline prekey model | **UNVERIFIED** | Design documented; backend `PrekeysModule` stores prekeys; **atomic one-time prekey consumption under concurrency is not tested** | High | Add concurrency test (Scenario I) |
| P9-006 | Identity key and device key hierarchy | **PARTIALLY IMPLEMENTED** | Design review specifies separate IK_A (Ed25519 signing) and IK_D (X25519 DH); **implementation conflates both into a single X25519 key pair** with no Ed25519 identity key present | High | Separate identity signing key from DH key; or explicitly document the decision to merge them |
| P9-007–P9-018 | Device linking, key-change UX, revocation, group strategy, attachment, backup, metadata, replay, duplicates, versioning, rotation, lost device | **UNVERIFIED** | Design decisions are documented; no application-level implementation or integration test for any of these lifecycle events | Medium–High | Classify as design-complete, not implementation-complete |

### 9.2 Tests and Test Vectors

| ID | Item | Status | Evidence | Risk | Required Repair |
|---|---|---|---|---|---|
| P9-019 | Test vectors | **PARTIALLY IMPLEMENTED** | `packages/remote/helix_remote_crypto/test/remote_crypto_test.dart`: 7 tests pass (X3DH shared secret, encrypt/decrypt, group, attachment, backup, key storage); **no negative tests for wrong key, wrong signature, state isolation on auth failure** | High | Add Scenario A and B tests (see below) |
| P9-020 | Cross-platform interoperability tests | **PLACEHOLDER** | No cross-platform test harness; no comparison with Signal or other reference implementation | High | Mark BLOCKED until a reference implementation is available |
| P9-021 | Malformed-ciphertext and downgrade tests | **PARTIALLY IMPLEMENTED** | One malformed-ciphertext test exists; **state-preservation after auth failure is not tested**; no downgrade test | High | Add auth-failure-state test; add downgrade rejection test |
| P9-022 | Secure key storage adapters | **PARTIALLY IMPLEMENTED** | `RemoteSecureKeyStorage` with prefix isolation exists; 1 test passes; **no platform adapter test for Android or Windows; no rotation or revocation tests** | Medium | Add rotation and deletion tests |
| P9-023 | Backend stores no private keys or plaintext | **PARTIALLY IMPLEMENTED** | Backend stores ciphertext fields only; `messages.text` column name misleadingly holds ciphertext; **no physical byte test confirming absence of plaintext sentinel** | Medium | Add Scenario C physical byte test; rename column |
| P9-024 | Independent external review | **BLOCKED** | No external reviewer has reviewed this codebase. Cannot be self-certified. | Blocker | Engage reviewer when implementation is stable |

### Phase 9 Summary

- **Verified complete:** P9-001
- **Partially implemented:** P9-002, P9-003 (critical), P9-004 (critical), P9-005, P9-006, P9-007–P9-018, P9-019, P9-021, P9-022, P9-023
- **Placeholder:** P9-020
- **Blocked:** P9-024

---

## Phase 10 — Remote Backend Core

### 10.1 Account and Device Management

| ID | Item | Status | Evidence | Risk | Required Repair |
|---|---|---|---|---|---|
| P10-001 | Account registration | **PARTIALLY IMPLEMENTED** | `AuthModule._registerHandler` exists; no input-size limits; no test for duplicate registration behavior | Medium | Add registration tests |
| P10-002 | Authentication / session tokens | **PARTIALLY IMPLEMENTED** | JWT-based challenge/login flow implemented; challenge nonces are stored in-memory (lost on restart) | Medium | Persist challenges; add expiry |
| P10-003 | Refresh-token rotation | **PARTIALLY IMPLEMENTED** | `/refresh` endpoint exists; **reuse detection is not implemented** | High | Add reuse detection test |
| P10-004–P10-006 | Device registration, listing, revocation | **PARTIALLY IMPLEMENTED** | Endpoints exist; no device-revocation-invalidates-sessions behavior | Medium | Implement session invalidation on revoke |
| P10-007 | Public key / prekey publication | **PARTIALLY IMPLEMENTED** | `PrekeysModule` `/publish` and `/bundle` exist; **signed prekey signature is stored but not verified server-side** | High | Add server-side signature verification |
| P10-008 | Account recovery policy | **UNVERIFIED** | No recovery flow; placeholder only | High | Design and implement |
| P10-009 | Brute-force and credential-stuffing controls | **PARTIALLY IMPLEMENTED** | `RateLimiter` (token bucket) exists and is wired; **no per-IP or per-account limiting, only global** | Medium | Add per-account and per-IP limiter |
| P10-010 | Audit events with no sensitive content | **UNVERIFIED** | No structured audit logging; `print()` statements throughout | Medium | Replace with structured audit logging |

### 10.2 Messaging Substrate

| ID | Item | Status | Evidence | Risk | Required Repair |
|---|---|---|---|---|---|
| P10-011–P10-017 | Conversation, message storage, sequence, idempotent send, mailbox, delivery ack, cursor | **PARTIALLY IMPLEMENTED** | `MessagingModule` exists (345 lines); idempotency key check exists; **no foreign key between messages and conversations enforced in backend DB; no server-sequence uniqueness constraint** | High | Add DB constraints; add idempotency tests |
| P10-018 | Tombstone events | **PARTIALLY IMPLEMENTED** | Tombstone table in backend DB; event dispatched; **not propagated to WebSocket subscribers atomically** | Medium | Fix outbox-to-WebSocket flow |
| P10-019 | Transactional outbox | **PARTIALLY IMPLEMENTED** | `OutboxWorker` exists; **sending a message and creating its outbox record is NOT in a single DB transaction** (verified by code inspection of `MessagingModule`) | **CRITICAL** | Wrap message insert + outbox insert in one transaction |
| P10-020–P10-023 | Push worker, quotas, rate limits, blocking | **PARTIALLY IMPLEMENTED** | Push worker is mock-only; quota and blocking stubs exist | Medium | Mark as NOT PRODUCTION READY |

### 10.3 Operations and Infrastructure

| ID | Item | Status | Evidence | Risk | Required Repair |
|---|---|---|---|---|---|
| P10-024 | Database migrations | **NOT STARTED** | `BackendDatabase` has one-shot `_onInit()`; no versioned migration framework | High | Add migration framework |
| P10-025 | Local development stack | **NOT STARTED** | No `docker-compose.yml`, no local setup scripts | Medium | Add compose file for local dev |
| P10-026 | Automated integration tests | **PARTIALLY IMPLEMENTED** | `services/helix_remote_backend/test/integration_test.dart` exists; **not part of canonical verify pipeline** | High | Wire into `scripts/verify.ps1` |
| P10-027 | Staging deployment | **BLOCKED** | No deployment infrastructure; no actual deployment evidence | Blocker | Cannot self-certify; mark BLOCKED |
| P10-028 | Secret management | **PARTIALLY IMPLEMENTED** | JWT secret injected via `JWT_SECRET` env var; default is a development constant visible in `server.dart` (not hardcoded in production, but risky) | Medium | Document rotation; confirm no default in CI |
| P10-029 | TLS configuration | **UNVERIFIED** | Not implemented in server code; expected to be handled by reverse proxy; not documented | Medium | Document TLS strategy |
| P10-030 | Metrics, logs, traces | **NOT STARTED** | `print()` only; no structured observability | Medium | Design and implement |
| P10-031 | Backup and restore test | **NOT STARTED** | No backup mechanism | Medium | Implement and test |
| P10-032 | Dependency and container scanning | **NOT STARTED** | Not in CI | Medium | Add to CI |
| P10-033 | API load test baseline | **NOT STARTED** | No load test tooling or baseline | Low | Create minimal baseline |
| P10-034 | Incident response runbook | **NOT STARTED** | No runbook | Low | Author runbook |

### Phase 10 Summary

- **Partially implemented:** P10-001–P10-009, P10-011–P10-020
- **Unverified:** P10-008, P10-010, P10-029
- **Not started:** P10-024, P10-025, P10-030, P10-031, P10-032, P10-033, P10-034
- **Blocked:** P10-027

---

## Phase 11 — Remote Client Persistence and Synchronization

### 11.1 Encrypted Database

| ID | Item | Status | Evidence | Risk | Required Repair |
|---|---|---|---|---|---|
| P11-001 | Remote-only encrypted local database | **REPAIRED IN P2-01** | `HelixRemoteDatabase` now requires SQLCipher for keyed opens, rejects wrong keys, migrates plaintext files with copy/integrity/swap/rollback, and has binary marker tests in `remote_storage_test.dart` | Low | Continue platform build verification; broader Remote session/E2EE work remains Phase 2 |
| P11-002 | Schema separated from Local | **VERIFIED COMPLETE** | Separate package `helix_remote_storage`; no Local tables | Low | None |
| P11-003–P11-012 | Account, device, contact, conversation, member, message, revision, reaction, receipt, attachment, group, call history tables | **PARTIALLY IMPLEMENTED** | Tables exist in `_onCreate()`; **no reaction, receipt, or processed_event_ids tables**; `messages.text` stores ciphertext (misleading column name); **no encryption enforced** | High | Add missing tables; rename `text` → `ciphertext_blob` |
| P11-013 | Sync cursors | **PARTIALLY IMPLEMENTED** | `sync_cursors` table exists; scoped per `conversation_id`; design review implies global account/device stream | Medium | Clarify scope; add global cursor support if required |
| P11-014 | Pending operations | **PARTIALLY IMPLEMENTED** | `pending_operations` table exists; **missing `next_attempt_at` and `idempotency_key` columns** | High | Add columns; update schema |
| P11-015 | Tombstones | **PARTIALLY IMPLEMENTED** | `tombstones` table exists; checked in sync engine | Low | None immediately |
| P11-016 | Indexes and pagination | **PARTIALLY IMPLEMENTED** | One index on `messages(conversation_id, server_sequence)`; **no tombstone index, no pending_operations scheduling index** | Medium | Add indexes |
| P11-017 | Migration rollback/recovery policy | **NOT STARTED** | `_applyMigrations()` only sets `user_version = 1` with no schema migration steps; no transaction; no rollback | High | Implement proper migration framework |
| P11-018 | Corruption detection and safe recovery | **NOT STARTED** | No `PRAGMA integrity_check`; no typed corruption error; silent fallback possible | High | Add integrity check; add typed error |
| P11-019 | Backup/restore tests | **NOT STARTED** | No backup mechanism for Remote client DB | Medium | Implement and test |

> P2-01 update, 2026-06-20: P11-001 is repaired after this closure snapshot.
> `HelixRemoteDatabase` now requires SQLCipher for keyed opens, rejects wrong
> keys, migrates plaintext files with copy/integrity/swap/rollback, and has
> binary marker plus crash-injection tests in `remote_storage_test.dart`.

### 11.2 Synchronization Engine

| ID | Item | Status | Evidence | Risk | Required Repair |
|---|---|---|---|---|---|
| P11-020 | Outbound operation queue | **PARTIALLY IMPLEMENTED** | Queue table and `enqueueOperation`/`processOutboundQueue` exist; **missing `idempotency_key` and `next_attempt_at` columns** | High | Add columns; add Scenario E test |
| P11-021 | Stable client-generated operation IDs | **PARTIALLY IMPLEMENTED** | `op_id` column exists; no uniqueness constraint in schema | Medium | Add UNIQUE constraint |
| P11-022 | Retry with exponential backoff and jitter | **PARTIALLY IMPLEMENTED** | Basic retry logic exists; **jitter is described in comments but not implemented** (no random); **backoff computes from `created_at` not last failure time**; no `next_attempt_at` persistence | High | Fix backoff; add real jitter; add Scenario F test |
| P11-023 | Inbound cursor-based sync | **PARTIALLY IMPLEMENTED** | Cursor tracked per conversation; events fetched since cursor; basic deduplication | Medium | None immediately beyond atomicity fix |
| P11-024 | Atomic application of event batches | **PARTIALLY IMPLEMENTED** | **Events are processed one-by-one with individual cursor updates; the batch is NOT wrapped in a single transaction** | **CRITICAL** | Wrap batch in single BEGIN/COMMIT; add Scenario D test |
| P11-025 | Duplicate suppression | **PARTIALLY IMPLEMENTED** | Sequence-based dedup; **no event-ID uniqueness constraint in DB** | Medium | Add unique constraint on event IDs |
| P11-026–P11-027 | Ordering and conflict | **PARTIALLY IMPLEMENTED** | Sort by sequence on fetch; no conflict resolution logic | Medium | Document and test ordering scope |
| P11-028 | Tombstone handling | **PARTIALLY IMPLEMENTED** | Tombstone checked before message insert; cursor still advances for tombstoned items | Low | None immediately |
| P11-029 | Offline-first read | **UNVERIFIED** | DB reads are available offline; no test | Low | Add offline read test |
| P11-030–P11-033 | Reconnect, background limits, network change, clock skew | **NOT STARTED** | No implementation beyond the engine itself | Medium | Implement and test |
| P11-034 | Sync health diagnostics | **NOT STARTED** | No diagnostics interface | Low | Design and implement |
| P11-035 | No plaintext in sync logs | **PARTIALLY IMPLEMENTED** | `kDebugMode` guard exists; **event IDs and sequence numbers are still logged** in debug mode; these are not plaintext messages but are still metadata | Low | Suppress event IDs from debug logs |

### Phase 11 Summary

- **Verified complete:** P11-002
- **Partially implemented:** P11-003–P11-016, P11-020–P11-028, P11-035
- **Unverified:** P11-029
- **Not started:** P11-017, P11-018, P11-019, P11-030–P11-034
- **Repaired after closure:** P11-001 (P2-01 SQLCipher-backed Remote DB)

---

## Critical Defects Requiring Immediate Repair

These are code-level defects — not design gaps — that must be repaired before any production path proceeds:

### DEFECT-1: Decrypt-Before-Auth in DoubleRatchetSession
**File:** `packages/remote/helix_remote_crypto/lib/src/double_ratchet.dart:42-60`  
**Severity:** CRITICAL  
`receivingChainKey` is mutated before `aesGcm.decrypt()` is called. An authentication failure leaves the session in a permanently corrupt state. Original state must be preserved if decryption fails.

### DEFECT-2: Decrypt-Before-Auth in GroupSenderChain
**File:** `packages/remote/helix_remote_crypto/lib/src/group_encryption.dart:44-68`  
**Severity:** CRITICAL  
Same pattern: `chainKey` is advanced before `aesGcm.decrypt()`. An authentication failure corrupts the sender chain permanently.

### DEFECT-3: No Signed Prekey Signature Verification in X3DH
**File:** `packages/remote/helix_remote_crypto/lib/src/x3dh.dart:11-69`  
**Severity:** CRITICAL  
`initiateSession()` accepts `bobSignedPrekey` as a raw public key with no Ed25519 signature parameter and no verification step. The design review (Section 3, Step 2) states "Alice verifies Bob's SPK_Bob signature against Bob's Account Identity Key IK_A_Bob" — this step is completely missing. A man-in-the-middle can substitute an arbitrary signed prekey.

### DEFECT-4: Remote Database is Not Encrypted
**File:** `packages/remote/helix_remote_storage/lib/src/database.dart:16`  
**Severity:** CRITICAL  
The original defect was that `PRAGMA key = '$password'` executed against standard SQLite and was silently ignored, leaving database content plaintext.
**Status: RESOLVED IN P2-01** — Remote database-at-rest encryption now has SQLCipher-backed implementation and tests.

**P2-01 update, 2026-06-20:** DEFECT-4 is resolved for Remote local
database-at-rest encryption with SQLCipher-backed `sqlite3` hooks, runtime
SQLCipher detection, wrong-key failure, plaintext migration, integrity checks,
and rollback tests.

### DEFECT-5: Sync Batch Not Atomic
**File:** `packages/remote/helix_remote_sync/lib/src/sync_engine.dart:27-87`  
**Severity:** HIGH  
Events are applied one-by-one with individual cursor updates. A crash mid-batch leaves the cursor and data in an inconsistent state.

### DEFECT-6: Retry Backoff Not Persisted
**File:** `packages/remote/helix_remote_sync/lib/src/sync_engine.dart:101-108`  
**Severity:** HIGH  
Backoff computes `created_at + backoffMs`, not from last failure time. No `next_attempt_at` column persists the deadline across process restarts. A restarted process will immediately retry regardless of backoff state.

### DEFECT-7: Outbox–Message Transaction
**File:** `services/helix_remote_backend/lib/src/modules/messaging.dart`  
**Severity:** HIGH  
Message insertion and outbox record creation are separate operations. A crash between them creates a message with no outbox entry (delivery silently lost) or an orphaned outbox entry.

### DEFECT-8: Local Wipe False Success
**File:** `apps/helix_local/lib/application/wipe/local_panic_wipe_orchestrator.dart`  
**Severity:** MEDIUM  
`WipeResult.succeeded` is `errors.isEmpty`, which returns `true` when `phase == partialFailure` if the errors list was somehow cleared. It should check `phase == WipePhase.complete`. File deletions silently swallow errors.

---

## Missing Tables / Schema Gaps

| Gap | Location | Impact |
|---|---|---|
| `next_attempt_at` column | `pending_operations` (Remote client) | Retry backoff not persisted |
| `idempotency_key` column | `pending_operations` (Remote client) | No server-side duplicate prevention |
| `processed_event_ids` table | Remote client DB | No event-ID uniqueness enforcement |
| Reaction / receipt tables | Remote client DB | Phase 11 model claims incomplete |
| Backend migration framework | Backend DB | No upgrade path for production |
| `UNIQUE` on `op_id` | `pending_operations` | Duplicate enqueue possible |
| `ciphertext_blob` / rename `text` | `messages` table | Misleading plaintext column name |

---

## CI and Verification Gaps

| Gap | Impact |
|---|---|
| `scripts/verify.ps1` does not run backend tests | Backend regressions go undetected |
| `scripts/verify.ps1` does not run `helix_remote_api` or `helix_remote_domain` package tests | Package regressions go undetected |
| `database_migration_test.dart` lacks Windows sqlite3 DLL loading setup | 7 migration tests fail on Windows in CI |
| `protocol_fixtures_test.dart` fixtures file missing | Fixtures test fails on every run |
| No CI job for Remote crypto package | Crypto regressions go undetected |
| No CI job for Remote storage package | Storage regressions go undetected |
| No CI job for Remote sync package | Sync regressions go undetected |

---

## Baseline Test Results (2026-06-19, commit bc2650e)

| Suite | Command | Pass | Fail | Notes |
|---|---|---|---|---|
| flutter analyze | `flutter analyze` | ✓ No issues | — | Clean |
| Secret scan | `dart run tool/check_secrets.dart` | ✓ Passed | — | Clean |
| Boundary check | `dart run tool/check_boundaries.dart` | ✓ Passed | — | Clean |
| Local app tests | `flutter test apps/helix_local/test/` | 173 | 9 | 7 = native SQLite3 DLL loading in migration tests; 1 = missing fixtures file; 1 = widget smoke test |
| Remote app tests | `flutter test apps/helix_remote/test/` | 7 | 0 | Composition root + placeholder UI only |
| Remote crypto tests | `flutter test packages/remote/helix_remote_crypto/test/` | 7 | 0 | Happy path only; no negative tests for key/signature |
| Remote storage tests | `flutter test packages/remote/helix_remote_storage/test/` | 4 | 0 | In-memory SQLite only; no encryption test |
| Remote sync tests | `flutter test packages/remote/helix_remote_sync/test/` | 2 | 0 | Mock gateway; no atomicity or crash test |
| Backend tests | Not in verify pipeline | Unknown | Unknown | Must be wired in |

---

## Roadmap Correction

The following master-plan checkboxes are inaccurate and must be corrected:

**Revert to unchecked (implementation or evidence is missing):**
- P9-003, P9-004 (critical defects)
- P9-005, P9-006 (unverified key lifecycle)
- P9-019, P9-020, P9-021 (insufficient negative tests)
- P9-022 (no platform tests)
- P9-023 (no physical byte test)
- P9-024 (BLOCKED)
- P10-019 (transactional outbox not atomic)
- P10-024, P10-025, P10-026 (not started or not wired)
- P10-027 (BLOCKED — staging)
- P10-030–P10-034 (not started)
- P11-001 (REPAIRED IN P2-01)
- P11-017, P11-018, P11-019 (not started)
- P11-020, P11-022, P11-024 (critical defects)
- P11-030–P11-034 (not started)

---

## Closure Repair Pass Items

Items repaired in this pass are recorded here as they are completed.

| Item | Status | Commit |
|---|---|---|
| Scenario B current symmetric-chain coverage | PARTIALLY IMPLEMENTED / BLOCKED | Current tests prove early out-of-order ciphertext and replay are rejected without corrupting state. Successful 3->1->2 skipped-key decryption remains BLOCKED until a reviewed DH/skipped-key ratchet is selected. |
| (closure pass in progress) | — | — |
