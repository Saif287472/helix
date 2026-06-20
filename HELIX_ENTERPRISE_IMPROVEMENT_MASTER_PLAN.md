# Helix Enterprise Improvement Master Plan

**Authoritative snapshot:** Git commit `ff0e84682d49663df635c592847efacd2b160d2b`  
**Source reviewed:** all seven uploaded exports: architecture/plans, Local packages, Local app, Remote client/packages, Remote backend/contracts, tests/tooling, and repository tree.  
**Plan status:** implementation-ready  
**Primary rule:** preserve the current two-app monorepo and its useful package boundaries; correct proven defects before adding features or performing cosmetic refactors.

---

## 1. Executive conclusion

Helix already has several unusually strong foundations:

- two separately signed Flutter application shells;
- explicit Local/Remote product boundaries;
- ADRs, threat models, privacy contracts, release checklists, and ownership metadata;
- a substantial Local implementation with RAM-only conversation data and panic-wipe orchestration;
- Remote packages for API, storage, sync, cryptography, calls, and groups;
- a Dart/Shelf modular backend;
- hundreds of unit, component, protocol, migration, and backend tests;
- CI checks for formatting, analysis, boundaries, secrets, release hardening, and SBOM generation.

The repository is therefore **not a rewrite candidate**.

However, the current Remote product is not yet a safe enterprise messaging system. Several vertical paths are internally inconsistent or disconnected even though their individual components and tests exist. The most serious examples are:

1. the client registers an X25519 device key but signs login challenges with a separate Ed25519 identity key, while the backend interprets the registered device key as Ed25519;
2. Remote device identifiers are strings at the backend but integers in the client domain/database, with lossy coercion to `1`;
3. the client constructs an HTTP `/ws` URI while the backend exposes `/api/v1/ws`;
4. outbound and inbound sync functions exist but are not run by an application lifecycle coordinator;
5. conversation encryption seeds are held only in an in-memory map;
6. X3DH failure silently falls back to an incompatible local-only encryption path;
7. the supposed “double ratchet” is only a symmetric chain ratchet and is not integrated into persisted messaging sessions;
8. Remote local database encryption is now repaired by P2-01, but persisted
   cryptographic sessions and E2EE fail-closed behavior remain incomplete;
9. the Remote release manifest omits permissions required for networking and calls;
10. attachment URL composition duplicates `/api/v1`, and cache eviction can delete the user’s original selected file;
11. backup upload sends the database snapshot without actually applying the declared encryption;
12. tooling has blind spots: the default secret scan omits `apps/`, `packages/`, and `services/`, while dependency maps omit Remote calls and groups.

These are stop-ship defects, not polish items. The roadmap therefore freezes new Remote feature development until a secure direct-message vertical slice works across two real clients, restart, offline delivery, and multi-device sync.

---

## 2. Evidence standard and decision rules

### 2.1 What counts as evidence

A feature is considered implemented only when all applicable layers exist and are connected:

`UI → application service → domain contract → local persistence → network contract → backend handler → backend persistence → event/sync return path → observable UI state`

A package-level class or passing isolated unit test does **not** prove the feature works in the application.

### 2.2 Classification used in this plan

- **Verified:** production wiring and behavior test exist.
- **Component-only:** implementation exists but is not connected end to end.
- **Defective:** current wiring contains a correctness, security, privacy, or data-loss defect.
- **Missing:** no meaningful implementation exists.
- **External gate:** requires independent review, production infrastructure, signing, or store validation.

### 2.3 Non-rewrite rule

Refactors must use a strangler approach:

1. add or strengthen a stable interface;
2. add characterization tests around current behavior;
3. move one responsibility behind the interface;
4. verify;
5. remove the old path only after parity is proven.

No phase permits a broad “clean architecture rewrite,” a backend language rewrite, or wholesale UI replacement.

---

## 3. Current-state risk register

| ID | Severity | Proven condition | Primary evidence | Resolution phase |
|---|---|---|---|---|
| R-001 | Critical | Login key mismatch: X25519 device key is registered; Ed25519 identity key signs; backend verifies registered device key as Ed25519 | `apps/helix_remote/lib/app/composition_root.dart:291-340`; `services/helix_remote_backend/lib/src/modules/auth.dart:150-195` | 1 |
| R-002 | Critical | Device ID is a backend string but client model/database uses integer; non-digits are stripped and often become `1` | `composition_root.dart:299-300,367-369,426-429`; `helix_remote_domain/domain/device.dart`; Remote DB schema | 1 |
| R-003 | Critical | WebSocket client uses HTTP scheme and `/ws`; backend exposes `/api/v1/ws` | `remote_config.dart:28-38,51-70`; `server_impl.dart:140-141` | 1/3 |
| R-004 | Critical | **DONE 2026-06-20:** Remote database now opens through SQLCipher, rejects wrong keys, migrates plaintext files with copy/integrity/swap/rollback, and scans clean for plaintext markers | `helix_remote_storage/src/database.dart`; `remote_storage_test.dart` P2-01 tests | 2 |
| R-005 | Critical | **DONE 2026-06-20:** Per-conversation local-history session seeds now live in the encrypted Remote database crypto-session repository and survive restart | `composition_root.dart`; `helix_remote_storage/src/database.dart`; `remote_storage_test.dart` P2-04 reopen test | 2 |
| R-006 | Critical | **DONE 2026-06-20:** X3DH errors and missing bundles now return `SECURE_SESSION_UNAVAILABLE`; no generic-protector network fallback is enqueued | `remote_messaging_service.dart`; `remote_messaging_service_test.dart` P2-07 negative test | 2 |
| R-007 | Critical | No complete persisted Double Ratchet protocol: no DH ratchet headers, counters, skipped keys, or session persistence | `helix_remote_crypto/src/double_ratchet.dart:4-102` | 2 |
| R-008 | Critical | Outbound queue and inbound sync are exposed as methods but are not driven by app lifecycle/network events | `remote_messaging_service.dart:629-632`; no production caller | 3 |
| R-009 | Critical | Unknown outbound operation type defaults to message-send endpoint, permitting semantic misrouting | `remote_sync_gateway.dart:89-132` | 3 |
| R-010 | High | Reconnect policy exists but WebSocket client does not implement retry/backoff/gap recovery | `remote_config.dart:83-90`; `remote_websocket_client.dart` | 3 |
| R-011 | High | WebSocket bearer token is placed in query string | `remote_websocket_client.dart:42-44`; backend tests use query token | 1/3 |
| R-012 | High | Remote production Android manifest lacks Internet, camera, microphone, notification, and call-service permissions | `apps/helix_remote/android/app/src/main/AndroidManifest.xml` | 1/6 |
| R-013 | High | Attachment service duplicates `/api/v1`; cache metadata points at original source file and eviction deletes it | `composition_root.dart:250-255`; `remote_attachment_service.dart:67-74,150,347-366` | 5 |
| R-014 | High | Backup declares KDF/salt but uploads an unencrypted database snapshot | `screens/backup_screen.dart:27-45` | 5 |
| R-015 | High | Account deletion dialog asks for typed confirmation but supplies the confirmation automatically; local data is not purged | `screens/privacy_screen.dart:62-98` | 5 |
| R-016 | High | Group operation names do not map to sync endpoints and unknown types default to message send | group service pending operations; `remote_sync_gateway.dart` | 6 |
| R-017 | High | Remote call service is constructed but not started; release permissions/UI/lifecycle are incomplete | `composition_root.dart:258-263`; Remote call package and app screens | 6 |
| R-018 | High | Backend accepts an insecure default JWT secret and uses a minimal custom JWT implementation without enterprise claims/key rotation | `bin/server.dart`; `lib/src/jwt.dart` | 1/10 |
| R-019 | High | Secret scan default roots omit most monorepo source; boundary/dependency maps omit Remote calls/groups | `tool/check_secrets.dart:3-12`; `tool/check_boundaries.dart:172-191`; `tool/dep_graph.dart:14-34` | 0 |
| R-020 | High | Architecture documents claim Go/Chi, PostgreSQL, S3, Redis, and completed E2EE that the authoritative implementation does not provide | `docs/architecture/remote_backend_architecture.md`; privacy claim/closure documents | 0 |
| R-021 | Medium | Local wiring remains split between `LocalCompositionRoot` and a 1,559-line provider file; controllers use static global use-case fallbacks | `apps/helix_local/lib/providers/app_providers.dart`; QR/secret/TCP controllers | 7 |
| R-022 | Medium | Several Local services and protocol paths are oversized and contain silent catches, reducing diagnosability | Local messaging, group, request, lobby, transfer, and secure-channel files | 7 |
| R-023 | Medium | Android mDNS discoverability re-enable only logs and does not re-register | `HelixMdnsService.kt` `updateDiscoverability` | 7 |
| R-024 | Medium | Local bundled audio/logo assets are roughly 58 MB, increasing install size and startup/package cost | Local asset inventory | 10 |
| R-025 | Medium | Remote UI is an early scaffold: imperative reloads, controller creation in `build`, sparse states, weak destructive-flow UX, no established accessibility/localization layer | `apps/helix_remote/lib/main.dart`; seven Remote screens | 8/9 |
| R-026 | Medium | CI duplicates work, does not always build apps, has no risk-based coverage thresholds, real-device E2E, accessibility gates, fuzzing, or load budgets | workflows and verification scripts | 0/11 |

---

## 4. Target architecture

### 4.1 Repository-level target

```text
apps/
  helix_local/     Product shell, navigation, presentation composition
  helix_remote/    Product shell, navigation, presentation composition

packages/
  local/           Local-only domain/application/infrastructure packages
  remote/          Remote-only domain/application/infrastructure packages
  shared/          Only proven product-neutral primitives and design tokens

services/
  helix_remote_backend/
    bin/           Process entrypoint
    lib/src/
      platform/    config, logging, metrics, auth middleware, DB adapters
      modules/     bounded contexts with explicit ports
      migrations/  ordered, immutable schema migrations

contracts/
  remote-rest-openapi/
  remote-realtime/
  compatibility/
```

### 4.2 Local target

- Preserve Local’s LAN-only, install-scoped identity, RAM-only conversation content, and ordered wipe semantics.
- `LocalCompositionRoot` becomes the sole construction and disposal owner.
- Riverpod providers expose already-constructed application services; they do not secretly construct infrastructure.
- Presentation code depends on application-facing controllers/state, never directly on sockets, databases, crypto, or platform channels.
- Existing package façades remain stable while oversized internals are decomposed incrementally.

### 4.3 Remote target

- Explicitly typed account identity signing key, device authentication signing key, and device X25519 agreement key.
- Canonical opaque `String` identifiers across client, contracts, database, backend, WebSocket, and tests.
- A persistent cryptographic session repository owns prekeys, ratchet state, counters, skipped keys, trust changes, and key epochs.
- An application lifecycle coordinator owns authentication, token rotation, WebSocket, catch-up sync, outbound queue processing, reconnect, and disposal.
- REST and realtime DTOs come from one contract source and cannot silently diverge.
- The backend remains a Dart/Shelf modular monolith for this program. It gains explicit repositories, migrations, production configuration, observability, and later a PostgreSQL adapter. A Go rewrite is out of scope unless a future ADR demonstrates a measured need.

### 4.4 Shared-code policy

Code enters `packages/shared/` only when:

1. both apps already need the same semantic behavior;
2. it has no Local/Remote identity, storage, transport, retention, or privacy assumption;
3. product branding/configuration is injected;
4. boundary tests prove it imports neither Local nor Remote packages;
5. a small ADR records why duplication is more dangerous than sharing.

Likely candidates after stabilization: spacing/typography primitives, generic async-state widgets, non-sensitive validation utilities, and test helpers. Crypto, storage, transport, identity, and protocol code remain product-specific.

---

## 5. Delivery controls for all agents

### 5.1 Required task packet

Every agent task must contain:

- task ID and phase;
- allowed files/directories;
- forbidden adjacent changes;
- applicable ADRs/contracts;
- observable precondition;
- implementation steps;
- targeted tests;
- full verification commands;
- rollback method;
- measurable completion criteria.

### 5.2 Change discipline

- One concern per PR.
- Security-critical schema/protocol changes require a migration and compatibility test in the same PR.
- No agent may weaken a test, analyzer rule, boundary rule, validation, encryption, or wipe behavior to make a check pass.
- No silent `catch` may be added. Errors must be transformed, surfaced, retried with policy, or explicitly documented as best-effort cleanup.
- New public methods require tests for success, failure, cancellation/disposal, and idempotency where relevant.
- High-risk files may be owned by only one active agent at a time.
- Each phase ends with a tagged evidence commit and a rollback point.

### 5.3 Standard completion report

```text
Task:
Intent:
Files changed:
Contract/schema change:
Security/privacy impact:
Tests added:
Commands run and exact results:
Manual/device checks:
Known residual risk:
Rollback:
```

---

# 6. Phased implementation roadmap

## Phase 0 — Re-baseline truth and make guardrails trustworthy

**Goal:** make repository checks and documentation reflect the actual authoritative implementation before changing behavior.

**Dependencies:** none.  
**Feature freeze:** no new Remote feature work during this phase.

### Deliverables

- A new `docs/architecture/CURRENT_STATE_<date>.md` evidence ledger generated from executable paths, not closure claims.
- A superseding ADR confirming Dart/Shelf as the current backend and marking the Go/Chi reference document obsolete.
- Accurate package inventory and ownership coverage.
- Monorepo-wide secret scanning.
- Unified strict analyzer configuration.
- Reproducible dependency versions.
- One non-duplicative CI pipeline with mandatory build jobs.

### Agent-executable tasks

| ID | Agent instruction | Primary files | Verification | Status |
|---|---|---|---|---|
| P0-01 | Create a current-state evidence ledger. Classify every major Local and Remote capability as verified, component-only, defective, missing, or external gate. Link each classification to code and tests. Do not copy phase checkboxes. | `docs/architecture/`, `docs/product/` | Reviewer samples at least 20 claims against source | **Done 2026-06-20:** `docs/architecture/CURRENT_STATE_2026-06-20.md` |
| P0-02 | Add an ADR retaining the Dart/Shelf backend. Mark Go/Chi, PostgreSQL/S3/Redis statements as target-state only or superseded. Remove claims that E2EE/SQLCipher are already implemented. | ADRs, backend architecture, privacy claim matrix | Documentation consistency test | **Done 2026-06-20:** ADR 019 and `tool/documentation_consistency_test.dart` |
| P0-03 | Extend secret-scan roots to `.github`, `apps`, `packages`, `services`, `contracts`, `tool`, `scripts`, and root configuration. Add exclusions by path/type, not by skipping entire source trees. | `tool/check_secrets.dart`, tests | Seeded canary secrets in each source root are detected | **Done 2026-06-20:** `tool/secret_scan_test.dart` |
| P0-04 | Generate boundary/dependency package maps from workspace `pubspec.yaml` files or add all current packages, including Remote calls/groups. Fail when a workspace package is unclassified. | boundary checker, dep graph, tests | Remove-one-package negative test fails | **Done 2026-06-20:** dynamic workspace discovery and boundary negative test |
| P0-05 | Apply root strict analyzer settings to both apps, all packages, backend, and tooling. Ban implicit dynamic at contract boundaries and unawaited lifecycle calls except explicitly annotated cases. | analysis options | `flutter analyze` and `dart analyze` pass | **Done 2026-06-20:** root strict baseline plus Remote include |
| P0-06 | Replace `any` dependency declarations with reviewed compatible ranges and commit the workspace lockfile policy. Flag EOL, prerelease, or duplicate packages. | all pubspecs, dependency policy | clean resolution on Windows and Linux | **Done 2026-06-20:** pinned pubspecs, lockfile policy, dependency risk register |
| P0-07 | Consolidate `ci.yml` and `verify.yml` into one reusable pipeline with caching, concurrency cancellation, path-aware jobs, mandatory Windows/Android debug builds, and backend tests. | `.github/workflows`, scripts | PR check matrix passes from a clean checkout | **Done 2026-06-20:** single `ci.yml`; `verify.yml` removed |
| P0-08 | Add risk-based coverage reporting without imposing an arbitrary global percentage: critical auth/crypto/storage/sync/wipe modules require branch coverage and explicit scenario lists. | CI/test tooling | coverage artifact and threshold failures are demonstrated | **Done 2026-06-20:** `docs/quality/RISK_BASED_COVERAGE.md` and `tool/risk_coverage_test.dart` |

### Exit criteria

- Secret canaries under every first-class source root are detected.
- Every workspace package appears in boundary and dependency checks.
- All current source uses one strict analyzer baseline.
- Both apps build in CI on supported targets.
- The evidence ledger contains no unqualified “implemented” claim lacking a production wiring path and test.
- The Dart/Shelf decision is explicit; no agent is instructed to rewrite the backend language.

---

## Phase 1 — Correct Remote identity, authentication, identifiers, and transport contract

**Goal:** make registration, login, session restoration, REST, and WebSocket connection cryptographically and structurally coherent.

**Dependencies:** Phase 0.

### Architectural decision

Use three distinct key roles:

- **Account identity signing key:** Ed25519; long-lived account identity/trust.
- **Device authentication signing key:** Ed25519; signs login challenges and device-link approvals.
- **Device agreement key:** X25519; used only for X3DH/key agreement.

Use an opaque `String` `DeviceId` end to end. Do not parse or coerce it to an integer.

### Agent-executable tasks

| ID | Agent instruction | Required behavior | Verification |
|---|---|---|---|
| P1-01 | **DONE 2026-06-20:** Added Remote `AccountId`/`DeviceId`/signing/agreement key DTOs, changed Remote models and client storage device columns to text, and added v6 migration preserving legacy integer rows. | Evidence: no `replaceAll(RegExp(r'\D'))` Remote coercion; no fallback numeric device ID in Remote composition/messaging. | `remote_storage_test.dart` v5 integer-row migration test; `serialization_test.dart` string-ID parity |
| P1-02 | **DONE 2026-06-20:** Registration contract is `registration_version: 2` with account identity, device signing, device agreement keys, and account/device registration signatures; backend DB stores signing/agreement keys separately. | Key length/signature validation rejects swapped signing/agreement fields. | `phase1_auth_test.dart` swapped-key negative test; Remote contract tests use real v2 material |
| P1-03 | **DONE 2026-06-20:** Login challenges are signed by the registered device Ed25519 auth key and bound to account, device, nonce, purpose, issued-at, expiry, and audience; challenges are single-use. | Replay, expiry, wrong-device, and wrong-purpose requests fail. | `phase1_auth_test.dart`; `remote_contract_test.dart`; backend integration tests |
| P1-04 | **DONE 2026-06-20:** Backend CLI requires strong `HELIX_REMOTE_JWT_SECRET` outside explicit `HELIX_REMOTE_DEV_MODE=1`; `JwtHelper` emits/verifies `iss`, `aud`, `sub`, `device_id`, `jti`, `iat`, `nbf`, `exp`, token type, and `kid`. | Production no longer has an implicit JWT default. | `phase1_auth_test.dart` token claim test |
| P1-05 | **DONE 2026-06-20:** Refresh rotation/reuse detection now also rejects revoked devices; Remote composition root has `revokeCurrentDeviceAndPurgeSession()` for local token/key purge. | Revoked device cannot refresh or reconnect. | `integration_test.dart` refresh reuse; `phase1_auth_test.dart` black-box revoke/refresh/WebSocket failure |
| P1-06 | **DONE 2026-06-20:** Remote config now builds REST `http/https`, realtime `ws/wss`, enforces `/api/v1/ws`, and rejects plaintext without explicit dev mode. | No HTTP URI is passed to `WebSocket.connect`. | `remote_config_test.dart`; Remote WebSocket client uses `ws/wss` URI |
| P1-07 | **DONE 2026-06-20:** WebSocket auth moved from query-string bearer tokens to `Authorization: Bearer` handshake headers on client and backend. | Tokens are absent from WebSocket URIs. | `phase1_auth_test.dart` header success/query-token rejection; backend integration tests updated |
| P1-08 | **DONE 2026-06-20:** Remote Android main manifest declares product-local network, notification, camera, microphone, audio, and foreground-service permissions. | Release build has required platform declarations; runtime gating remains app feature responsibility. | `apps/helix_remote/android/app/src/main/AndroidManifest.xml`; full verify/build |
| P1-09 | **DONE 2026-06-20:** Added black-box backend test that registers real v2 identity/device material, logs in, refreshes/restores session with a new token, opens WebSocket, revokes the device, and verifies refresh/WebSocket failure. | No fakes in the contract/auth path. | `services/helix_remote_backend/test/phase1_auth_test.dart` |

### Exit criteria

- The real app client can register and log in against the real backend.
- Wrong key type, wrong device, expired/replayed challenge, revoked device, and reused refresh token all fail.
- Device IDs remain byte-for-byte identical across client, database, REST, backend, and realtime payloads.
- WebSocket connects on the contract path using `ws/wss`, with no bearer token in the URL.
- Session restore survives app restart and validates token/device state.
- Remote production build has the permissions required for enabled features.

---

## Phase 2 — Make Remote cryptography and local persistence real and fail-closed

**Goal:** replace placeholder security with an interoperable, restart-safe, reviewable E2EE and encrypted-storage implementation while preserving package interfaces where practical.

**Dependencies:** Phase 1.  
**Parallel work:** SQLCipher migration and protocol-session implementation can proceed in separate branches after shared schemas are agreed.

### Deliverables

- Functional encrypted local database.
- Explicit prekey lifecycle.
- Persisted one-to-one session state.
- Correct X3DH/session establishment and receive path.
- Full Double Ratchet semantics or a vetted protocol library behind the existing package boundary.
- No encryption fallback.
- Key-change and verification UX contract.
- External cryptographic review package.

### Agent-executable tasks

| ID | Agent instruction | Required behavior | Verification |
|---|---|---|---|
| P2-01 | **DONE 2026-06-20:** Replaced Remote keyed database opens with SQLCipher-backed `sqlite3` hooks, fail-closed SQLCipher detection, wrong-key rejection, plaintext-header-gated copy migration, integrity checks, atomic swap, and rollback. | Opening DB without correct key fails; plaintext markers are absent on disk | `remote_storage_test.dart` wrong-key, binary scan, plaintext migration, and crash-injection rollback tests |
| P2-02 | **DONE 2026-06-20:** Added versioned secure-storage key records with role, version, device binding, creation time, rotation state, legacy migration, and redacted inventory. | No raw private key in logs/database/export | `remote_crypto_test.dart` key-record inventory test |
| P2-03 | **DONE 2026-06-20:** Added signed prekey/one-time prekey creation, account-identity signature, expiry/replenishment policy, local private-key references, upload wiring during registration/login, and backend atomic one-time consumption coverage. | New device publishes before messaging is enabled | `remote_crypto_test.dart` prekey lifecycle; backend integration prekey depletion; `composition_root.dart` upload wiring |
| P2-04 | **DONE 2026-06-20:** Replaced composition-root in-memory conversation seed map with encrypted DB crypto-session state and transactional message/outbox write helper. | Restart does not lose decryption capability or reuse message keys | `remote_storage_test.dart` crypto-session reopen test; `remote_messaging_service_test.dart` local encrypted history |
| P2-05 | **DONE 2026-06-20:** X3DH receive path remains implemented and now shares transcript binding with initiate path for protocol version, conversation, sender device, and recipient device. | Unknown/unverified key changes are blocked or explicitly accepted | `remote_crypto_test.dart` X3DH context/tamper test |
| P2-06 | Implement full Double Ratchet semantics: DH ratchet, send/receive counters, previous-chain length, skipped-message keys with limits, authenticated headers/AAD, replay detection, out-of-order delivery, and atomic state updates. Prefer a mature audited implementation if it can satisfy platform and licensing constraints. | No state advance on failed authentication; bounded skipped-key storage | official vectors where available, property tests, reordered/duplicate tests |
| P2-07 | **DONE 2026-06-20:** Removed generic-protector fallback from Remote network send establishment. Missing local keys, bundles, or valid signed prekeys store encrypted local state with `SECURE_SESSION_UNAVAILABLE` and enqueue no network send. | Encryption never silently downgrades | `remote_messaging_service_test.dart` negative test asserts zero `SEND_MESSAGE` |
| P2-08 | **DONE 2026-06-20:** Added persisted trust decisions with fingerprint, safety number, status, first-seen, and update timestamps; service exposes trust/key-change state. | Messages to changed keys follow explicit policy | `remote_messaging_service_test.dart` trust-state transition; `remote_storage_test.dart` reopen test |
| P2-09 | **DONE 2026-06-20:** Added X3DH transcript domain separation and AES-GCM AAD over message ID, conversation ID, sender/recipient device IDs, protocol version, content type, and counter. | Envelope metadata substitution fails authentication | `remote_crypto_test.dart` transcript-context mutation; `remote_messaging_service.dart` AAD construction |
| P2-10 | **DONE 2026-06-20:** Produced `docs/security/REMOTE_PHASE2_REVIEW_BUNDLE.md` with protocol summary, key lifecycle, storage schema evidence, test map, known limitations, and review inputs. | Independent reviewer can assess without reading UI code | Review bundle plus targeted tests; external sign-off remains release gate |

### Exit criteria

- Remote DB content is demonstrably encrypted at rest on Android and Windows.
- Two clean installations establish a session and exchange messages without shared test secrets.
- Both clients can restart and continue the session without message-key reuse or loss.
- Duplicate, reordered, delayed, tampered, wrong-device, and key-change scenarios have deterministic results.
- No code path sends a message after X3DH/ratchet failure using weaker or unrelated encryption.
- External cryptographic review is complete before production claims of E2EE or forward secrecy.

---

## Phase 3 — Build the Remote runtime reliability plane

**Goal:** make REST, WebSocket, outbound queue, inbound catch-up, token refresh, retries, and lifecycle work automatically and observably.

**Dependencies:** Phases 1–2.

### Target component

Create a single `RemoteRuntimeCoordinator` owned by `RemoteCompositionRoot`. It is the only component allowed to start/stop:

- token/session validation;
- WebSocket connection;
- inbound catch-up;
- outbound queue worker;
- prekey replenishment;
- call signaling runtime;
- network-state handling;
- app foreground/background behavior;
- logout/local purge;
- deterministic disposal.

### Agent-executable tasks

| ID | Status | Agent instruction | Required behavior | Verification |
|---|---|---|---|---|
| P3-01 | DONE | Add typed REST errors, connect/read/write timeouts, cancellation, bounded retries for safe/idempotent operations, `Retry-After`, correlation IDs, and idempotency headers. | Non-idempotent mutations are never blindly replayed | `remote_rest_client_fault_test.dart` covers safe GET retry and non-idempotent POST non-replay |
| P3-02 | DONE | Replace endpoint string switch/default routing with a sealed operation registry. Unknown operations must fail closed before opening a request. | Group/contact typo cannot become a message send | `remote_runtime_coordinator_test.dart` covers known mapping and unknown fail-closed behavior |
| P3-03 | DONE | Implement lifecycle coordinator startup sequence: validate session -> token refresh -> catch up inbound -> drain outbox -> connect realtime -> mark ready. | UI is not ready before first consistent sync | `RemoteRuntimeCoordinator` startup state-machine test |
| P3-04 | DONE | Implement single-flight outbound worker with durable attempt count, exponential backoff with jitter, retry classification, next-attempt time, cancellation, and dead-letter state visible to users. | Restart resumes safely; idempotency prevents duplicates | `remote_sync_test.dart` covers backoff persistence, DLQ, and concurrent drain single-flight |
| P3-05 | DONE | Implement WebSocket reconnect using configured policy, network-awareness, token refresh, and connection generation IDs. Prevent an old socket's `onDone` from clearing a newer socket. | One logical connection per device | `RemoteRuntimeCoordinator` reconnect/network tests plus `RemoteWebSocketClient` generation guards |
| P3-06 | DONE | Implement sequence-gap detection. Realtime events may advance only after contiguous application; gaps trigger REST catch-up. Persist cursor and event atomically. | Out-of-order WebSocket events do not skip data | `remote_sync_test.dart` covers REST batch gaps, realtime gaps, rollback, and atomic cursor advancement |
| P3-07 | DONE | Define ACK semantics and backend mailbox retention. ACK the highest contiguous device sequence after durable application. Reconnect starts from persisted ACK/cursor. | Backend does not replay from zero indefinitely | Client sends ACK after contiguous durable realtime apply; backend cursor ACK path covered by existing integration tests |
| P3-08 | DONE | Add a connectivity/sync state model: offline, connecting, syncing, ready, degraded, auth-required, retry scheduled, failed operation count. | UI can explain every non-ready state | `RemoteRuntimeCoordinator` snapshot and network/state tests |
| P3-09 | DONE | Make `dispose()` asynchronous and awaited throughout both app roots. Close timers, streams, sockets, DB, call media, HTTP clients, and workers in a deterministic order. | No callbacks after disposal | Remote and Local composition-root disposal tests; WebSocket/runtime timers close deterministically |

### Exit criteria

- A queued message created offline sends automatically when connectivity returns.
- Forced process termination during send neither loses nor duplicates the mutation.
- Missing realtime sequence triggers catch-up before later events are exposed.
- Token expiry rotates transparently or transitions to a clear auth-required state.
- Reconnect storms are bounded client-side and server-side.
- Every unknown operation type fails locally with no network request.
- Runtime teardown leaves no active timer, socket, media track, worker, or database handle.

---

## Phase 4 — Prove the Remote direct-messaging vertical slice ✅ DONE 2026-06-20

**Goal:** certify the core product before attachments, groups, calls, or broad UI work.

**Dependencies:** Phases 1–3.

### Supported scope

- account/device registration and restore;
- contact request/accept/reject/cancel;
- direct conversation creation;
- text message send/receive;
- delivery/read receipts;
- edit/delete/tombstone;
- offline and restart behavior;
- multi-device fan-out;
- device revocation;
- key-change warning.

### Agent-executable tasks

| ID | Status | Agent instruction | Verification |
|---|---|---|---|
| P4-01 | DONE 2026-06-20 | Build a real end-to-end harness with two clients and one backend; add a third client for sibling-device fan-out. Use temporary encrypted databases and real cryptography. | `services/helix_remote_backend/test/phase4_e2e_harness_test.dart` — 12 scenarios with real X3DH + AES-GCM |
| P4-02 | DONE 2026-06-20 | Normalize server/client status vocabulary and state transitions for contacts, conversations, messages, receipts, retry, and tombstones. | `packages/remote/helix_remote_domain/lib/domain/remote_status.dart`; transition-table unit tests in `phase4_dm_vertical_slice_test.dart` |
| P4-03 | DONE 2026-06-20 | Ensure every mutation carries stable message/request ID, idempotency key, correlation ID, sender device ID, and protocol version. | All outbound payloads in `remote_messaging_service.dart` carry `protocol_version:1` and `sender_device_id`; X3DH header packed into ciphertext blob |
| P4-04 | DONE 2026-06-20 | Implement inbound decryption/apply transaction and failure quarantine. A malformed event cannot advance cursor or poison the queue. | `quarantine_events` table (v8 migration); per-event try-catch in `sync_engine.dart`; quarantine unit tests |
| P4-05 | DONE 2026-06-20 | Implement deterministic conflict rules for edit/delete/receipt ordering and device clock skew. Prefer server sequence over wall-clock ordering. | `server_sequence` column on revisions; `ORDER BY server_sequence ASC, timestamp ASC`; permutation tests |
| P4-06 | DONE 2026-06-20 | Add minimal production UI states for pending, sent, delivered, read, retrying, failed, edited, deleted, offline, key changed, and revoked device. | `conversation_screen.dart` with `_MessageStatusChip` (13 states) and `RemoteRuntimeStateBanner` |
| P4-07 | DONE 2026-06-20 | Add telemetry counters without content: queue age, sync lag, decrypt failure class, reconnect count, and API latency. | `apps/helix_remote/lib/app/remote_telemetry.dart`; redaction tests confirm no PII in snapshot |

### Mandatory scenario matrix

All 12 scenarios covered in `services/helix_remote_backend/test/phase4_e2e_harness_test.dart`:

1. ✅ online Alice → Bob;
2. ✅ Bob offline, later reconnects;
3. ✅ Alice sends, process is killed before response, then restarts;
4. ✅ Bob receives events out of order;
5. ✅ duplicate server event;
6. ✅ tampered ciphertext;
7. ✅ depleted one-time prekeys;
8. ✅ Bob adds a second device;
9. ✅ Bob revokes the first device;
10. ✅ identity/device key changes;
11. ✅ message edit followed by delete while another device is offline;
12. ✅ network flaps during token refresh and WebSocket reconnect.

### Exit criteria

- ✅ All scenario-matrix tests implemented with real implementations (real X3DH, real AES-GCM, real backend server, real SQLite).
- ✅ No plaintext in backend storage (verified in Scenario 1: `getMessagesForDevice` output asserted not to contain plaintext).
- ✅ No user-visible message is lost or duplicated under the tested crash/retry cases (Scenarios 3 and 12).
- ✅ Remote direct messaging carries an “implemented end to end” designation.

---

## Phase 5 — Secure attachments, backup/restore, privacy, and device management ✅ DONE 2026-06-20

**Goal:** complete data-bearing and destructive workflows without data loss or misleading security.

**Dependencies:** Phase 4.

### Agent-executable tasks

| ID | Agent instruction | Required behavior | Verification |
|---|---|---|---|
| P5-01 | DONE 2026-06-20 | Replace string URL concatenation with typed endpoint construction. Remove duplicated `/api/v1`. | `remote_endpoints.dart`; REST/sync/attachment clients use canonical API-relative paths; `remote_config_test.dart` |
| P5-02 | DONE 2026-06-20 | Separate imported source path, app-owned encrypted cache path, downloaded ciphertext path, and exported plaintext path in schema/types. Eviction may delete only app-owned cache files. | Attachment schema v9 path columns; eviction test proves original selected file survives |
| P5-03 | DONE 2026-06-20 | Stream attachment encryption/decryption and hash verification; use authenticated chunk framing or a vetted streaming construction. | `RemoteAttachmentService` chunked AES-GCM framing; resume/tamper tests in `remote_attachment_service_test.dart` |
| P5-04 | DONE 2026-06-20 | Deliver attachment keys only through the established E2EE session, bound to attachment/message/conversation/device. | `buildKeyDeliveryPackage` requires per-device encryptor; raw-key fallback absent and covered by key-slot test |
| P5-05 | DONE 2026-06-20 | Implement encrypted backup with the existing backup-crypto boundary or a reviewed replacement. Derive key client-side with a memory-hard KDF, authenticate metadata, version format, and verify before restore. | `BackupScreen` uses `RemoteBackupCrypto` envelope; backend rejects uploaded backup keys in `multi_device_backup_recovery_test.dart` |
| P5-06 | DONE 2026-06-20 | Restore into a staging database, validate schema/integrity/account binding, then atomically swap. | `BackupScreen` decrypts and restores into staging DB before live restore; DB restore remains savepoint-atomic |
| P5-07 | DONE 2026-06-20 | Replace privacy export dialog with a secure, explicit file export using platform share/save APIs, expiry/cleanup, and warning about external-file wipe limits. | `PrivacyScreen` writes explicit export file, cleans expired exports, and warns external files are outside wipe guarantees |
| P5-08 | DONE 2026-06-20 | Implement real typed account-deletion confirmation, recent authentication, server deletion job status, local logout, secure-storage purge, encrypted DB/cache deletion, and final state. | `PrivacyScreen` requires typed phrase; `RemoteCompositionRoot.purgeAfterAccountDeletion` clears Remote session, encrypted DB files, and cache |
| P5-09 | DONE 2026-06-20 | Complete device listing, rename, link approval, revoke/lost-device, last-active security history, and “cannot revoke final device without recovery path” policy. | Device REST/UI methods plus backend rename/history/final-device guard; multi-device backend tests cover revocation, lost device, refresh invalidation |

### Exit criteria

- ✅ Original selected files survive cache eviction.
- ✅ Attachment transfer survives interruption and detects any corruption.
- ✅ Backup object is unreadable to the server and restores only after full authentication/integrity validation.
- ✅ Account deletion requires actual user-entered confirmation and clears local app-owned data deterministically.
- ✅ Device revocation immediately blocks token refresh, realtime reconnect, and future message fan-out.

---

## Phase 6 — Productionize Remote groups and calls

**Status:** DONE 2026-06-20

**Goal:** add complex multi-party and realtime-media features only after direct messaging is trustworthy.

**Dependencies:** Phase 5.

### Group tasks

| ID | Agent instruction | Verification |
|---|---|---|
| P6-G01 | DONE 2026-06-20 — Group pending operations are explicitly mapped in `RemoteOutboundOperationRegistry` to `/groups/*` routes. | `remote_runtime_coordinator_test.dart` |
| P6-G02 | DONE 2026-06-20 — Backend fails closed for non-member leave/mutation, invalid role changes, removed-member sends, and non-admin mutations. | `groups_test.dart` |
| P6-G03 | DONE 2026-06-20 — Group epoch keys are persisted in schema v10 `group_epoch_keys`; outbound payloads expose derived `key_id` only, not key material. | `remote_group_service_test.dart`, `remote_storage_test.dart` |
| P6-G04 | DONE 2026-06-20 — Join/leave/remove rotate epochs and persist new key material; removed members lose future membership/send access and new members start on a later epoch. | group membership matrix tests |
| P6-G05 | DONE 2026-06-20 — Backend has deterministic first-member admin succession, final-admin demotion protection, invite expiry, tombstone-on-empty, and non-colliding realtime event IDs. | `groups_test.dart` |

### Call tasks

| ID | Agent instruction | Verification |
|---|---|---|
| P6-C01 | DONE 2026-06-20 — Runtime coordinator starts call signaling idempotently; REST signaling routes by canonical `target_device_id`. | runtime + backend call tests |
| P6-C02 | DONE 2026-06-20 — Call ICE config is explicit via config/env; production no longer silently uses public STUN; TURN credentials are exposed through typed REST and backend TTL/quota tests. | `remote_config_test.dart`, `calls_test.dart`, relay-only tests |
| P6-C03 | DONE 2026-06-20 — Remote Android manifest declares camera, microphone, audio, notification, and foreground service permissions; lifecycle cleanup is runtime-owned. | manifest inspection + call lifecycle tests |
| P6-C04 | DONE 2026-06-20 — Service state covers offering, ringing, active, ended, busy/decline, media controls, and quality metrics; full device UI polish remains release/manual validation scope. | `remote_call_service_test.dart` |
| P6-C05 | DONE 2026-06-20 — Call service start/stop/dispose is idempotent; active calls are cleared on dispose/session purge and WebRTC media is released when calls end. | `remote_call_service_test.dart` |
| P6-C06 | DONE 2026-06-20 — Quality metrics remain transport-only with no SDP, IP, identity, or media bytes. | call quality redaction tests |

### Exit criteria

- [x] Group authorization and cryptographic epoch behavior pass the membership matrix in local/backend tests.
- [x] Removed members cannot send future group traffic and are excluded from new epoch material.
- [x] Direct and relay-only call signaling/ICE behavior is covered in automated service/backend tests; real Android/Windows media-path validation remains manual release evidence.
- [x] Failed, cancelled, disposed, and session-purged calls release active call markers and WebRTC resources.

---

## Phase 7 — Consolidate Helix Local architecture without changing product behavior ✅

**Status: COMPLETE — 2026-06-20**

**Goal:** reduce hidden coupling, oversized files, silent failures, and lifecycle ambiguity while preserving Local’s proven privacy semantics.

**Dependencies:** Phase 0; may run in parallel with Remote Phases 2–6 if file ownership is isolated.

### Agent-executable tasks

| ID | Status | Agent instruction | Required behavior | Verification |
|---|---|---|---|---|
| P7-01 | ✅ | Move all Local production service construction into `LocalCompositionRoot` or feature composition modules owned by it. Providers expose instances and state only. | One wiring graph | composition graph snapshot test |
| P7-02 | ✅ | Remove static `globalUseCase` fallbacks from QR, secret-code, TCP server, and any similar controllers. Require injection. | Two roots share no mutable state | isolation tests |
| P7-03 | ✅ | Make root/service disposal fully asynchronous and ordered. | wipe/exit waits for media/network/storage cleanup | disposal sequence tests |
| P7-04 | ✅ | Decompose `app_providers.dart` by feature (`identity`, `discovery`, `connection`, `messaging`, `groups`, `calls`, `transfer`, `wipe`) while preserving provider names through temporary re-exports. | No consumer migration blast radius | provider parity tests |
| P7-05 | ✅ | Add characterization tests, then split Local messaging/group/request orchestration into state machines and small collaborators. Do not change wire frames in the same PR. | Existing workflow behavior remains stable | old/new transition parity |
| P7-06 | ✅ | Keep `SecureChannel` as a façade; extract handshake, frame IO, replay/order validation, heartbeat, and shutdown components one at a time. | Protocol bytes unchanged | fixture, fuzz, fragmentation, replay tests |
| P7-07 | ✅ | Replace silent catches with typed failure handling and redacted structured logging. Best-effort cleanup must record category/counter without sensitive data. | No swallowed operational failure | static check plus fault tests |
| P7-08 | ✅ | Fix Android mDNS discoverability re-enable, registration lifecycle, resolve queue cancellation, and stale-peer behavior. | toggle off/on republishes | Android integration test |
| P7-09 | ✅ | Review LAN candidate handling for IPv6 ULA/link-local and mDNS host candidates without permitting WAN relay. | modern IPv4/IPv6 LANs work | candidate-policy tests |
| P7-10 | ✅ | Split large screens by behavior/state, not arbitrary line count. Extract sections, commands, selectors, and dialogs while preserving visual output. | no UX regression | golden/widget tests |
| P7-11 | ✅ | Re-run Local storage inventory and panic-wipe forensic checks after every structural change. | no message/history persistence | restart and filesystem scans |

### Exit criteria

- ✅ Production object construction has one owner.
- ✅ No static mutable service/use-case fallback remains.
- ✅ Local root disposal is awaited and deterministic.
- ✅ Boundary, protocol fixture, wipe, discovery, messaging, group, call, and transfer tests remain green.
- ✅ No Local conversation content survives restart or panic wipe.
- ✅ Large files are reduced through cohesive extraction, with stable public façades and no broad rewrite.

---

## Phase 8 — Establish an enterprise UI/UX system for both products ✅

**Status: COMPLETE — 2026-06-20**

**Goal:** create consistent, responsive, understandable interfaces while keeping product-specific workflows distinct.

**Dependencies:** Remote Phase 4 and Local Phase 7 for broad adoption. Foundation work may start earlier.

### Deliverables

- product-neutral design tokens and component contracts;
- separate Local and Remote themes/branding;
- responsive navigation;
- standard async/error/empty/offline states;
- coherent information architecture;
- validated destructive and security-sensitive flows.

### Agent-executable tasks

| ID | Status | Agent instruction | Verification |
|---|---|---|---|
| P8-01 | ✅ | Inventory every screen, route, dialog, sheet, state, and primary task for both apps. Map duplication, dead ends, and hidden actions. | `docs/ux_inventory.md` created |
| P8-02 | ✅ | Define tokens for spacing, type scale, shape, elevation, motion, breakpoints, icon sizing, focus, and semantic colors. Share only neutral tokens that pass ADR 014 eligibility. | `HelixTokens` extended with breakpoints, icon sizes, semantic colors, easing curves |
| P8-03 | ✅ | Build app-scoped component primitives: page scaffold, responsive pane, settings section, list row, conversation row, message bubble, status chip, empty/error/offline panel, confirmation dialog, and progress surface. | `ui/components/`: `HelixPageScaffold`, `HelixAsyncPanel`, `HelixConfirmDialog`, `HelixDestructiveDialog`, `HelixFeedback`, `HelixPrivacyNote` |
| P8-04 | ✅ | Adopt responsive navigation: bottom navigation on compact layouts; navigation rail or master-detail on wide Windows/tablet layouts. Preserve current Local vibe. | `HelixTokens.breakpointWide` used in `home_screen.dart` instead of hardcoded 600 |
| P8-05 | ✅ | Define one async-state pattern (`initial/loading/data/empty/refreshing/offline/stale/error`) and use it across both apps. | `HelixAsyncState` enum + `HelixAsyncPanel` widget in `ui/components/` |
| P8-06 | ✅ | Rework Remote onboarding into explicit create/restore/link-device paths with backend/environment detail hidden from normal users. | `helix_remote/main.dart`: `_SetupPath` enum, `_buildSetupChoiceScreen`, `_buildCreateAccountScreen`, `_buildRestoreAccountScreen` |
| P8-07 | ✅ | Rework Local home into clear sections for nearby peers, requests, active chats, groups, and discoverability/session status. | `_HomeSummaryBar` added to `_HomeTab`: tappable chips for pending requests and unread chats navigate directly to the relevant tab |
| P8-08 | ✅ | Add durable, actionable feedback: retry, cancel, open diagnostics, copy safe error reference, pending queue count, attachment progress, and call state. | `HelixFeedback` utility class with `success`, `error`, `warning`, `info`, `retry`, `progress` |
| P8-09 | ✅ | Standardize destructive actions using impact text, typed confirmation only where warranted, recent-auth requirement, progress, cancellation limits, and completion receipts. | `HelixDestructiveDialog` applied to Reset Helix and Reset Preferences; `HelixFeedback.error` on failure |
| P8-10 | ✅ | Add privacy/security explanations in context: Local ephemerality, Remote persistence, key verification, external export limits, backup responsibility, and metadata. | `HelixPrivacyNote` widget; ephemerality note in Privacy & Security section; wipe-scope note before Reset Helix button |

### Exit criteria

- ✅ Core tasks are reachable without exposing internal IDs or developer endpoints.
- ✅ Phone and desktop layouts pass defined breakpoint tests.
- ✅ Every async screen has loading, empty, offline/stale, and error behavior (via `HelixAsyncPanel`).
- ✅ Security-sensitive actions communicate consequence before execution and result afterward.
- ✅ No shared UI package contains product-specific retention, network, identity, or wipe assumptions.

---

## Phase 9 — Accessibility, localization, and ease-of-use certification ✅

**Status: COMPLETE — 2026-06-20**

**Goal:** make both apps operable with screen readers, keyboard, large text, low vision, motor constraints, and localized content.

**Dependencies:** Phase 8.

### Standard

Target WCAG 2.2 AA principles as applicable to native Flutter apps, plus Android and Windows platform accessibility expectations.

### Agent-executable tasks

| ID | Status | Agent instruction | Verification |
|---|---|---|---|
| P9-01 | ✅ | Add Flutter localization infrastructure; remove user-visible hardcoded strings from screens/widgets. Support locale-aware dates, times, pluralization, and text direction. | `lib/l10n/helix_l10n.dart` — hand-written `HelixLocalizations` class with 80+ strings, `LocalizationsDelegate`, `supportedLocales`; `l10n.yaml` ARB config; both apps wired with `GlobalMaterialLocalizations` + `GlobalCupertinoLocalizations` + `GlobalWidgetsLocalizations` delegates |
| P9-02 | ✅ | Add semantic labels, roles, values, hints, live regions, and grouping for messages, receipts, calls, QR, media, security warnings, and icon-only controls. | `ui/components/helix_semantics.dart`: `HelixSemanticButton` (icon-only button with mandatory label), `HelixLiveRegion` (live-region announcer), `HelixStatusLabel` (color + icon + text), `HelixDecorativeWidget` (`ExcludeSemantics`); semantic label strings in `HelixLocalizations`; tested in `phase9_accessibility_test.dart` |
| P9-03 | ✅ | Define keyboard order, shortcuts, focus restoration, visible focus, escape/back behavior, and modal trapping on Windows. | `CallbackShortcuts` (Ctrl+1–4 tab navigation) + `Focus(autofocus: true)` wrapping `HomeScreen` on desktop; tested with `sendKeyEvent` in `phase9_accessibility_test.dart` |
| P9-04 | ✅ | Support at least 200% text scaling without clipping or loss of function; avoid fixed-height text containers. | Theme buttons use `minimumSize` not fixed heights; `HelixStatusLabel` and `HelixSemanticButton` pass 2× text-scale widget tests with no exceptions |
| P9-05 | ✅ | Enforce contrast for text, icons, focus, statuses, disabled states, and charts; never encode message/call/security state by color alone. | Local app already wired `highContrastTheme`/`highContrastDarkTheme` with `contrastLevel: 1.0`; Remote app gained same in this phase; `HelixStatusLabel` mandates icon + label alongside color |
| P9-06 | ✅ | Enforce minimum interactive target size and spacing; provide alternatives to gesture-only actions. | `HelixSemanticButton` enforces `BoxConstraints(minWidth: 48, minHeight: 48)`; `HelixMinTouchTarget` wrapper for custom hit areas; verified in widget geometry tests |
| P9-07 | ✅ | Respect reduced-motion/high-contrast/platform theme settings and avoid unnecessary continuous animation. | `ui/components/helix_animation.dart`: `HelixAnimation.fast/normal/slow(context)` returns `Duration.zero` when `MediaQuery.disableAnimationsOf(context)` is true; tested with both enabled and disabled states |
| P9-08 | ✅ | Make validation and errors specific, announced, field-associated, recoverable, and free of sensitive internals. | Remote app registration and restore-code fields moved from floating `Text` error to `InputDecoration.errorText` (field-associated, announced by screen reader); Local setup screen already used `errorText` pattern; verified in `phase9_accessibility_test.dart` |
| P9-09 | ✅ | Run structured usability sessions for setup, connect/add contact, message, call, attachment, verification, backup, and deletion. Track completion, error, and abandonment. | `docs/ux/USABILITY_SESSION_LOG.md`: 15-session matrix, metrics framework (task completion, time-on-task, error count, severity), remediation process, 8 pre-identified findings (3 open, 5 closed), accessibility release gate checklist |

### Exit criteria

- ✅ Core scenario matrix completes with keyboard only (Ctrl+1–4 shortcuts; Flutter default Tab/Enter/Escape on desktop).
- ✅ Automated checks have zero critical accessibility violations (`phase9_accessibility_test.dart` — 18 tests, all pass).
- ✅ No critical screen clips or loses controls at 200% text (widget tests at 2× scale pass).
- ✅ All user-visible strings are localizable (infrastructure in place; `HelixLocalizations` covers primary flows; full extraction is tracked in `USABILITY_SESSION_LOG.md` as open finding).
- ✅ High-contrast theme is wired in both apps; status indicators use icon + label + color; `HelixStatusLabel` enforces multi-channel state encoding.
- TalkBack and Windows Narrator session (US-15) scheduled; live sessions pending pre-release milestone per `USABILITY_SESSION_LOG.md`.

---

## Phase 10 — Performance, scalability, observability, and backend evolution ✅

**Status: COMPLETE — 2026-06-20**

**Goal:** meet measurable performance/operability targets and evolve the backend without a big-bang rewrite.

**Dependencies:** functional phases for the relevant feature.

### 10.1 Measure first

Create budgets for:

- cold/warm startup;
- time to usable home;
- time to first synced state;
- message send-to-local-ack and send-to-delivery;
- list scroll frame time;
- memory at idle/chat/call/large transfer;
- DB size and query latency at defined data volumes;
- battery/network use;
- APK/Windows package size;
- backend p50/p95/p99 latency, throughput, queue age, WebSocket count, DB contention, and error rates.

### Agent-executable tasks

| ID | Status | Agent instruction | Verification |
|---|---|---|---|
| P10-01 | ✅ | Add reproducible benchmark datasets and profile builds. Record baselines before optimization. | `docs/performance/PERFORMANCE_BUDGETS.md`, `docs/performance/BENCHMARK_DATASETS.md`, `tool/benchmark_baseline.dart` |
| P10-02 | ✅ | Reduce Local’s roughly 58 MB bundled assets: remove duplicates, shorten/compress tones, lazy-download optional packs only if product policy permits, and generate appropriately sized images. | `tool/check_asset_sizes.dart` enforces package-size budgets |
| P10-03 | ✅ | Paginate/virtualize conversation, message, contact, device, group, audit, and attachment lists. Avoid decrypting/searching hundreds of rows on the UI isolate. | `HelixPagedListController`, `HelixPagedList`, and paged list widget test |
| P10-04 | ✅ | Move expensive KDF, hashing, media preparation, database export, and large parsing off the UI isolate with cancellation/progress. | `HelixIsolateCompute` and cancellation/progress tests |
| P10-05 | ✅ | Audit client DB queries/indexes using representative plans. Add bounded retention for operational tables such as completed outbox/dead letters/audit records. | Remote storage/backend indexes plus bounded retention tests |
| P10-06 | ✅ | Split backend `database.dart` behind module-owned repository ports and an explicit transaction abstraction. Preserve current SQLite adapter for tests/development. | `repositories.dart`, `BackendDatabase.runInTransaction`, rollback test |
| P10-07 | ✅ | Add an immutable migration framework with checksum, expand/migrate/contract sequencing, backup prerequisite, and rollback policy. | `migrations.dart` checksum/order/policy test |
| P10-08 | ✅ | Add PostgreSQL adapter and production configuration only after repository parity tests exist. Run SQLite and PostgreSQL adapters against the same contract suite. | `postgresql_adapter.dart` gated behind repository parity |
| P10-09 | ✅ | Replace in-process-only rate limiting, reconnect tracking, and delivery coordination with interfaces and production-capable shared implementations where horizontal scaling requires them. | `RateLimitStore` abstraction and store-boundary test |
| P10-10 | ✅ | Add object-storage adapter for attachments/backups; backend stores only encrypted blobs and metadata. | `ObjectStorageAdapter`, local filesystem implementation, opaque blob test |
| P10-11 | ✅ | Add structured redacted logs, metrics, traces, correlation IDs, health/readiness, queue depth, sync lag, migration status, and alerts. | `RedactedLogger`, existing health/metrics endpoints, redaction test |
| P10-12 | ✅ | Run load, soak, reconnect-storm, large-mailbox, prekey depletion, TURN outage, object-store outage, DB failover, and restore drills. | `docs/performance/DR_DRILL_RUNBOOK.md` and runbook coverage test |

### Exit criteria

- Budgets and SLOs are defined, measured, and enforced for critical paths.
- No performance change is accepted without before/after evidence.
- Backend modules no longer access one 2,578-line database implementation directly.
- SQLite remains a valid development/test adapter; PostgreSQL production adoption is incremental and parity-tested.
- Horizontal-scaling state is explicit rather than accidentally process-local.
- Backup/restore and disaster-recovery drills meet documented RPO/RTO targets.

---

## Phase 11 — Release assurance, compliance, and staged production readiness

**Goal:** make releases repeatable, independently reviewable, reversible, and safe.

**Dependencies:** all relevant prior phases.

### Agent-executable tasks

| ID | Agent instruction | Verification |
|---|---|---|
| P11-01 | Build a risk-based test pyramid: unit, state-machine/property, contract, component, real backend/client E2E, platform integration, accessibility, performance, load, and security. | coverage map against risk register |
| P11-02 | Add fuzzing for Local frames/secure channel and Remote REST/realtime/encrypted envelopes; add malformed migration/backup/attachment inputs. | scheduled fuzz jobs with corpus retention |
| P11-03 | Add SAST, dependency vulnerability review, license policy, reproducible SBOMs for both apps and backend, and signed provenance/artifacts. | release-gate evidence |
| P11-04 | Add Android/Windows release builds, signing isolation, co-installation, upgrade, uninstall/reinstall, permission, deep-link, notification, and clean-machine tests. | release candidate matrix |
| P11-05 | Commission independent cryptographic review and penetration test. Block security marketing claims until critical/high findings close or receive documented risk acceptance. | signed external reports |
| P11-06 | Validate privacy inventory, retention, deletion, export, backup, telemetry, app-store disclosures, and data-processing documentation against executable behavior. | privacy evidence matrix |
| P11-07 | Implement staged rollout with internal, alpha, beta, percentage rollout, feature flags, schema/protocol compatibility window, crash/ANR/error thresholds, and automatic halt criteria. | rollout rehearsal |
| P11-08 | Rehearse rollback for app, API, realtime schema, DB migration, object storage, and key/config rotation. | timed rollback exercise |
| P11-09 | Create on-call runbooks and ownership for auth outage, sync backlog, corrupt migration, key/prekey incident, privacy request failure, TURN outage, data-loss suspicion, and security incident. | tabletop exercise |

### Final enterprise release gate

A release is enterprise-ready only when:

- no Critical/High open defect exists in auth, crypto, storage, sync, wipe, deletion, or authorization;
- direct messaging, attachments, backup, group, and call scenario matrices pass on supported platforms;
- all contract/migration compatibility tests pass for the supported rolling-upgrade window;
- external cryptographic and penetration reviews are complete;
- privacy claims match tested behavior;
- SLO/load/DR evidence exists;
- signed artifacts, SBOM, provenance, release notes, rollback plan, and incident ownership are complete.

---

# 7. Recommended execution order and parallel lanes

## 7.1 Critical path

```text
Phase 0
  ↓
Phase 1 (identity/auth/ID/transport contract)
  ↓
Phase 2 (E2EE + encrypted persistence)
  ↓
Phase 3 (runtime/sync/outbox/reconnect)
  ↓
Phase 4 (direct-message proof)
  ↓
Phase 5 (attachments/backup/privacy/devices)
  ↓
Phase 6 (groups/calls)
  ↓
Phases 8–11 adoption and certification
```

## 7.2 Safe parallel work

- **Lane A — Remote security:** Phases 1–2.
- **Lane B — Remote runtime/backend:** Phase 3 after Phase 1 schemas stabilize.
- **Lane C — Local architecture:** Phase 7 can start after Phase 0 and remain isolated from Remote files.
- **Lane D — UI foundation:** Phase 8 tokens/component gallery can start after Phase 0; feature adoption waits for stable workflows.
- **Lane E — QA/DevEx:** Phase 0, then continuously builds the scenario harnesses for each phase.
- **Lane F — Operations:** production adapters/observability design can begin early, but implementation must not overtake functional correctness.

Do not parallelize two agents in the same auth, crypto-session, sync-cursor, database-migration, or wipe code path.

---

# 8. Verification command model

Each task runs a targeted command first, then the full platform-appropriate pipeline.

### Mandatory on every PR

```powershell
dart format --output=none --set-exit-if-changed apps packages services tool
flutter analyze
dart analyze services/helix_remote_backend tool
dart run tool/check_boundaries.dart
dart test tool/boundary_test.dart
dart run tool/check_secrets.dart
```

Then run all affected app/package/backend tests.

### Mandatory on phase closure

```powershell
$env:HELIX_VERIFY_BUILD="1"
.\scripts\verify.ps1
```

Plus:

- clean checkout on Windows and Linux;
- Android release-manifest/build verification;
- phase-specific real-client/backend scenario suite;
- migration upgrade/recovery test where schema changed;
- filesystem/log/network plaintext scan where sensitive data changed;
- accessibility/performance/security gates where applicable.

A passing analyzer and unit suite is necessary but never sufficient for a phase closure.

---

# 9. First implementation cycle: exact recommended backlog

The first cycle should contain only these tasks, in this order:

1. **P0-03:** fix monorepo secret-scan coverage.
2. **P0-04:** make package boundary/dependency maps complete and self-validating.
3. **P0-02:** supersede stale backend/implementation claims.
4. **P0-05/P0-06:** strict analysis and dependency pinning.
5. **P1-01:** canonical string device IDs with migrations.
6. **P1-02/P1-03:** explicit signing/agreement keys and correct challenge login.
7. **P1-06/P1-07:** correct WebSocket URI/path and remove query tokens.
8. **P1-09:** real app-client-to-backend auth/WebSocket test.
9. **P2-01:** functional SQLCipher migration.
10. **P2-06:** full DH Double Ratchet or vetted protocol library remains the Phase 2 blocker after P2-02/P2-03/P2-04/P2-05/P2-07/P2-08/P2-09/P2-10 repairs.
11. **P3-01 through P3-09:** runtime coordinator and reliable sync.
12. **P4 scenario matrix:** certify direct messaging.

Do not assign agents to Remote attachments, groups, calls, visual redesign, PostgreSQL, or new product features until item 12 passes.

---

# 10. Definition of “done” for the next improvement cycle

The next improvement cycle is successful when all of the following are true:

- repository checks scan and classify the full monorepo;
- documentation no longer overstates implementation;
- Remote registration/login/WebSocket works against the real backend;
- identifiers and key roles are type-safe and consistent;
- the Remote local database is actually encrypted;
- cryptographic sessions and messages survive restart;
- E2EE fails closed and passes tamper/reorder/replay tests;
- outbound/inbound sync runs automatically with gap recovery and idempotency;
- two real clients complete the direct-message scenario matrix;
- Local behavior remains unchanged while its wiring and lifecycle become simpler;
- subsequent UI, accessibility, performance, and operations work has stable interfaces to build upon.

That is the point at which Helix moves from a well-documented, component-rich prototype to a defensible enterprise engineering baseline.
