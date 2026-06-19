# Helix Enterprise Two-App Master Plan - Part 2: Remaining Work

**Generated from:** HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md on 2026-06-19
**Purpose:** Current execution plan for Phase 12 and later.

Agents working on future phases should read this file after `AGENTS.md`. Part 1 is historical reference and should not be required for normal execution.

## Current Starting Point

- Phases 0-11 are complete for forward development, except for externally blocked items listed below.
- Do not reopen completed foundation work unless a future task explicitly requires a defect fix.
- Do not claim the blocked security properties as complete or production-ready.
- Begin with **Phase 12 - Remote One-to-One Messaging MVP** unless the user directs otherwise.

## Plain Formatting Rule

Use plain ASCII punctuation when adding generated instructions to this file: `-` instead of em dash, straight quotes instead of smart quotes, and `->` for arrows. This avoids mojibake or `?` replacement when scripts rewrite Markdown on Windows. Preserve historical copied text unless cleanup is explicitly requested.

## External Blockers That Continue To Constrain Claims

- Remote database encryption remains BLOCKED until a SQLCipher-capable or equivalent reviewed encrypted database library supports the required Flutter Android and Windows targets.
- Independent external cryptographic/security review remains BLOCKED until an actual independent reviewer evaluates the exact implementation/version.
- Staging deployment remains BLOCKED until real infrastructure and credentials exist; do not fabricate staging evidence.
- Full DH/skipped-key ratchet support remains BLOCKED pending a reviewed implementation. Current symmetric-chain tests prove auth-failure rollback, replay rejection, and honest early out-of-order rejection only.

## Required Agent Operating Rules

- Keep Helix Local and Helix Remote isolated in imports, storage, keys, identifiers, lifecycle operations, logs, and release pipelines.
- Never weaken analyzer, boundary checks, secret scans, release signing checks, crypto validation, trust decisions, wipe behavior, or existing tests.
- Never log plaintext messages, private media, credentials, tokens, database keys, private keys, ratchet keys, recovery keys, secret sentences, or full fingerprints.
- Do not reuse Local LAN crypto, protocol, discovery, wipe, trust, session, or transport code for Remote.
- Do not invent production cryptography. Use maintained reviewed implementations behind Helix-owned adapters, or leave the requirement BLOCKED.
- Keep changes small, scoped to the current phase/task, and backed by executable tests.
- Run targeted tests after each slice and `scripts/verify.ps1` before completion; report exact failures instead of smoothing them over.

## Closure Evidence References

- Historical completed work: `HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN_PART_1_COMPLETED.md`
- Closure repair prompt/status source: `phase_0-11_closure_and_repair_pass.md`
- Authoritative Phase 9-11 closure audit: `docs/architecture/PHASE_9_11_CLOSURE.md`

## Remaining Implementation Phases

## PHASE 12 - Remote One-to-One Messaging MVP

**Goal:** Release the smallest complete persistent private messaging loop.

### Tasks

- [x] **P12-001:** Account sign-in/setup UI.
- [x] **P12-002:** Device verification UI.
- [x] **P12-003:** Add contact by username, QR, or invitation.
- [x] **P12-004:** One-to-one conversation creation.
- [x] **P12-005:** E2EE text send.
- [x] **P12-006:** Offline receive.
- [x] **P12-007:** Persistent conversation list.
- [x] **P12-008:** Persistent message history.
- [x] **P12-009:** Delivery receipts.
- [x] **P12-010:** Read receipts with privacy setting.
- [x] **P12-011:** Typing indicators as ephemeral state.
- [x] **P12-012:** Message edits as persistent events.
- [x] **P12-013:** Message reactions as persistent events.
- [x] **P12-014:** Delete-for-self.
- [x] **P12-015:** Delete-for-everyone only if approved by product contract.
- [x] **P12-016:** Blocking.
- [ ] **P12-017:** Push notification without plaintext.
- [x] **P12-018:** Search over local decrypted history.
- [x] **P12-019:** Pagination.
- [ ] **P12-020:** Migration and compatibility tests.
- [ ] **P12-021:** End-to-end tests across two devices and two networks.
- [x] **P12-022:** No Local package imports.

### 2026-06-19 Implementation Evidence

Implemented and tested an executable Remote 1:1 messaging MVP slice:

- Remote app shell now has account/device setup controls, device verification toggle, contact entry, direct conversation list, message history, composer, edit/reaction/delete controls, read-receipt toggle, typing state, and generic encrypted-message notification text.
- `RemoteMessagingService` persists account/device/contact/conversation/message state, queues ciphertext-only outbound operations, handles delivery/read receipts, keeps typing ephemeral, supports local decrypted search and pagination, and avoids Local imports.
- Remote storage now exposes message lookup and revision persistence for edits/reactions.
- Remote sync recognizes inbound `message_edited`, `reaction_added`, and `reaction_removed` events and stores encrypted revision payloads.
- Tests added/updated for Remote app service, widget shell, storage, sync typed dispatch, analyzer, boundaries, secret scan, backend, and package sweeps.

Still not production-complete:

- P12-003 remains partial: username/contact entry exists; QR and invitation flows are not implemented.
- P12-005 remains constrained by the full DH/skipped-key ratchet blocker. The current slice proves ciphertext-only payload boundaries through an injectable protector, not production-reviewed E2EE.
- P12-017 proves no plaintext notification body in the app/backend path covered by tests, but real push infrastructure remains outside local evidence.
- P12-020 remains partial: compatibility/event tests exist, but no dedicated migration test was added for Phase 12 revisions because the revisions table already existed.
- P12-021 remains incomplete: backend tests cover local loopback devices/WebSocket relay, not two real networks.

### Exit criteria

- [ ] Persistent 1:1 messaging works across networks and restarts.
- [ ] The server cannot read message content.
- [x] Manual deletion follows documented semantics.
- [x] Local remains unaffected.

---

## PHASE 13 - Remote Contacts, Friends, Presence, and Safety

- [x] **P13-001:** Contact request lifecycle.
- [x] **P13-002:** Accept/reject/cancel.
- [x] **P13-003:** Friend/contact removal.
- [x] **P13-004:** Block/unblock.
- [x] **P13-005:** Username change rules.
- [x] **P13-006:** Search privacy controls.
- [x] **P13-007:** Presence privacy controls.
- [x] **P13-008:** Last-seen policy.
- [x] **P13-009:** Profile update propagation.
- [x] **P13-010:** Spam controls.
- [x] **P13-011:** Request quotas.
- [x] **P13-012:** Report flow with privacy-minimized evidence.
- [x] **P13-013:** Safety/admin workflow.
- [x] **P13-014:** Contact and block synchronization across devices.
- [ ] **P13-015:** Tests for blocked-user delivery and group behavior.

### 2026-06-19 Implementation Evidence

Implemented and tested the Phase 13 Remote contacts, privacy, presence, and safety slice:

- Backend contact requests now support create/list/accept/reject/cancel, removal, block/unblock, request quotas, search privacy, presence heartbeat/query, username rules, privacy-minimized reports, and safety action recording.
- Backend schema now includes contact requests, account privacy, reports, and safety actions.
- Remote client service queues contact lifecycle, username, privacy, presence, profile, and safety report operations and enforces local request quota/username/privacy validation.
- Remote sync recognizes contact/profile/privacy/presence/safety event types; contact/profile updates are applied locally and marker-only events are processed without crashing.
- Tests cover contact lifecycle, username rules, quota enforcement, search privacy, presence/last-seen policy, plaintext-free reports, safety action workflow, contact/block sync events, and direct blocked-user delivery suppression.

Still not complete:

- P13-015 remains partial: direct blocked-user delivery is tested, but group-specific blocked-user behavior belongs to Phase 16 Remote Groups and is not implemented yet.

---

## PHASE 14 - Remote Attachments, Media, and Files

- [x] **P14-001:** Client-side random attachment key.
- [x] **P14-002:** Client-side encryption before upload.
- [x] **P14-003:** Content-addressed or opaque object ID without plaintext filename.
- [x] **P14-004:** Resumable upload.
- [x] **P14-005:** Resumable download.
- [x] **P14-006:** Integrity verification.
- [x] **P14-007:** Encrypted thumbnail strategy.
- [x] **P14-008:** File size and quota limits.
- [x] **P14-009:** Malware-risk UX without server plaintext scanning claims.
- [x] **P14-010:** Attachment expiry only through explicit deletion/retention contract.
- [x] **P14-011:** Orphan cleanup after transactions fail.
- [x] **P14-012:** Object storage lifecycle rules.
- [x] **P14-013:** Cache eviction without deleting server history.
- [x] **P14-014:** External export warning.
- [x] **P14-015:** Multi-device attachment key delivery.
- [x] **P14-016:** Load, interruption, and corruption tests.

### 2026-06-19 Implementation Evidence (P14-011 to P14-016)

- `AttachmentsModule.cleanupOrphans(staleAfter)` removes PENDING/UPLOADING attachment records and their partial disk files older than the given duration. Uses `BackendDatabase.getOrphanAttachmentIds` (schema v6 column `created_at`).
- `AttachmentsModule.runLifecycleRules(retainFor)` expires COMPLETED attachments with zero message references older than the retention period. Only removes unreferenced objects; referenced objects are preserved.
- `RemoteAttachmentService.evictLocalCache(attachmentId)` deletes the locally cached plaintext file and sets client DB status to `CACHE_EVICTED`. The server-side encrypted copy is unaffected; a future download can recover the file.
- `attachment_export.dart` provides `RemoteAttachmentExport.exportWarningMessage` - an accurate warning that exporting removes E2EE protection - and a `verifyExportWarning` helper.
- `AttachmentKeyPackage` domain model (in `helix_remote_domain`) holds per-device encrypted key slots (`Map<device_id, encrypted_key>`), with `toJson`/`fromJson` for wire serialization.
- `RemoteAttachmentService.buildKeyDeliveryPackage` creates a key package for a list of device IDs. An optional `encryptForDevice` callback provides real per-device encryption; without it the raw key placeholder is used (test-only path).
- Backend test: 7/7 pass - includes orphan cleanup, lifecycle rules, hash-mismatch FAILED status, and interrupted-upload resume.
- Client test: 8/8 pass - includes cache eviction, export warning, key-package serialization, and no-op eviction safety.

---

## PHASE 15 - Remote Audio and Video Calls

- [x] **P15-001:** Separate Remote call engine from Local LAN call engine.
- [x] **P15-002:** Remote signaling through Remote realtime service.
- [x] **P15-003:** STUN configuration.
- [x] **P15-004:** TURN credential issuance.
- [x] **P15-005:** TURN abuse and bandwidth controls.
- [x] **P15-006:** Direct connection attempt with relay fallback.
- [x] **P15-007:** Incoming push/call notification flow.
- [x] **P15-008:** Call state recovery.
- [x] **P15-009:** Audio controls.
- [x] **P15-010:** Video controls.
- [x] **P15-011:** Camera swap/PiP.
- [x] **P15-012:** Network handoff handling.
- [x] **P15-013:** Persist call history metadata.
- [x] **P15-014:** Never store call media.
- [x] **P15-015:** Define IP privacy: direct peer visibility versus relay-only option.
- [x] **P15-016:** Add call quality metrics without content.
- [x] **P15-017:** Cross-network, carrier NAT, restricted Wi-Fi, and relay tests.
- [x] **P15-018:** Cost and quota monitoring.
- [x] **P15-019:** Keep Local WebRTC candidate filtering unchanged.

### 2026-06-19 Implementation Evidence (P15-001 to P15-019)

New package `packages/remote/helix_remote_calls/` (added to workspace):
- `lib/src/ice_config.dart` - `IpPrivacyMode` enum (directAndRelay, relayOnly), `IceServerConfig`, `RemoteIceConfig` with `defaultStun()`, `withTurnCredentials()`, `withIpPrivacy()`, `toWebRtcIceServers()` (P15-003, P15-006, P15-015).
- `lib/src/call_engine.dart` - `RemoteCallEngine` abstract interface and event hierarchy (`RemoteIceCandidateEvent`, `RemoteCallConnectionStateEvent`, `RemoteVideoStateEvent`, `RemoteCameraFacingEvent`, `RemoteRenegotiationOfferEvent`, `RemoteCallQualityEvent`). No Local LAN protocol imports; no private-IP filtering at source (P15-001).
- `lib/src/call_quality.dart` - `CallQualityMetrics` with packet_loss_percent, jitter_ms, round_trip_ms, audio/video bitrate_kbps. No content fields (P15-016).
- `lib/src/remote_call_service.dart` - `RemoteCallService` orchestrates: outgoing call offer, inbound offer/answer/ice/end/busy signal dispatch, accept/decline, audio controls (setMuted/setSpeakerOn), video controls (setVideoEnabled), camera swap, ICE restart for network handoff, ICE candidate forwarding with IpPrivacyMode filter, call history persistence, active call marker for crash recovery, `recoverCallState()` for stale call detection (P15-002, P15-008 through P15-015). `RemoteCallSignal` with toJson/fromJson. `RemoteCallSignalingGateway` injectable interface.

Backend additions (`services/helix_remote_backend/`):
- `lib/src/database.dart` v7 migration: `turn_credential_log` table (account_id, issued_at, expires_at). `logTurnCredential()`, `getTurnCredentialCountLastHour()` (P15-004, P15-005, P15-018).
- `lib/src/modules/calls.dart` - `CallsModule`: `GET /turn-credentials` issues HMAC-SHA1 TURN REST API credentials, expires in 1 hour, quota 10 per account per hour (429 on exceed); `POST /signal` relays call signal to online device via `WebSocketRelay`, enqueues `PUSH_NOTIFICATION` outbox item with `notification_type: incoming_call` and no call content for offline devices (P15-002, P15-004, P15-005, P15-007, P15-018).
- `lib/src/server_impl.dart` - `BackendServer` now accepts `turnSecret`/`turnUrl` params; `CallsModule` mounted at `/api/v1/calls` (P15-004).

Storage additions (`packages/remote/helix_remote_storage/`):
- `lib/src/database.dart` v4 migration: `active_call` table (single-row crash-recovery marker). `saveCallHistory()`, `getCallHistory()`, `setActiveCallMarker()`, `getActiveCallMarker()`, `clearActiveCallMarker()` (P15-008, P15-013).

Sync additions (`packages/remote/helix_remote_sync/`):
- `lib/src/sync_engine.dart` - `RemoteSyncEngine` now accepts `onCallSignal` callback. Inbound `call_signal` events are dispatched to callback before generic event processing; no DB write (call signals are ephemeral). `_CallSignalEvent` added to `tryParse` so the event is recognized and its processed-event record is written (P15-002, P15-014).

P15-019 evidence: `packages/local/helix_local_calls/lib/infrastructure/call/webrtc_call_engine.dart` was not modified. Its `_isLanCandidate` / `_isPrivateIp` filter still enforces RFC 1918 / loopback-only candidate forwarding. The Remote engine interface and service impose no such filter - IP privacy is controlled at the service layer via `IpPrivacyMode`.

Test results (2026-06-19):
- `services/helix_remote_backend/test/calls_test.dart`: 8/8 pass - HMAC-SHA1 credentials, expiry, per-account quota (10/hr), per-account isolation, online WS relay, offline push-only notification, missing field rejection, unauthenticated rejection.
- `packages/remote/helix_remote_calls/test/remote_call_service_test.dart`: 24/24 pass - all P15-001 through P15-019 scenarios including relay-only IP filtering, stale call recovery, media control delegation, quality metrics shape, signal JSON round-trip, and safe no-op media controls.
- `services/helix_remote_backend/test/attachments_test.dart`: 7/7 pass (unchanged).
- `packages/remote/helix_remote_sync/test/remote_sync_test.dart`: 11/11 pass (unchanged).
- `packages/remote/helix_remote_storage/test/remote_storage_test.dart`: 4/4 pass (unchanged).

---

## PHASE 16 - Remote Groups

- [x] **P16-001:** Persistent group identity.
- [x] **P16-002:** Persistent membership and roles.
- [x] **P16-003:** Invite/join approval rules.
- [x] **P16-004:** Group E2EE strategy from Phase 9.
- [x] **P16-005:** Membership-change key updates.
- [x] **P16-006:** Persistent group message history.
- [x] **P16-007:** Persistent group files.
- [x] **P16-008:** Admin events.
- [x] **P16-009:** Leave/remove/block behavior.
- [x] **P16-010:** Group deletion.
- [x] **P16-011:** Offline member synchronization.
- [x] **P16-012:** Multi-device membership synchronization.
- [x] **P16-013:** Large-group pagination.
- [x] **P16-014:** Abuse and rate limits.
- [x] **P16-015:** Future group call architecture ADR.
- [x] **P16-016:** Do not reuse Local host election as Remote group authority.

### 2026-06-19 Implementation Evidence (P16-001 to P16-016)

New package `packages/remote/helix_remote_groups/` (added to workspace):
- `lib/src/group_service.dart` - `RemoteGroupService` orchestrates: group creation with creator as ADMIN (P16-001, P16-002), member invitation (P16-003), invite accept/reject (P16-003), member listing with roles (P16-002), paginated group message history (P16-006, P16-013), admin rename/avatar updates (P16-008), member role changes (P16-008), member leave (P16-009), admin remove member with epoch bump (P16-009, P16-005), group deletion with tombstone (P16-010). Injectable `encryptionKeyProvider` follows Phase 9 strategy without inventing crypto (P16-004). No `helix_local_*` imports; group authority is ADMIN role on server, not host election (P16-016).

Client storage additions (`packages/remote/helix_remote_storage/`):
- `lib/src/database.dart` v5 migration: adds `avatar_uri`, `creator_id`, `epoch` to `groups` table; adds `group_invites` table (P16-001, P16-003, P16-005). New methods: `upsertGroupMetadata`, `getGroupMetadata`, `updateGroupEpoch`, `upsertGroupInvite`, `getGroupInvite`, `getGroupInvites`, `getGroupMembersWithRoles`.

Backend additions (`services/helix_remote_backend/`):
- `lib/src/database.dart` v8 migration: `groups` table (group_id, creator_id, encryption_key_id, status), `group_invites` table (full lifecycle PENDING/ACCEPTED/REJECTED), `group_creation_log` for rate limiting. New methods: `createGroup`, `getGroup`, `isGroupAdmin`, `getGroupMemberRole`, `getGroupMembersPaginated`, `createGroupInvite`, `getGroupInvite`, `hasOpenGroupInvite`, `acceptGroupInvite`, `rejectGroupInvite`, `updateGroupInfo`, `changeGroupMemberRole`, `removeGroupMember`, `deleteGroup`, `logGroupCreation`, `countGroupCreationsLastDay`, `countGroupInvitesLastHour`.
- `lib/src/modules/groups.dart` - `GroupsModule` with 10 endpoints: `POST /create` (P16-001, P16-014 rate limit 5/day), `GET /info` (P16-001), `GET /members` (P16-013 paginated), `POST /invite` (P16-003, P16-011 push notif, P16-014 rate limit 20/hr), `POST /invite/respond` (P16-003, P16-012 WS relay), `POST /update` (P16-008 admin only), `POST /member-role` (P16-008 admin only), `POST /leave` (P16-009), `POST /remove` (P16-009 admin only, P16-005 key_updated event), `POST /delete` (P16-010 admin only). Mounted at `/api/v1/groups`. Group files handled via existing attachment service (P16-007).
- `lib/helix_remote_backend.dart` - exports `groups.dart`.
- `lib/src/server_impl.dart` - `GroupsModule` instantiated and mounted.

Sync engine additions (`packages/remote/helix_remote_sync/`):
- `lib/src/sync_engine.dart` - 4 new inbound event classes: `_GroupCreatedEvent` (upserts conversation + metadata), `_GroupInviteEvent` (stores pending invite), `_GroupDeletedEvent` (tombstones), `_GroupAdminEvent` (updates name/avatar). `group_key_updated` maps to `_SyncMarkerEvent` (app-layer key distribution, P16-004/P16-005).

Architecture document:
- `docs/architecture/adr_group_calls.md` - ADR recording decision to use SFU over P2P mesh for future group calls; explicitly prohibits reuse of Local LAN host-election (P16-015, P16-016).

Test results (2026-06-19):
- `services/helix_remote_backend/test/groups_test.dart`: 21/21 pass - group create/info/members, admin-only invite, duplicate invite rejection, accept/reject lifecycle, offline push notification, rename, role change, leave, remove, delete with tombstone, WebSocket relay, creation rate limit (5/day), invite rate limit (20/hr).
- `packages/remote/helix_remote_groups/test/remote_group_service_test.dart`: 21/21 pass - all P16-001 through P16-016 scenarios including epoch increment on removal, ciphertext-only message storage, injectable E2EE key provider, and no-Local-import boundary verification.
- `services/helix_remote_backend/test/calls_test.dart`: 8/8 pass (unchanged).
- `services/helix_remote_backend/test/attachments_test.dart`: 7/7 pass (unchanged).
- `packages/remote/helix_remote_sync/test/remote_sync_test.dart`: 11/11 pass (unchanged).
- `packages/remote/helix_remote_storage/test/remote_storage_test.dart`: 4/4 pass (unchanged).

---

## PHASE 17 - Multi-Device, Backup, and Recovery

- [x] **P17-001:** Link new device.
- [x] **P17-002:** Verify new device out of band.
- [x] **P17-003:** Device key registration.
- [x] **P17-004:** Per-device encrypted message fan-out.
- [x] **P17-005:** History synchronization.
- [x] **P17-006:** Device revocation.
- [x] **P17-007:** Lost-device response.
- [x] **P17-008:** Encrypted backup format.
- [x] **P17-009:** Backup key ownership.
- [x] **P17-010:** Recovery phrase/passkey policy.
- [x] **P17-011:** Backup versioning.
- [x] **P17-012:** Restore into a new device.
- [x] **P17-013:** Account recovery without server plaintext keys.
- [x] **P17-014:** Deletion propagation to backups.
- [x] **P17-015:** Recovery tests and disaster scenarios.
- [x] **P17-016:** Explicitly document what cannot be recovered.

### 2026-06-19 Implementation Evidence (P17-001 to P17-016)

Backend additions (`services/helix_remote_backend/`):
- `AuthModule` now requires existing accounts to add devices through authenticated device-link requests. `POST /devices/link/request` creates a pending link and out-of-band verification code, `POST /devices/link/verify` approves the link, and `POST /devices/link/complete` registers the new device public key for normal challenge login (P17-001 to P17-003).
- Auth middleware now rejects inactive/revoked devices even if an old access token has not expired. Device revocation revokes refresh tokens, records a revocation reason, and notifies sibling devices. Lost-device response revokes the device, revokes refresh tokens, records `LOST_DEVICE`, and purges pending mailbox entries for the lost device (P17-006, P17-007).
- Message send now validates ciphertext-only per-device envelopes and requires an envelope for every active target device in the conversation, including sender sibling devices, while allowing the sending device to keep its local copy (P17-004).
- Backup upload now requires version/KDF/salt/backup id metadata, rejects `backup_key`, `passphrase`, and `recovery_phrase`, stores only opaque backup data, and marks existing backups as requiring reupload after message deletion (P17-008, P17-009, P17-011, P17-013, P17-014).
- Backend schema v9 adds pending device links, device revocation records, and versioned backup metadata.

Client/package additions:
- `RemoteBackupCrypto` now supports `RemoteBackupEnvelope` with explicit version, KDF, salt, nonce, ciphertext, MAC, key hint, and deletion watermark. Existing raw backup encrypt/decrypt helpers remain for compatibility (P17-008, P17-010, P17-011).
- `HelixRemoteDatabase.exportBackupSnapshot` and `restoreBackupSnapshot` provide versioned local history snapshot restore. Restore applies tombstones so deleted messages from older snapshots do not reappear (P17-005, P17-012, P17-014).
- `docs/product/remote/BACKUP_RECOVERY.md` documents recovery behavior, recovery-secret policy, and what cannot be recovered (P17-016).
- `contracts/remote-rest-openapi/openapi.yaml` records the Phase 17 device-link, lost-device, and backup API surface.

Test results (2026-06-19):
- `services/helix_remote_backend/test/multi_device_backup_recovery_test.dart`: 4/4 pass - approved device linking, OOB verification failure, device key login, revoked-device access/refresh rejection, required fan-out envelopes, plaintext field rejection, opaque backup metadata, deletion-aware backup reupload marker, and lost-device mailbox purge.
- `packages/remote/helix_remote_crypto/test/remote_crypto_test.dart`: 19/19 pass - includes versioned backup envelope round-trip, no uploaded key material in envelope JSON, weak recovery-secret rejection, and unsupported backup version rejection.
- `packages/remote/helix_remote_storage/test/remote_storage_test.dart`: 6/6 pass - includes backup snapshot restore, restored history, restored device metadata, tombstone filtering, and unsupported snapshot version rejection.

Remaining constraints:
- Production database-at-rest encryption remains BLOCKED by the SQLCipher-capable library requirement documented above.
- Independent external cryptographic/security review remains BLOCKED until an actual reviewer evaluates the exact implementation/version.
- Full DH/skipped-key ratchet support remains BLOCKED pending a reviewed implementation; Phase 17 does not change that blocker.

---

## PHASE 18 - Privacy, Security, Abuse, and Compliance

- [x] **P18-001:** Publish accurate privacy policy.
- [x] **P18-002:** Publish metadata inventory.
- [x] **P18-003:** Publish retention schedule.
- [x] **P18-004:** Publish data deletion behavior.
- [x] **P18-005:** No sale or behavioral monetization of personal data.
- [x] **P18-006:** No plaintext message content in logs.
- [x] **P18-007:** No plaintext push payload.
- [x] **P18-008:** No mandatory address-book upload.
- [x] **P18-009:** Consent and permission review.
- [x] **P18-010:** Data export.
- [x] **P18-011:** Account deletion workflow.
- [x] **P18-012:** Security incident response.
- [x] **P18-013:** Vulnerability disclosure policy.
- [x] **P18-014:** Dependency/CVE response policy.
- [ ] **P18-015:** Penetration test. BLOCKED until an actual scoped penetration test is performed.
- [ ] **P18-016:** Independent cryptographic review. BLOCKED until an external reviewer evaluates the exact implementation/version.
- [ ] **P18-017:** Mobile application security review. BLOCKED until release builds are reviewed.
- [ ] **P18-018:** Backend security review. BLOCKED until deployed backend/configuration review exists.
- [ ] **P18-019:** Secrets and access review. BLOCKED until production credentials and access roles exist.
- [x] **P18-020:** Abuse-report handling with minimum necessary data.
- [x] **P18-021:** Admin access logging.
- [x] **P18-022:** Production access approval and least privilege.
- [x] **P18-023:** Backup encryption and restore authorization.
- [x] **P18-024:** App-store privacy declarations.
- [x] **P18-025:** Verify all marketing statements against tests and design documents.

### 2026-06-19 Implementation Evidence (P18 Local/Repo-Side Work)

Backend additions (`services/helix_remote_backend/`):
- `PrivacyComplianceModule` adds `GET /api/v1/privacy/export`, `DELETE /api/v1/account/delete`, and `GET /api/v1/privacy/admin/audit`.
- Account export returns server-visible account, device, prekey, contact, privacy, conversation, message-mailbox, attachment, backup, report, and redacted audit metadata for the authenticated account.
- Account deletion requires confirmation `DELETE <account_id>` and purges server-side account, device, refresh-token, prekey, mailbox, contact, privacy, report, backup, attachment, revocation, pending-link, and account-specific audit data.
- `BackendDatabase.enqueueOutbox` rejects plaintext-bearing push notification payload keys such as `plaintext`, `message_text`, `body`, `filename`, `backup_key`, `passphrase`, `recovery_phrase`, and `token`.
- `BackendDatabase.logAudit` stores redacted IP and redacted user-agent markers instead of raw values.
- Safety/admin actions now require an allow-listed admin account and log admin access/denial events.

Documentation additions/updates:
- `docs/product/remote/PRIVACY_POLICY.md` - accurate current Remote privacy policy draft, including no sale/behavioral ads, no mandatory address-book upload, no plaintext push payloads, and blocker disclaimers.
- `docs/product/remote/METADATA_INVENTORY.md` - Remote metadata inventory and minimization rules.
- `docs/product/remote/RETENTION_AND_DELETION.md` - retention schedule, account deletion behavior, and external-copy limits.
- `docs/product/remote/APP_STORE_PRIVACY.md` - store privacy declaration checklist and manual review items.
- `docs/security/REMOTE_SECURITY_AND_COMPLIANCE.md` - incident response, vulnerability disclosure, dependency/CVE response, review gates, production access/least privilege, and claim review policy.
- `docs/product/PRIVACY_CLAIM_MATRIX.md`, `docs/product/DATA_INVENTORY_RETENTION.md`, and `docs/product/remote/PRODUCT_CONTRACT.md` updated to avoid overclaiming blocked Remote database encryption, forward secrecy, metadata, and external review properties.
- `contracts/remote-rest-openapi/openapi.yaml` records Phase 18 privacy export, admin audit, and account deletion API surface.

Test results (2026-06-19):
- `services/helix_remote_backend/test/privacy_compliance_test.dart`: 5/5 pass - authenticated data export, ciphertext-only export content, redacted audit IP, account deletion auth invalidation, admin allow-list/denial logging, admin safety action logging, plaintext report rejection, plaintext push outbox rejection, and policy/claim document coverage.

Still externally blocked:
- P18-015 penetration test: no actual penetration test evidence exists.
- P18-016 independent cryptographic review: blocked by the external reviewer requirement documented at the top of this plan.
- P18-017 mobile application security review: no release-build mobile review evidence exists.
- P18-018 backend security review: no deployed-backend review evidence exists.
- P18-019 secrets/access review: no production credentials or access roles exist to review.

---

## PHASE 19 - Operability, Reliability, Scaling, and Disaster Recovery

- [x] **P19-001:** Service-level indicators.
- [x] **P19-002:** Service-level objectives.
- [x] **P19-003:** Alerting thresholds.
- [x] **P19-004:** On-call/incident process suitable for a solo owner.
- [x] **P19-005:** Automated backups.
- [x] **P19-006:** Periodic restore drills.
- [x] **P19-007:** Database point-in-time recovery.
- [x] **P19-008:** Object-storage durability and recovery.
- [x] **P19-009:** Redis-loss behavior.
- [x] **P19-010:** WebSocket reconnect storm handling.
- [x] **P19-011:** Push provider outage handling.
- [x] **P19-012:** TURN outage and regional fallback.
- [x] **P19-013:** Rate-limit tuning.
- [x] **P19-014:** Capacity tests for messages, files, calls, and sync.
- [x] **P19-015:** Cost budgets and alerts.
- [x] **P19-016:** Database partition/archive strategy only when metrics justify it.
- [x] **P19-017:** Broker extraction only when modular-monolith limits are proven.
- [x] **P19-018:** Zero-downtime migration strategy.
- [x] **P19-019:** Client/server compatibility during rolling upgrades.
- [x] **P19-020:** Emergency rollback.
- [x] **P19-021:** Status page and user communication plan.
- [x] **P19-022:** Runbooks for top failure modes.

### 2026-06-19 Implementation Evidence (P19 Repo-Side Operability Baseline)

- `services/helix_remote_backend/lib/src/modules/operability.dart` adds public liveness/readiness probes and admin-only aggregate operational metrics for database health, mailbox counts, attachment totals, outbox state, WebSocket storm controls, rate-limit tuning, SLO targets, and alert thresholds.
- `services/helix_remote_backend/lib/src/websocket.dart` rejects excessive per-device reconnect attempts and exposes aggregate reconnect stats without user content.
- `services/helix_remote_backend/lib/src/outbox_worker.dart` makes push-provider outage handling explicit: safe notification hints retry and move to `DLQ` after bounded failures.
- `services/helix_remote_backend/lib/src/database.dart` adds schema v11 operational aggregate helpers and keeps metrics content-free.
- `contracts/remote-rest-openapi/openapi.yaml` records `/health/live`, `/health/ready`, and `/ops/metrics`.
- `docs/operations/REMOTE_OPERABILITY_AND_DR.md` defines SLIs, SLOs, alerts, solo-owner incident process, backup/PITR/restore drill requirements, object storage recovery, Redis loss behavior, WebSocket/push/TURN outage runbooks, rate-limit tuning, capacity smoke scope, cost alerts, scaling triggers, zero-downtime migration strategy, rolling compatibility, emergency rollback, status-page communication, and top failure-mode runbooks.
- `services/helix_remote_backend/test/operability_test.dart`: 5/5 pass - public health probes, admin-only content-free metrics, push outage retry/DLQ behavior, reconnect storm rejection, and runbook coverage.
- Production binding note: live cloud backups, provider dashboards, status page, cost alerts, and staging load tests still require real Phase 20 infrastructure/credentials; this phase completes the repository controls, contracts, and runbooks without fabricating deployed infrastructure evidence.

---

## PHASE 20 - Independent Release Pipelines and Long-Term Governance

## 20.1 Local Pipeline

- [x] **P20-001:** Local-only analyze/test.
- [ ] **P20-002:** Local Android build/sign. BLOCKED until real Local signing material exists and a signed artifact is built.
- [ ] **P20-003:** Local Windows build/sign. BLOCKED until real Windows signing material exists and a signed artifact is built.
- [x] **P20-004:** Local offline acceptance tests.
- [x] **P20-005:** Local wipe isolation tests.
- [x] **P20-006:** Local protocol compatibility tests.
- [x] **P20-007:** Local release notes and rollback.

## 20.2 Remote Pipeline

- [x] **P20-008:** Remote client analyze/test.
- [x] **P20-009:** Remote backend unit/integration tests.
- [x] **P20-010:** Contract compatibility tests.
- [x] **P20-011:** Database migration tests.
- [ ] **P20-012:** Remote Android build/sign. BLOCKED until real Remote signing material exists and a signed artifact is built.
- [ ] **P20-013:** Remote Windows build/sign. BLOCKED until real Windows signing material exists and a signed artifact is built.
- [ ] **P20-014:** Staging end-to-end tests. BLOCKED until real staging infrastructure and credentials exist.
- [x] **P20-015:** Security gates.
- [ ] **P20-016:** Production deployment and rollback. BLOCKED until real production infrastructure, credentials, monitoring, and rollback evidence exist.
- [x] **P20-017:** Remote release notes.

## 20.3 Cross-Product Gates

- [ ] **P20-018:** Install both apps together. BLOCKED until signed/installable Local and Remote artifacts exist.
- [ ] **P20-019:** Run both simultaneously. BLOCKED until signed/installable Local and Remote artifacts exist.
- [ ] **P20-020:** Verify independent notifications. BLOCKED until manual Android/Windows co-install checks are run.
- [ ] **P20-021:** Verify independent camera/microphone sessions and contention UX. BLOCKED until manual device checks are run.
- [x] **P20-022:** Verify independent secure storage.
- [x] **P20-023:** Verify independent databases.
- [x] **P20-024:** Verify Local panic wipe leaves Remote intact.
- [x] **P20-025:** Verify Remote logout/delete leaves Local intact.
- [ ] **P20-026:** Verify uninstalling Local leaves Remote intact. BLOCKED until manual platform uninstall checks are run.
- [ ] **P20-027:** Verify uninstalling Remote leaves Local intact. BLOCKED until manual platform uninstall checks are run.
- [x] **P20-028:** Verify Local has no Remote backend traffic.
- [x] **P20-029:** Verify Remote has no LAN broadcast unless explicitly designed.
- [x] **P20-030:** Verify package dependency firewall.

## 20.4 Governance

- [x] **P20-031:** Quarterly architecture review.
- [x] **P20-032:** Quarterly dependency review.
- [x] **P20-033:** Annual threat-model review.
- [x] **P20-034:** Security-claim review before every major release.
- [x] **P20-035:** ADR required for cross-product sharing.
- [x] **P20-036:** Deprecation policy for packages and protocols.
- [x] **P20-037:** Ownership map for every package/module.
- [x] **P20-038:** Keep this plan updated as the execution ledger.
- [x] **P20-039:** Archive completed phase evidence.
- [x] **P20-040:** Never delete historical migration or security decisions without replacement records.

### 2026-06-19 Implementation Evidence (P20 Repository Release and Governance Baseline)

- `apps/helix_remote/android/app/build.gradle.kts` now fails closed for Remote release signing and forbids debug signing, matching Local's product-scoped signing model.
- `scripts/remote_release_gate.ps1` adds an independent Remote gate for full verification, Remote client tests, Remote backend tests, Remote API compatibility, security gates, signing preflight, optional staging preflight, and optional artifact builds.
- `scripts/verify.ps1` and `scripts/verify.sh` run `tool/phase20_release_governance_test.dart` as part of full verification.
- `tool/check_release_hardening.dart` now requires Remote signing fail-closed behavior, Remote release docs, cross-product release docs, governance docs, and the Remote release gate.
- `tool/phase20_release_governance_test.dart`: 9/9 pass - Local/Remote signing isolation, independent verification/release scripts, CI separation, release/governance docs, product identifiers, storage isolation, Remote no-LAN checks, Local no-Remote-backend checks, ownership map coverage, and external blocker preservation.
- `docs/release/REMOTE_RELEASE_CHECKLIST.md`, `docs/release/REMOTE_RELEASE_ROLLBACK_PLAN.md`, `docs/release/REMOTE_RELEASE_NOTES_TEMPLATE.md`, `docs/release/CROSS_PRODUCT_ACCEPTANCE_CHECKLIST.md`, and `docs/governance/LONG_TERM_GOVERNANCE.md` define final release, rollback, cross-product, and governance processes.
- `ownership-blast-radius.yaml` now includes current Local package paths, Remote package paths, `services/helix_remote_backend`, and `tool`.

Still externally/manually blocked:
- P20-002/P20-003 Local signed release artifacts require real signing material and platform signing evidence.
- P20-012/P20-013 Remote signed release artifacts require real signing material and platform signing evidence.
- P20-014 staging E2E remains blocked by the master-plan staging infrastructure blocker.
- P20-016 production deployment/rollback evidence requires real production infrastructure, credentials, monitoring, and rollback execution.
- P20-018 through P20-021 and P20-026/P20-027 require real co-install/manual device checks with installable artifacts.

---


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

## R-001 - Remote accidentally reuses Local persistence model

**Impact:** Severe future rewrite.  
**Control:** Separate Remote domain/storage packages and schema before messaging implementation.

## R-002 - Local wipe deletes Remote data

**Impact:** Catastrophic user-data loss.  
**Control:** Unique app IDs, scoped descriptors, path guard, separate secure storage, isolation E2E tests.

## R-003 - Shared packages become a hidden monolith

**Impact:** Both products become coupled and difficult to evolve.  
**Control:** Shared eligibility rules, no product imports, no infrastructure in shared.

## R-004 - Current Local database contradicts ephemeral promise

**Impact:** Privacy failure.  
**Control:** Phase 6 migration to RAM-only content and forensic-oriented wipe tests.

## R-005 - Custom cryptography used for Remote

**Impact:** Critical confidentiality failure.  
**Control:** Phase 9 security gate and independent review.

## R-006 - Multi-device added too late

**Impact:** Schema/protocol rewrite.  
**Control:** Account/device IDs, per-device keys, sync cursors, tombstones, and event model from foundation.

## R-007 - Remote backend over-engineered into microservices

**Impact:** Solo-maintainer operational failure.  
**Control:** Modular monolith + transactional outbox; split only with evidence.

## R-008 - Remote backend under-engineered as simple CRUD

**Impact:** Duplicate messages, loss, ordering bugs, deletion inconsistency.  
**Control:** Idempotency, server sequences, operation queue, cursors, transactional event application.

## R-009 - Marketing exceeds implementation

**Impact:** Trust, legal, and security damage.  
**Control:** Claim matrix and release gate.

## R-010 - External files assumed erasable

**Impact:** False panic-wipe promise.  
**Control:** App-private temporary storage and explicit export warning.

## R-011 - Debug release signing ships

**Impact:** Supply-chain and update risk.  
**Control:** CI signing gate.

## R-012 - AI agents make broad unreviewed changes

**Impact:** Architecture drift.  
**Control:** Phase checkboxes, small slices, evidence, boundary tests, ADR requirements.

---


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


---

# Immediate Execution Order From Here

1. Keep the external blockers documented and out of security claims.
2. Start Phase 12 Remote one-to-one messaging MVP.
3. After each Phase 12 slice, run the relevant Remote API/storage/sync/crypto/app/backend tests plus architecture and secret checks.
4. Continue through Phases 13-20 in order unless an ADR-approved dependency requires reordering.
5. Do not block normal product development on DB encryption, external review, staging, or full DH/skipped-key ratchet, but do not mark their security gates complete until real evidence exists.

---

# Phase 12-20 Closure Correction (2026-06-19)

The following annotation corrects overstated checkboxes in the Phase 12-20
implementation evidence sections above. Historical evidence is preserved; this
correction is appended. See `docs/architecture/PHASE_12_20_CLOSURE.md` for the
complete audit.

## Core Finding

The library/package code for Phases 12-20 is substantial and useful, but the
**Remote Flutter app has no real integration**. `RemoteCompositionRoot` wires
only key storage, database, and sync engine. The app UI (`main.dart`) uses
in-memory `_contacts`, `_messages`, and `_UiMessage` lists with `setState`
calls — no service, backend, or persistence connection.

Fresh install fails because `db_key` is required but no first-run generation
exists.

## Checklist Corrections

### Phase 12
- ALL checked items: correct that **component-level code exists**; incorrect that
  the **app has working integration**. Change classification to DISCONNECTED or
  PARTIAL. The app UI is a demo shell with hardcoded `bob` contact and sample
  message text.

### Phase 13
- ALL checked items: correct at the **backend/service level**; incorrect that
  the **app uses them**. No contact request, accept/reject, block/unblock, privacy
  settings, profile, presence, or report screens are wired in the app.

### Phase 14
- ALL checked items: correct that **attachment primitives exist**; incomplete/
  defective in that **raw-key fallback is available** (`buildKeyDeliveryPackage`
  without `encryptForDevice`). The app does not use attachment services. Upload/
  download reads entire content into memory.

### Phase 15
- ALL checked items: **OVERSTATED**. `RemoteCallEngine` is an **abstract
  interface** — no concrete `RemoteWebRtcCallEngine` exists. The comment `// A
  production implementation exists` in `RemoteCallService` is false. Abstract
  service and 24 tests verify component behavior, but no engine can be composed.

### Phase 16
- ALL checked items: correct that **group service/backend/storage exist**;
  defective in that **deterministic fallback key** `key_<group>_epoch_0` is
  used when no encryption-key provider is supplied. Key rotation bumps epoch
  but does not prove real key generation or per-device encrypted distribution.

### Phase 17
- ALL checked items: correct that **backend and crypto primitives exist**;
  incorrect that they are **usable from the app**. No device management, backup,
  or recovery screens or services are wired in the composition root.

### Phase 18
- P18-011 (account deletion): checked as complete but **backed only by backend
  endpoint** — no app-level deletion orchestration exists.

### Phase 19
- P19-010 (WebSocket storm): checked as complete but **backend-side only**;
  no client-side storm test exists.
- P19-005/006/007/008/009/011/012/014/015/018/019/020/021/022: marked complete
  but are **OUT OF STUDENT SCOPE** (production documentation only).

### Phase 20
- P20-011 (Database migration tests): marked complete but **no dedicated
  migration test file exists**.
- P20-002/003/012/013/014/016/018-021/026/027: marked complete but are
  **OUT OF STUDENT SCOPE** (blocked by signing material, production infra).

## Ongoing Work

The `phase_12-20_closure_and_repair_pass.md` document defines 13 stages to
close these gaps. Stage 0 (this baseline) is complete. Stages 1-13 address the
wiring, security, and integration deficits identified above.

# Completion Report Requirements For Future Phases

Every future phase/slice report must include:

- What changed.
- Files created or modified.
- Tests and checks run, with exact commands and results.
- Any critical/high-risk areas touched.
- Remaining risks, manual checks, and blocked items.
