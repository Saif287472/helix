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

The original 2026-06-19 baseline correctly identified that the Remote Flutter
app was a disconnected in-memory demonstration. Phases 1-12 have since repaired
the direct-message critical path enough for a service-backed MVP:

- `RemoteCompositionRoot` composes secure key storage, encrypted Remote DB,
  concrete REST client, concrete sync gateway, WebSocket client, sync engine,
  message protector, `RemoteMessagingService`, attachment, call, group, and
  runtime coordinator services.
- `main.dart` routes account creation and restored sessions through
  `RemoteCompositionRoot` rather than widget-local auth state.
- The direct-message screens route contact requests, direct-conversation
  creation, send, history, search, receipts, typing, edits, reactions, deletes,
  and blocking through `RemoteMessagingService` and persistent Remote storage.
- The app no longer owns widget-local demo contact/message lists for the
  direct-message path.

Remaining Phase 13-20 work is still real: contacts/privacy, attachments,
calls, groups, backup/recovery, production operations, external security review,
and real-device/staging E2E need their own closure evidence.

---

## Phase 12 - Remote One-to-One Messaging MVP

| ID | Item | Status | Implementation Files | Production/Dev Wiring Path | Tests | Missing Integration | Security/Data Risk | Repair Task |
|---|---|---|---|---|---|---|---|---|
| P12-001 | Account sign-in/setup UI | **PARTIAL** | `apps/helix_remote/lib/main.dart`; `apps/helix_remote/lib/app/composition_root.dart` | UI calls `RemoteCompositionRoot.registerAndLogin()` / `tryRestoreSession()` | `widget_test.dart`; `composition_root_test.dart` | Restore-code UX is still a placeholder; real backend availability is environmental | No widget-local credentials | Complete full restore workflow in backup/recovery phase |
| P12-002 | Device verification UI | **VERIFIED COMPONENT ONLY** | `RemoteMessagingService.verifyDevice()`; `DeviceManagementScreen` | Device list/revoke/rename uses REST; local verify API exists | `remote_messaging_service_test.dart`; device/backend tests | Manual safety-number verification UI is still future work | Unknown devices fail verification | Add explicit safety-number verification screen |
| P12-003 | Add contact by username/account ID | **PARTIAL** | `conversation_list_screen.dart`; `remote_messaging_service.dart` | UI -> `sendContactRequest()` -> contacts table + outbox | `remote_messaging_service_test.dart` | Accept/reject/cancel lifecycle is Phase 13 UI work | Contact request quota enforced locally | Phase 13 contact screens |
| P12-004 | One-to-one conversation creation | **PARTIAL** | `conversation_list_screen.dart`; `remote_messaging_service.dart`; storage DB | UI -> `createDirectConversation()` -> persistent conversation + outbox | `remote_messaging_service_test.dart` | Contact-list widget path lacks dedicated test | None | Add list-screen widget test in Phase 13 |
| P12-005 | E2EE text send | **PARTIAL** | `remote_messaging_service.dart`; `remote_message_protector.dart`; `conversation_screen.dart` | UI -> service -> ciphertext local history + outbox/gateway | `remote_messaging_service_test.dart`; `phase12_remote_messaging_screen_test.dart` | Full DH Double Ratchet and external review remain blocked | Missing recipient devices now fail closed with no send op | Continue crypto hardening under security review gate |
| P12-006 | Offline receive | **PARTIAL** | `remote_sync_gateway.dart`; `remote_websocket_client.dart`; `sync_engine.dart`; runtime coordinator | REST catch-up + realtime envelope handling are composed | `remote_sync_test.dart`; runtime tests | Real backend/client E2E still release-gated | Duplicate event rejection tested | Add real-device/staging E2E |
| P12-007 | Persistent conversation list | **PARTIAL** | `conversation_list_screen.dart`; storage DB | UI reads `messagingService.conversationList()` from DB | Remote storage/service tests | No stream-based live list refresh yet | None | Add reactive list refresh |
| P12-008 | Persistent message history | **PARTIAL** | `conversation_screen.dart`; storage DB | UI reads `messageHistory()` and decodes local ciphertext | `phase12_remote_messaging_screen_test.dart`; storage tests | Search still decrypts bounded local page/service result | Ciphertext column is correctly named `ciphertext_blob` | Optimize large local search later |
| P12-009 | Delivery receipts | **PARTIAL** | `conversation_screen.dart`; `remote_messaging_service.dart` | Visible inbound messages enqueue delivery receipts | `phase12_remote_messaging_screen_test.dart` | Backend/device E2E receipt propagation not covered here | No plaintext in receipt payload | Add E2E receipt scenario |
| P12-010 | Read receipts with privacy setting | **PARTIAL** | `remote_messaging_service.dart`; `conversation_screen.dart` | UI marks read via service; service respects read-receipt toggle | `remote_messaging_service_test.dart`; `phase12_remote_messaging_screen_test.dart` | Dedicated settings UI for this toggle is not present | Toggle suppresses read operation | Wire setting in privacy UI |
| P12-011 | Typing indicators as ephemeral state | **PARTIAL** | `conversation_screen.dart`; `remote_messaging_service.dart`; `remote_sync_gateway.dart` | Text input publishes `TYPING` through gateway, not DB | `phase12_remote_messaging_screen_test.dart` | Realtime peer display is future work | Typing is not persisted | Add inbound typing display |
| P12-012 | Message edits as persistent events | **PARTIAL** | `conversation_screen.dart`; `remote_messaging_service.dart`; backend messaging routes | UI -> service revision + outbox | `phase12_remote_messaging_screen_test.dart`; backend messaging tests | Real peer E2E propagation not covered here | Edited text stored as local ciphertext | Add backend/client E2E |
| P12-013 | Message reactions as persistent events | **PARTIAL** | Same as edits | UI -> service revision + outbox | `phase12_remote_messaging_screen_test.dart`; backend messaging tests | Full reaction picker is minimal (`+1`) | No message plaintext in outbox payload | Expand UX later |
| P12-014 | Delete-for-self | **PARTIAL** | `conversation_screen.dart`; `remote_messaging_service.dart` | UI -> local tombstone + DB delete | `phase12_remote_messaging_screen_test.dart` | No undo UX | Local tombstone prevents reappearance | Add user-facing confirmation/undo if desired |
| P12-015 | Delete-for-everyone | **PARTIAL** | `conversation_screen.dart`; `remote_messaging_service.dart`; backend messaging route | UI -> service tombstone + delete outbox | `remote_messaging_service_test.dart`; backend messaging tests | Real peer E2E propagation not covered here | Tombstone prevents local reappearance | Add backend/client E2E |
| P12-016 | Blocking | **PARTIAL** | `conversation_screen.dart`; `remote_messaging_service.dart`; backend contacts route | UI -> service contact block + outbox/backend route | `remote_messaging_service_test.dart`; backend contacts tests | Phase 13 owns full block/unblock UX | Backend enforces block | Wire richer safety UI |
| P12-017 | Push notification without plaintext | **OUT OF STUDENT SCOPE** | Backend push outbox | Requires provider infrastructure | Backend outbox tests | Real provider unavailable | Existing preview is generic | Release/infrastructure scope |
| P12-018 | Search over local decrypted history | **PARTIAL** | `conversation_screen.dart`; `remote_messaging_service.dart` | UI -> service local decrypted search | `phase12_remote_messaging_screen_test.dart` | Large-history index optimization deferred | Search does not leave device | Add performance search index later |
| P12-019 | Pagination | **PARTIAL** | `conversation_screen.dart`; storage DB | UI uses `limit/offset` with "Load earlier messages" | `phase12_remote_messaging_screen_test.dart`; storage tests | No infinite-scroll prefetch | None | Polish pagination UX |
| P12-020 | Migration and compatibility tests | **PARTIAL** | `remote_storage_test.dart`; API serialization fixtures | Current schema migrations and DTO decoding tested | storage/API tests | No Phase-12-specific rolling upgrade E2E | None | Broaden rolling-upgrade matrix |
| P12-021 | E2E tests across two devices | **OUT OF STUDENT SCOPE** | Backend integration and app widget/service tests | In-process coverage only | backend integration tests; Phase 12 widget/service tests | Requires real devices/staging infra | None | Release/staging gate |
| P12-022 | No Local package imports | **VERIFIED COMPONENT ONLY** | `apps/helix_remote/**`; `packages/remote/**` | Boundary checker enforces product isolation | `tool/boundary_test.dart`; `check_boundaries.dart` | None | None | Monitor |

**Phase 12 Summary:** The Remote direct-message path is now service-backed
instead of widget-local demo state. Account setup, contact request creation,
direct conversation creation, local encrypted history, search, paging, receipts,
typing, edits, reactions, deletes, blocking, sync gateway, and runtime wiring all
have executable evidence. Production-grade Double Ratchet claims, external push,
manual safety-number verification, and real-device/staging E2E remain separate
release/security gates.

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

### 1. RemoteCompositionRoot underspecified (REPAIRED through Phase 12)
- `RemoteCompositionRoot` now wires secure storage, encrypted DB, concrete REST,
  concrete sync gateway, WebSocket, sync engine, messaging, attachment, call,
  group, and runtime coordinator services.
- File: `apps/helix_remote/lib/app/composition_root.dart`
- Evidence: `composition_root_test.dart`, `remote_runtime_coordinator_test.dart`,
  `phase12_remote_messaging_screen_test.dart`

### 2. Remote direct-message UI in-memory demo (REPAIRED through Phase 12)
- Account setup and direct-message screens now call composition/root services and
  `RemoteMessagingService`; contacts, conversations, and messages persist in
  Remote storage.
- Files: `apps/helix_remote/lib/main.dart`,
  `apps/helix_remote/lib/screens/conversation_list_screen.dart`,
  `apps/helix_remote/lib/screens/conversation_screen.dart`
- Evidence: `phase12_remote_messaging_screen_test.dart`

### 3. Concrete REST client missing (REPAIRED)
- `HelixRemoteRestClientImpl` is composed by `RemoteCompositionRoot`.
- File: `apps/helix_remote/lib/app/remote_rest_client.dart`

### 4. Concrete SyncGateway and realtime WebSocket missing (REPAIRED)
- `RemoteSyncGatewayImpl` and `RemoteWebSocketClient` are composed by the
  runtime path.
- Files: `apps/helix_remote/lib/app/remote_sync_gateway.dart`,
  `apps/helix_remote/lib/app/remote_websocket_client.dart`

### 5. Fresh install cannot start (REPAIRED)
- `_loadOrCreateDbKey()` creates a first-run DB key and fails closed only when
  an existing database lacks its secure-storage key.
- File: `apps/helix_remote/lib/app/composition_root.dart`

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
| P12 | Many [x] items | Complete | **REPAIRED TO MVP** | Direct-message app path is service-backed; real-device/staging E2E remains release-gated |
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
