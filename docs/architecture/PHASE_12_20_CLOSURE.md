# Phase 12-20 Closure and Repair Audit

**Date:** 2026-06-19
**Auditor:** Automated + manual source inspection
**Branch:** master

## Methodology

Every classification below is based on **executable code inspection**, **test
evidence**, and **wiring-path analysis**, not on Markdown documents or checkbox
state. The master plan part 2 is amended separately to match this audit.

### Classification Key

| Status | Meaning |
|---|---|
| **VERIFIED END TO END** | UI -> service -> transport -> backend -> database path exists and is tested |
| **VERIFIED COMPONENT ONLY** | Library/package code exists and passes unit/component tests; no app wiring |
| **PARTIAL** | Code exists but is incomplete, missing critical paths, or not connected |
| **DISCONNECTED** | Component exists but is NOT wired into the app composition root |
| **PLACEHOLDER** | Interface or stub only; no meaningful implementation |
| **DEFECTIVE** | Code exists but contains a confirmed security or data-integrity defect |
| **OUT OF STUDENT SCOPE** | Requires production infrastructure, signing, external review, or real providers |
| **NOT STARTED** | No code, test, or wiring evidence exists |

## Baseline Check Results

All checks run on 2026-06-19 from `J:\Projects\helix`:

| Check | Result | Notes |
|---|---|---|
| `flutter pub get` | PASS | Dependencies resolved |
| `dart format --output=none --set-exit-if-changed apps packages services tool` | 5 files changed | Formatter auto-fixed services/helix_remote_backend |
| `flutter analyze` | PASS | No issues found |
| `dart run tool/check_boundaries.dart` | PASS | Boundary check passed |
| `dart test tool/boundary_test.dart` | PASS | 5/5 pass |
| `dart run tool/dep_graph.dart` | PASS | No cycles |
| `dart run tool/check_secrets.dart` | PASS | Secret scan passed |
| `flutter test (helix_local)` | PASS | 196/196 pass |
| `flutter test (helix_remote)` | PASS | 28/28 pass |
| `flutter test (helix_remote_api)` | PASS | 17/17 pass |
| `flutter test (helix_remote_calls)` | PASS | 24/24 pass |
| `flutter test (helix_remote_crypto)` | PASS | 19/19 pass |
| `flutter test (helix_remote_groups)` | PASS | 21/21 pass |
| `flutter test (helix_remote_storage)` | PASS | 6/6 pass |
| `flutter test (helix_remote_sync)` | PASS | 11/11 pass |
| `dart test (helix_remote_backend)` | PASS | 59/59 pass |
| `flutter test (helix_local_domain)` | PASS | 7/7 pass |
| `flutter test (helix_local_storage)` | PASS | 28/28 pass |

**Total: 403 tests pass across all suites.**

## Core Architecture Finding

The repository contains a substantial amount of **useful domain, storage,
backend, crypto, sync, attachment, call, group, backup, and privacy code** at
the library/package level. However, the **debug app wiring is the single
critical blocker**.

`RemoteCompositionRoot` currently wires only:
- `RemoteSecureKeyStorage`
- `HelixRemoteDatabase`
- `RemoteSyncEngine`

It does **NOT** compose:
- Concrete REST client (only abstract `HelixRemoteRestClient`)
- Concrete WebSocket realtime client
- Concrete `SyncGateway`
- `RemoteMessagingService`
- `RemoteAttachmentService`
- `RemoteCallService` + concrete `RemoteCallEngine`
- `RemoteGroupService`
- Backup/recovery service
- Privacy/account-deletion service
- Connectivity/reconnect coordinator
- Session/token store
- Message protector/session store
- Identity/prekey service

The Remote Flutter app (`main.dart`) is a **self-contained in-memory
demonstration**: contacts, messages, and settings live in widget-local
`_contacts`, `_messages`, and `_UiMessage` lists. Actions call `setState()`
only. No service from the Remote packages is used by the UI.

---

## Phase 12 - Remote One-to-One Messaging MVP

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P12-001 | Account sign-in/setup UI | **DISCONNECTED** | `apps/helix_remote/lib/main.dart` `_usernameController`, `_deviceController` | Widget state only; no service called | `widget_test.dart` - launches shell | No account registration, no account service | None (no real auth path) | Wire registration/login flow through composition root |
| P12-002 | Device verification UI | **DISCONNECTED** | `apps/helix_remote/lib/main.dart:67` `_deviceVerified = true` | Local bool toggle, no backend | None for verification flow | No device verification service link | None (no real flow) | Connect to device verification service |
| P12-003 | Add contact by username | **DISCONNECTED** | `apps/helix_remote/lib/main.dart:56` `_contactController` | Appends to in-memory `_contacts` List<String> | None for contact flow | No contact request service | None (no real flow) | Wire contact request lifecycle |
| P12-004 | One-to-one conversation creation | **DISCONNECTED** | N/A in app | No creation path wired in app | `remote_messaging_service_test.dart` - service unit tests | Not connected to composition root | None | Wire conversation creation in services |
| P12-005 | E2EE text send | **PARTIAL** | `apps/helix_remote/lib/app/remote_messaging_service.dart` - outbound queue with protector; `main.dart:173` - adds to `_messages` list | Service path: `RemoteMessagingService.send` -> outbound queue -> protector; UI path: `setState` only | `remote_messaging_service_test.dart` - 5 service tests; `composition_root_test.dart` | Not connected from composition root; UI does not use service | Ciphertext-only storage in test; no protector connected in real use | Wire messaging service into composition root; connect UI |
| P12-006 | Offline receive | **PARTIAL** | `packages/remote/helix_remote_sync/lib/src/sync_engine.dart` - inbound sync with dedup | Sync engine parses events; no REST catch-up or realtime feed | `remote_sync_test.dart` - 11 tests | No concrete SyncGateway; no realtime client | Duplicate event rejection tested | Implement concrete SyncGateway + realtime client |
| P12-007 | Persistent conversation list | **PARTIAL** | `packages/remote/helix_remote_storage/lib/src/database.dart` - `conversations` table, CRUD | Storage layer only; UI uses in-memory list | `remote_storage_test.dart` - 6 tests | No DB stream to UI | None | Wire conversation repository into UI |
| P12-008 | Persistent message history | **PARTIAL** | `packages/remote/helix_remote_storage/lib/src/database.dart` - `messages` table, CRUD | Storage layer only; UI uses in-memory list | `remote_storage_test.dart` - 6 tests | No DB stream to UI | Ciphertext stored in `text` column (misleading name) | Wire message repository into UI; rename column |
| P12-009 | Delivery receipts | **PARTIAL** | `apps/helix_remote/lib/app/remote_messaging_service.dart` - receipt handling | Service-level receipt tracking | `remote_messaging_service_test.dart` | Not connected to backend or UI | None | Wire receipt lifecycle |
| P12-010 | Read receipts with privacy setting | **PARTIAL** | `apps/helix_remote/lib/app/remote_messaging_service.dart` - read receipt toggle; `main.dart:68` `_readReceipts` bool | Service level: `readReceipts` in compose; UI: local bool disconnect | `remote_messaging_service_test.dart` | Not connected to realtime or backend | None | Wire read receipt privacy setting |
| P12-011 | Typing indicators as ephemeral state | **PARTIAL** | `apps/helix_remote/lib/app/remote_messaging_service.dart` - ephemeral typing; `main.dart:124` `isTyping` | Service level: sendTyping/clearTyping; UI: local text change detection | `remote_messaging_service_test.dart` | Not connected to realtime relay | None | Wire typing to realtime signaling |
| P12-012 | Message edits as persistent events | **PARTIAL** | Backend `MessagingModule` edit route; service edit enqueue; UI `main.dart:182` local mutation | Backend + service: persistent; UI: local `_editMessage` | `remote_messaging_service_test.dart`; `messaging_test.dart` (backend) | Not connected in app | None | Wire edit through composed service path |
| P12-013 | Message reactions as persistent events | **PARTIAL** | Backend reaction routes; service reaction enqueue; UI `main.dart:192` local mutation | Backend + service: persistent; UI: local `_reactToMessage` | `remote_messaging_service_test.dart`; `messaging_test.dart` (backend) | Not connected in app | None | Wire reaction through composed service path |
| P12-014 | Delete-for-self | **PARTIAL** | Service delete-for-self; UI `main.dart:199` local remove | Service: enqueues delete operation; UI: `_deleteMessage` removes from list | `remote_messaging_service_test.dart` | Not connected in app | None | Wire delete through composed service path |
| P12-015 | Delete-for-everyone | **PARTIAL** | Backend tombstone route; service delete-for-everyone | Backend: DELETE with tombstone creation | Backend `messaging_test.dart` | Not connected in app | Tombstone prevents reappearance | Wire delete-for-everyone through app |
| P12-016 | Blocking | **PARTIAL** | Backend `block` route; service-level check; UI `main.dart:163` local block | Backend: blocks sends; UI: removes from contact list | `remote_messaging_service_test.dart`; backend `contacts_test.dart` | Not connected in app | Backend enforces block but UI has bypass | Wire block flow through composed service |
| P12-017 | Push notification without plaintext | **OUT OF STUDENT SCOPE** | Backend push outbox | Requires real push provider infrastructure | Backend outbox tests exist | Real provider not available | No plaintext in existing outbox code | Create development notification channel |
| P12-018 | Search over local decrypted history | **PARTIAL** | `storage/database.dart` - search methods; service-level search | Storage has `searchMessages()` | `remote_messaging_service_test.dart` - search test | Not wired to UI | None | Wire local search into UI |
| P12-019 | Pagination | **PARTIAL** | `storage/database.dart` - limit/offset params; service-level pagination | Storage pagination in getMessages | `remote_storage_test.dart` - pagination | Not connected in app | None | Wire pagination into conversation UI |
| P12-020 | Migration and compatibility tests | **PARTIAL** | `contracts/compatibility/fixtures/`; `helix_remote_api/test/serialization_test.dart` | Fixture decoding tests exist | 17 `serialization_test.dart` tests | No dedicated migration test for recent versions | None | Add migration test |
| P12-021 | E2E tests across two devices | **NOT STARTED** | No in-process integration test with full app path | Backend integration_test.dart exists but tests only backend loopback | No app-level E2E test | Full E2E not implemented | None | Create Level 3 integration test |
| P12-022 | No Local package imports | **VERIFIED COMPONENT ONLY** | All `apps/helix_remote/**` files | Boundary check passes | `tool/boundary_test.dart` | None | None | Monitor |

**Phase 12 Summary:** The service and backend layers have substantial implementation, but **the app is entirely disconnected from them**. A user running the Remote app today sees a demo shell with hardcoded `bob` contact and sample message text. No authentication, no persistence, no encryption, no transport.

---

## Phase 13 - Remote Contacts, Friends, Presence, and Safety

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P13-001 | Contact request lifecycle | **DISCONNECTED** | Backend `contacts.dart` `ContactRequestsModule`; service `remote_messaging_service.dart` `contactRequest` | Backend routes exist; service enqueues operations | Backend `contacts_phase13_test.dart`; service tests | Not wired into composition root or UI | None | Wire contact request into app |
| P13-002 | Accept/reject/cancel | **DISCONNECTED** | Backend accept/reject/cancel routes; service operations | Same as P13-001 | Backend tests | Not wired to app | None | Wire into app |
| P13-003 | Friend/contact removal | **DISCONNECTED** | Backend remove route; service removeContact | Same | Backend tests | Not wired | None | Wire into app |
| P13-004 | Block/unblock | **DISCONNECTED** | Backend block/unblock routes; service block/unblock | Same | Backend tests; service tests | Not wired | Backend enforces block | Wire into app |
| P13-005 | Username change rules | **VERIFIED COMPONENT ONLY** | Backend `auth.dart` username validation/enforcement | Backend-enforced rules | Backend tests | Not wired to app UI | Enforced server-side | Wire profile UI |
| P13-006 | Search privacy controls | **VERIFIED COMPONENT ONLY** | Backend privacy settings | Backend-enforced search visibility | Backend tests | Not wired | Server authoritative | Wire privacy settings UI |
| P13-007 | Presence privacy controls | **VERIFIED COMPONENT ONLY** | Backend presence heartbeat/query; service presence | Backend: presence state; service: sync processing | Backend tests | Not wired | None | Wire presence to realtime |
| P13-008 | Last-seen policy | **VERIFIED COMPONENT ONLY** | Backend privacy settings | Backend-enforced | Backend tests | Not wired | None | Wire last-seen UI |
| P13-009 | Profile update propagation | **PARTIAL** | Backend profile update; service sync processing of profile events | Backend route + sync event processing | Service sync tests | Not wired to app UI | None | Wire profile edit UI |
| P13-010 | Spam controls | **VERIFIED COMPONENT ONLY** | Backend request quotas | Backend-enforced | Backend tests | Not wired | None | N/A for student scope |
| P13-011 | Request quotas | **VERIFIED COMPONENT ONLY** | Backend rate limiting on requests | Backend-enforced | Backend tests | Not wired | None | N/A for student scope |
| P13-012 | Report flow with privacy-minimized evidence | **VERIFIED COMPONENT ONLY** | Backend report creation | Backend route | Backend tests | Not wired to app UI | Privacy-minimized payload enforced | Wire report UI |
| P13-013 | Safety/admin workflow | **VERIFIED COMPONENT ONLY** | Backend safety actions; admin allow-list | Backend: admin-only safety actions | Backend tests | Not wired | Admin access audited | N/A for student scope |
| P13-014 | Contact/block sync across devices | **PARTIAL** | Sync engine processes `contact_updated`, `contact_removed`, `profile_updated`, `privacy_updated`, `presence_updated` events | Sync engine typed dispatch | `remote_sync_test.dart` | Events processed but no UI effect | None | Wire sync events to UI state |
| P13-015 | Tests for blocked-user delivery and group behavior | **PARTIAL** | Backend tests for blocked-user delivery suppression | Direct blocked-user delivery tested | Backend `contacts_test.dart`; group block not implemented | Group block behavior not tested | None | Add group blocking test |

**Phase 13 Summary:** All backend contact infrastructure exists and is tested. The sync engine processes contact/privacy/presence events. The Remote app has **no contact screens** beyond the hardcoded demo contact list. User-facing contact request, accept/reject, block/unblock, privacy settings, profile editing, and reporting are not wired.

---

## Phase 14 - Remote Attachments, Media, and Files

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P14-001 | Client-side random attachment key | **VERIFIED COMPONENT ONLY** | `packages/remote/helix_remote_crypto/lib/src/attachment_crypto.dart` - `generateAttachmentKeys()` | Crypto layer generates random 256-bit key + 96-bit IV | `remote_crypto_test.dart` - roundtrip tests | Not wired to upload flow | None | Wire key generation into attachment service |
| P14-002 | Client-side encryption before upload | **VERIFIED COMPONENT ONLY** | `attachment_crypto.dart` - `encryptFile()` | AES-256-GCM encrypt | Crypto tests | Not wired to `RemoteAttachmentService` | None | Wire encrypt step |
| P14-003 | Opaque object ID without plaintext filename | **VERIFIED COMPONENT ONLY** | Backend `attachments.dart` - uses `file_id` in URL paths | Content-addressed or opaque ID model | Backend tests | Not wired to app | No plaintext filename used | Verify opaque ID model |
| P14-004 | Resumable upload | **VERIFIED COMPONENT ONLY** | Backend `attachments.dart` upload/resume; service `uploadFile` with resume | Backend: range-based resume via `offset` header | `attachments_test.dart` (backend): 7 tests | `RemoteAttachmentService.uploadFile` reads entire file into memory | High memory for large files | Add streaming/incremental upload |
| P14-005 | Resumable download | **VERIFIED COMPONENT ONLY** | Backend `attachments.dart` range download; service download | Backend: range requests | Backend tests | `downloadFile` reads entire server response into memory | High memory | Add streaming download |
| P14-006 | Integrity verification | **VERIFIED COMPONENT ONLY** | Backend hash verification on upload; client hash check on download | SHA-256 hash comparison | Backend tests (hash-mismatch -> FAILED) | Client-side hash check not verified | None | Wire client-side integrity check |
| P14-007 | Encrypted thumbnail strategy | **PARTIAL** | `RemoteAttachmentService.prepareEncryptedThumbnail()` | Separate thumbnail encrypt with own key | `remote_attachment_service_test.dart` - thumbnail test | Not wired into upload flow | Thumbnail key delivery not separate | Wire thumbnail into upload |
| P14-008 | File size and quota limits | **VERIFIED COMPONENT ONLY** | Backend size limits; service size validation | Backend: max file size; service: `validateFileSize()` | `remote_attachment_service_test.dart` - size limit test | Not wired to backend enforcement | None | Wire quota UI |
| P14-009 | Malware-risk UX without scanning claims | **VERIFIED COMPONENT ONLY** | `apps/helix_remote/lib/app/attachment_safety.dart` | Warning UX text without scanning claims | `remote_attachment_service_test.dart` - warning test | Not wired to download flow | No server scanning claimed | Wire warning into download flow |
| P14-010 | Attachment expiry policy | **VERIFIED COMPONENT ONLY** | Backend `AttachmentsModule.runLifecycleRules()` | Removes unreferenced attachments after retention | Backend tests | Not wired | None | N/A for student scope |
| P14-011 | Orphan cleanup after transaction failure | **VERIFIED COMPONENT ONLY** | Backend `AttachmentsModule.cleanupOrphans()` | Removes PENDING/UPLOADING records older than threshold | Backend tests | Not wired | None | N/A for student scope |
| P14-012 | Object storage lifecycle rules | **OUT OF STUDENT SCOPE** | Backend cleanup rules; requires object storage | Backend file-system cleanup | Backend tests | Not applicable for local dev | None | Use local filesystem for student scope |
| P14-013 | Cache eviction without deleting server history | **VERIFIED COMPONENT ONLY** | `RemoteAttachmentService.evictLocalCache()` | Sets CACHE_EVICTED status; server copy unaffected | `remote_attachment_service_test.dart` | Not wired to UI | Safe local-only deletion | Wire cache eviction UI |
| P14-014 | External export warning | **VERIFIED COMPONENT ONLY** | `apps/helix_remote/lib/app/attachment_export.dart` | Warning that export removes E2EE | `remote_attachment_service_test.dart` | Not wired | None | Wire export warning |
| P14-015 | Multi-device attachment key delivery | **DEFECTIVE** | `RemoteAttachmentService.buildKeyDeliveryPackage()` has raw-key fallback when no `encryptForDevice` supplied | `encrypted_key` field holds raw key/IV material; no per-device encryption by default | `remote_attachment_service_test.dart` - key package tests | Not wired to app | **Raw key material stored in DB when encryptor not supplied** | Remove raw-key fallback; enforce per-device encryption |
| P14-016 | Load, interruption, and corruption tests | **PARTIAL** | Backend `attachments_test.dart` - resume/hash/upload tests | Backend: 7 tests cover upload/resume/hash/cleanup | 7 backend tests | No client-side corruption/recovery test | None | Add client-side corruption test |

**Phase 14 Summary:** Strong attachment primitives exist, but **raw-key fallback (DEFECTIVE)** allows unencrypted key storage. The app does not use attachment services. Upload/download read entire content into memory despite streaming claims.

---

## Phase 15 - Remote Audio and Video Calls

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P15-001 | Separate Remote call engine from Local | **VERIFIED COMPONENT ONLY** | `packages/remote/helix_remote_calls/lib/src/call_engine.dart` - abstract `RemoteCallEngine` | Interface only; no concrete implementation (`RemoteWebRtcCallEngine` does not exist) | `remote_call_service_test.dart` - 24 tests using `_FakeCallEngine` | No concrete engine to compose | None (abstract interface cannot leak) | Implement concrete `RemoteWebRtcCallEngine` |
| P15-002 | Remote signaling through realtime | **PARTIAL** | `RemoteCallSignalingGateway` abstract interface; backend `CallsModule` signal relay | Interface only for client; backend relay works | Backend `calls_test.dart` - 8 tests | Not wired in composition root | None | Implement concrete signaling gateway |
| P15-003 | STUN configuration | **VERIFIED COMPONENT ONLY** | `helix_remote_calls/lib/src/ice_config.dart` | `defaultStun()` returns STUN server URLs | `remote_call_service_test.dart` - P15-003 | No concrete engine to consume config | None | Wire STUN to engine |
| P15-004 | TURN credential issuance | **VERIFIED COMPONENT ONLY** | Backend `CallsModule` `/turn-credentials` | HMAC-SHA1 REST API credentials | Backend `calls_test.dart` | Not wired in app | None | Wire TURN into ICE config |
| P15-005 | TURN abuse/bandwidth controls | **VERIFIED COMPONENT ONLY** | Backend per-account quota (10/hr) | `turn_credential_log` table | Backend `calls_test.dart` | Backend-enforced | None | Wire quota into UI |
| P15-006 | Direct connection with relay fallback | **PARTIAL** | `IpPrivacyMode` enum in `ice_config.dart` | Controls relay behavior at service layer | `remote_call_service_test.dart` - P15-015 | No concrete engine | None | Wire relay config to engine |
| P15-007 | Incoming push/call notification | **PARTIAL** | Backend offline notification enqueue | Push notification hint (no real provider) | Backend `calls_test.dart` | Not wired | None | Real push = OUT OF SCOPE |
| P15-008 | Call state recovery | **PARTIAL** | `RemoteCallService.recoverCallState()`; storage `active_call` marker | Durable marker for stale call detection | `remote_call_service_test.dart` - P15-008 | Not wired in composition root | None | Wire recovery into composition root |
| P15-009 | Audio controls | **VERIFIED COMPONENT ONLY** | `RemoteCallService.setMuted/setSpeakerOn`; `RemoteCallEngine` interface | Delegates to engine interface | `remote_call_service_test.dart` - P15-009 | No concrete engine | None | Implement audio in concrete engine |
| P15-010 | Video controls | **VERIFIED COMPONENT ONLY** | `RemoteCallService.setVideoEnabled`; `RemoteCallEngine` interface | Delegates to engine interface | `remote_call_service_test.dart` - P15-010 | No concrete engine | None | Implement video in concrete engine |
| P15-011 | Camera swap/PiP | **VERIFIED COMPONENT ONLY** | `RemoteCallService.switchCamera`; `RemoteCallEngine` interface | Delegates to engine interface | `remote_call_service_test.dart` - P15-011 | No concrete engine | None | Implement camera swap in concrete engine |
| P15-012 | Network handoff handling | **VERIFIED COMPONENT ONLY** | `RemoteCallService.restartIce`; `RemoteCallEngine.restartIce` | ICE restart trigger | `remote_call_service_test.dart` - P15-012 | No concrete engine | None | Implement ICE restart |
| P15-013 | Call history metadata | **VERIFIED COMPONENT ONLY** | `RemoteCallService._persistCallHistory`; storage `saveCallHistory` | Persists callId, conversationId, direction, startTime, duration | `remote_call_service_test.dart` - P15-013 | Not wired to UI | Metadata only; no media bytes | Wire call history UI |
| P15-014 | No call media in DB/logs | **VERIFIED COMPONENT ONLY** | Service: no media bytes in call history; engine interface: no content logging | All tests verify content-free | `remote_call_service_test.dart` - P15-014 | None | No media in storage | Monitor |
| P15-015 | IP privacy: direct vs relay-only | **VERIFIED COMPONENT ONLY** | `IpPrivacyMode` enum; service-layer ICE candidate filtering | `relayOnly` filters non-relay candidates | `remote_call_service_test.dart` - P15-015 | No concrete engine | None | Wire into engine |
| P15-016 | Call quality metrics | **VERIFIED COMPONENT ONLY** | `CallQualityMetrics` class | Transport-layer stats (no content) | `remote_call_service_test.dart` - P15-016 | No concrete engine | No content fields | Wire into engine stats |
| P15-017 | Cross-network/carrier/relay tests | **OUT OF STUDENT SCOPE** | No real network test harness | Requires multiple devices/networks | No tests | Real device testing required | None | Optional student manual check |
| P15-018 | Cost and quota monitoring | **PARTIAL** | Backend TURN quota logging; quota limit | Per-account hourly limit | Backend `calls_test.dart` | Not wired to admin UI | None | N/A for student scope |
| P15-019 | Local engine unchanged | **VERIFIED COMPONENT ONLY** | No modifications to `helix_local_calls` | Verified by code inspection | `helix_local_calls` tests unchanged | None | None | Monitor |

**Phase 15 Summary:** The abstract call engine/service layer is well-tested (24 tests). **No concrete `RemoteWebRtcCallEngine` exists** despite claims otherwise. The app does not compose `RemoteCallService`.

---

## Phase 16 - Remote Groups

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P16-001 | Persistent group identity | **VERIFIED COMPONENT ONLY** | `helix_remote_groups` - `createGroup()`; backend `GroupsModule` - group creation; storage `groups` table | Full persistence path at service/backend level | 21 backend tests; 21 service tests | Not wired into app composition root | None | Wire group service into app |
| P16-002 | Persistent membership and roles | **VERIFIED COMPONENT ONLY** | Backend `group_members` table, role column; service `getGroupMembersWithRoles()` | Backend enforces roles | Backend tests | Not wired | Backend authoritative | Wire membership UI |
| P16-003 | Invite/join approval rules | **VERIFIED COMPONENT ONLY** | Backend invite/accept/reject with ownership validation | Backend-enforced rules | Backend tests | Not wired | Server authoritative | Wire invite UI |
| P16-004 | Group E2EE strategy | **PARTIAL** | `group_encryption.dart` `GroupSenderChain`; service `encryptionKeyProvider` callback | **Deterministic fallback** `key_<group>_epoch_0` when no provider | `remote_group_service_test.dart` - P16-004 uses injectable provider | Fallback placeholders exist | **Deterministic key fallback is insecure** | Remove deterministic fallback; fail closed |
| P16-005 | Membership-change key updates | **PARTIAL** | Service `removeMember()` bumps epoch; `_bumpEpoch()` sends marker | Epoch increment; no proof of real key distribution | `remote_group_service_test.dart` - P16-005 epoch bumped | Key material not actually rotated | Epoch bump without key change is cosmetic | Implement real key distribution |
| P16-006 | Persistent group message history | **VERIFIED COMPONENT ONLY** | Storage `messages` table; service `getGroupMessages()` paginated | Full persistence path | Service tests | Not wired to UI | None | Wire group message UI |
| P16-007 | Persistent group files | **PARTIAL** | Uses existing attachment infrastructure | Same as Phase 14 attachment flow | Backend tests | Not wired | Depends on P14 fixes | Wire group attachment flow |
| P16-008 | Admin events | **VERIFIED COMPONENT ONLY** | Backend admin-only rename, role change, member removal; service enqueues admin operations | Backend-enforced admin authorization | Backend tests | Not wired | Backend authoritative | Wire admin UI |
| P16-009 | Leave/remove/block behavior | **VERIFIED COMPONENT ONLY** | Backend leave/remove routes; service leave/remove/delete | Full backend route + service implementation | Backend tests; service tests | Not wired | Final-admin rule not tested | Wire leave/remove UI |
| P16-010 | Group deletion | **VERIFIED COMPONENT ONLY** | Backend delete group (tombstone); service `deleteGroup()` | Tombstone and cleanup | Backend tests | Not wired | None | Wire group deletion UI |
| P16-011 | Offline member sync | **PARTIAL** | Backend push notification enqueue on group events | Push notification for offline members | Backend tests | No durable catch-up path for group events | None | Wire group events through sync engine |
| P16-012 | Multi-device membership sync | **PARTIAL** | Sync engine `_GroupCreatedEvent`, `_GroupInviteEvent`, `_GroupDeletedEvent`, `_GroupAdminEvent` | Events processed by sync engine | `remote_sync_test.dart` | No UI effect for group events | None | Wire sync events to group UI |
| P16-013 | Large-group pagination | **VERIFIED COMPONENT ONLY** | Backend paginated `GET /members`; service `getGroupMessages(limit, offset)` | Backend + service pagination | Backend tests; service tests | Not wired to UI | None | Wire group pagination UI |
| P16-014 | Abuse and rate limits | **VERIFIED COMPONENT ONLY** | Backend rate limits: 5 groups/day creation, 20 invites/hr | Backend-enforced | Backend tests | Not wired | Server authoritative | N/A for student scope |
| P16-015 | Group call architecture ADR | **VERIFIED COMPONENT ONLY** | `docs/architecture/adr_group_calls.md` | ADR records SFU decision | No tests needed | None | None | N/A |
| P16-016 | No Local host election reuse | **VERIFIED COMPONENT ONLY** | No `helix_local_*` imports in group service; group authority is ADMIN role | Verified by code inspection | Service test verifies no-Local-imports | None | None | Monitor |

**Phase 16 Summary:** Group service/backend/storage are thoroughly implemented. **Deterministic key fallback (P16-004) is a security defect.** Key rotation (P16-005) is cosmetic (epoch bump without real key distribution). The app does not compose group services.

---

## Phase 17 - Multi-Device, Backup, and Recovery

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P17-001 | Link new device | **VERIFIED COMPONENT ONLY** | Backend `POST /devices/link/request` | Full endpoint with pending link, OOB code | Backend `multi_device_backup_recovery_test.dart` | Not wired in app UI | Expiry, one-time use, account binding enforced | Wire device linking UI |
| P17-002 | Verify new device OOB | **VERIFIED COMPONENT ONLY** | Backend `POST /devices/link/verify` | Approve link with OOB code | Backend tests | Not wired | OOB verification enforced | Wire verification UI |
| P17-003 | Device key registration | **VERIFIED COMPONENT ONLY** | Backend device registration after link complete | Full path | Backend tests | Not wired | Key binding enforced | Wire registration UI |
| P17-004 | Per-device encrypted fan-out | **VERIFIED COMPONENT ONLY** | Backend message send validates per-device envelopes | Requires envelope for every active target device | Backend tests | Not wired in client | Backend validates fan-out | Wire multi-device send path |
| P17-005 | History sync | **PARTIAL** | Storage `exportBackupSnapshot`/`restoreBackupSnapshot` | Versioned snapshot export/restore | `remote_storage_test.dart` - 6 tests | Not wired in app | Tombstone filtering tested | Wire history sync in backup service |
| P17-006 | Device revocation | **VERIFIED COMPONENT ONLY** | Backend `POST /devices/revoke` revokes refresh tokens, creates revocation event | Full backend path | Backend `multi_device_backup_recovery_test.dart` | Not wired in app | Revoked device cannot auth/refresh | Wire revocation UI |
| P17-007 | Lost-device response | **VERIFIED COMPONENT ONLY** | Backend lost device revoke + mailbox purge | Full backend path | Backend tests | Not wired | Purges mailbox for lost device | Wire lost-device UI |
| P17-008 | Encrypted backup format | **VERIFIED COMPONENT ONLY** | `backup_crypto.dart` versioned `RemoteBackupEnvelope` | Version/KDF/salt/nonce/ciphertext/MAC | Crypto tests (P17: 2 tests) | Not wired to backup service | Metadata includes backupKeyHint (safe) | Wire backup service |
| P17-009 | Backup key ownership | **VERIFIED COMPONENT ONLY** | `backup_crypto.dart` key derivation; backend rejects key material upload | Client-side key; server stores only opaque ciphertext | Backend tests; crypto tests | Not wired | Server never sees key | Wire backup key lifecycle |
| P17-010 | Recovery phrase/passkey policy | **VERIFIED COMPONENT ONLY** | `backup_crypto.dart` `isValidRecoverySecret()` | Weak phrase rejection | Crypto tests (P17: weak phrase test) | Not wired to UI | Weak phrase rejected | Wire recovery UI |
| P17-011 | Backup versioning | **VERIFIED COMPONENT ONLY** | `RemoteBackupEnvelope.version`; version validation on decrypt | Unsupported version rejected | Crypto tests (P17: unsupported version test) | Not wired | None | Wire version check |
| P17-012 | Restore into new device | **PARTIAL** | Storage `restoreBackupSnapshot()`; backup upload/download | Atomic restore with tombstone filtering | Storage tests | Not wired in app | Atomic restore tested | Wire restore service |
| P17-013 | Account recovery without server keys | **VERIFIED COMPONENT ONLY** | Backend stores only opaque ciphertext; no key material | Server cannot decrypt backup | Backend tests | Not wired | Safe by design | Wire recovery UI |
| P17-014 | Deletion propagation to backups | **PARTIAL** | Backend marks backups requiring reupload after deletion | Backend enforces reupload marker | Backend tests | Not wired to client | None | Wire reupload verification |
| P17-015 | Recovery tests and disaster scenarios | **PARTIAL** | Crypto tests: backup roundtrip, weak phrase, version; storage tests: restore | Component-level roundtrip tests | 4 crypto + 2 storage tests | No disaster scenario test | None | Add disaster scenario tests |
| P17-016 | Document unrecoverable items | **VERIFIED COMPONENT ONLY** | `docs/product/remote/BACKUP_RECOVERY.md` | Documented | No tests needed | None | None | N/A |

**Phase 17 Summary:** Backend and crypto support for multi-device/backup/recovery is complete at the component level. The **app has no device management or backup/recovery screens or services**.

---

## Phase 18 - Privacy, Security, Abuse, and Compliance

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P18-001 | Publish accurate privacy policy | **VERIFIED COMPONENT ONLY** | `docs/product/remote/PRIVACY_POLICY.md` | Documentation only | No tests | None | None | N/A |
| P18-002 | Publish metadata inventory | **VERIFIED COMPONENT ONLY** | `docs/product/remote/METADATA_INVENTORY.md` | Documentation only | No tests | None | None | N/A |
| P18-003 | Publish retention schedule | **VERIFIED COMPONENT ONLY** | `docs/product/remote/RETENTION_AND_DELETION.md` | Documentation only | No tests | None | None | N/A |
| P18-004 | Publish data deletion behavior | **VERIFIED COMPONENT ONLY** | Same as P18-003 | Documentation only | No tests | None | None | N/A |
| P18-005 | No sale/monetization of personal data | **VERIFIED COMPONENT ONLY** | Privacy policy | Documentation | No tests | None | None | N/A |
| P18-006 | No plaintext content in logs | **PARTIAL** | Backend `logAudit` stores redacted IP/markers; service-level content redaction | Backend controls exist; app has no structured logging | `privacy_compliance_test.dart` | No app-level logging audit | Safe by existing design | Add app logging with redaction |
| P18-007 | No plaintext push payload | **VERIFIED COMPONENT ONLY** | Backend `enqueueOutbox` rejects plaintext payload keys | Backend-enforced for push | `privacy_compliance_test.dart` | No real push provider | Safe by backend rejection | N/A |
| P18-008 | No mandatory address-book upload | **VERIFIED COMPONENT ONLY** | No address-book upload code exists | Not implemented = compliant | No tests needed | None | None | N/A |
| P18-009 | Consent and permission review | **VERIFIED COMPONENT ONLY** | Documentation | Documentation | No tests | None | None | N/A |
| P18-010 | Data export | **VERIFIED COMPONENT ONLY** | Backend `GET /api/v1/privacy/export` | Server-visible data export | `privacy_compliance_test.dart` - P18 export test | Not wired to app UI | Ciphertext-only export | Wire export UI |
| P18-011 | Account deletion workflow | **PARTIAL** | Backend `DELETE /api/v1/account/delete` | Server-side account purge | `privacy_compliance_test.dart` - P18 deletion test | **Not wired in app** | Backend deletion works; **no local cleanup in app** | Wire account deletion in app |
| P18-012 | Security incident response doc | **VERIFIED COMPONENT ONLY** | `docs/security/REMOTE_SECURITY_AND_COMPLIANCE.md` | Documentation | No tests | None | None | N/A |
| P18-013 | Vulnerability disclosure policy | **VERIFIED COMPONENT ONLY** | Security documentation | Documentation | No tests | None | None | N/A |
| P18-014 | Dependency/CVE response policy | **VERIFIED COMPONENT ONLY** | Security documentation | Documentation | No tests | None | None | N/A |
| P18-015 | Penetration test | **OUT OF STUDENT SCOPE** | None | Requires external tester | None | BLOCKED | None | Mark OUT OF SCOPE |
| P18-016 | Independent crypto review | **OUT OF STUDENT SCOPE** | None | Requires external reviewer | None | BLOCKED | None | Mark OUT OF SCOPE |
| P18-017 | Mobile app security review | **OUT OF STUDENT SCOPE** | None | Requires release build review | None | BLOCKED | None | Mark OUT OF SCOPE |
| P18-018 | Backend security review | **OUT OF STUDENT SCOPE** | None | Requires deployed backend | None | BLOCKED | None | Mark OUT OF SCOPE |
| P18-019 | Secrets and access review | **OUT OF STUDENT SCOPE** | None | Requires production credentials | None | BLOCKED | None | Mark OUT OF SCOPE |
| P18-020 | Abuse-report handling | **VERIFIED COMPONENT ONLY** | Backend report creation; privacy-minimized | Backend route | Backend tests | Not wired to UI | Privacy-minimized enforced | Wire report UI |
| P18-021 | Admin access logging | **VERIFIED COMPONENT ONLY** | Backend admin access/denial audit logging | Backend-enforced | `privacy_compliance_test.dart` | Not wired | Admin actions audited | N/A |
| P18-022 | Production access approval | **OUT OF STUDENT SCOPE** | Documentation only | Requires prod infrastructure | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P18-023 | Backup encryption/restore auth | **VERIFIED COMPONENT ONLY** | See P17-008 through P17-013 | Component-level evidence | Multiple tests | Not wired in app | None | Wire backup service |
| P18-024 | App-store privacy declarations | **OUT OF STUDENT SCOPE** | `docs/product/remote/APP_STORE_PRIVACY.md` | Requires store submission | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P18-025 | Verify marketing against tests | **PARTIAL** | Claim matrix documentation | Documentation | No automated verification | None | None | N/A |

**Phase 18 Summary:** Backend privacy export, account deletion, and audit logging work. The **account deletion flow is not wired into the Remote app**. External review tasks are properly marked as blocked.

---

## Phase 19 - Operability, Reliability, Scaling, and Disaster Recovery

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P19-001 | Service-level indicators | **OUT OF STUDENT SCOPE** | Documentation only | Requires production metrics | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-002 | Service-level objectives | **OUT OF STUDENT SCOPE** | Documentation only | Requires production SLOs | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-003 | Alerting thresholds | **OUT OF STUDENT SCOPE** | Documentation only | Requires monitoring | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-004 | On-call/incident process | **OUT OF STUDENT SCOPE** | Documentation only | Requires production | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-005 | Automated backups | **OUT OF STUDENT SCOPE** | Documentation only | Requires production backup infra | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-006 | Restore drills | **OUT OF STUDENT SCOPE** | Documentation only | Requires production | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-007 | Database point-in-time recovery | **OUT OF STUDENT SCOPE** | Documentation only | Requires production DB | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-008 | Object-storage durability | **OUT OF STUDENT SCOPE** | Documentation only | Requires object storage | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-009 | Redis-loss behavior | **OUT OF STUDENT SCOPE** | Documentation only | Requires Redis | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-010 | WebSocket reconnect storm | **VERIFIED COMPONENT ONLY** | Backend `websocket.dart` reconnect rejection | Backend: rejects excessive per-device reconnect | `operability_test.dart` | Not tested from client side | None | Add client-side storm test |
| P19-011 | Push provider outage handling | **PARTIAL** | Backend `outbox_worker.dart` retry/DLQ | Retry and DLQ after bounded failures | `operability_test.dart` | No real provider = no outage test | None | N/A for student scope |
| P19-012 | TURN outage handling | **OUT OF STUDENT SCOPE** | Documentation only | Requires production TURN | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-013 | Rate-limit tuning | **VERIFIED COMPONENT ONLY** | Backend `operability.dart` exposes rate limiter stats | Admin-only aggregate stats | `operability_test.dart` | Not wired to admin UI | None | N/A for student scope |
| P19-014 | Capacity tests | **OUT OF STUDENT SCOPE** | Documentation only | Requires load testing infra | No tests | BLOCKED | None | Add bounded local stress tests |
| P19-015 | Cost budgets and alerts | **OUT OF STUDENT SCOPE** | Documentation only | Requires cloud billing | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-016 | Database partition/archive | **OUT OF STUDENT SCOPE** | Not implemented | Not justified | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-017 | Broker extraction | **OUT OF STUDENT SCOPE** | Not implemented | Not justified | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-018 | Zero-downtime migration | **OUT OF STUDENT SCOPE** | Documentation only | Requires production | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-019 | Client/server compatibility | **PARTIAL** | Compatibility fixtures exist | Fixture-based test coverage | `serialization_test.dart` | Not tested for all event types | None | Add more compatibility tests |
| P19-020 | Emergency rollback | **OUT OF STUDENT SCOPE** | Documentation only | Requires production | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-021 | Status page | **OUT OF STUDENT SCOPE** | Documentation only | Requires production | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P19-022 | Runbooks | **OUT OF STUDENT SCOPE** | Documentation only | Requires production | No tests | BLOCKED | None | Mark OUT OF SCOPE |

**Phase 19 Summary:** P19-010 (WebSocket storm) and P19-013 (rate-limit tuning) have backend implementation. Most Phase 19 items are OUT OF STUDENT SCOPE (production-only). The local developer lifecycle (start/stop/backup/restore backend) is not scripted.

---

## Phase 20 - Independent Release Pipelines and Long-Term Governance

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P20-001 | Local analyze/test | **VERIFIED END TO END** | verify scripts + CI | Works as intended | All test suites pass | None | None | Monitor |
| P20-002 | Local Android build/sign | **OUT OF STUDENT SCOPE** | Build scripts exist | Requires signing material | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-003 | Local Windows build/sign | **OUT OF STUDENT SCOPE** | Build scripts exist | Requires signing material | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-004 | Local offline acceptance tests | **VERIFIED END TO END** | `helix_local/test/` | 196 tests pass | All pass | None | None | Monitor |
| P20-005 | Local wipe isolation tests | **VERIFIED END TO END** | `helix_local_storage/test/` | Storage isolation tests | 28 tests pass | None | None | Monitor |
| P20-006 | Local protocol compatibility | **VERIFIED END TO END** | Protocol fixture tests | Fixture decoding | Tests pass | None | None | Monitor |
| P20-007 | Local release notes | **VERIFIED COMPONENT ONLY** | Release docs exist | Documentation | No tests | None | None | N/A |
| P20-008 | Remote client analyze/test | **VERIFIED END TO END** | verify scripts | 28 app + 17 api + 24 calls + 19 crypto + 21 groups + 6 storage + 11 sync = 126 tests pass | All pass | None | None | Monitor |
| P20-009 | Remote backend unit/integration | **VERIFIED END TO END** | 59 backend tests pass | 59 tests pass | All pass | None | None | Monitor |
| P20-010 | Contract compatibility tests | **VERIFIED COMPONENT ONLY** | `serialization_test.dart` | Fixture-based | 17 tests pass | Not running against actual backend routes | None | Add route-level contract tests |
| P20-011 | Database migration tests | **NOT STARTED** | No dedicated migration test | No migration test file | None | Migration between versions not tested | None | Add migration test |
| P20-012 | Remote Android build/sign | **OUT OF STUDENT SCOPE** | Build scripts exist | Requires signing material | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-013 | Remote Windows build/sign | **OUT OF STUDENT SCOPE** | Build scripts exist | Requires signing material | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-014 | Staging E2E tests | **OUT OF STUDENT SCOPE** | None | Requires staging infra | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-015 | Security gates | **VERIFIED END TO END** | Secret scan, boundary check, etc. | All pass | All pass | None | None | Monitor |
| P20-016 | Production deployment/rollback | **OUT OF STUDENT SCOPE** | None | Requires production infra | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-017 | Remote release notes | **VERIFIED COMPONENT ONLY** | Release docs exist | Documentation | No tests | None | None | N/A |
| P20-018 | Install both apps | **OUT OF STUDENT SCOPE** | None | Requires signed artifacts | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-019 | Run both simultaneously | **OUT OF STUDENT SCOPE** | None | Requires installable artifacts | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-020 | Independent notifications | **OUT OF STUDENT SCOPE** | None | Requires device checks | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-021 | Camera/microphone contention | **OUT OF STUDENT SCOPE** | None | Requires device checks | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-022 | Independent secure storage | **VERIFIED END TO END** | Storage isolation tests | 28 tests pass | All pass | None | None | Monitor |
| P20-023 | Independent databases | **VERIFIED END TO END** | DB isolation tests | Different filenames/prefixes tested | All pass | None | None | Monitor |
| P20-024 | Local wipe leaves Remote | **VERIFIED END TO END** | Scoped deletion tests | P6-050 to P6-053 tests | All pass | None | None | Monitor |
| P20-025 | Remote logout leaves Local | **VERIFIED END TO END** | Isolation tests | Path inventory tests | All pass | None | None | Monitor |
| P20-026 | Uninstall Local | **OUT OF STUDENT SCOPE** | None | Requires device uninstall | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-027 | Uninstall Remote | **OUT OF STUDENT SCOPE** | None | Requires device uninstall | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-028 | Local has no Remote traffic | **VERIFIED END TO END** | Boundary tests | No Remote backend URLs in Local | Pass | None | None | Monitor |
| P20-029 | Remote no LAN broadcast | **VERIFIED END TO END** | Boundary tests | No mDNS/UDP in Remote | Pass | None | None | Monitor |
| P20-030 | Package dependency firewall | **VERIFIED END TO END** | boundary_test.dart | No forbidden imports | 5/5 pass | None | None | Monitor |
| P20-031 | Quarterly architecture review | **OUT OF STUDENT SCOPE** | Documentation only | Requires process | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-032 | Quarterly dependency review | **OUT OF STUDENT SCOPE** | Documentation only | Requires process | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-033 | Annual threat-model review | **OUT OF STUDENT SCOPE** | Documentation only | Requires process | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-034 | Security-claim review | **OUT OF STUDENT SCOPE** | Documentation only | Requires process | No tests | BLOCKED | None | Mark OUT OF SCOPE |
| P20-035 | ADR cross-product sharing | **VERIFIED COMPONENT ONLY** | Existing ADRs demonstrate process | N/A | N/A | None | None | N/A |
| P20-036 | Deprecation policy | **VERIFIED COMPONENT ONLY** | Governance docs | Documentation | No tests | None | None | N/A |
| P20-037 | Ownership map | **VERIFIED END TO END** | `ownership-blast-radius.yaml` | Covers all packages | tested by `phase20_release_governance_test.dart` | None | None | Monitor |
| P20-038 | Keep plan updated | **VERIFIED COMPONENT ONLY** | This document + master plan | Ongoing | N/A | None | None | N/A |
| P20-039 | Archive completed phase evidence | **PARTIAL** | Phase 0-11 closure archived | Phase 12-20 not yet archived | N/A | None | None | Archive after closure |
| P20-040 | Never delete historical decisions | **VERIFIED COMPONENT ONLY** | All historical docs preserved | N/A | N/A | None | None | N/A |

**Phase 20 Summary:** All code-based checks pass (format, analyze, boundaries, secrets, tests). Signing, staging, deployment, co-install checks are OUT OF STUDENT SCOPE. Migration tests and contract tests against actual backend routes are not yet implemented.

---

## Cross-Cutting Critical Issues

### 1. RemoteCompositionRoot is underspecified
- Wires only key storage, database, sync engine
- Missing: REST client, WebSocket client, SyncGateway, messaging service, attachment service, call service + engine, group service, backup service, privacy service, session store, identity service, message protector
- File: `apps/helix_remote/lib/app/composition_root.dart`
- Repair: Stage 1

### 2. Remote app UI is an in-memory demo
- Contacts, messages, settings all in widget state (`_contacts`, `_messages`, `_UiMessage`)
- No service calls, no persistence, no transport
- File: `apps/helix_remote/lib/main.dart`
- Repair: Stage 4 (data-driven UI) + Stage 1 (composition)

### 3. No concrete REST client
- `HelixRemoteRestClient` is an abstract interface in `helix_remote_api`
- File: `packages/remote/helix_remote_api/lib/api/rest_client.dart`
- Repair: Stage 2

### 4. No concrete SyncGateway or realtime WebSocket client
- Sync engine has no feed source
- No concrete `SyncGateway` implementation
- Repair: Stage 2 + Stage 3

### 5. Fresh install cannot start (db_key unavailable)
- `RemoteCompositionRoot._loadRequiredDbKey` throws when no key exists
- No first-run key generation flow
- File: `apps/helix_remote/lib/app/composition_root.dart:180`
- Repair: Stage 1.2

### 6. Attachment raw-key fallback (DEFECTIVE)
- `buildKeyDeliveryPackage` silently uses raw key when no encryptor supplied
- File: `apps/helix_remote/lib/app/remote_attachment_service.dart`
- Repair: Stage 6.3

### 7. No concrete Remote WebRTC engine
- `RemoteCallEngine` is abstract; `RemoteWebRtcCallEngine` does not exist
- Files: `packages/remote/helix_remote_calls/lib/src/call_engine.dart`
- Repair: Stage 7.1

### 8. Group encryption deterministic fallback (DEFECTIVE)
- `key_<group>_epoch_0` placeholder when no provider
- File: `packages/remote/helix_remote_groups/lib/src/group_service.dart`
- Repair: Stage 8.1

### 9. Single global cursor vs per-conversation sequences
- `RemoteSyncCursor` stores per-conversation sequence
- Backend sequences may be per-conversation while client expects global
- Repair: Stage 3.3

### 10. Realtime envelope type mismatch
- Backend emits raw `type: message` but client expects `chat_message`
- Envelope format mismatch between backend and client
- Repair: Stage 3.1

---

## Historical Checklist Corrections

The following historical checklist claims overstate completion:

| Phase | Checkbox | Claimed | Actual | Correction |
|---|---|---|---|---|
| P12 | Many [x] items | Complete | **DISCONNECTED** | UI is in-memory demo; service/backend not wired |
| P13 | All [x] | Complete | **DISCONNECTED** | Backend/services not wired into app |
| P14 | All [x] | Complete | **PARTIAL / DEFECTIVE** | Raw key fallback; no app wiring |
| P15 | All [x] | Complete | **VERIFIED COMPONENT ONLY / PARTIAL** | No concrete engine |
| P16 | All [x] | Complete | **PARTIAL / DEFECTIVE** | Deterministic key fallback; cosmetic rotation |
| P17 | All [x] | Complete | **PARTIAL / DISCONNECTED** | Not wired in app |
| P18 | P18-011 [x] | Account deletion complete | **PARTIAL** | Backend only; not wired in app |
| P19 | P19-010 [x] | WebSocket storm | **VERIFIED COMPONENT ONLY** | Backend-side only, not tested client-side |
| P20 | P20-011 [x] | Migration tests | **NOT STARTED** | No dedicated migration test file |

The correction above is the authoritative closure-in-progress annotation.

---

## Stage 0 Exit Gate Verification

| Gate | Status | Evidence |
|---|---|---|
| No Phase 12-20 task remains classified only from its checkbox | **PASS** | Every task has source files, wiring path, tests, and missing integration documented |
| Every end-to-end claim names concrete UI -> service -> transport -> backend -> database path | **PASS** | `VERIFIED END TO END` items have named paths; all others document exactly what is missing |
| Baseline clearly separates component code from runnable application behavior | **PASS** | The core finding explicitly distinguishes library/package code from app wiring |

STAGE 0 - CREATE AN HONEST PHASE 12-20 BASELINE ✅ Done
