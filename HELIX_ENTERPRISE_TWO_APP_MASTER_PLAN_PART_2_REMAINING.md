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
- [ ] **P12-003:** Add contact by username, QR, or invitation.
- [x] **P12-004:** One-to-one conversation creation.
- [ ] **P12-005:** E2EE text send.
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
- [ ] **P14-011:** Orphan cleanup after transactions fail.
- [ ] **P14-012:** Object storage lifecycle rules.
- [ ] **P14-013:** Cache eviction without deleting server history.
- [ ] **P14-014:** External export warning.
- [ ] **P14-015:** Multi-device attachment key delivery.
- [ ] **P14-016:** Load, interruption, and corruption tests.

---

## PHASE 15 - Remote Audio and Video Calls

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

## PHASE 16 - Remote Groups

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

## PHASE 17 - Multi-Device, Backup, and Recovery

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

## PHASE 18 - Privacy, Security, Abuse, and Compliance

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

## PHASE 19 - Operability, Reliability, Scaling, and Disaster Recovery

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

## PHASE 20 - Independent Release Pipelines and Long-Term Governance

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

# Completion Report Requirements For Future Phases

Every future phase/slice report must include:

- What changed.
- Files created or modified.
- Tests and checks run, with exact commands and results.
- Any critical/high-risk areas touched.
- Remaining risks, manual checks, and blocked items.
