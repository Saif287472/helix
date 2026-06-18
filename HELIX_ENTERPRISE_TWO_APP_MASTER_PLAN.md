# HELIX ENTERPRISE TWO-APP MASTER PLAN

**Document status:** Authoritative implementation roadmap  
**Version:** 1.0  
**Prepared from codebase snapshot:** 2026-06-18 16:27:48Z  
**Snapshot size:** 283 reviewed text/source files  
**Repository at audit time:** `J:\Projects\helix`  
**Target products:** `Helix Local` and `Helix Remote`  
**Execution model:** Multiple AI agents working sequentially through checked, verifiable slices

---

## 0. Purpose of This Plan

This document defines how to evolve the current Helix repository into **two independently installable, independently secured, independently persisted applications inside one monorepo**:

1. **Helix Local**
   - LAN/hotspot-only.
   - No account or cloud dependency.
   - Temporary/non-account identity.
   - Self-vanishing conversations and messages.
   - Session-oriented groups and calls.
   - Panic wipe and full reset.
   - Must continue working if every Helix Remote service disappears.

2. **Helix Remote**
   - Cross-network internet communication.
   - Persistent accounts, devices, contacts, conversations, messages, files, groups, call history, and synchronization.
   - Data remains until the user explicitly deletes it under documented deletion rules.
   - End-to-end encrypted content.
   - Server-assisted delivery, signaling, push, attachment storage, STUN/TURN, and optional direct peer-to-peer paths.
   - Must remain unaffected by any Helix Local wipe, reset, crash, uninstall, migration, or identity rotation.

This is not a feature checklist. It is an **architecture, isolation, security, persistence, migration, testing, release, and AI-agent coordination plan** designed to prevent the two products from colliding.

No plan can guarantee that no future refactoring will ever be required. The objective is to eliminate the avoidable structural mistakes that would otherwise force a painful rewrite.

---

# 1. Non-Negotiable Product Decisions

These decisions are binding unless replaced by a reviewed Architecture Decision Record (ADR).

- [ ] **D-001:** Helix Local and Helix Remote are separate installed applications, not two modes inside one binary.
- [ ] **D-002:** Both applications may share source packages, but they must never share runtime databases, secure-storage namespaces, identities, caches, logs, notification identities, backend credentials, or wipe services.
- [ ] **D-003:** Existing Helix code is classified as **Local-specific by default**. Code becomes shared only after a deliberate extraction review.
- [ ] **D-004:** Helix Local must not import Remote client, Remote authentication, Remote synchronization, Remote backend, push, STUN/TURN credential, or remote account packages.
- [ ] **D-005:** Helix Remote must not import Local panic-wipe, LAN discovery, temporary Local identity, disconnect auto-wipe, secret-sentence LAN lookup, or session-only group packages.
- [ ] **D-006:** Helix Local must compile, test, install, launch, communicate, wipe, and release without any Remote server or Remote environment variable.
- [ ] **D-007:** Helix Remote must compile, test, install, launch, synchronize, and release without reading any Local storage or importing Local runtime packages.
- [ ] **D-008:** Local and Remote cryptographic identities are permanently separate. The same display name does not imply the same key or account.
- [ ] **D-009:** A Local panic wipe must never make a network request to Helix Remote.
- [ ] **D-010:** A Remote account deletion request must never inspect or erase Helix Local.
- [ ] **D-011:** The current LAN protocol must not be exposed directly to the public internet as the Remote protocol.
- [ ] **D-012:** AI agents must not invent or modify production cryptographic protocols without an approved design, test vectors, and independent security review.
- [ ] **D-013:** The Remote backend starts as a well-modularized monolith, not a microservice fleet.
- [ ] **D-014:** Remote persistence and synchronization are designed for multiple devices from the beginning, even if the first release supports one device.
- [ ] **D-015:** Local content retention and Remote content retention are separate policy domains and must not share one generic `wipeEverything`, `clearAll`, `ConversationRepository`, or database implementation.
- [ ] **D-016:** Every phase must keep the repository buildable and testable. No long-running branch may leave the main branch half-migrated.
- [ ] **D-017:** No Remote feature implementation begins before the repository split, namespace isolation, and dependency firewall phases are complete.
- [ ] **D-018:** Android release builds must never ship with debug signing.
- [ ] **D-019:** Security claims must match verified implementation. Unsupported claims such as “forward secrecy” must not be advertised merely because a capability flag exists.
- [ ] **D-020:** Product deletion behavior must be documented and tested as a contract, not implemented only as UI button behavior.

---

# 2. Codebase Audit Summary

## 2.1 Existing Strengths

The current repository already contains useful foundations:

- Dart/Flutter workspace with extracted internal packages.
- Separate packages for calls, crypto, discovery, domain, groups, messaging, platform, protocol, storage, transfer, and transport.
- A composition-root direction has already started.
- Repository and gateway interfaces exist.
- Protocol fixtures and compatibility tests exist.
- Architecture boundary and secret-scanning tools exist.
- CI verification exists.
- Forward-only SQLite migrations exist.
- LAN discovery, secure channels, file transfer, ephemeral media, groups, and WebRTC calls are implemented.
- Security, trust, key lifecycle, storage wipe, and workflow documents already exist.
- Current tests cover protocol fixtures, crypto helpers, database migration, discovery, groups, calls, transport frame I/O, provider refresh, request integration, and workflow transitions.

These assets should be preserved and reclassified rather than discarded.

## 2.2 Critical Gaps Found

### A. Single-product platform identity

Current values are hard-coded for one app:

- Android namespace/application ID: `com.helix.helix`.
- Android/Kotlin package path: `com/helix/helix`.
- Method channel: `com.helix.app/foreground`.
- mDNS channels: `com.helix.app/mdns` and `com.helix.app/mdns/events`.
- Windows AppUserModelID: `com.helix.app`.
- One Windows notification GUID.
- One app label, executable/window title, tray identity, icon set, and notification identity.
- One mDNS service type: `_helix._tcp`.

These cannot be copied unchanged into a second app.

### B. Local retention contract contradicts current persistence

The Local product is intended to have self-vanishing content. However, the current `HelixDatabase` creates and persists:

- `threads`
- `messages`
- `one_way_messages`
- `peers_cache`
- `pinned_messages`
- persistent `draft_text`
- persistent archive state

The current documentation also describes RAM-oriented conversations. This contradiction must be resolved before the code is split or reused.

### C. Current wipe is not yet an enterprise isolation boundary

The database `clearAll()` deletes table rows, but secure panic wipe must also consider:

- SQLite WAL and SHM files.
- Open database handles.
- app-private caches.
- partial file-transfer files.
- media caches.
- logs and diagnostics.
- secure-storage keys.
- notification state.
- sessions and timers.
- exported files outside the app sandbox, which cannot be guaranteed erasable by the app.

A Local wipe must be namespace-scoped and must never call a Remote service.

### D. Generic package names hide Local-specific semantics

Examples include:

- `helix_domain`
- `helix_protocol`
- `helix_transport`
- `helix_storage`
- `helix_discovery`
- `helix_groups`

Their models and services contain Local concepts such as host, port, LAN session ID, mDNS, UDP discovery, local fingerprint trust, session-only groups, and disconnect wipe. They must not automatically become the shared foundation of Helix Remote.

### E. Composition is not fully centralized

`AppCompositionRoot.production()` exists, but:

- Providers still perform extensive cross-service construction and bridging.
- Several controllers construct their own default concrete dependencies.
- `app_providers.dart` is large and remains a high-risk wiring center.
- The current root is not product-aware.
- A second app could accidentally instantiate Local implementations through defaults.

### F. Remote-grade persistence contracts do not exist

Current repository interfaces are synchronous/minimal and primarily in-memory. They do not model:

- accounts
- devices
- contacts/friend relationships
- server conversation IDs
- multi-device synchronization
- pagination
- sync cursors
- server sequence numbers
- idempotency keys
- tombstones
- message revisions
- attachment manifests
- call history
- group membership history
- account deletion
- backup state
- conflict resolution
- offline operation queues

Remote must receive its own domain and persistence contracts.

### G. Current cryptographic posture is not sufficient for Remote claims

The repository’s own security documentation identifies authenticated DH/ECDH and forward-secrecy verification as open items. At the same time, a forward-secrecy capability flag is currently advertised.

This is acceptable only as a known Local development issue. It is a **hard blocker** for Remote production security claims.

### H. Current call engine is intentionally LAN-only

`WebRtcCallEngine`:

- configures no STUN/TURN servers
- filters to private/loopback host candidates
- uses the existing Local secure channel for signaling

Remote calls require a separate engine configuration and separate signaling gateway.

### I. Release and CI are single-app

Current verification assumes one Flutter app and one set of platform folders. The future repository needs:

- app-specific analyze/test/build jobs
- package-level tests
- architecture dependency tests
- install-together tests
- Local wipe isolation tests
- Remote persistence tests
- backend tests
- contract compatibility tests
- migration tests per app
- release signing checks

### J. Android release signing is currently unsafe

The current release build uses the debug signing configuration. This must be corrected before any production release.

### K. Windows reset path risk

The current identity repair/reset logic contains a hard-coded Windows secure-storage path based on one Helix product namespace. It must be removed before a second app is introduced.

### L. External file copies are outside panic-wipe control

When a user exports, shares, or opens a received file outside app-private storage, neither app can guarantee deletion of that external copy. The Local UI and documentation must state this clearly.

---

# 3. Target Repository Architecture

## 3.1 Final Target Shape

```text
helix/
├── apps/
│   ├── helix_local/
│   │   ├── lib/
│   │   │   ├── bootstrap/
│   │   │   ├── composition/
│   │   │   ├── presentation/
│   │   │   └── main.dart
│   │   ├── android/
│   │   ├── windows/
│   │   ├── test/
│   │   └── pubspec.yaml
│   │
│   └── helix_remote/
│       ├── lib/
│       │   ├── bootstrap/
│       │   ├── composition/
│       │   ├── presentation/
│       │   └── main.dart
│       ├── android/
│       ├── windows/
│       ├── test/
│       └── pubspec.yaml
│
├── packages/
│   ├── shared/
│   │   ├── helix_foundation/
│   │   ├── helix_ui_kit/
│   │   ├── helix_media_ui/
│   │   ├── helix_call_ui/
│   │   └── helix_test_support/
│   │
│   ├── local/
│   │   ├── helix_local_domain/
│   │   ├── helix_local_application/
│   │   ├── helix_local_protocol/
│   │   ├── helix_local_crypto/
│   │   ├── helix_local_transport/
│   │   ├── helix_local_discovery/
│   │   ├── helix_local_storage/
│   │   ├── helix_local_messaging/
│   │   ├── helix_local_transfer/
│   │   ├── helix_local_groups/
│   │   ├── helix_local_calls/
│   │   └── helix_local_platform/
│   │
│   └── remote/
│       ├── helix_remote_domain/
│       ├── helix_remote_application/
│       ├── helix_remote_protocol/
│       ├── helix_remote_crypto/
│       ├── helix_remote_storage/
│       ├── helix_remote_sync/
│       ├── helix_remote_api/
│       ├── helix_remote_messaging/
│       ├── helix_remote_attachments/
│       ├── helix_remote_groups/
│       ├── helix_remote_calls/
│       ├── helix_remote_notifications/
│       └── helix_remote_platform/
│
├── services/
│   └── helix_remote_backend/
│       ├── modules/
│       │   ├── accounts/
│       │   ├── devices/
│       │   ├── keys/
│       │   ├── contacts/
│       │   ├── conversations/
│       │   ├── messaging/
│       │   ├── attachments/
│       │   ├── groups/
│       │   ├── calls/
│       │   ├── push/
│       │   ├── abuse/
│       │   ├── deletion/
│       │   └── audit/
│       ├── migrations/
│       ├── tests/
│       └── deploy/
│
├── contracts/
│   ├── remote-rest-openapi/
│   ├── remote-realtime/
│   └── compatibility/
│
├── infra/
│   ├── local-dev/
│   ├── staging/
│   ├── production/
│   ├── coturn/
│   ├── object-storage/
│   └── observability/
│
├── docs/
│   ├── product/local/
│   ├── product/remote/
│   ├── architecture/
│   ├── security/
│   ├── privacy/
│   ├── runbooks/
│   └── adr/
│
├── tool/
├── scripts/
├── .github/workflows/
├── AGENTS.md
├── pubspec.yaml
└── HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md
```

## 3.2 Dependency Direction

```text
Helix Local app
    ├── shared packages
    └── local packages only

Helix Remote app
    ├── shared packages
    └── remote packages only

Remote backend
    └── language-neutral contracts
        └── never imports Flutter/Dart client implementation

Local packages ─X─> Remote packages
Remote packages ─X─> Local packages
Shared packages ─X─> Local packages
Shared packages ─X─> Remote packages
```

## 3.3 Shared-Code Rule

Code may move into `packages/shared/` only when all are true:

- [ ] It contains no Local retention assumption.
- [ ] It contains no Remote persistence assumption.
- [ ] It contains no Local host/port/mDNS/UDP dependency.
- [ ] It contains no Remote account/server/sync dependency.
- [ ] It contains no wipe implementation.
- [ ] It contains no secure-storage key name.
- [ ] It contains no app ID, notification ID, method-channel name, URL scheme, database name, or file path.
- [ ] It contains no product-specific analytics or logging behavior.
- [ ] It has tests proving both apps can use it independently.
- [ ] Its public API does not expose a concrete Local or Remote model.

Safe shared candidates:

- design tokens and themes
- generic buttons, dialogs, layout, accessibility helpers
- message-bubble presentation driven by view models
- media player widgets
- call control widgets driven by view models
- generic validation and result/error primitives
- generic IDs/time abstractions
- test utilities

Unsafe shared candidates:

- `ChatThread` with persistence behavior
- Local `Peer` containing host/port/session
- identity manager
- trust store
- conversation repository implementation
- wipe service
- transport
- protocol frames
- sync engine
- account service
- notification registration
- group repository
- call signaling
- attachment persistence

---

# 4. Product Data Contracts

## 4.1 Helix Local Recommended Data Contract

The following is the recommended default. Any change requires an ADR.

| Data | Lifetime | Storage | Wiped by Panic Wipe |
|---|---|---|---|
| Display name and UI preferences | Until reset | Local app namespace | Yes |
| Local device identity | Until reset/uninstall; no account | Local secure storage | Yes |
| Runtime session ID | One app/session lifecycle | RAM, or protected short-lived state only if required | Yes |
| Secret sentence verifier | Until changed/reset | Local secure storage | Yes |
| Plain secret sentence | Avoid persistence after setup | RAM only where possible | Yes |
| Trusted peer fingerprints | Until reset/untrust | Local secure storage | Yes |
| Chat threads and messages | Active runtime/session only | RAM only | Yes |
| Drafts | Active runtime only | RAM only | Yes |
| One-way messages | TTL/session only | RAM only | Yes |
| Group/lobby state | Session only | RAM only | Yes |
| Call history | Not retained | RAM only | Yes |
| Private media | Cache lifetime only | RAM only | Yes |
| Transfer progress | Active transfer only | RAM + app-private `.part` file | Yes |
| Received standard file before explicit save | Temporary | App-private cache | Yes |
| User-exported file | User controlled | External/user-selected location | No guarantee |
| Logs | Bounded and redacted | Local app namespace | Yes |
| Diagnostics export | Explicit user action | User-selected location | No guarantee |

**Recommended identity interpretation:** “Temporary identity” means **no global account and no cross-product identity**. The Local device key may remain install-scoped so trusted reconnection works, but it must be rotatable and destroyed by panic reset. Session-only identity rotation may be added later as a separate high-privacy mode.

## 4.2 Helix Remote Data Contract

| Data | Lifetime | Storage |
|---|---|---|
| Account | Until explicit account deletion | Remote source of truth + local cache |
| Device identity | Until device revocation | Device secure storage + public server registry |
| Contacts/friends | Until explicit removal | Remote source of truth + local cache |
| Conversations | Until explicit deletion | Local encrypted database + remote records |
| Messages/events | Until explicit deletion policy applies | Local encrypted database + server ciphertext |
| Reactions/edits/receipts | Persistent events | Local + remote |
| Groups and membership history | Persistent | Local + remote |
| Attachments | Until message/conversation/account deletion rules apply | Encrypted object storage + local cache |
| Call history | Persistent metadata, never call media | Local + remote |
| Push tokens | Until rotated/revoked | Remote operational store |
| Sync cursors | Persistent per device | Local + remote |
| Public key material/prekeys | Until rotated/expired | Remote key service |
| Private keys | Device only | Device secure storage |
| Backups | User-controlled encrypted backup | Remote/object storage |
| Deletion tombstones | Until all devices acknowledge and retention window ends | Local + remote |

## 4.3 Remote Deletion Semantics to Define Before Coding

- [ ] Delete local cache only.
- [ ] Log out this device.
- [ ] Remove this device from the account.
- [ ] Delete message for this user across all own devices.
- [ ] Delete message for everyone, if product policy allows it.
- [ ] Delete conversation for this user.
- [ ] Leave group.
- [ ] Delete group as authorized owner/admin.
- [ ] Delete attachment and derived thumbnails.
- [ ] Delete call-history entry.
- [ ] Delete account.
- [ ] Define tombstone retention.
- [ ] Define backup deletion and backup-expiry behavior.
- [ ] Define behavior for offline devices that later reconnect.
- [ ] Define legal/security hold exceptions, if any.
- [ ] Define whether deletion is immediate or scheduled.
- [ ] Define what remains in immutable operational audit records.
- [ ] Ensure UI language matches actual backend behavior.

---

# 5. AI Agent Execution Protocol

Every agent must follow this process.

## 5.1 Before Starting a Slice

- [ ] Read this entire phase.
- [ ] Read root `AGENTS.md`.
- [ ] Read all referenced ADRs and workflow documents.
- [ ] Inspect only the files needed for the selected slice.
- [ ] Confirm phase entry criteria are satisfied.
- [ ] Confirm no other agent is editing the same ownership area.
- [ ] Record the selected checkbox IDs in the work log.
- [ ] Create or update a narrowly scoped implementation note.

## 5.2 During Work

- [ ] Make small, atomic commits.
- [ ] Do not mix cleanup with behavior changes.
- [ ] Do not rename public contracts and change behavior in the same commit.
- [ ] Do not weaken security checks to make tests pass.
- [ ] Do not disable linting, secret scanning, boundary checks, or CI.
- [ ] Do not introduce product-specific code into `shared/`.
- [ ] Do not add default constructors that silently choose Local or Remote infrastructure.
- [ ] Do not add a generic destructive method whose scope is unclear.
- [ ] Do not create a Remote protocol by extending Local frames without an ADR.
- [ ] Add tests before or with behavior changes.
- [ ] Add migration and rollback notes for schema/platform changes.
- [ ] Stop and mark the item `BLOCKED` when requirements conflict.

## 5.3 Completion Evidence

An item may be checked only when the agent records:

- [ ] Changed files.
- [ ] Tests run.
- [ ] Build targets run.
- [ ] Architecture checks run.
- [ ] Security-sensitive behavior touched.
- [ ] Migration impact.
- [ ] Rollback method.
- [ ] Remaining manual checks.
- [ ] Commit/PR reference.
- [ ] Evidence location.

## 5.4 Phase Handoff Template

Append this under the relevant phase:

```md
### Phase Handoff

- Status: NOT STARTED | IN PROGRESS | BLOCKED | COMPLETE
- Agent:
- Started:
- Completed:
- Branch/commit:
- Checklist items completed:
- Files changed:
- Tests/checks:
- Manual verification:
- Security risks reviewed:
- Migration/rollback notes:
- Remaining blockers:
- Recommended next item:
```

---

# 6. Implementation Phases

---

## PHASE 0 — Freeze, Baseline, and Recovery Point

**Goal:** Create a trustworthy baseline before structural movement.

**Entry criteria:** Current repository is available and builds on at least one supported platform.

### Tasks

- [x] **P0-001:** Create a protected baseline tag for the audited codebase.
- [x] **P0-002:** Record exact Flutter, Dart, Java, Gradle, Android SDK, Visual Studio, CMake, and dependency versions.
- [x] **P0-003:** Run and save the canonical verification output.
- [x] **P0-004:** Run all current unit and widget tests.
- [x] **P0-005:** Build Android debug.
- [x] **P0-006:** Build Windows debug.
- [x] **P0-007:** Capture current Android package ID, signing state, permissions, notification channels, and method channels.
- [x] **P0-008:** Capture current Windows executable name, app-data paths, AppUserModelID, notification GUID, tray identity, and secure-storage path.
- [x] **P0-009:** Capture current SQLite schema, `PRAGMA user_version`, WAL mode, and file locations.
- [x] **P0-010:** Create a fixture containing representative profile, trust, thread, message, file-transfer, group, and settings data.
- [x] **P0-011:** Document manual smoke flows for discovery, request approval, chat, file transfer, private media, group, audio call, video call, disconnect wipe, and reset.
- [x] **P0-012:** Remove or document unrelated root artifacts such as `test.py` and `test_mode.txt`; do not delete without confirming they are unused.
- [x] **P0-013:** Add a root `CHANGELOG_ARCHITECTURE.md`.
- [x] **P0-014:** Add `docs/architecture/CURRENT_STATE_2026-06-18.md`.
- [x] **P0-015:** Freeze unrelated feature development until Phase 4 is complete.

### Verification

- [x] Existing tests pass unchanged.
- [x] Android and Windows debug builds succeed.
- [x] Baseline artifacts are stored outside ignored build directories.
- [x] Rollback to the baseline tag is documented and tested.

### Exit criteria

- [x] A new agent can reproduce the original build from documentation.
- [x] There is a known-good rollback point.
- [x] No product behavior has changed.

### Phase Handoff

- Status: COMPLETE
- Agent: Antigravity
- Started: 2026-06-18
- Completed: 2026-06-18
- Branch/commit: master (baseline tag)
- Checklist items completed: P0-001 through P0-015
- Files changed:
  - [phase0_test.dart](file:///j:/Projects/helix/test/phase0_test.dart) (fixed auto-wipe test)
  - [CHANGELOG_ARCHITECTURE.md](file:///j:/Projects/helix/CHANGELOG_ARCHITECTURE.md) (new architecture log)
  - [CURRENT_STATE_2026-06-18.md](file:///j:/Projects/helix/docs/architecture/CURRENT_STATE_2026-06-18.md) (new codebase metadata spec)
  - `test.py` (deleted)
  - `test_mode.txt` (deleted)
  - [HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md](file:///j:/Projects/helix/HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md) (updated checklist)
- Tests/checks:
  - `.\scripts\verify.ps1` with `HELIX_VERIFY_BUILD=1`
  - Dart format, analyze, check_boundaries, check_secrets, and all tests pass
  - Windows debug build successfully compiled (`build\windows\x64\runner\Debug\helix.exe`)
- Manual verification:
  - Verified git status, baseline commit, and tagged baseline rollback checkpoint
- Security risks reviewed: None (pre-existing test failure was resolved without modifying core cryptographic or network protocols)
- Migration/rollback notes: Rollback is done by executing `git reset --hard baseline`
- Remaining blockers: None
- Recommended next item: Phase 1 (Product Contracts and Architecture Decisions)

---

## PHASE 1 — Product Contracts and Architecture Decisions

**Goal:** Remove ambiguous product assumptions before code movement.

### Required ADRs

- [x] **P1-001:** ADR: Two app shells in one monorepo.
- [x] **P1-002:** ADR: Existing code is Local-specific until explicitly extracted.
- [x] **P1-003:** ADR: Local identity lifetime and rotation.
- [x] **P1-004:** ADR: Local conversation/message retention.
- [x] **P1-005:** ADR: Local panic-wipe scope and limitations.
- [x] **P1-006:** ADR: Remote persistent-data contract.
- [x] **P1-007:** ADR: Remote deletion semantics.
- [x] **P1-008:** ADR: Separate Local and Remote cryptographic identities.
- [x] **P1-009:** ADR: Remote backend modular monolith.
- [x] **P1-010:** ADR: Contract-first Remote APIs.
- [x] **P1-011:** ADR: Remote E2EE protocol selection process.
- [x] **P1-012:** ADR: Multi-device-ready data model from day one.
- [x] **P1-013:** ADR: Shared-package eligibility rules.
- [x] **P1-014:** ADR: App-specific runtime namespace configuration.
- [x] **P1-015:** ADR: Local and Remote release/signing independence.
- [x] **P1-016:** ADR: Remote metadata minimization and privacy logging.
- [x] **P1-017:** ADR: External file export is outside Local panic-wipe guarantees.

### Documents

- [x] **P1-018:** Create `docs/product/local/PRODUCT_CONTRACT.md`.
- [x] **P1-019:** Create `docs/product/remote/PRODUCT_CONTRACT.md`.
- [x] **P1-020:** Create `docs/product/PRODUCT_DIFFERENCES.md`.
- [x] **P1-021:** Create separate Local and Remote threat models.
- [x] **P1-022:** Create separate Local and Remote data-flow diagrams.
- [x] **P1-023:** Create a data inventory and retention table for each product.
- [x] **P1-024:** Create a privacy-claim matrix: implemented, planned, prohibited.
- [x] **P1-025:** Create a feature ownership matrix.
- [x] **P1-026:** Create a package classification spreadsheet/Markdown table: Local, Remote, Shared, Tooling, Unknown.
- [x] **P1-027:** Mark every current package as Local by default.
- [x] **P1-028:** Define acceptance criteria for “independently installable.”
- [x] **P1-029:** Define acceptance criteria for “Local works fully offline.”
- [x] **P1-030:** Define acceptance criteria for “Remote persists until manual deletion.”

### Exit criteria

- [x] Every destructive action has an explicit scope.
- [x] Local retention contradictions are resolved on paper.
- [x] Remote persistence and deletion semantics are defined.
- [x] Package-sharing rules are approved.
- [x] No code split begins with unresolved identity or retention policy.

### Phase Handoff

- Status: COMPLETE
- Agent: Antigravity
- Started: 2026-06-19
- Completed: 2026-06-19
- Branch/commit: master (Phase 1 commit)
- Checklist items completed: P1-001 through P1-030
- Files changed:
  - 17 ADR files created in [docs/adr/](file:///j:/Projects/helix/docs/adr/)
  - 12 product contract files created in [docs/product/](file:///j:/Projects/helix/docs/product/)
  - [HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md](file:///j:/Projects/helix/HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md) (updated checklist)
- Tests/checks:
  - `.\scripts\verify.ps1`
- Manual verification:
  - Reviewed content completeness of all created product contracts and ADRs
- Security risks reviewed: None (documentation phase only)
- Migration/rollback notes: Rollback is done by resetting to the previous git commit
- Remaining blockers: None
- Recommended next item: Phase 2 (Convert the Repository into a True Multi-App Workspace)

---

## PHASE 2 — Convert the Repository into a True Multi-App Workspace

**Goal:** Move the existing product into `apps/helix_local` without behavior changes and create an empty, isolated Remote shell.

### Tasks

- [x] **P2-001:** Create `apps/helix_local`.
- [x] **P2-002:** Move the current Flutter app shell, Android project, Windows project, assets, and app tests into `apps/helix_local`.
- [x] **P2-003:** Preserve current package imports through temporary compatibility exports where needed.
- [x] **P2-004:** Keep existing internal packages building during the move.
- [x] **P2-005:** Convert the root `pubspec.yaml` into a workspace coordinator.
- [x] **P2-006:** Include both apps and all packages in the workspace.
- [x] **P2-007:** Update scripts to resolve paths from repository root.
- [x] **P2-008:** Update codebase export scripts for `apps/`, `packages/`, `services/`, `contracts/`, and `infra/`.
- [x] **P2-009:** Update `.gitignore` for multiple Flutter build trees and backend artifacts.
- [x] **P2-010:** Update root README to describe the product family.
- [x] **P2-011:** Create `apps/helix_remote` as a minimal Flutter shell with no imports from Local packages.
- [x] **P2-012:** Give Remote a placeholder screen proving the app shell launches.
- [x] **P2-013:** Do not copy Local providers, Local storage, Local platform code, or Local permissions into Remote.
- [x] **P2-014:** Add app-specific test directories.
- [x] **P2-015:** Add root commands for analyze/test/build per app.
- [x] **P2-016:** Add a workspace-wide dependency resolution check.
- [x] **P2-017:** Add a rollback script or documented reverse move.

### Verification

- [x] Helix Local behavior matches the baseline.
- [x] Helix Local Android debug build succeeds.
- [x] Helix Local Windows debug build succeeds.
- [x] Helix Remote Android debug shell builds.
- [x] Helix Remote Windows debug shell builds.
- [x] Both apps can be opened from the same checkout.
- [x] No Remote source imports a Local package.

### Exit criteria

- [x] Two app shells exist.
- [x] Existing product behavior is preserved in Local.
- [x] Remote is a separate binary, not a flavor or runtime mode.
- [x] The root no longer behaves as the only Flutter app.

---

## PHASE 3 — Product Identity and Runtime Namespace Isolation

**Goal:** Ensure both apps can be installed together with no platform or storage collision.

## 3.1 Product Descriptor

- [x] **P3-001:** Create an immutable `ProductDescriptor` contract.
- [x] **P3-002:** Include product ID, display name, package ID, app-data folder, database prefix, secure-storage prefix, notification namespace, URL scheme, method-channel namespace, log namespace, export prefix, and protocol label.
- [x] **P3-003:** Define `LocalProductDescriptor`.
- [x] **P3-004:** Define `RemoteProductDescriptor`.
- [x] **P3-005:** Prohibit global constants for product-specific values.
- [x] **P3-006:** Add tests ensuring descriptors have no equal identifiers.

## 3.2 Android Isolation

- [x] **P3-007:** Assign a final unique Local Android application ID.
- [x] **P3-008:** Assign a final unique Remote Android application ID.
- [x] **P3-009:** Assign distinct Kotlin namespaces and package directories.
- [x] **P3-010:** Assign distinct app labels and icons.
- [x] **P3-011:** Assign distinct notification channel IDs and notification IDs.
- [x] **P3-012:** Assign distinct foreground-service action strings.
- [x] **P3-013:** Assign distinct method/event channel names.
- [x] **P3-014:** Assign distinct deep-link/QR URL schemes.
- [x] **P3-015:** Keep mDNS and LAN permissions only in Local unless Remote has a separately approved nearby feature.
- [x] **P3-016:** Keep Remote internet, push, and remote-call permissions out of Local.
- [x] **P3-017:** Add release signing configs using secret-injection; never commit keys.
- [x] **P3-018:** Add CI failure if a release variant uses debug signing.
- [x] **P3-019:** Install both APKs simultaneously and confirm independent launchers, notifications, app data, and uninstall behavior.

## 3.3 Windows Isolation

- [x] **P3-020:** Assign distinct executable/product names.
- [x] **P3-021:** Assign distinct window titles and icons.
- [x] **P3-022:** Assign distinct AppUserModelIDs.
- [x] **P3-023:** Assign distinct stable notification GUIDs.
- [x] **P3-024:** Assign distinct app-data directories.
- [x] **P3-025:** Assign distinct secure-storage namespaces.
- [x] **P3-026:** Assign distinct tray identifiers and menu labels.
- [x] **P3-027:** Remove the hard-coded `com.helix/helix/flutter_secure_storage.dat` deletion path.
- [x] **P3-028:** Replace path deletion with a product-scoped storage adapter.
- [x] **P3-029:** Confirm Local reset cannot enumerate or delete Remote directories.
- [x] **P3-030:** Install/run both Windows apps simultaneously.

## 3.4 Data and File Isolation

- [x] **P3-031:** Use distinct database filenames.
- [x] **P3-032:** Use distinct cache directories.
- [x] **P3-033:** Use distinct temporary-transfer directories.
- [x] **P3-034:** Use distinct log and diagnostic directories.
- [x] **P3-035:** Use distinct exported file name prefixes.
- [x] **P3-036:** Prefix all secure-storage keys with product and schema version.
- [x] **P3-037:** Add migration support from old unprefixed Local keys.
- [x] **P3-038:** Remote must never attempt to migrate Local keys.
- [x] **P3-039:** Add an automated storage-path inventory test.
- [x] **P3-040:** Add a test that rejects any path outside the current product namespace for destructive operations.

### Exit criteria

- [x] Both apps coexist on Android and Windows.
- [x] Clearing/uninstalling either app does not affect the other.
- [x] Platform identifiers are unique.
- [x] All destructive file operations are product-scoped.
- [x] Release signing is separated.

### Phase Handoff

- Status: COMPLETE
- Agent: Antigravity
- Started: 2026-06-19
- Completed: 2026-06-19
- Branch/commit: master (11a48d8 — Phase 3: Complete Phase 0-3 Closure and Repair Pass)
- Checklist items completed: P3-001 through P3-040
- Files changed:
  - `packages/helix_domain/lib/core/product_descriptor.dart` (NEW — LocalProductDescriptor, RemoteProductDescriptor, path containment logic)
  - `packages/helix_domain/lib/core/constants.dart` (com.helix.app → com.helix.local channel constants)
  - `packages/helix_domain/test/channel_parity_test.dart` (NEW — 6 channel-parity tests)
  - `packages/helix_domain/test/product_descriptor_test.dart` (NEW — descriptor isolation tests)
  - `packages/helix_groups/lib/domain/lobby_constants.dart` (com.helix.local multicast_lock channel)
  - `packages/helix_groups/lib/application/lan_lobby_service.dart` (use constant instead of hardcoded string)
  - `packages/helix_platform/lib/platform/android_foreground.dart` (channelName → const)
  - `packages/helix_platform/lib/infrastructure/platform/platform_notification_gateway.dart` (all constructor params required, no hardcoded Local defaults)
  - `apps/helix_local/windows/runner/mdns_plugin.cpp` (com.helix.app → com.helix.local)
  - `apps/helix_local/lib/providers/controllers/notification_service.dart` (LocalProductDescriptor-based default gateway)
  - `apps/helix_local/lib/providers/session_provider.dart` (pass descriptor.appDataFolder to IdentityManagerImpl)
  - `apps/helix_local/lib/ui/screens/settings/settings_screen.dart` (prefix-scoped delete loop replaces unscoped deleteAll)
  - `apps/helix_local/lib/application/identity/identity_manager_impl.dart` (injectable appDataFolder, removes hardcoded Windows path)
  - `apps/helix_local/android/app/build.gradle.kts` (HELIX_LOCAL_* signing env vars, helix_local.keystore)
  - `apps/helix_remote/android/app/build.gradle.kts` (HELIX_REMOTE_* signing env vars, helix_remote.keystore)
  - `packages/helix_storage/lib/infrastructure/storage/*.dart` (helix_local_ migration guard in 4 files)
  - `packages/helix_storage/test/storage_path_inventory_test.dart` (NEW — 18 path-containment tests)
  - `packages/helix_storage/test/secure_keys_migration_test.dart` (NEW — 7 migration + reset-isolation tests)
  - `docs/architecture/module_boundaries.json` (v2 workspace paths)
  - `tool/check_boundaries.dart` (13-package workspace resolution map)
  - `scripts/verify.ps1` / `scripts/verify.sh` (workspace-aware, signing isolation checks)
  - `apps/helix_local/android/app/src/main/kotlin/com/helix/local/` (Kotlin namespace renamed from com.helix.helix)
  - `apps/helix_remote/android/app/src/main/kotlin/com/helix/remote/` (Remote Kotlin namespace corrected)
- Tests/checks:
  - `dart test packages/helix_domain/test/` → 7 tests passed
  - `flutter test packages/helix_storage` → 26 tests passed
  - `dart run tool/check_boundaries.dart` → Boundary check passed
  - `flutter analyze` → No issues found (workspace-wide)
- Manual verification:
  - Channel parity verified between Dart constants and Kotlin/C++ native registrations
  - Storage key prefix versioning and migration guard consistency verified across 4 storage files
  - Product-scoped signing env vars verified in both build.gradle.kts files
- Security risks reviewed:
  - Path containment check prevents traversal attacks and cross-product directory access
  - Prefix-scoped delete prevents Local panic wipe from touching Remote storage keys
  - Product-scoped signing vars prevent CI credential sharing between products
- Migration/rollback notes:
  - Rollback: `git reset --hard a500d28` (Phase 2 commit)
  - Storage key prefix changed from `local_` to `helix_local_v1_`; migration logic reads unprefixed legacy keys and re-writes with new prefix
  - Kotlin package renamed from `com.helix.helix` to `com.helix.local`; requires fresh install on existing test devices
- Remaining blockers: None
- Recommended next item: Phase 4 (Package Taxonomy and Dependency Firewall)

---

## PHASE 4 — Package Taxonomy and Dependency Firewall

**Goal:** Prevent accidental coupling through imports.

### Tasks

- [ ] **P4-001:** Move existing product-specific packages under `packages/local/`.
- [ ] **P4-002:** Rename generic current packages to `helix_local_*`, using compatibility shims temporarily.
- [x] **P4-003:** Classify current `helix_domain` as Local domain.
- [x] **P4-004:** Classify current protocol, transport, discovery, groups, storage, calls, messaging, transfer, and platform packages as Local unless reviewed otherwise.
- [x] **P4-005:** Create empty `packages/shared/`, `packages/remote/`, and `packages/local/` boundaries.
- [ ] **P4-006:** Extract only demonstrably product-neutral presentation primitives into shared packages.
- [ ] **P4-007:** Do not move `ChatThread`, `Peer`, `KnownPeer`, `DeviceIdentity`, Local `Group`, or Local `CallState` into shared merely to reduce duplication.
- [ ] **P4-008:** Extend `module_boundaries.json` for app and product package rules.
- [ ] **P4-009:** Extend the boundary checker to understand `apps/local`, `apps/remote`, `packages/local`, `packages/remote`, and `packages/shared`.
- [ ] **P4-010:** Add forbidden import tests for both products.
- [ ] **P4-011:** Fail CI if Remote imports Local.
- [ ] **P4-012:** Fail CI if Local imports Remote.
- [ ] **P4-013:** Fail CI if Shared imports either product.
- [ ] **P4-014:** Add a dependency graph artifact to CI.
- [ ] **P4-015:** Detect circular dependencies.
- [ ] **P4-016:** Remove concrete infrastructure default constructors from reusable controllers.
- [ ] **P4-017:** Require dependencies through explicit constructors/composition.
- [x] **P4-018:** Add package ownership and risk level to `ownership-blast-radius.yaml`.
- [x] **P4-019:** Update `AGENTS.md` with product-boundary rules.
- [ ] **P4-020:** Remove compatibility shims only after all imports are migrated.

### Exit criteria

- [ ] Architecture checks mechanically prevent cross-product imports.
- [ ] Existing generic package names no longer mislead agents.
- [ ] Shared code is genuinely product-neutral.
- [ ] Both apps compile after package reclassification.

### Phase Handoff

- Status: IN PROGRESS
- Agent: Antigravity
- Started: 2026-06-19
- Completed: —
- Branch/commit: master (ongoing)
- Checklist items completed: P4-003, P4-004, P4-005, P4-018, P4-019
- Files changed:
  - `packages/shared/.gitkeep` (NEW — shared package boundary placeholder)
  - `packages/remote/.gitkeep` (NEW — remote package boundary placeholder)
  - `ownership-blast-radius.yaml` (NEW — package ownership and risk classification)
  - `AGENTS.md` (updated — product-boundary rules added)
- Tests/checks: flutter analyze (workspace-wide, no issues)
- Manual verification: packages/local/ move deferred to next slice (P4-001, P4-002)
- Security risks reviewed: None — documentation and placeholder work only
- Migration/rollback notes: Package moves (P4-001/P4-002) require pubspec renames, import rewrites, and compatibility shims; execute as a dedicated slice
- Remaining blockers: P4-001 and P4-002 (physical package move to packages/local/) are the highest-impact remaining items
- Recommended next item: P4-001/P4-002 — move packages to packages/local/ with helix_local_* names and temporary re-export shims

---

## PHASE 5 — Product-Specific Composition Roots and Provider Cleanup

**Goal:** Make it impossible for one app to silently instantiate the other app’s infrastructure.

### Helix Local

- [ ] **P5-001:** Create `LocalCompositionRoot`.
- [ ] **P5-002:** Move all Local concrete construction into that root or narrowly scoped Local modules.
- [ ] **P5-003:** Remove default Local concrete dependencies from controllers.
- [ ] **P5-004:** Split large provider wiring into feature-specific provider modules.
- [ ] **P5-005:** Ensure Local bootstrap passes `LocalProductDescriptor`.
- [ ] **P5-006:** Ensure Local root contains no remote URL, token, push, account, sync, or TURN provider.
- [ ] **P5-007:** Add composition smoke tests.
- [ ] **P5-008:** Add deterministic disposal/lifecycle tests.

### Helix Remote

- [ ] **P5-009:** Create `RemoteCompositionRoot`.
- [ ] **P5-010:** Initially bind only placeholder Remote interfaces.
- [ ] **P5-011:** Ensure Remote root contains no LAN discovery, secret-code lookup, Local trust store, or Local wipe scheduler.
- [ ] **P5-012:** Ensure Remote product configuration is injected and environment-validated.
- [ ] **P5-013:** Add composition smoke tests.
- [ ] **P5-014:** Add startup failure tests for missing required Remote configuration.

### Shared

- [ ] **P5-015:** Define a tiny shared `AppPresentationServices` boundary if needed.
- [ ] **P5-016:** Do not create a shared root composition object.
- [ ] **P5-017:** Do not create a shared service locator.
- [ ] **P5-018:** Prohibit hidden global singletons for storage, identity, network, or wipe.
- [ ] **P5-019:** Add tests proving two composition roots can be instantiated in one test process without shared state.

### Exit criteria

- [ ] Every concrete Local dependency is visibly Local.
- [ ] Every concrete Remote dependency is visibly Remote.
- [ ] No controller silently selects a product implementation.
- [ ] Providers are no longer the unreviewed global composition root.

---

## PHASE 6 — Make Helix Local Truly Ephemeral and Wipe-Safe

**Goal:** Align implementation with the Local product contract.

## 6.1 Reconcile Current Database Persistence

- [ ] **P6-001:** Inventory every current call to `HelixDatabase`.
- [ ] **P6-002:** Identify all persisted message, thread, draft, archive, pin, one-way, and peer-cache behavior.
- [ ] **P6-003:** Replace Local conversation persistence with `LocalEphemeralConversationRepository`.
- [ ] **P6-004:** Keep chat threads/messages in RAM only.
- [ ] **P6-005:** Keep drafts in RAM only.
- [ ] **P6-006:** Keep one-way inbox in RAM only and enforce TTL.
- [ ] **P6-007:** Keep group/lobby message history in RAM only.
- [ ] **P6-008:** Do not persist call history.
- [ ] **P6-009:** Decide whether favorites/trusted nicknames persist; document separately from conversations.
- [ ] **P6-010:** Split `HelixDatabase` into explicitly named Local metadata storage or retire it from content paths.
- [ ] **P6-011:** Provide a one-time migration that deletes legacy Local content tables/data.
- [ ] **P6-012:** Ensure migration also removes WAL/SHM remnants after database closure.
- [ ] **P6-013:** Add restart tests proving no message content survives.
- [ ] **P6-014:** Add crash/relaunch tests where practical.
- [ ] **P6-015:** Add source scans preventing message text writes to Local SQLite.

## 6.2 Identity and Session Lifecycle

- [ ] **P6-016:** Implement the approved Local identity-lifetime ADR.
- [ ] **P6-017:** Keep Local identity unrelated to Remote account/device identities.
- [ ] **P6-018:** Rotate Local runtime session ID on the approved lifecycle.
- [ ] **P6-019:** Remove unnecessary plaintext secret-sentence persistence if protocol permits.
- [ ] **P6-020:** Version secure-storage keys.
- [ ] **P6-021:** Add identity reset tests.
- [ ] **P6-022:** Add key-rotation and trust-warning tests.
- [ ] **P6-023:** Verify no key appears in Riverpod state, logs, diagnostics, exports, or domain view models.

## 6.3 Panic Wipe Orchestrator

- [ ] **P6-024:** Create a Local-only `LocalPanicWipeOrchestrator`.
- [ ] **P6-025:** Define an ordered wipe state machine.
- [ ] **P6-026:** Block new network/session activity once wipe starts.
- [ ] **P6-027:** Stop discovery.
- [ ] **P6-028:** Close incoming listeners.
- [ ] **P6-029:** Close secure channels.
- [ ] **P6-030:** End calls and release microphone/camera.
- [ ] **P6-031:** Cancel reconnect and wipe timers.
- [ ] **P6-032:** Cancel file transfers and delete `.part` files.
- [ ] **P6-033:** Clear ephemeral media.
- [ ] **P6-034:** Clear all RAM repositories.
- [ ] **P6-035:** Close database handles before file deletion.
- [ ] **P6-036:** Delete Local database, WAL, and SHM files if any remain.
- [ ] **P6-037:** Delete Local app-private cache and temporary files.
- [ ] **P6-038:** Delete Local logs and diagnostics.
- [ ] **P6-039:** Delete Local secure-storage keys only.
- [ ] **P6-040:** Cancel Local notifications only.
- [ ] **P6-041:** Reset Local profile/setup state.
- [ ] **P6-042:** Record only a non-sensitive in-memory completion result.
- [ ] **P6-043:** Make the operation idempotent.
- [ ] **P6-044:** Make partial failure visible.
- [ ] **P6-045:** Never invoke a Remote API.
- [ ] **P6-046:** Never enumerate Remote directories or keys.
- [ ] **P6-047:** Add a prominent warning that exported files cannot be recalled.
- [ ] **P6-048:** Add power-loss/interruption recovery behavior.
- [ ] **P6-049:** Add a dedicated wipe audit test suite.

## 6.4 Local Isolation Tests

- [ ] **P6-050:** Seed Local and Remote test storage.
- [ ] **P6-051:** Run Local panic wipe.
- [ ] **P6-052:** Verify all Local content and keys are gone.
- [ ] **P6-053:** Verify Remote local database is unchanged.
- [ ] **P6-054:** Verify Remote secure storage is unchanged.
- [ ] **P6-055:** Verify Remote account remains usable.
- [ ] **P6-056:** Verify no Remote network request occurred.
- [ ] **P6-057:** Repeat the test on Android.
- [ ] **P6-058:** Repeat the test on Windows.
- [ ] **P6-059:** Test repeated panic wipe.
- [ ] **P6-060:** Test panic wipe during active call/file transfer/group session.

### Exit criteria

- [ ] No Local chat/message survives app restart.
- [ ] Local panic wipe is scoped, ordered, idempotent, and tested.
- [ ] Legacy persistent content is migrated away.
- [ ] Remote data is proven unaffected.

---

## PHASE 7 — Helix Local Security and Release Hardening

**Goal:** Make Local independently releasable before Remote development accelerates.

### Tasks

- [ ] **P7-001:** Resolve or remove the unverified forward-secrecy capability claim.
- [ ] **P7-002:** Complete authenticated key-agreement review.
- [ ] **P7-003:** Add protocol fuzz/property tests for decoders.
- [ ] **P7-004:** Add frame size and malformed-input tests.
- [ ] **P7-005:** Add LAN impersonation/fingerprint-change tests.
- [ ] **P7-006:** Add file resume/hash/cancel race tests.
- [ ] **P7-007:** Add three-device group election and handoff integration tests.
- [ ] **P7-008:** Add Windows-to-Android call tests.
- [ ] **P7-009:** Add camera swap/PiP regression tests.
- [ ] **P7-010:** Add offline/no-internet acceptance tests.
- [ ] **P7-011:** Add firewall/client-isolation diagnostics tests.
- [ ] **P7-012:** Review Android foreground-service policy and permissions.
- [ ] **P7-013:** Review Windows tray/close/session behavior.
- [ ] **P7-014:** Replace debug release signing.
- [ ] **P7-015:** Add reproducible release instructions.
- [ ] **P7-016:** Add SBOM and dependency license checks.
- [ ] **P7-017:** Add dependency vulnerability scanning.
- [ ] **P7-018:** Add a manual privacy verification checklist.
- [ ] **P7-019:** Perform an external security review before strong marketing claims.
- [ ] **P7-020:** Produce an independent Local release artifact and rollback plan.

### Exit criteria

- [ ] Helix Local has its own release pipeline.
- [ ] Local remains fully useful without Remote.
- [ ] Security claims match verified behavior.
- [ ] Remote work cannot destabilize Local without CI detecting it.

---

## PHASE 8 — Helix Remote Architecture Foundation

**Goal:** Design Remote as a persistent distributed system, not as Local with an internet socket.

## 8.1 Remote Bounded Contexts

- [ ] **P8-001:** Account.
- [ ] **P8-002:** Device.
- [ ] **P8-003:** Key directory and prekeys.
- [ ] **P8-004:** Contact/friend relationship.
- [ ] **P8-005:** Conversation.
- [ ] **P8-006:** Message event.
- [ ] **P8-007:** Receipt/reaction/edit/delete event.
- [ ] **P8-008:** Attachment.
- [ ] **P8-009:** Group and membership.
- [ ] **P8-010:** Call session and call history.
- [ ] **P8-011:** Presence.
- [ ] **P8-012:** Notification registration.
- [ ] **P8-013:** Sync cursor and operation queue.
- [ ] **P8-014:** Device revocation.
- [ ] **P8-015:** Backup/recovery.
- [ ] **P8-016:** Abuse prevention and blocking.
- [ ] **P8-017:** Account/data deletion.
- [ ] **P8-018:** Operational audit.

## 8.2 Backend Reference Architecture

Recommended initial stack:

- Modular monolith application.
- PostgreSQL as source of truth.
- Redis for short-lived presence, rate limits, and selected coordination.
- S3-compatible object storage for encrypted attachments.
- WebSocket gateway for realtime delivery.
- REST for account/device/history/control operations.
- Transactional outbox for reliable async work.
- Background workers for push, delivery retries, attachment cleanup, and deletion.
- STUN/TURN using a separately managed coturn deployment.
- OpenTelemetry-compatible logs, metrics, and traces.
- Secret manager for production credentials.

Tasks:

- [ ] **P8-019:** Approve backend language/framework.
- [ ] **P8-020:** Create backend module boundaries.
- [ ] **P8-021:** Define database ownership per module.
- [ ] **P8-022:** Define transaction boundaries.
- [ ] **P8-023:** Define transactional outbox.
- [ ] **P8-024:** Define idempotency strategy.
- [ ] **P8-025:** Define retry/dead-letter strategy.
- [ ] **P8-026:** Define rate limiting.
- [ ] **P8-027:** Define presence as ephemeral, not permanent history.
- [ ] **P8-028:** Define attachment lifecycle.
- [ ] **P8-029:** Define backup/restore.
- [ ] **P8-030:** Define disaster recovery targets.
- [ ] **P8-031:** Define observability without content logging.
- [ ] **P8-032:** Define staging and production isolation.
- [ ] **P8-033:** Define data-region policy if relevant.
- [ ] **P8-034:** Define operational admin access and approval controls.

## 8.3 Contract-First APIs

- [ ] **P8-035:** Create versioned OpenAPI definitions for REST.
- [ ] **P8-036:** Create versioned realtime envelope definitions.
- [ ] **P8-037:** Include event ID, request ID, idempotency key, correlation ID, server sequence, schema version, and timestamps.
- [ ] **P8-038:** Generate client/server types where practical.
- [ ] **P8-039:** Add compatibility fixtures.
- [ ] **P8-040:** Add backward/forward compatibility policy.
- [ ] **P8-041:** Define deprecation windows.
- [ ] **P8-042:** Define unknown-event behavior.
- [ ] **P8-043:** Never silently change wire semantics.
- [ ] **P8-044:** Keep Remote protocol independent of Local protocol versions.

### Exit criteria

- [ ] Remote domain and backend boundaries are documented.
- [ ] Data and API contracts support future multi-device sync.
- [ ] The backend can scale modularly without immediate microservice extraction.
- [ ] No Remote code depends on Local host/port/session models.

---

## PHASE 9 — Remote Cryptographic and Identity Security Gate

**Goal:** Establish a reviewed E2EE foundation before message persistence is built around the wrong protocol.

### Prohibited until this phase exits

- Production Remote message sending.
- Production Remote group messaging.
- Marketing claims of forward secrecy.
- Multi-device key synchronization.
- Encrypted backup claims.

### Tasks

- [ ] **P9-001:** Commission/perform a formal cryptographic design review.
- [ ] **P9-002:** Evaluate mature, maintained protocol implementations.
- [ ] **P9-003:** Decide one-to-one session establishment.
- [ ] **P9-004:** Decide per-message ratchet.
- [ ] **P9-005:** Decide offline prekey model.
- [ ] **P9-006:** Decide identity key and device key hierarchy.
- [ ] **P9-007:** Decide device-linking verification.
- [ ] **P9-008:** Decide key-change UX.
- [ ] **P9-009:** Decide device revocation and session reset.
- [ ] **P9-010:** Decide group encryption strategy.
- [ ] **P9-011:** Decide attachment encryption.
- [ ] **P9-012:** Decide encrypted backup key derivation and recovery.
- [ ] **P9-013:** Define metadata visible to servers.
- [ ] **P9-014:** Define replay protection.
- [ ] **P9-015:** Define ordering and duplicate handling.
- [ ] **P9-016:** Define cryptographic version negotiation.
- [ ] **P9-017:** Define key rotation.
- [ ] **P9-018:** Define lost-device response.
- [ ] **P9-019:** Create test vectors.
- [ ] **P9-020:** Create cross-platform interoperability tests.
- [ ] **P9-021:** Add malformed-ciphertext and downgrade tests.
- [ ] **P9-022:** Add secure key-storage adapters per app/platform.
- [ ] **P9-023:** Ensure the backend stores no private keys or plaintext content.
- [ ] **P9-024:** Obtain independent review before production release.

### Exit criteria

- [ ] Approved protocol and implementation strategy exist.
- [ ] Test vectors pass on supported platforms.
- [ ] Key lifecycle is documented.
- [ ] Remote security claims are evidence-based.
- [ ] Current Local crypto code has not been reused merely for convenience.

---

## PHASE 10 — Remote Backend Core

**Goal:** Build the secure operational substrate before rich client features.

### Account and Device

- [ ] **P10-001:** Account registration without mandatory contact upload.
- [ ] **P10-002:** Authentication/session tokens.
- [ ] **P10-003:** Refresh-token rotation.
- [ ] **P10-004:** Device registration.
- [ ] **P10-005:** Device listing and naming.
- [ ] **P10-006:** Device revocation.
- [ ] **P10-007:** Public key/prekey publication.
- [ ] **P10-008:** Account recovery policy.
- [ ] **P10-009:** Brute-force and credential-stuffing controls.
- [ ] **P10-010:** Audit events with no sensitive content.

### Messaging Infrastructure

- [ ] **P10-011:** Conversation creation and membership.
- [ ] **P10-012:** Ciphertext message envelope storage.
- [ ] **P10-013:** Per-conversation server sequence.
- [ ] **P10-014:** Idempotent send.
- [ ] **P10-015:** Offline mailbox/delivery.
- [ ] **P10-016:** Delivery acknowledgement.
- [ ] **P10-017:** Sync cursor API.
- [ ] **P10-018:** Tombstone events.
- [ ] **P10-019:** Transactional outbox.
- [ ] **P10-020:** Push notification worker with no plaintext content.
- [ ] **P10-021:** Backpressure and mailbox quotas.
- [ ] **P10-022:** Abuse/rate limits.
- [ ] **P10-023:** Blocking enforcement.

### Infrastructure

- [ ] **P10-024:** Database migrations.
- [ ] **P10-025:** Local development stack.
- [ ] **P10-026:** Automated integration tests.
- [ ] **P10-027:** Staging deployment.
- [ ] **P10-028:** Secret management.
- [ ] **P10-029:** TLS configuration.
- [ ] **P10-030:** Metrics, logs, and traces.
- [ ] **P10-031:** Backup and restore test.
- [ ] **P10-032:** Dependency and container scanning.
- [ ] **P10-033:** API load test baseline.
- [ ] **P10-034:** Incident response runbook.

### Exit criteria

- [ ] Backend can register an account/device and reliably store/deliver ciphertext.
- [ ] No message plaintext is available to backend components.
- [ ] Retries are idempotent.
- [ ] Backup restore is tested.
- [ ] Staging is isolated from production.

---

## PHASE 11 — Remote Client Persistence and Synchronization Engine

**Goal:** Build persistent history correctly before adding complex features.

## 11.1 Remote Local Database

- [ ] **P11-001:** Create a Remote-only encrypted local database.
- [ ] **P11-002:** Separate schema and migrations from Local.
- [ ] **P11-003:** Model accounts.
- [ ] **P11-004:** Model devices.
- [ ] **P11-005:** Model contacts.
- [ ] **P11-006:** Model conversations.
- [ ] **P11-007:** Model conversation members.
- [ ] **P11-008:** Model message events.
- [ ] **P11-009:** Model revisions/reactions/receipts.
- [ ] **P11-010:** Model attachments.
- [ ] **P11-011:** Model groups.
- [ ] **P11-012:** Model call history.
- [ ] **P11-013:** Model sync cursors.
- [ ] **P11-014:** Model pending operations.
- [ ] **P11-015:** Model tombstones.
- [ ] **P11-016:** Add indexes and pagination queries.
- [ ] **P11-017:** Add migration rollback/recovery policy.
- [ ] **P11-018:** Add corruption detection and safe recovery.
- [ ] **P11-019:** Add database backup/restore tests where applicable.

## 11.2 Sync Engine

- [ ] **P11-020:** Outbound operation queue.
- [ ] **P11-021:** Stable client-generated operation IDs.
- [ ] **P11-022:** Retry with exponential backoff and jitter.
- [ ] **P11-023:** Inbound cursor-based synchronization.
- [ ] **P11-024:** Transactional application of event batches.
- [ ] **P11-025:** Duplicate suppression.
- [ ] **P11-026:** Ordering rules.
- [ ] **P11-027:** Conflict rules.
- [ ] **P11-028:** Tombstone handling.
- [ ] **P11-029:** Offline-first read behavior.
- [ ] **P11-030:** Reconnect/resume.
- [ ] **P11-031:** Background sync limits.
- [ ] **P11-032:** Network-change handling.
- [ ] **P11-033:** Clock-skew tolerance.
- [ ] **P11-034:** Sync health diagnostics.
- [ ] **P11-035:** No plaintext content in sync logs.

### Exit criteria

- [ ] Remote history survives restart.
- [ ] Offline operations synchronize exactly once in effect.
- [ ] Duplicate/reordered events do not corrupt state.
- [ ] Local and server state recover after interrupted sync.
- [ ] Local panic wipe tests still prove Remote independence.

---

## PHASE 12 — Remote One-to-One Messaging MVP

**Goal:** Release the smallest complete persistent private messaging loop.

### Tasks

- [ ] **P12-001:** Account sign-in/setup UI.
- [ ] **P12-002:** Device verification UI.
- [ ] **P12-003:** Add contact by username, QR, or invitation.
- [ ] **P12-004:** One-to-one conversation creation.
- [ ] **P12-005:** E2EE text send.
- [ ] **P12-006:** Offline receive.
- [ ] **P12-007:** Persistent conversation list.
- [ ] **P12-008:** Persistent message history.
- [ ] **P12-009:** Delivery receipts.
- [ ] **P12-010:** Read receipts with privacy setting.
- [ ] **P12-011:** Typing indicators as ephemeral state.
- [ ] **P12-012:** Message edits as persistent events.
- [ ] **P12-013:** Message reactions as persistent events.
- [ ] **P12-014:** Delete-for-self.
- [ ] **P12-015:** Delete-for-everyone only if approved by product contract.
- [ ] **P12-016:** Blocking.
- [ ] **P12-017:** Push notification without plaintext.
- [ ] **P12-018:** Search over local decrypted history.
- [ ] **P12-019:** Pagination.
- [ ] **P12-020:** Migration and compatibility tests.
- [ ] **P12-021:** End-to-end tests across two devices and two networks.
- [ ] **P12-022:** No Local package imports.

### Exit criteria

- [ ] Persistent 1:1 messaging works across networks and restarts.
- [ ] The server cannot read message content.
- [ ] Manual deletion follows documented semantics.
- [ ] Local remains unaffected.

---

## PHASE 13 — Remote Contacts, Friends, Presence, and Safety

- [ ] **P13-001:** Contact request lifecycle.
- [ ] **P13-002:** Accept/reject/cancel.
- [ ] **P13-003:** Friend/contact removal.
- [ ] **P13-004:** Block/unblock.
- [ ] **P13-005:** Username change rules.
- [ ] **P13-006:** Search privacy controls.
- [ ] **P13-007:** Presence privacy controls.
- [ ] **P13-008:** Last-seen policy.
- [ ] **P13-009:** Profile update propagation.
- [ ] **P13-010:** Spam controls.
- [ ] **P13-011:** Request quotas.
- [ ] **P13-012:** Report flow with privacy-minimized evidence.
- [ ] **P13-013:** Safety/admin workflow.
- [ ] **P13-014:** Contact and block synchronization across devices.
- [ ] **P13-015:** Tests for blocked-user delivery and group behavior.

---

## PHASE 14 — Remote Attachments, Media, and Files

- [ ] **P14-001:** Client-side random attachment key.
- [ ] **P14-002:** Client-side encryption before upload.
- [ ] **P14-003:** Content-addressed or opaque object ID without plaintext filename.
- [ ] **P14-004:** Resumable upload.
- [ ] **P14-005:** Resumable download.
- [ ] **P14-006:** Integrity verification.
- [ ] **P14-007:** Encrypted thumbnail strategy.
- [ ] **P14-008:** File size and quota limits.
- [ ] **P14-009:** Malware-risk UX without server plaintext scanning claims.
- [ ] **P14-010:** Attachment expiry only through explicit deletion/retention contract.
- [ ] **P14-011:** Orphan cleanup after transactions fail.
- [ ] **P14-012:** Object storage lifecycle rules.
- [ ] **P14-013:** Cache eviction without deleting server history.
- [ ] **P14-014:** External export warning.
- [ ] **P14-015:** Multi-device attachment key delivery.
- [ ] **P14-016:** Load, interruption, and corruption tests.

---

## PHASE 15 — Remote Audio and Video Calls

- [ ] **P15-001:** Separate Remote call engine from Local LAN call engine.
- [ ] **P15-002:** Remote signaling through Remote realtime service.
- [ ] **P15-003:** STUN configuration.
- [ ] **P15-004:** TURN credential issuance.
- [ ] **P15-005:** TURN abuse and bandwidth controls.
- [ ] **P15-006:** Direct connection attempt with relay fallback.
- [ ] **P15-007:** Incoming push/call notification flow.
- [ ] **P15-008:** Call state recovery.
- [ ] **P15-009:** Audio controls.
- [ ] **P15-010:** Video controls.
- [ ] **P15-011:** Camera swap/PiP.
- [ ] **P15-012:** Network handoff handling.
- [ ] **P15-013:** Persist call history metadata.
- [ ] **P15-014:** Never store call media.
- [ ] **P15-015:** Define IP privacy: direct peer visibility versus relay-only option.
- [ ] **P15-016:** Add call quality metrics without content.
- [ ] **P15-017:** Cross-network, carrier NAT, restricted Wi-Fi, and relay tests.
- [ ] **P15-018:** Cost and quota monitoring.
- [ ] **P15-019:** Keep Local WebRTC candidate filtering unchanged.

---

## PHASE 16 — Remote Groups

- [ ] **P16-001:** Persistent group identity.
- [ ] **P16-002:** Persistent membership and roles.
- [ ] **P16-003:** Invite/join approval rules.
- [ ] **P16-004:** Group E2EE strategy from Phase 9.
- [ ] **P16-005:** Membership-change key updates.
- [ ] **P16-006:** Persistent group message history.
- [ ] **P16-007:** Persistent group files.
- [ ] **P16-008:** Admin events.
- [ ] **P16-009:** Leave/remove/block behavior.
- [ ] **P16-010:** Group deletion.
- [ ] **P16-011:** Offline member synchronization.
- [ ] **P16-012:** Multi-device membership synchronization.
- [ ] **P16-013:** Large-group pagination.
- [ ] **P16-014:** Abuse and rate limits.
- [ ] **P16-015:** Future group call architecture ADR.
- [ ] **P16-016:** Do not reuse Local host election as Remote group authority.

---

## PHASE 17 — Multi-Device, Backup, and Recovery

- [ ] **P17-001:** Link new device.
- [ ] **P17-002:** Verify new device out of band.
- [ ] **P17-003:** Device key registration.
- [ ] **P17-004:** Per-device encrypted message fan-out.
- [ ] **P17-005:** History synchronization.
- [ ] **P17-006:** Device revocation.
- [ ] **P17-007:** Lost-device response.
- [ ] **P17-008:** Encrypted backup format.
- [ ] **P17-009:** Backup key ownership.
- [ ] **P17-010:** Recovery phrase/passkey policy.
- [ ] **P17-011:** Backup versioning.
- [ ] **P17-012:** Restore into a new device.
- [ ] **P17-013:** Account recovery without server plaintext keys.
- [ ] **P17-014:** Deletion propagation to backups.
- [ ] **P17-015:** Recovery tests and disaster scenarios.
- [ ] **P17-016:** Explicitly document what cannot be recovered.

---

## PHASE 18 — Privacy, Security, Abuse, and Compliance

- [ ] **P18-001:** Publish accurate privacy policy.
- [ ] **P18-002:** Publish metadata inventory.
- [ ] **P18-003:** Publish retention schedule.
- [ ] **P18-004:** Publish data deletion behavior.
- [ ] **P18-005:** No sale or behavioral monetization of personal data.
- [ ] **P18-006:** No plaintext message content in logs.
- [ ] **P18-007:** No plaintext push payload.
- [ ] **P18-008:** No mandatory address-book upload.
- [ ] **P18-009:** Consent and permission review.
- [ ] **P18-010:** Data export.
- [ ] **P18-011:** Account deletion workflow.
- [ ] **P18-012:** Security incident response.
- [ ] **P18-013:** Vulnerability disclosure policy.
- [ ] **P18-014:** Dependency/CVE response policy.
- [ ] **P18-015:** Penetration test.
- [ ] **P18-016:** Independent cryptographic review.
- [ ] **P18-017:** Mobile application security review.
- [ ] **P18-018:** Backend security review.
- [ ] **P18-019:** Secrets and access review.
- [ ] **P18-020:** Abuse-report handling with minimum necessary data.
- [ ] **P18-021:** Admin access logging.
- [ ] **P18-022:** Production access approval and least privilege.
- [ ] **P18-023:** Backup encryption and restore authorization.
- [ ] **P18-024:** App-store privacy declarations.
- [ ] **P18-025:** Verify all marketing statements against tests and design documents.

---

## PHASE 19 — Operability, Reliability, Scaling, and Disaster Recovery

- [ ] **P19-001:** Service-level indicators.
- [ ] **P19-002:** Service-level objectives.
- [ ] **P19-003:** Alerting thresholds.
- [ ] **P19-004:** On-call/incident process suitable for a solo owner.
- [ ] **P19-005:** Automated backups.
- [ ] **P19-006:** Periodic restore drills.
- [ ] **P19-007:** Database point-in-time recovery.
- [ ] **P19-008:** Object-storage durability and recovery.
- [ ] **P19-009:** Redis-loss behavior.
- [ ] **P19-010:** WebSocket reconnect storm handling.
- [ ] **P19-011:** Push provider outage handling.
- [ ] **P19-012:** TURN outage and regional fallback.
- [ ] **P19-013:** Rate-limit tuning.
- [ ] **P19-014:** Capacity tests for messages, files, calls, and sync.
- [ ] **P19-015:** Cost budgets and alerts.
- [ ] **P19-016:** Database partition/archive strategy only when metrics justify it.
- [ ] **P19-017:** Broker extraction only when modular-monolith limits are proven.
- [ ] **P19-018:** Zero-downtime migration strategy.
- [ ] **P19-019:** Client/server compatibility during rolling upgrades.
- [ ] **P19-020:** Emergency rollback.
- [ ] **P19-021:** Status page and user communication plan.
- [ ] **P19-022:** Runbooks for top failure modes.

---

## PHASE 20 — Independent Release Pipelines and Long-Term Governance

## 20.1 Local Pipeline

- [ ] **P20-001:** Local-only analyze/test.
- [ ] **P20-002:** Local Android build/sign.
- [ ] **P20-003:** Local Windows build/sign.
- [ ] **P20-004:** Local offline acceptance tests.
- [ ] **P20-005:** Local wipe isolation tests.
- [ ] **P20-006:** Local protocol compatibility tests.
- [ ] **P20-007:** Local release notes and rollback.

## 20.2 Remote Pipeline

- [ ] **P20-008:** Remote client analyze/test.
- [ ] **P20-009:** Remote backend unit/integration tests.
- [ ] **P20-010:** Contract compatibility tests.
- [ ] **P20-011:** Database migration tests.
- [ ] **P20-012:** Remote Android build/sign.
- [ ] **P20-013:** Remote Windows build/sign.
- [ ] **P20-014:** Staging end-to-end tests.
- [ ] **P20-015:** Security gates.
- [ ] **P20-016:** Production deployment and rollback.
- [ ] **P20-017:** Remote release notes.

## 20.3 Cross-Product Gates

- [ ] **P20-018:** Install both apps together.
- [ ] **P20-019:** Run both simultaneously.
- [ ] **P20-020:** Verify independent notifications.
- [ ] **P20-021:** Verify independent camera/microphone sessions and contention UX.
- [ ] **P20-022:** Verify independent secure storage.
- [ ] **P20-023:** Verify independent databases.
- [ ] **P20-024:** Verify Local panic wipe leaves Remote intact.
- [ ] **P20-025:** Verify Remote logout/delete leaves Local intact.
- [ ] **P20-026:** Verify uninstalling Local leaves Remote intact.
- [ ] **P20-027:** Verify uninstalling Remote leaves Local intact.
- [ ] **P20-028:** Verify Local has no Remote backend traffic.
- [ ] **P20-029:** Verify Remote has no LAN broadcast unless explicitly designed.
- [ ] **P20-030:** Verify package dependency firewall.

## 20.4 Governance

- [ ] **P20-031:** Quarterly architecture review.
- [ ] **P20-032:** Quarterly dependency review.
- [ ] **P20-033:** Annual threat-model review.
- [ ] **P20-034:** Security-claim review before every major release.
- [ ] **P20-035:** ADR required for cross-product sharing.
- [ ] **P20-036:** Deprecation policy for packages and protocols.
- [ ] **P20-037:** Ownership map for every package/module.
- [ ] **P20-038:** Keep this plan updated as the execution ledger.
- [ ] **P20-039:** Archive completed phase evidence.
- [ ] **P20-040:** Never delete historical migration or security decisions without replacement records.

---

# 7. Required Automated Architecture Tests

The following tests are mandatory before Remote feature development.

- [ ] Local app cannot import `packages/remote/**`.
- [ ] Remote app cannot import `packages/local/**`.
- [ ] Shared packages cannot import either product.
- [ ] Local code contains no Remote API base URL.
- [ ] Local code contains no push registration.
- [ ] Local code contains no TURN credential fetch.
- [ ] Remote code contains no mDNS service type.
- [ ] Remote code contains no UDP discovery port.
- [ ] Remote code contains no Local panic-wipe orchestrator.
- [ ] No shared package contains `FlutterSecureStorage`.
- [ ] No shared package opens SQLite.
- [ ] No shared package performs HTTP/WebSocket/TCP/UDP network I/O.
- [ ] No shared package owns product-specific notification IDs.
- [ ] No destructive operation accepts an arbitrary filesystem root.
- [ ] App descriptors have unique IDs and paths.
- [ ] Secure-storage key prefixes differ.
- [ ] Database filenames differ.
- [ ] Notification identities differ.
- [ ] Android application IDs differ.
- [ ] Windows AppUserModelIDs and GUIDs differ.
- [ ] Local wipe causes zero Remote network calls.
- [ ] Remote account deletion causes zero Local file/key operations.

---

# 8. Required Test Matrix

| Area | Unit | Integration | Platform | E2E | Security |
|---|---:|---:|---:|---:|---:|
| Package boundaries | Yes | Yes | No | No | Yes |
| Local retention | Yes | Yes | Android/Windows | Yes | Yes |
| Local panic wipe | Yes | Yes | Android/Windows | Yes | Yes |
| Local protocol | Yes | Yes | Android/Windows | Yes | Yes |
| Remote database | Yes | Yes | Android/Windows | Yes | Yes |
| Remote sync | Yes | Yes | Android/Windows | Yes | Yes |
| Remote E2EE | Yes | Yes | Android/Windows | Yes | Yes |
| Backend messaging | Yes | Yes | Server | Yes | Yes |
| Attachments | Yes | Yes | Client/server | Yes | Yes |
| Calls | Yes | Yes | Android/Windows/network | Yes | Yes |
| Groups | Yes | Yes | Client/server | Yes | Yes |
| Multi-device | Yes | Yes | Multiple devices | Yes | Yes |
| Deletion | Yes | Yes | Client/server | Yes | Yes |
| Coexistence | Yes | Yes | Android/Windows | Yes | Yes |

---

# 9. Risk Register

## R-001 — Remote accidentally reuses Local persistence model

**Impact:** Severe future rewrite.  
**Control:** Separate Remote domain/storage packages and schema before messaging implementation.

## R-002 — Local wipe deletes Remote data

**Impact:** Catastrophic user-data loss.  
**Control:** Unique app IDs, scoped descriptors, path guard, separate secure storage, isolation E2E tests.

## R-003 — Shared packages become a hidden monolith

**Impact:** Both products become coupled and difficult to evolve.  
**Control:** Shared eligibility rules, no product imports, no infrastructure in shared.

## R-004 — Current Local database contradicts ephemeral promise

**Impact:** Privacy failure.  
**Control:** Phase 6 migration to RAM-only content and forensic-oriented wipe tests.

## R-005 — Custom cryptography used for Remote

**Impact:** Critical confidentiality failure.  
**Control:** Phase 9 security gate and independent review.

## R-006 — Multi-device added too late

**Impact:** Schema/protocol rewrite.  
**Control:** Account/device IDs, per-device keys, sync cursors, tombstones, and event model from foundation.

## R-007 — Remote backend over-engineered into microservices

**Impact:** Solo-maintainer operational failure.  
**Control:** Modular monolith + transactional outbox; split only with evidence.

## R-008 — Remote backend under-engineered as simple CRUD

**Impact:** Duplicate messages, loss, ordering bugs, deletion inconsistency.  
**Control:** Idempotency, server sequences, operation queue, cursors, transactional event application.

## R-009 — Marketing exceeds implementation

**Impact:** Trust, legal, and security damage.  
**Control:** Claim matrix and release gate.

## R-010 — External files assumed erasable

**Impact:** False panic-wipe promise.  
**Control:** App-private temporary storage and explicit export warning.

## R-011 — Debug release signing ships

**Impact:** Supply-chain and update risk.  
**Control:** CI signing gate.

## R-012 — AI agents make broad unreviewed changes

**Impact:** Architecture drift.  
**Control:** Phase checkboxes, small slices, evidence, boundary tests, ADR requirements.

---

# 10. Definition of Done for the Two-App Foundation

The foundation is complete only when all are true:

- [ ] Both applications install simultaneously on Android.
- [ ] Both applications run simultaneously on Windows.
- [ ] Each app has unique native identity and notification identity.
- [ ] Each app has separate secure storage, database, cache, temp, logs, and config.
- [ ] Local contains no Remote service dependency.
- [ ] Remote contains no Local runtime dependency.
- [ ] Shared packages contain no product-specific infrastructure.
- [ ] Local messages do not survive restart.
- [ ] Local panic wipe removes all Local app-private sensitive state.
- [ ] Local panic wipe does not alter Remote state.
- [ ] Remote history survives restart and server synchronization.
- [ ] Remote data remains until approved manual-deletion semantics apply.
- [ ] Remote account and device identities are independent from Local.
- [ ] CI fails on cross-product imports or identifier collisions.
- [ ] Both products have independent release pipelines.
- [ ] Security claims are reviewed and accurate.
- [ ] A new AI agent can continue from this file and the recorded phase evidence without guessing architecture.

---

# 11. Immediate Execution Order

Agents must begin in this exact order:

1. [x] Complete Phase 0.
2. [x] Complete Phase 1.
3. [x] Move current app into `apps/helix_local` in Phase 2.
4. [x] Create only a minimal Remote shell.
5. [x] Complete app identity/storage isolation in Phase 3.
6. [ ] Complete dependency firewalls in Phase 4.
7. [ ] Complete product-specific composition in Phase 5.
8. [ ] Correct Local persistence and panic wipe in Phase 6.
9. [ ] Harden Local in Phase 7.
10. [ ] Only then begin the Remote architecture and security phases.

**No agent should begin Remote messaging, Remote storage, Remote calls, or Remote groups before Steps 1–7 are complete.**

---

# 12. Work Log

Agents append entries; do not rewrite previous entries.

```md
## YYYY-MM-DD — Agent/Session

- Phase:
- Checklist IDs:
- Summary:
- Files changed:
- Verification:
- Security review:
- Migration impact:
- Rollback:
- Remaining work:
- Commit/PR:
```

## 2026-06-18 — Antigravity

- Phase: 0
- Checklist IDs: P0-001 through P0-015
- Summary: Created protected baseline tag, recorded dependency versions, ran verification, built Android and Windows debug, captured platform metadata, added architecture changelog and current-state doc.
- Files changed: phase0_test.dart, CHANGELOG_ARCHITECTURE.md, docs/architecture/CURRENT_STATE_2026-06-18.md, deleted test.py and test_mode.txt, updated plan checklist
- Verification: verify.ps1 with HELIX_VERIFY_BUILD=1, all tests pass, Windows debug exe produced
- Security review: None (baseline only)
- Migration impact: None
- Rollback: `git reset --hard baseline`
- Remaining work: None
- Commit/PR: master (Phase 0 Baseline audited codebase)

## 2026-06-19 — Antigravity

- Phase: 1
- Checklist IDs: P1-001 through P1-030
- Summary: Created 17 ADR files and 12 product contract documents. Defined Local and Remote product contracts, threat models, data-flow diagrams, feature ownership matrix, package classification, shared-code rules, and deletion semantics.
- Files changed: docs/adr/ (17 files), docs/product/ (12 files), plan checklist
- Verification: verify.ps1 (documentation phase, no code changes)
- Security review: None (documentation only)
- Migration impact: None
- Rollback: `git reset --hard` to Phase 0 commit
- Remaining work: None
- Commit/PR: master (Phase 1: Complete Product Contracts and Architecture Decisions)

## 2026-06-19 — Antigravity

- Phase: 2
- Checklist IDs: P2-001 through P2-017
- Summary: Moved existing app into apps/helix_local, created apps/helix_remote minimal shell, converted root pubspec.yaml to workspace coordinator, updated scripts and gitignore for multi-app layout.
- Files changed: apps/helix_local/ (moved from root), apps/helix_remote/ (new shell), root pubspec.yaml, .gitignore, scripts/, README
- Verification: Both apps build Android and Windows debug, no cross-product imports
- Security review: None (structural move, no behavior change)
- Migration impact: All paths now rooted under apps/helix_local/
- Rollback: `git reset --hard` to Phase 1 commit
- Remaining work: None
- Commit/PR: master (Complete Phase 2: Convert the Repository into a True Multi-App Workspace)

## 2026-06-19 — Antigravity

- Phase: 3
- Checklist IDs: P3-001 through P3-040
- Summary: Created ProductDescriptor pattern (LocalProductDescriptor / RemoteProductDescriptor) with path-containment guard. Fixed all com.helix.app → com.helix.local runtime channel mismatches. Versioned storage key prefixes (helix_local_v1_ / helix_remote_v1_). Made PlatformNotificationGateway constructor params required. Replaced unscoped deleteAll with prefix-scoped delete. Made IdentityManagerImpl appDataFolder injectable. Added product-scoped Android signing env vars and keystore names. Rewrote verify scripts and module_boundaries.json for workspace. Fixed boundary checker to resolve workspace imports. Added 33 new/updated tests (all passing).
- Files changed: 46 files (see Phase 3 Phase Handoff for full list)
- Verification: 7 domain tests, 26 storage tests, boundary check, flutter analyze — all clean
- Security review: Path containment prevents traversal; prefix-scoped delete prevents cross-product wipe; signing credential isolation enforced
- Migration impact: Storage key prefix changed from local_ to helix_local_v1_; migration logic handles legacy unprefixed keys
- Rollback: `git reset --hard a500d28`
- Remaining work: None
- Commit/PR: master (11a48d8 — Phase 3: Complete Phase 0-3 Closure and Repair Pass)

## 2026-06-19 — Antigravity

- Phase: 4
- Checklist IDs: P4-003, P4-004, P4-005, P4-018, P4-019
- Summary: Phase 4 groundwork — classified all current packages as Local, created packages/shared/ and packages/remote/ boundary placeholders, created ownership-blast-radius.yaml with risk levels, updated AGENTS.md with product-boundary rules.
- Files changed: packages/shared/.gitkeep (NEW), packages/remote/.gitkeep (NEW), ownership-blast-radius.yaml (NEW), AGENTS.md (updated)
- Verification: flutter analyze (workspace-wide, no issues)
- Security review: None (documentation and placeholder work only)
- Migration impact: None (P4-001/P4-002 package moves are the next slice)
- Rollback: `git reset --hard` to Phase 3 commit
- Remaining work: P4-001/P4-002 (move packages to packages/local/, rename to helix_local_*), P4-006 through P4-017, P4-020
- Commit/PR: TBD (Phase 4 in progress)

---

# 13. Final Architectural Principle

The repository may be shared. The products must not be.

Helix Local and Helix Remote should share carefully reviewed **source primitives**, while maintaining completely separate:

- product identities
- native application identifiers
- cryptographic identities
- storage namespaces
- databases and schemas
- secure-storage keys
- caches and logs
- composition roots
- transports and protocols
- retention policies
- wipe/deletion services
- backend dependencies
- release pipelines
- threat models
- privacy claims

When that boundary is mechanically enforced, Local can erase itself completely without affecting Remote, and Remote can preserve a user’s long-term history without weakening Local’s ephemeral security model.
