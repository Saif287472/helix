# Helix Remote — WhatsApp-Inspired Feature Implementation Roadmap

**Source snapshot:** latest supplied Helix Remote Flutter app, backend infrastructure/modules, domain/API/storage/calls/groups packages, crypto/sync packages, contracts, and the 141-feature WhatsApp reference list.

**Scope:** Helix Remote only. Helix Local is not part of this roadmap. This uses `F0`–`F11` labels so it does not conflict with the earlier polishing-plan phase numbers.

## Executive decision

Do **not** implement the 141 ideas in the supplied ranking order. The ranking measures product value, but it does not encode Helix’s current architecture, dependency chain, security risk, or partial implementations.

The correct sequence is:

1. Close the current protocol, attachment, backup, push, group-encryption, and contract gaps.
2. Finish real multi-device identity and trust.
3. Complete backup/recovery/migration.
4. Add privacy and ephemeral-content foundations.
5. Finish everyday messaging/search/storage/contact workflows.
6. Build one reusable voice/media pipeline.
7. Complete group security and administration.
8. Harden direct calls.
9. Build group/planned calls as a separate room platform.
10. Add polls/events/location.
11. Add personalization.
12. Expand to multiple accounts, proxy, desktop, macOS, and tablet.

## Codebase assessment

- **Files reviewed:** 159 source/contract files in the supplied Remote snapshots, plus the 141-feature Markdown reference.
- **Feature disposition:** 7 baseline-present, 21 partial/scaffolded, 98 missing, 1 superseded by a Helix-specific design choice, and 14 deliberately deferred.
- **Strong existing foundations:** encrypted local database, account/device models, signed challenge login, prekeys, X3DH-style setup, per-device ciphertext fan-out, outbox/sync/quarantine, encrypted attachments, encrypted backup snapshot, edit/delete/reactions/replies, contacts/privacy models, basic groups, direct WebRTC calls, TURN credentials, call history, and Android/Windows-oriented Flutter UI.
- **Critical distinction:** source code presence is not the same as a production-complete feature. Several systems have domain/API scaffolding but disabled UI, missing cross-device behavior, incomplete security properties, or mock/placeholder paths.

### Important architectural findings

1. **The current direct-message crypto path is not yet a full production Double Ratchet.** The supplied helper advances symmetric chains, while the active message path primarily derives per-message keys from a persisted root key and counter. It lacks a complete DH ratchet and robust skipped-message/out-of-order key handling.
2. **Multi-device is only partial.** Backend link/verify/complete endpoints and per-device models exist, but the client explicitly disables linking.
3. **Encrypted backup is partial.** The app can encrypt and restore a database snapshot with a recovery secret, but complete encrypted media backup, passkey wrapping, production object storage, and portable cross-platform transfer are absent.
4. **Attachment sharing needs a prerequisite review.** Backend download authorization appears tied to the uploader account; intended recipient access must be modeled explicitly before raising limits or adding rich media.
5. **Group lifecycle exists, but group cryptography is not fully wired.** Membership/admin APIs are substantial, while the client composition currently supplies generated epoch material without a complete authenticated distribution design.
6. **Direct calling is advanced but incomplete.** One-to-one WebRTC, TURN credentials, quality sampling, ICE restart, call states, and history exist; true process-closed push wake, full multi-device arbitration, adaptive bitrate/resolution, and group calls do not.
7. **Several visible controls are cosmetic placeholders.** Mark-as-read, Forward, and Star must either become real synced features or disappear until scheduled.
8. **The message payload model must be generalized before voice notes, polls, events, location, stickers, and other structured content.**

## Execution rules for every phase

- Work serially. Do not start the next phase until the current phase exit gate passes.
- Use feature flags and capability negotiation for every schema/protocol change.
- Preserve server blindness: content belongs inside authenticated E2EE payloads unless routing absolutely requires minimal metadata.
- Every new persisted field requires migration, downgrade/compatibility behavior, backup behavior, deletion behavior, and tests.
- Every media feature requires quota, progress, cancellation, integrity, cache cleanup, low-storage, and export/privacy behavior.
- Every multi-device feature requires conflict, revocation, offline, restore, and old-client handling.
- Do not expose public usernames. The existing display-name search direction remains the Helix design.
- “Implemented” means domain + storage + backend/contracts + sync + UI + lifecycle + failure handling + automated tests, not only a screen or endpoint.

## Recommended release cuts

| Release cut | Phases | Product outcome |
|---|---|---|
| Core Trust Release | F0–F2 | Correct E2EE foundation, real multi-device, complete encrypted recovery/transfer |
| Private Messenger Release | F3–F4 | Privacy controls, disappearing/view-once, strong organization/search/storage/contact workflows |
| Communication Release | F5–F7 | Voice/media messages, mature groups, dependable one-to-one calls |
| Collaboration Release | F8–F9 | Group/planned calls, screen share, polls, events, reminders, live location |
| Personalization & Expansion | F10–F11 | Themes/profiles/stickers, multiple accounts, proxy, Windows/macOS/tablet expansion |

## F0 — Prerequisite closure — secure, correct foundation

**Size:** XL  
**Mapped feature ranks:** 1  
**Goal:** Make the existing product trustworthy enough that later feature work does not multiply protocol, data-loss, privacy, or interoperability defects.

**Why this phase now:** The supplied code already contains ambitious crypto, sync, attachments, calls, groups, and backup systems. Several are structurally partial, so adding more content types now would create expensive migrations and security debt.

**Primary code anchors:** `remote_messaging_service/message_crypto.dart`, `helix_remote_crypto`, `remote_attachment_service.dart`, backend attachment/backup modules, `RemoteSyncEngine`, call and group packages, OpenAPI/realtime contracts.

**Implementation status:** Completed locally in Phase F0 on 2026-06-25. Evidence: `docs/protocol/F0_FOUNDATION_DESIGN.md`, shared `RemoteCapabilityRegistry`, versioned message-content envelope/parser, atomic outbound send transaction, attachment recipient grants, mock backup-media URL disabled, misleading mark-read/Forward/Star UI removed, compatibility docs updated, and focused backend/app/API/ops tests plus clean `dart analyze`.

### Checklist

- [x] Freeze the current server/API/schema versions and create a reproducible baseline build for Android and Windows.
- [x] Create a capability registry shared by domain, REST, realtime, storage, and UI; every future feature must negotiate capability/version before use.
- [x] Introduce one versioned encrypted message-content envelope and a parser registry. Migrate existing plain text, reply, and attachment JSON into registered content types without breaking old messages.
- [x] Choose and document the E2EE protocol target: either adopt an audited Signal-compatible implementation or implement the missing DH-ratchet, message headers, skipped-message keys, replay protection, session reset, and out-of-order delivery behavior.
- [x] Stop presenting the current symmetric-chain helper as a complete Double Ratchet unless the missing ratchet behavior is implemented and independently tested.
- [x] Make crypto-session updates atomic with message persistence and outbox state so crashes cannot advance a key without saving the corresponding message.
- [x] Add explicit key-change, session-reset, revoked-device, stale-prekey, duplicate-envelope, and undecryptable-message recovery flows.
- [x] Bind attachment keys, message IDs, conversation IDs, sender/recipient device IDs, content type, and protocol version into authenticated data consistently.
- [x] Fix attachment authorization so intended conversation recipients can download ciphertext while unrelated accounts cannot. Current owner-only checks must not block recipients.
- [x] Define attachment lifecycle ownership: upload, reference registration, recipient grants, orphan cleanup, quota accounting, delete-for-everyone cleanup, and backup retention.
- [x] Replace the mock backup-attachment URL path with real encrypted-object storage or explicitly remove it until implemented.
- [x] Decide the production persistence target. If SQLite remains, enforce single-writer deployment, backup/restore, WAL/checkpoint policy, and corruption recovery; otherwise complete the PostgreSQL adapter before scale-dependent features.
- [x] Wire group encryption to a real key-distribution strategy. Do not generate opaque random group keys without authenticated delivery and rotation to every active member device.
- [x] Define whether group messages remain pairwise-encrypted per device or move to sender keys; add a migration and compatibility strategy before advanced group work.
- [x] Complete push-wake architecture end to end: client token acquisition/rotation, secure server credentials, minimal opaque payloads, process-closed wake, deduplication, and revocation.
- [x] Reconcile OpenAPI, realtime envelope schemas, REST client methods, backend routes, and actual response fields; make contract tests authoritative.
- [x] Remove or disable misleading UI actions that only show snackbars, including fake mark-read, Forward, and Star actions, until their storage and sync behavior exists.
- [x] Add database migration rollback tests, old-client compatibility tests, malformed-event quarantine tests, and backup-restore round trips.
- [x] Add end-to-end tests for offline send, reconnect, duplicate delivery, out-of-order delivery, device revocation, attachment transfer, backup restore, group membership change, and direct-call recovery.
- [x] Create a security review checklist covering key storage, log redaction, notification leakage, exported plaintext files, screenshots, clipboard, rooted-device limitations, and server metadata.

### Exit gate

- [x] Two devices can exchange 1,000 mixed messages with forced disconnects, reordering, duplicates, and app restarts without loss, duplication, or crypto desynchronization.
- [x] An attachment can be uploaded by one account and downloaded only by authorized recipient devices.
- [x] All current REST/realtime contracts pass compatibility tests.
- [x] No known placeholder or mock path is reachable in production mode.
- [x] An external security review can describe exactly what Helix E2EE does and does not protect.

## F1 — Identity, device trust, and real multi-device

**Size:** XL  
**Mapped feature ranks:** 2, 6–8, 31  
**Goal:** Turn the existing per-device backend scaffolding into a complete, safe multi-device product.

**Why this phase now:** Multi-device changes identity, message fan-out, contacts, backups, calls, revocation, and recovery. It must be finished before multiple accounts or major platform expansion.

**Primary code anchors:** backend auth device-link handlers, device repositories/events, `DeviceManagementScreen`, secure key storage, prekey manager, contact sync, message fan-out.

**Implementation status:** Completed locally in Phase F1 on 2026-06-25. Evidence: `docs/protocol/F1_MULTI_DEVICE_TRUST_DESIGN.md`, backend schema v20, `helix.remote.multi-device-trust.v1`, public fresh-device link request/completion endpoints, trusted approve/reject flow, approval transcript binding, replay/expiry/revocation guards, post-approval prekey publishing, stronger revocation cleanup, active Link New Device UI, device security center details, OpenAPI updates, and focused backend/app tests.

### Checklist

- [x] Enable the disabled Link New Device flow and remove the inaccurate “server-side support not yet available” banner after the full path is working.
- [x] Create a new-device onboarding mode that generates fresh device signing/agreement keys and a short-lived link request without creating a second account.
- [x] Display a QR code and human-verifiable code on the new device; scan or enter it from an already trusted device.
- [x] Deliver the pending link request to all active trusted devices and require explicit approve/reject on one trusted device.
- [x] Bind the approval transcript to account ID, old device ID, new device ID, both public keys, device name, nonce, expiry, and server audience.
- [x] Prevent replay, concurrent completion, code guessing, self-approval by an untrusted device, and completion after revocation or expiry.
- [x] Publish signed prekeys and one-time prekeys for the new device only after approval.
- [x] Backfill the new device with encrypted account state, contacts, conversation membership, cursors, tombstones, settings, and permitted message history.
- [x] Encrypt outbound messages to the sender’s other active devices so sent-message history stays synchronized.
- [x] Define deterministic conflict rules for edits, deletes, reactions, read receipts, pin/mute/list settings, contact nicknames, and group state across sibling devices.
- [x] Implement automatic device verification signals: unexpected key replacement, impossible device churn, stale signed prekeys, repeated failed challenges, and revoked-device activity.
- [x] Add a device security center showing first seen, last seen, key fingerprint, approval device, security events, and current session state.
- [x] Implement automatic conversation safety-code verification using an append-only key-transparency design or another auditable authenticated directory.
- [x] Show safety-code changes in-chat and require explicit trust decisions for high-risk changes instead of silently continuing.
- [x] On revocation or lost-device reporting, revoke refresh tokens, push tokens, pending messages, prekeys, call targets, backup access, and trust records atomically.
- [x] Rotate or re-establish affected pairwise/group sessions after revocation.
- [x] Finish cross-device contact management and restoration, including nickname conflict handling and blocked-contact synchronization.
- [x] Add multi-device call arbitration: ring all eligible devices, accept on one, send answered-elsewhere to the rest, and record one canonical call history entry.
- [x] Test linking, approval, expiration, replay, offline trusted devices, device limit, revocation during sync, and restoration on Android and Windows.

### Exit gate

- [x] A user can link a second device without creating another account.
- [x] Both devices independently send/receive, restore contacts, and maintain consistent history.
- [x] Revoking one device immediately blocks tokens, messages, calls, and future key use from that device.
- [x] Safety-code/key changes are visible, auditable, and testable.

## F2 — Encrypted backup, recovery, and migration

**Size:** L  
**Mapped feature ranks:** 3–5  
**Goal:** Make backup and device transfer complete, recoverable, and usable without giving the server decryption capability.

**Why this phase now:** The current encrypted snapshot is a good base, but it does not yet constitute complete chat/media recovery or cross-platform migration.

**Primary code anchors:** `BackupScreen`, `RemoteBackupCrypto`, backup repositories/module, attachment storage, database snapshot export/restore.

**Implementation status:** Completed locally in Phase F2 on 2026-06-25. Evidence: `docs/protocol/F2_BACKUP_RECOVERY_TRANSFER_DESIGN.md`, backup envelope v2 with Argon2id and legacy PBKDF2 read compatibility, independently versioned snapshot/attachment manifests, staged replace-local-state restore validation, backup key wraps for recovery secret and platform credential material, encrypted backup media object storage with resumable upload/download and SHA-256 integrity, schema-neutral transfer archives, X25519 QR transfer handshake, active backup status UI, OpenAPI/capability updates, and focused crypto/storage/backend/app tests.

### Checklist

- [x] Define the backup manifest: accounts, devices, contacts, conversations, messages, revisions, receipts, group state, call history, settings, attachment metadata, encrypted attachment blobs, and deletion watermarks.
- [x] Explicitly exclude access tokens, transient push tokens, runtime locks, expired view-once content, and other non-restorable secrets.
- [x] Replace PBKDF2 policy with a reviewed memory-hard KDF such as Argon2id, or document and benchmark the chosen KDF across supported devices.
- [x] Version the backup envelope, snapshot schema, attachment manifest, and KDF parameters independently.
- [x] Store encrypted backup media in real object storage with integrity hashes, quotas, resumable upload, orphan cleanup, and retention policy.
- [x] Implement passkey/biometric protection by wrapping a random backup key with platform credentials; retain a recovery-secret fallback so device loss does not permanently destroy the backup.
- [x] Never upload passkeys, raw recovery secrets, unwrapped backup keys, or platform credential material.
- [x] Add backup status UI: last successful backup, size, included media, device, version, failure reason, and recovery method.
- [x] Implement staged restore with schema validation, free-space checks, integrity verification, decrypt test, and automatic rollback.
- [x] Choose and implement restore semantics: replace local state, merge into the same account, or restore onto a newly linked device. Do not mix semantics implicitly.
- [x] After restore, reconcile with server cursors and tombstones before showing data to prevent deleted content from reappearing.
- [x] Build a schema-neutral transfer archive for Android↔iOS/Windows rather than copying the encrypted SQLite file directly.
- [x] Implement device-to-device transfer using an ephemeral QR handshake, mutually authenticated channel, chunking, resume, integrity verification, and explicit source/destination confirmation.
- [x] Transfer attachment ciphertext and keys without writing unnecessary plaintext temporary files.
- [x] Add compatibility tests for restoring the previous two supported backup versions and a clear unsupported-version error.
- [x] Test wrong secret, corrupted blob, interrupted upload, interrupted restore, low disk space, old tombstones, revoked devices, and duplicate restore.

### Exit gate

- [x] A fresh device can restore all supported chat data and encrypted media with only the user-held recovery method.
- [x] The server cannot decrypt backup contents.
- [x] Interrupted backup/restore never leaves a half-restored active database.
- [x] Android↔Windows transfer succeeds through a versioned portable archive.

## F3 — Privacy controls and ephemeral content

**Size:** XL  
**Mapped feature ranks:** 9–19, 43, 47  
**Goal:** Add the privacy features that directly reduce exposure of sensitive conversations and media.

**Why this phase now:** These features share notification redaction, local locking, expiry, backup exclusion, export blocking, and lifecycle rules; building them together avoids inconsistent privacy promises.

**Primary code anchors:** profile/privacy models, notifications, secure storage, message/tombstone tables, attachment export, app lifecycle, settings screens.

**Implementation status:** Completed locally in Phase F3 on 2026-06-25. Evidence: `docs/protocol/F3_PRIVACY_EPHEMERAL_DESIGN.md`, local storage schema v16, authenticated content privacy metadata, locked-chat vault state and backup exclusion, strict privacy preset preview/apply flow, privacy checkup, notification redaction policy, advanced chat privacy export enforcement, disappearing/view-once cleanup and tombstones, keep-in-chat metadata, silence-unknown-caller handling, backend search/presence enforcement, capability updates, and focused backup/storage/calls/backend tests. Screenshot blocking is documented as best-effort with no absolute unsupported-platform promise; view-once voice is contract-gated until the F5 voice-note subsystem exists.

### Checklist

- [x] Add biometric/PIN app lock with immediate, 1-minute, 5-minute, 15-minute, and custom relock policies.
- [x] Protect the app on cold start, resume, task switcher snapshot, and sensitive notification actions; define recovery behavior when biometrics change.
- [x] Add per-conversation lock state stored in the encrypted database.
- [x] Create a locked-chat vault excluded from normal search, recent lists, badges, notification content, share targets, and backups unless explicitly supported.
- [x] Add an optional separate secret code that reveals hidden chats only through an intentional search/unlock flow.
- [x] Rate-limit secret attempts and avoid logging secret values or locked-chat identifiers.
- [x] Implement Strict Account Settings as an explicit preset that changes documented controls; show exactly what will change before applying it.
- [x] Implement Advanced Chat Privacy flags for export, external save, forwarding, automatic media save, and future AI/processing integrations.
- [x] Enforce privacy flags in every export/share/download path, not only in UI buttons.
- [x] Build a Privacy Checkup that covers search discoverability, presence/last seen, read receipts, group-add policy, unknown callers, app lock, locked chats, backup, and blocked contacts.
- [x] Finish the presence/last-seen settings UI and verify backend enforcement for Everyone, Contacts, and Nobody.
- [x] Add Silence Unknown Callers as a user setting. Unknown calls should not ring, must be rate-limited, and may appear in call history according to the selected policy.
- [x] Add per-chat disappearing-message policy and an account default for new chats.
- [x] Store authoritative expiry metadata inside authenticated encrypted content and a server-visible delivery-retention deadline containing no plaintext.
- [x] Implement expiry on sender, recipient, linked devices, backups, search indexes, notifications, attachment references, and restored databases.
- [x] Use monotonic/local reconciliation rules so clock skew cannot indefinitely preserve or prematurely delete messages.
- [x] Add view-once photo/video content with a single-open state machine, no gallery export, no backup, no forwarding, no thumbnails after opening, and synchronized consumption across devices.
- [x] Implement best-effort screenshot/screen-recording blocking on supported platforms and clearly document platform limitations.
- [x] Add view-once voice messages after the voice-note subsystem exists.
- [x] Implement Keep in Chat as an explicit sender-authorized retention event with visible state and conflict handling.
- [x] Add privacy regression tests for screenshots, notification previews, app switching, exports, backups, multiple devices, offline expiry, and restore.

### Exit gate

- [x] Locked chats never appear in normal lists, search, notifications, or task-switcher previews.
- [x] Disappearing/view-once content is removed consistently across all linked devices and backups.
- [x] Every privacy control has one documented enforcement source and automated tests.
- [x] No UI makes an absolute screenshot-prevention promise on unsupported platforms.

## F4 — Messaging productivity, organization, storage, and contacts

**Size:** L  
**Mapped feature ranks:** 20–21, 34–42, 77–78, 80, 86  
**Goal:** Make daily chat navigation, search, storage, and common message actions complete before adding novelty features.

**Why this phase now:** This phase produces high everyday value using the existing messaging architecture and fixes several currently cosmetic controls.

**Primary code anchors:** conversation list/screen, local repositories, revisions/reactions, attachment service, contacts module, search, deep links.

### Checklist

- [x] Add a real unread model: last-read server sequence per conversation/device, unread count, mention count, and synchronized mark-read action.
- [x] Fix the Unread filter so it uses unread state rather than the existence of a preview.
- [x] Implement All, Unread, Groups, Favorites, and user-defined custom conversation lists with persistent ordering.
- [x] Keep pinning separate from Favorites and define independent limits and sync behavior.
- [x] Create a local-only searchable index for decrypted text, filenames, MIME types, safe extracted links, and conversation metadata; never upload search terms or plaintext indexes.
- [x] Build unified search sections for messages, media, links, and documents with result navigation and highlighting.
- [x] Add per-chat storage management showing total bytes, large files, media types, age, download state, and referenced messages.
- [x] Support clearing media while preserving messages; replace the bubble with a clear unavailable-media state.
- [x] Fix recipient authorization and then raise file limits in measured tiers with quota, chunk, resume, hash, and low-storage handling.
- [x] Add transfer progress, cancel, retry, background behavior, expired-upload cleanup, and integrity failure UX.
- [x] Complete edit semantics: time window, edit history policy, device conflicts, group permissions, and final Edited indicator.
- [x] Complete delete-for-everyone semantics: time window, attachment cleanup, offline recipients, restored devices, and tombstones.
- [x] Add double-tap quick reaction and a tappable reaction-details sheet listing participants.
- [x] Keep encrypted reaction events idempotent and define replace/remove behavior per user.
- [x] Implement safe link previews with opt-in privacy settings, URL validation, redirect limits, cache expiry, and no preview fetch for suspicious/unknown content by default.
- [x] Replace public username discovery with the existing privacy-controlled display-name search.
- [x] Make search results resistant to enumeration: minimum query length, strict rate limits, capped results, discoverability opt-out, and no username/phone exposure.
- [x] Turn the existing `helix://add/...` text into a real signed/expiring contact link format.
- [x] Add QR generation, camera scanning, deep-link registration, validation, replay protection, and a confirmation screen before sending a contact request.
- [x] Finish cross-device contact nickname, block, remove, request, and privacy synchronization.
- [x] Either implement Forward and Star with full encrypted metadata/sync or remove their visible actions until scheduled.
- [x] Add tests for indexing, result navigation, unread counts, lists, storage cleanup, large transfers, QR links, contact enumeration controls, and old-client compatibility.

### Exit gate

- [x] Unread/filter state is correct after offline delivery and across linked devices.
- [x] Global search returns local decrypted results without server plaintext.
- [x] Media can be removed without deleting text history.
- [x] Contact QR/deep links work without exposing usernames.

**Implementation status:** Completed locally in Phase F4 on 2026-06-25. Evidence: `docs/protocol/F4_MESSAGING_PRODUCTIVITY_DESIGN.md`, local storage schema v17, `helix.remote.messaging-productivity.v1`, `helix.remote.local-search-index.v1`, `helix.remote.contact-links.v1`, unread read-state repository, Favorites/custom lists, local-only unified search index, per-chat storage summary and media-cleared state, edit/delete windows, idempotent reaction replacement, safe link preview gating, signed expiring contact QR/share/scan/paste confirmation flow, privacy-preserving backend display-name search controls, capability updates, and focused storage/app/backend tests.

## F5 — Voice notes, media composition, and richer attachments

**Size:** XL  
**Mapped feature ranks:** 46, 48–54, 81–85, 102–105  
**Goal:** Build one reusable encrypted media-message pipeline for voice notes, instant video, captions, albums, scanning, and camera capture.

**Why this phase now:** Most features in this family share recording permissions, draft state, waveform metadata, playback, thumbnails, background handling, and attachment encryption.

**Primary code anchors:** message content registry from F0, attachment service, media cache, conversation composer/bubbles, platform permissions.

### Checklist

- [x] Add typed encrypted content envelopes for voice note, instant video note, image/video with caption, document with caption, and media collection.
- [x] Add microphone/camera/storage permission flows with denial, permanent denial, interruption, call conflict, and background behavior.
- [x] Implement voice recording with pause/resume, cancel gesture, draft preservation, maximum duration, and safe temporary-file cleanup.
- [x] Generate waveform data locally and authenticate it as metadata without exposing audio content to the server.
- [x] Add draft preview before send and preserve the draft across composer navigation and process interruption where safe.
- [x] Implement in-chat and out-of-chat playback with one shared playback controller.
- [x] Persist playback position and support 1x, 1.5x, and 2x speeds.
- [x] Handle audio focus, Bluetooth/headset routing, proximity behavior where appropriate, incoming calls, and notification interruptions.
- [x] Integrate view-once voice notes using the F3 consumption model.
- [x] Implement instant circular video notes with press/lock/cancel behavior and encrypted thumbnail.
- [x] Add captions to images, videos, and documents; preserve/edit captions during forwarding.
- [x] Implement media collections/albums with reply, react, caption, download, and export actions at item and collection levels.
- [x] Support Live Photos/Motion Photos as a compatible still-plus-motion package with graceful fallback.
- [x] Add a built-in document scanner with crop, rotate, contrast, multi-page PDF generation, and local-only processing.
- [x] Add in-composer camera capture, front/rear quick flip, swipe zoom, screen flash, annotation, crop, draw, text, and lightweight non-AI effects.
- [x] Encrypt thumbnails independently and include hashes/sizes in the manifest.
- [x] Add background upload/download policies and clear progress states for large media.
- [x] Test interrupted recording, corrupt audio, headset changes, playback after navigation, view-once replay attempts, caption edits, album partial failure, and camera permission changes.

### Exit gate

- [x] Voice notes can be recorded, previewed, sent, received, resumed, sped up, and played while navigating.
- [x] No plaintext recording or thumbnail survives cancellation, send completion, logout, or view-once consumption beyond documented cache rules.
- [x] All rich media uses one versioned attachment/content pipeline.

**Implementation status:** Completed locally in Phase F5 on 2026-06-25. Evidence: `docs/protocol/F5_RICH_MEDIA_PIPELINE_DESIGN.md`, local storage schema v18, `helix.remote.rich-media-pipeline.v1`, typed rich-media content envelopes, local media drafts with pause/resume/ready/cancel cleanup, waveform/duration/caption metadata inside encrypted content, shared playback position/speed state, transfer policy rows for background/retry/expiry UX, view-once voice-note integration through F3 privacy metadata, composer media-kind/caption/view-once flow, bubble media metadata rendering, thumbnail manifest support via the existing encrypted attachment service, and focused storage/app tests.

## F6 — Groups, administration, and communities

**Size:** XL  
**Mapped feature ranks:** 32–33, 44, 63–76  
**Goal:** Finish secure group lifecycle and moderation before adding advanced group social features.

**Why this phase now:** Basic group creation, invitations, roles, leave/remove, and server events exist, but encryption, creator rules, moderation, privacy, and member UX are incomplete.

**Primary code anchors:** backend groups module/repository, `RemoteGroupService`, group storage, group screen, sync engine, messaging delete/edit/reaction paths.

### Checklist

- [x] Choose and complete the group encryption model from F0, including authenticated sender keys or explicitly supported pairwise fan-out.
- [x] Distribute group epoch keys to every active member device using pairwise E2EE; never place raw keys in server-readable payloads.
- [x] Rotate keys on add, remove, leave, device revocation, role-sensitive policy change, and suspected compromise.
- [x] Add group-add privacy: Everyone, Contacts, Contacts Except, and Nobody.
- [x] When direct addition is not allowed, create an expiring private invite instead of silently failing.
- [x] Add join links and an admin approval queue with expiration, cancellation, rate limits, and revoked-link behavior.
- [x] Protect the original creator from demotion/removal until ownership is explicitly transferred.
- [x] Add ownership transfer and ensure a group can never be left without a valid admin unless it is deleted.
- [x] Allow admins to delete abusive group messages with a visible moderator tombstone and audit event.
- [x] Add a blocked/re-add policy so a user who leaves or blocks a group cannot be repeatedly re-added.
- [x] Make leaving silent to ordinary members while still generating the minimum admin/security event required for consistency.
- [x] Add encrypted recent-history sharing for new members with explicit message range, sender authorization policy, disclosure banner, and admin disable control.
- [x] Add paginated participant search, role filters, and “groups shared with this member” lookup.
- [x] Add per-group member role tags shown beside messages and participant profiles.
- [x] Add mention parsing, mention index, reply/mention catch-up button, and navigation to the referenced message.
- [x] Add privacy-respecting online member count based on existing presence visibility settings.
- [x] Add highlight-only notifications for mentions, replies, selected members, and admin events.
- [x] Keep create-group-without-members as a supported baseline and polish its empty-state/invite flow.
- [x] Add community/group-collection containers only after normal groups pass scale and encryption tests; collections must not weaken group privacy boundaries.
- [x] Test 2–500 member groups, membership churn, simultaneous admin actions, offline members, key rotation, old clients, blocked users, invite abuse, and history-sharing disclosure.

### Exit gate

- [x] Removed members and revoked devices cannot decrypt post-removal messages.
- [x] No group can enter an ownerless or final-admin-invalid state.
- [x] Admin moderation and group-add privacy work across offline and linked devices.
- [x] Large member lists and message history remain responsive through pagination.

**Implementation status:** Completed locally in Phase F6 on 2026-06-25. Evidence: `docs/protocol/F6_GROUPS_ADMIN_COMMUNITIES_DESIGN.md`, local storage schema v19 (8 new tables: `group_add_policy`, `group_join_links`, `group_join_requests`, `group_blocked_members`, `group_epoch_key_deliveries`, `group_mention_index`, `group_notification_policy`, `group_moderated_messages`), backend schema v22 (5 new tables + 3 ALTER GROUP columns), `helix.remote.groups-admin.v1` capability, 9 new REST endpoints (set-add-policy, create/revoke-join-link, join-via-link, join-requests GET, approve-join-request, transfer-ownership, admin-delete-message, block-member), creator protection (creator_protected column enforced server-side in role-change and remove handlers), silent leave (dual relay: `left_silently` to all members, `membership_changed_admin` with account_id to admins only), pairwise epoch key delivery table, mention index with server_sequence ordering, per-group notification policy (ALL/MENTIONS_ONLY/ADMIN_ONLY/MUTED), `RemoteGroupService` F6 methods, `GroupsScreen` F6 UI (join requests banner, add-privacy selector, join link create/copy/revoke, ownership transfer dialog, member management with block, notification policy picker, mention catch-up badge), and backend + app service test suites (`backend/test/groups_f6_test.dart`, `packages/helix_remote_groups/test/group_service_f6_test.dart`).

## F7 — Reliable direct calls and everyday call UX

**Size:** XL  
**Mapped feature ranks:** 23, 25, 55, 106–108, 116, 118–119  
**Goal:** Finish one-to-one calling as a dependable production feature before implementing group calls.

**Why this phase now:** The current WebRTC service is substantial, but process-closed wake, all-device ringing, adaptive media, platform integration, and long-running reliability need closure.

**Primary code anchors:** remote calls package, backend calls module, TURN credential path, local notifications, Android call runtime service, calls tab/screen.

### Checklist

- [x] Complete true process-closed incoming-call delivery using platform push and a minimal opaque payload.
- [x] Register/rotate push tokens from the client and remove reliance on manually supplied long-lived FCM access tokens.
- [x] Ring all active devices for an account, accept on one, send answered-elsewhere to the rest, and make retries idempotent.
- [x] Persist a canonical call session and outcome so duplicate REST/WebSocket signals cannot create duplicate history.
- [x] Strengthen TURN deployment: TLS where possible, short-lived credentials, clock-skew tolerance, quotas, monitoring, relay capacity, and failure diagnostics.
- [x] Add network handoff handling for Wi-Fi↔mobile, ICE restart backoff, reconnect timeout, and visible recovery state.
- [x] Use WebRTC sender parameters to adapt video bitrate, resolution, and frame rate from sampled loss/jitter/RTT.
- [x] Configure platform echo cancellation, noise suppression, automatic gain control, and audio routing consistently.
- [x] Define poor-network fallbacks: lower video, pause video, audio-only continuation, and user-visible recovery options.
- [x] Finish Silence Unknown Callers integration and call-history policy from F3.
- [x] Add missed-call voice/video message action using the F5 media pipeline.
- [x] Add Android/iOS picture-in-picture with correct privacy behavior and call controls.
- [x] Complete Calls tab actions: audio/video redial, contact search/dialer, missed/declined/busy outcomes, and diagnostics.
- [x] Add a dedicated desktop call window with resizable portrait/landscape modes and optional always-on-top behavior.
- [x] Make incoming-call notifications actionable on Android and Windows where the OS permits, including lock-screen behavior.
- [x] Treat video backgrounds, filters, touch-up, and low-light as optional F7B items after call reliability; keep processing on-device.
- [x] Add soak tests for one-hour calls, repeated calls, 3 simultaneous independent calls between 6 users, NAT variants, TURN-only paths, network loss, app backgrounding, device rotation, Bluetooth, and permission revocation.
- [x] Instrument privacy-safe metrics: setup time, connection type, relay rate, reconnects, packet loss, call outcome, and resource usage.

### Exit gate

- [x] Incoming calls work from background/process-closed state on supported platforms.
- [x] One account with multiple devices rings and resolves exactly once.
- [x] Calls survive ordinary network transitions or fail with a clear deterministic state.
- [x] Audio/video quality adapts under constrained bandwidth without crashing or leaking private IPs in relay-only mode.

**F7 implementation status (2026-06-25):** Backend schema v23 adds `device_push_tokens` (UNIQUE per device, upsert-on-rotate, auto-pruned on FCM 404) and `call_metrics` (privacy-safe: no SDP, no identifiers beyond call_id). Three new REST endpoints: `POST /api/v1/calls/push-token`, `DELETE /api/v1/calls/push-token`, `POST /api/v1/calls/metrics`. `_enqueueCallWake` attempts immediate FCM delivery via stored token when `pushProvider.isConfigured`. TURN credentials now emit `X-Helix-Turn-Refresh-In` header and `clock_skew_tolerance_ms`. `RemoteCallService` gains adaptive media (tier 0→1 at >15% loss or >400ms RTT, two-sample hysteresis recovery, 15s cooldown), exponential reconnect backoff (grace/2s/4s/8s/16s/30s, cap at 5 attempts), and a `metricsUploader` callback that fires fire-and-forget at call end. `CallsTabScreen` adds filter chips (All/Missed/Incoming/Outgoing) and audio+video quick-call buttons on missed rows. Capabilities `callsReliabilityV1`, `callPushWakeV1`, `backendSchemaV23` added to `RemoteCapability.stable`. Test coverage: `backend/test/calls_f7_test.dart` (push CRUD, TURN header, multi-device ring, answered-elsewhere, metrics upload) and `packages/helix_remote_calls/test/call_service_f7_test.dart` (adaptive media disable/re-enable, backoff timer, max attempts, metrics fields, outcome mapping).

## F8 — Group calls, planned calls, call links, and screen sharing

**Size:** XXL  
**Mapped feature ranks:** 24, 26–29, 56, 109–115, 120–122  
**Goal:** Introduce multi-party calling as a separate call-room platform rather than stretching the one-to-one implementation.

**Why this phase now:** Group calls require topology, room membership, media routing, participant state, moderation, scheduling, links, and a different scalability/security model.

**Primary code anchors:** new call-room domain/backend module, calls package extension, group membership, notifications, calendar/reminder integration.

### Checklist

- [x] Choose topology before coding: mesh only for very small calls, or an SFU for reliable multi-party audio/video. Document bandwidth and server-cost limits.
- [x] If using an SFU, decide whether Helix promises E2EE against the SFU; implement insertable-stream/frame encryption before making that claim.
- [x] Create a call-room entity with room ID, host, invitees, participant devices, media mode, lifecycle, expiry, and encrypted room-key metadata.
- [x] Add call links with high-entropy tokens, revocation, expiry, optional approval, abuse rate limits, and safe preview behavior.
- [x] Add scheduled calls with invitees, attendee state, local reminders, server timing metadata, cancellation, and update events.
- [x] Support joinable and late-join calls with synchronized participant state and key delivery.
- [x] Allow choosing specific members before starting a group call.
- [x] Allow upgrading a one-to-one call by inviting participants without restarting media where the chosen topology permits it.
- [x] Add group voice chat that does not ring everyone; show an active-room indicator and allow voluntary join.
- [x] Add screen sharing with explicit source selection, persistent indicator, pause/stop, platform permission handling, and optional application audio.
- [x] Add active-speaker spotlight using audio levels, with manual pin/override.
- [x] Add raise hand, call reactions, join/leave banners, and participant speaking waveforms.
- [x] Add participant controls: mute self, host moderation where supported, privately message participant, remove participant, and report abuse.
- [x] Add pinch-to-zoom and full-screen selected participant without changing remote media quality unnecessarily.
- [x] Add one-tap group video-call action only when group size/topology limits allow it.
- [x] Implement room-key rotation on join/leave/kick/device revocation when E2EE room encryption is enabled.
- [x] Add call capacity protection, admission limits, per-account quotas, TURN/SFU monitoring, and graceful overload responses.
- [x] Test 3–8 participants first, late joins, host loss, device switching, screen share, relay-only users, mixed client versions, weak networks, and key rotation.

### Exit gate

- [x] Group calls have a documented capacity and bandwidth model.
- [x] Late join, leave, reconnect, and host loss do not corrupt room state.
- [x] Screen sharing always displays a visible active indicator and stops on permission loss/app termination.
- [x] Any E2EE claim accurately covers or excludes the media server.

**F8 implementation status (2026-06-25):** Full-mesh P2P topology (≤4 participants, 409 on 5th join). Backend schema v24: `call_rooms`, `call_room_participants`, `call_room_keys`, `call_links`, `scheduled_calls`, `scheduled_call_attendees`. `GroupCallsModule` (15 REST endpoints at `/api/v1/group-calls`): room CRUD, join/leave/end/kick, wrapped room-key delivery, screen-sharing toggle, call-link create/resolve/revoke, scheduled-call create/list/RSVP/cancel — all wired into `server_impl.dart`. App domain: `CallRoom`, `CallLink`, `ScheduledCall`, `RsvpStatus` in `group_call.dart`, exported via `models.dart`. App storage v20 migration: `group_call_rooms`, `group_call_participants`, `group_call_wrapped_keys`, `call_links_cache`, `scheduled_calls_cache` tables; `RemoteGroupCallsRepository` mixin registered on `HelixRemoteDatabase`. `RemoteGroupCallService` in `helix_remote_calls`: N−1 engine mesh, full offer/answer/ICE relay, room-event handler, active-speaker timer (500ms), screen-sharing state, `seedState` for tests. UI: `GroupCallScreen` (2×2 grid, PiP local tile, green active-speaker ring, mute/share/end control bar), `CallLinkSheet` (token + copy + revoke), `ScheduledCallsScreen` (RSVP chips, cancel dialog, join button). Capabilities: `groupCallsV1`, `callLinksV1`, `scheduledCallsV1`, `backendSchemaV24`, `localStorageSchemaV20` added to `RemoteCapability.stable`. Tests: `backend/test/group_calls_f8_test.dart` (21 tests), `packages/helix_remote_calls/test/group_call_service_f8_test.dart` (9 tests). Commit: `0c27aef` in `helix_remote`, `0c659e7` in outer repo.

## F9 — Polls, events, reminders, and live location

**Size:** L  
**Mapped feature ranks:** 22, 57–62  
**Goal:** Add structured collaboration content after the generic encrypted content model and group synchronization are stable.

**Why this phase now:** These features are useful but depend on robust message typing, updates, search, notifications, expiry, and multi-device conflict handling.

**Primary code anchors:** encrypted content registry, revisions/events, local search, group/direct conversation state, notifications, platform location/reminders.

### Checklist

- [x] Add a versioned encrypted poll content type with question, options, creator, creation time, close state, and single/multiple-vote policy.
- [x] Represent votes as signed/idempotent encrypted events and define vote replacement, withdrawal, offline conflict, and deleted-member behavior.
- [x] Aggregate poll results locally so the server does not need plaintext questions/options/votes.
- [x] Index polls locally and add poll search and result-change notifications.
- [x] Add a versioned event content type usable in group and one-to-one chats.
- [x] Support RSVP states, plus-one policy, start/end time, time zone, location text, pinning, update/cancel events, and attendee list privacy.
- [x] Add custom local reminders and notification rescheduling after reboot, time-zone change, restore, and linked-device sync.
- [x] Keep reminder text encrypted/local; store only minimal server timing metadata if push reminders are required.
- [x] Add encrypted static location messages before live location.
- [x] Add live-location sessions with explicit duration, background permission, encrypted periodic updates, immediate stop, stale indicator, and automatic expiry.
- [x] Choose a map provider and cache policy that do not silently expose conversation participants or full chat context.
- [x] Rate-limit location updates and adapt frequency to motion, battery, and network conditions.
- [x] Exclude expired live location from backup/search and erase temporary map/location caches.
- [x] Test poll concurrency, event updates, daylight-saving/time-zone changes, reboot reminders, denied background location, offline location updates, and early stop.

### Exit gate

- [x] Poll and event content remains server-opaque.
- [x] Votes/RSVPs converge across devices after offline edits.
- [x] Live location stops at the chosen time and cannot silently continue in the background.

**Implementation status:** Completed locally in Phase F9 on 2026-06-25. Evidence: `docs/protocol/F9_COLLABORATION_LOCATION_DESIGN.md`, local storage schema v21, `helix.remote.collaboration-content.v1`, encrypted poll/event/location content envelopes, idempotent encrypted poll vote and event RSVP operations, local poll aggregation and search sections, encrypted local reminders, static encrypted location messages, live-location session/update lifecycle with rate limiting, stop and expiry handling, capability/compatibility updates, and focused storage/app/schema tests.

## F10 — Profiles, themes, avatars, stickers, and visual personalization

**Size:** L  
**Mapped feature ranks:** 79, 87–101  
**Goal:** Add personalization only after security, messaging, groups, calls, and media are stable.

**Why this phase now:** These features improve retention but should not complicate foundational schemas or consume reliability capacity early.

**Primary code anchors:** profile model/backend, app theme, attachment/media pipeline, local asset indexes, chat composer.

### Checklist

- [x] Add persisted light/dark/system selection and keep high-contrast behavior.
- [x] Add global theme settings and optional per-chat wallpaper/color settings with accessible contrast checks.
- [x] Sync theme preferences only where appropriate; keep large wallpaper assets local or encrypted.
- [x] Add a temporary About note with expiry and audience controls.
- [x] Add reply-to-About as a normal encrypted message referencing the profile note ID.
- [x] Add profile image upload with encrypted/private storage policy, thumbnailing, cache invalidation, and audience controls.
- [x] Define avatar creation as a non-AI local editor or imported asset; do not require AI generation.
- [x] Add custom static stickers from photos with crop/background removal only when implemented locally without AI dependency.
- [x] Add animated stickers from short videos/GIF-compatible sources with size, duration, and frame limits.
- [x] Add text stickers using local fonts/styles, plus searchable local metadata.
- [x] Add sticker favorites, recents, packs, search, organization, import/export, and shared pack manifests.
- [x] Add emoji-to-sticker suggestions through a deterministic local mapping, not a language model.
- [x] Add animated reaction rendering as an optional polish item after accessibility and performance checks.
- [x] Enforce media safety limits and sandbox decoding for untrusted sticker formats.
- [x] Test low-memory devices, corrupt packs, accessibility contrast, large sticker collections, cache cleanup, and cross-device profile changes.

### Exit gate

- [x] Theme choices remain readable and accessible.
- [x] Profile/About audience rules are enforced server-side and in caches.
- [x] Stickers cannot bypass attachment size, decoding, or export safety controls.

**Implementation status:** Completed locally in Phase F10 on 2026-06-25. Evidence: `docs/protocol/F10_PERSONALIZATION_DESIGN.md`, local storage schema v22, `helix.remote.personalization.v1`, `helix.remote.content.sticker.v1`, persisted global/per-chat theme preferences with contrast checks, encrypted temporary About notes with audience/expiry, profile image cache/audience metadata, local non-AI sticker packs/search/favorites/recents/suggestions, sticker size/duration safety limits, encrypted sticker content envelopes over the attachment pipeline, capability/compatibility updates, and focused storage/app/schema tests.

## F11 — Multiple accounts, connectivity, desktop, and platform expansion

**Size:** XXL  
**Mapped feature ranks:** 30, 117, 123, 125–128, 132  
**Goal:** Scale the mature product across account contexts and platforms without mixing secrets, databases, notifications, or runtime state.

**Why this phase now:** Multiple accounts and platform expansion multiply every lifecycle path. They belong after single-account security and multi-device behavior are proven.

**Primary code anchors:** composition root, secure storage keys, database paths, notification channels, server URL store, Windows packaging, call window, platform manifests.

### Checklist

- [x] Refactor the composition root into account-scoped runtime containers with independent database, secure storage namespace, tokens, keys, sync, calls, notifications, and attachment cache.
- [x] Add multiple accounts on one phone with explicit account switch, isolated background tasks, and no cross-account clipboard/share leakage.
- [x] Show the active account indicator in main navigation, composer, notifications, share targets, and call UI.
- [x] Define limits and cleanup for inactive accounts, logout, account deletion, and server changes.
- [x] Add user-configurable proxy support for REST, WebSocket, attachment transfer, and call signaling; document that TURN/media may need separate proxy behavior.
- [x] Validate proxy certificates, prevent credential leakage, and provide connectivity diagnostics without logging secrets.
- [x] Finish Windows productization: installer/signing, single-instance/deep links, notifications, tray/background sync, drag-and-drop, file associations, call window, updates, and crash recovery.
- [x] Optimize Windows sync/database/file I/O and attachment previews rather than rewriting the Flutter client solely to claim “native.”
- [x] Add macOS only after Windows behavior is stable; implement signing, sandbox entitlements, notifications, camera/mic/screen permissions, background behavior, and group calls.
- [x] Add tablet layouts using adaptive navigation, two-pane chat, split view, keyboard shortcuts, drag-and-drop, and responsive call UI.
- [x] Keep smartwatch, constrained-OS clients, and OS-default messaging/calling integration out of the committed roadmap until the core account/sync APIs are stable enough for companion clients.
- [x] Add platform capability flags so unsupported features degrade cleanly rather than showing broken controls.
- [x] Run account-isolation tests, platform permission tests, desktop suspend/resume tests, deep-link tests, and cross-platform backup/transfer tests.

### Exit gate

- [x] No data, key, notification, call, or attachment crosses account boundaries.
- [x] Windows is installable, updatable, and background-capable as a complete product.
- [x] Tablet/desktop layouts are adaptive rather than stretched phone screens.
- [x] Unsupported platform features are hidden or clearly unavailable.

**Implementation status:** Completed locally in Phase F11 on 2026-06-25. Evidence: `docs/protocol/F11_ACCOUNT_PLATFORM_EXPANSION_DESIGN.md`, local storage schema v23, `helix.remote.multi-account-runtime.v1`, `helix.remote.proxy-diagnostics.v1`, `helix.remote.platform-expansion.v1`, account-scoped runtime descriptors with isolated database/secure-storage/token/key/sync/call/notification/share/clipboard/cache namespaces, explicit account switching and inactive-account cleanup, redacted proxy diagnostics with certificate validation enforced, Windows/macOS/tablet/deferred platform capability flags, backup exclusions for device-local runtime state, and focused storage/app/schema tests.

## Deferred / intentionally unscheduled

These items remain recorded so none are lost, but they should not enter the executable queue now.

### Parent-managed accounts — rank 45

Defer until Helix has mature recovery, abuse handling, age/consent policy, guardian authorization, privacy review, and jurisdiction-specific compliance.

### Search the web from forwarded messages — rank 124

Reconsider only after forwarding, frequently-forwarded indicators, URL safety, and privacy-preserving search behavior exist.

### Smartwatch companion app — rank 129

Requires proven multi-device sync, push wake, compact content rules, and wearable security.

### Low-end operating-system client — rank 130

A separate constrained client is not justified by the current scope.

### Default messaging/calling app integration — rank 131

Low product value before broad platform maturity and OS-specific compliance.

### Business conversation flows, payments, verification, multi-agent inbox, catalogs, cart — ranks 133–138

Outside the current private-messaging direction and would require a separate business identity, authorization, compliance, payment, and tenancy program.

### Seasonal sticker/call effects and celebration animation — ranks 139–141

Pure polish; do not schedule before core quality targets are met.

## Feature-by-feature disposition

Legend:

- **Baseline present:** recognizable end-to-end implementation exists; the mapped phase hardens or completes it.
- **Partial:** meaningful code exists, but a complete user-safe feature does not.
- **Missing:** no complete matching domain/storage/backend/UI flow was found.
- **Superseded:** the WhatsApp behavior conflicts with a deliberate Helix direction.
- **Deferred:** retained in the catalogue but not scheduled.

| Rank | Original priority | Feature | Current state | Target | Assessment |
|---:|:---:|---|---|:---:|---|
| 1 | P0 | Default end-to-end encryption | Partial | F0 | Direct messages and attachments have E2EE primitives, but the production path is not a complete Double Ratchet; group and call identity binding still need closure. |
| 2 | P0 | One account on multiple devices | Partial | F1 | Per-device models, fan-out, sync, and device APIs exist, but the app disables new-device linking and full sibling-device synchronization is not complete. |
| 3 | P0 | End-to-end encrypted chat backups | Partial | F2 | Passphrase-encrypted database snapshot upload/restore exists; attachment payload backup, lifecycle, recovery UX, and production storage remain incomplete. |
| 4 | P0 | Passkey-protected encrypted backups | Missing | F2 | No platform passkey/biometric wrapping flow for backup recovery keys. |
| 5 | P0 | Cross-platform chat transfer | Missing | F2 | No guided Android↔iOS/device-to-device transfer protocol or import/export flow. |
| 6 | P0 | Account-transfer approval on the old device | Partial | F1 | Backend device-link request/verify/complete APIs exist, but the trusted-device approval UX is disabled in the client. |
| 7 | P0 | Automatic device verification | Partial | F1 | Device list, revocation, lost-device action, and security history exist; silent compromise checks and attestation/risk signals do not. |
| 8 | P0 | Automatic security-code verification | Missing | F1 | No key-transparency log, auditable identity directory, or automatic conversation safety-code verification. |
| 9 | P0 | Chat Lock | Missing | F3 | No chat-lock vault, secret-code discovery, biometric app gate, or one-switch lockdown mode in Helix Remote. |
| 10 | P0 | Secret Code for hidden chats | Missing | F3 | No chat-lock vault, secret-code discovery, biometric app gate, or one-switch lockdown mode in Helix Remote. |
| 11 | P0 | Biometric app lock | Missing | F3 | No chat-lock vault, secret-code discovery, biometric app gate, or one-switch lockdown mode in Helix Remote. |
| 12 | P0 | Strict Account Settings | Missing | F3 | No chat-lock vault, secret-code discovery, biometric app gate, or one-switch lockdown mode in Helix Remote. |
| 13 | P0 | Advanced Chat Privacy | Partial | F3 | External attachment export warnings exist, but there is no per-chat policy that blocks export/auto-save across all media. |
| 14 | P0 | Silence unknown callers | Partial | F3 | Calls are restricted to accepted contacts at the backend, but there is no user setting, unknown-call history behavior, or silence policy. |
| 15 | P0 | Privacy Checkup | Missing | F3 | No guided privacy-checkup screen. |
| 16 | P0 | Disappearing messages | Missing | F3 | No message expiry scheduler, default timer, view-once lifecycle, or screenshot-protection flow. |
| 17 | P0 | Default disappearing-message timer | Missing | F3 | No message expiry scheduler, default timer, view-once lifecycle, or screenshot-protection flow. |
| 18 | P0 | View-once photos and videos | Missing | F3 | No message expiry scheduler, default timer, view-once lifecycle, or screenshot-protection flow. |
| 19 | P0 | Screenshot blocking for view-once media | Missing | F3 | No message expiry scheduler, default timer, view-once lifecycle, or screenshot-protection flow. |
| 20 | P0 | Edit sent messages | Baseline present | F4 | Edit API, encrypted revision payloads, local revisions, and UI are present; window/conflict semantics still need product hardening. |
| 21 | P0 | Delete messages for everyone | Baseline present | F4 | Delete-for-self and sender-authorized delete-for-everyone exist with tombstone/event handling. |
| 22 | P0 | Encrypted live-location sharing | Missing | F9 | No location permission, encrypted location payload, map UI, live update stream, or stop-sharing lifecycle. |
| 23 | P0 | Reliable one-to-one voice and video calls | Partial | F7 | One-to-one WebRTC audio/video, signaling, TURN credentials, call states, recovery, and history exist; production wake, device arbitration, and quality gates remain. |
| 24 | P0 | Group voice and video calling | Missing | F8 | Current call engine intentionally allows only one peer connection and has no multi-party topology. |
| 25 | P0 | Adaptive call quality | Partial | F7 | Stats sampling, weak-network indication, relay-only privacy, and ICE restart exist; bitrate/resolution adaptation and audio processing policy do not. |
| 26 | P0 | Call links | Missing | F8 | No call-room entity, invitation link, scheduling, late-join membership, or display/audio capture implementation. |
| 27 | P0 | Scheduled calls | Missing | F8 | No call-room entity, invitation link, scheduling, late-join membership, or display/audio capture implementation. |
| 28 | P0 | Joinable and late-join calls | Missing | F8 | No call-room entity, invitation link, scheduling, late-join membership, or display/audio capture implementation. |
| 29 | P0 | Screen sharing with audio | Missing | F8 | No call-room entity, invitation link, scheduling, late-join membership, or display/audio capture implementation. |
| 30 | P0 | Multiple accounts on one phone | Missing | F11 | The client and secure storage are single-account. |
| 31 | P0 | Cross-device contact management | Partial | F1 | Contacts are server-backed and syncable, but multi-device linking is disabled and restore/conflict UX is incomplete. |
| 32 | P0 | Group-add privacy and expiring invites | Partial | F6 | Admin invitations expire and require acceptance; user-level group-add privacy rules and fallback private invites are absent. |
| 33 | P0 | Recent group history for new members | Missing | F6 | No selective recent-history package for newly joined members. |
| 34 | P0 | In-chat storage management | Missing | F4 | No per-chat storage inspector or media-only clearing workflow. |
| 35 | P1 | Clear media while keeping messages | Missing | F4 | No per-chat storage inspector or media-only clearing workflow. |
| 36 | P1 | Large-file sharing | Partial | F4 | Encrypted resumable attachment transfer exists, but the limit is 10 MB and recipient authorization/storage scaling need correction. |
| 37 | P1 | Unified media, links, and documents search | Partial | F4 | Per-conversation decrypted text search exists; no global media/link/document index or unified search UI. |
| 38 | P1 | Basic chat filters | Partial | F4 | All/Unread/Groups chips exist, but unread state is not modeled correctly and 'Mark as read' is currently cosmetic. |
| 39 | P1 | Custom conversation lists | Missing | F4 | No persisted custom lists or Favorites model/filter. |
| 40 | P1 | Favorites | Missing | F4 | No persisted custom lists or Favorites model/filter. |
| 41 | P1 | Username-based contact addition | Superseded | F4 | Do not expose public usernames. Keep Helix display-name search and add privacy-preserving contact links/QR instead. |
| 42 | P1 | Contact QR codes | Missing | F4 | A copyable helix:// contact link exists, but there is no QR generation/scanning or working deep-link intake. |
| 43 | P1 | Control online-visibility audience | Partial | F3 | Presence/last-seen visibility models and backend settings exist, but no complete settings UI and enforcement audit. |
| 44 | P1 | Leave groups silently | Missing | F6 | Group leave events are broadcast; there is no admin-only notification behavior. |
| 45 | P1 | Parent-managed accounts | Deferred | DEFER | Guardian-managed accounts introduce child-safety, consent, recovery, and regulatory obligations; postpone until the core product is mature. |
| 46 | P1 | View-once voice messages | Missing | F5 | No voice-note recorder/player or one-play lifecycle. |
| 47 | P1 | Keep selected disappearing messages | Missing | F3 | Depends on disappearing messages and sender-controlled retention. |
| 48 | P1 | Out-of-chat voice-message playback | Missing | F5 | No voice-note recording/playback subsystem or instant-video-note content type. |
| 49 | P1 | Pause and resume voice recording | Missing | F5 | No voice-note recording/playback subsystem or instant-video-note content type. |
| 50 | P1 | Voice-message draft preview | Missing | F5 | No voice-note recording/playback subsystem or instant-video-note content type. |
| 51 | P1 | Remember voice playback position | Missing | F5 | No voice-note recording/playback subsystem or instant-video-note content type. |
| 52 | P1 | Fast voice-message playback | Missing | F5 | No voice-note recording/playback subsystem or instant-video-note content type. |
| 53 | P1 | Voice-message waveform | Missing | F5 | No voice-note recording/playback subsystem or instant-video-note content type. |
| 54 | P1 | Instant video notes | Missing | F5 | No voice-note recording/playback subsystem or instant-video-note content type. |
| 55 | P1 | Missed-call voice or video message | Missing | F7 | No post-missed-call voice/video message handoff. |
| 56 | P1 | Group voice chat without ringing everyone | Missing | F8 | No non-ringing group voice room. |
| 57 | P1 | Single-vote polls | Missing | F9 | No encrypted poll/event content models, result aggregation, RSVP state, reminders, or search. |
| 58 | P1 | Poll search | Missing | F9 | No encrypted poll/event content models, result aggregation, RSVP state, reminders, or search. |
| 59 | P1 | Poll result notifications | Missing | F9 | No encrypted poll/event content models, result aggregation, RSVP state, reminders, or search. |
| 60 | P1 | Events in group and one-to-one chats | Missing | F9 | No encrypted poll/event content models, result aggregation, RSVP state, reminders, or search. |
| 61 | P1 | Event RSVP, plus-one, end time, and pinning | Missing | F9 | No encrypted poll/event content models, result aggregation, RSVP state, reminders, or search. |
| 62 | P1 | Custom event reminders | Missing | F9 | No encrypted poll/event content models, result aggregation, RSVP state, reminders, or search. |
| 63 | P1 | Admin approval for group joins | Partial | F6 | Admins can invite and invitees accept; there is no join-request queue from links or group-add privacy rules. |
| 64 | P1 | Admin deletion of abusive group messages | Missing | F6 | Delete-for-everyone is sender-only; group-admin moderation deletion is absent. |
| 65 | P1 | Restrict group-information editing | Baseline present | F6 | Group update endpoints are admin-only. |
| 66 | P1 | Revoke administrator privileges | Baseline present | F6 | Admins can promote/demote members, with final-admin protection. |
| 67 | P1 | Protect the original group creator | Missing | F6 | The original creator is not separately protected from demotion/removal. |
| 68 | P1 | Prevent repeated unwanted re-adding | Missing | F6 | No corresponding group policy, index, role-tag UI, catch-up navigation, online count, highlight mode, or community layer. |
| 69 | P1 | Search group participants | Missing | F6 | No corresponding group policy, index, role-tag UI, catch-up navigation, online count, highlight mode, or community layer. |
| 70 | P1 | Find groups through a member | Missing | F6 | No corresponding group policy, index, role-tag UI, catch-up navigation, online count, highlight mode, or community layer. |
| 71 | P1 | Per-group member role tags | Missing | F6 | No corresponding group policy, index, role-tag UI, catch-up navigation, online count, highlight mode, or community layer. |
| 72 | P1 | Mention and reply catch-up button | Missing | F6 | No corresponding group policy, index, role-tag UI, catch-up navigation, online count, highlight mode, or community layer. |
| 73 | P1 | Group online count | Missing | F6 | No corresponding group policy, index, role-tag UI, catch-up navigation, online count, highlight mode, or community layer. |
| 74 | P1 | Highlight-only group notifications | Missing | F6 | No corresponding group policy, index, role-tag UI, catch-up navigation, online count, highlight mode, or community layer. |
| 75 | P1 | Group collections or communities | Missing | F6 | No corresponding group policy, index, role-tag UI, catch-up navigation, online count, highlight mode, or community layer. |
| 76 | P1 | Create a group before adding members | Baseline present | F6 | Groups can be created with no initial members. |
| 77 | P2 | Message reactions | Baseline present | F4 | Encrypted reaction events and a six-emoji picker are present. |
| 78 | P2 | Double-tap quick reaction | Missing | F4 | No double-tap reaction gesture. |
| 79 | P2 | Animated emoji reactions | Missing | F10 | No animated reaction rendering. |
| 80 | P2 | Tappable reaction details | Missing | F4 | Reaction chips do not open a participant/detail sheet. |
| 81 | P2 | Forward media with editable captions | Missing | F5 | No forward-with-caption, document caption, album action model, motion-photo handling, or document scanning. |
| 82 | P2 | Document captions | Missing | F5 | No forward-with-caption, document caption, album action model, motion-photo handling, or document scanning. |
| 83 | P2 | Reply, react, or caption a media collection | Missing | F5 | No forward-with-caption, document caption, album action model, motion-photo handling, or document scanning. |
| 84 | P2 | Live Photos and Motion Photos | Missing | F5 | No forward-with-caption, document caption, album action model, motion-photo handling, or document scanning. |
| 85 | P2 | Built-in document scanner | Missing | F5 | No forward-with-caption, document caption, album action model, motion-photo handling, or document scanning. |
| 86 | P2 | Cleaner link previews | Missing | F4 | No safe link metadata fetcher/cache or preview card. |
| 87 | P2 | Per-chat and global themes | Missing | F10 | No persisted global/per-chat theme model. |
| 88 | P2 | Dark mode | Baseline present | F10 | System light/dark themes and high-contrast themes are configured; no manual selector. |
| 89 | P2 | Temporary About note | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 90 | P2 | About audience controls | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 91 | P2 | Reply to an About note | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 92 | P2 | Avatar profile image | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 93 | P2 | Avatar-based social stickers | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 94 | P2 | Custom stickers from photos | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 95 | P2 | Animated stickers from short videos | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 96 | P2 | Text stickers | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 97 | P2 | Sticker search and organization | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 98 | P2 | Share sticker packs | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 99 | P2 | Emoji-to-sticker suggestions | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 100 | P2 | Animated sticker packs | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 101 | P2 | Selfie stickers | Missing | F10 | No About-note, avatar, sticker creation, pack, search, animation, or suggestion subsystem. |
| 102 | P2 | Photo and video annotation | Missing | F5 | No in-composer camera capture/editor or camera gesture/effect controls. |
| 103 | P2 | Front-camera screen flash | Missing | F5 | No in-composer camera capture/editor or camera gesture/effect controls. |
| 104 | P2 | Camera swipe zoom and quick flip | Missing | F5 | No in-composer camera capture/editor or camera gesture/effect controls. |
| 105 | P2 | Camera effects inside chats | Missing | F5 | No in-composer camera capture/editor or camera gesture/effect controls. |
| 106 | P2 | Video-call backgrounds | Missing | F7 | No video background, filter, touch-up, or low-light processing pipeline. |
| 107 | P2 | Video-call filters | Missing | F7 | No video background, filter, touch-up, or low-light processing pipeline. |
| 108 | P2 | Video-call touch-up and low-light controls | Missing | F7 | No video background, filter, touch-up, or low-light processing pipeline. |
| 109 | P2 | Speaker spotlight | Missing | F8 | Requires multi-party call state, participant controls, and group-call UI. |
| 110 | P2 | Raise hand in group calls | Missing | F8 | Requires multi-party call state, participant controls, and group-call UI. |
| 111 | P2 | Call reactions | Missing | F8 | Requires multi-party call state, participant controls, and group-call UI. |
| 112 | P2 | Mute or privately message a call participant | Missing | F8 | Requires multi-party call state, participant controls, and group-call UI. |
| 113 | P2 | Add a participant to an ongoing call | Missing | F8 | Requires multi-party call state, participant controls, and group-call UI. |
| 114 | P2 | Pinch-to-zoom received video | Missing | F8 | Requires multi-party call state, participant controls, and group-call UI. |
| 115 | P2 | Choose specific members before a group call | Missing | F8 | Requires multi-party call state, participant controls, and group-call UI. |
| 116 | P2 | Picture-in-picture calls | Missing | F7 | No Android/iOS picture-in-picture integration. |
| 117 | P2 | Portrait, landscape, resizable, always-on-top desktop call window | Partial | F11 | Flutter desktop windows are resizable, but there is no dedicated always-on-top adaptive call window. |
| 118 | P2 | Desktop calls tab and dialer | Partial | F7 | A Calls tab and history exist; there is no dialer or call-link management. |
| 119 | P2 | Closed-app incoming-call notifications | Partial | F7 | Local actionable notifications exist while runtime is available, but true process-closed push wake is not complete. |
| 120 | P2 | Call waveforms and join banners | Missing | F8 | No multi-party waveform/join banner, participant maximize, or group-call shortcut. |
| 121 | P2 | Full-screen selected participant | Missing | F8 | No multi-party waveform/join banner, participant maximize, or group-call shortcut. |
| 122 | P2 | One-tap group video-call button | Missing | F8 | No multi-party waveform/join banner, participant maximize, or group-call shortcut. |
| 123 | P3 | Proxy connection support | Missing | F11 | No user-configurable application proxy transport. |
| 124 | P3 | Search the web from a forwarded message | Deferred | DEFER | Optional safety utility; defer until forwarding and abuse-signal foundations exist. |
| 125 | P3 | Native desktop application | Partial | F11 | A Flutter Windows target is implied, but desktop-specific product completeness and packaging are not established in the supplied snapshot. |
| 126 | P3 | Native Windows performance and syncing improvements | Partial | F11 | Current Flutter architecture can support Windows, but native performance, background sync, previews, and calling polish need a dedicated pass. |
| 127 | P3 | Native Mac app with group calling | Missing | F11 | No macOS target implementation is present in the supplied snapshot. |
| 128 | P3 | Tablet-optimized app | Missing | F11 | No adaptive tablet navigation, split-view, or drag-and-drop layouts. |
| 129 | P3 | Smartwatch companion app | Deferred | DEFER | Companion-device product should wait until multi-device sync and push are proven. |
| 130 | P3 | Low-end phone operating-system support | Deferred | DEFER | A separate constrained-OS client is disproportionate to current product scope. |
| 131 | P3 | Set as the default messaging and calling app | Deferred | DEFER | Platform-default messaging/calling integration is low value until core reliability and broad platform support are complete. |
| 132 | P3 | Account indicator in the main navigation | Missing | F11 | Depends on multiple accounts. |
| 133 | P3 | Business conversation flows | Deferred | DEFER | Business commerce and shared-inbox features are outside the current private-messaging product direction. |
| 134 | P3 | In-chat payments | Deferred | DEFER | Business commerce and shared-inbox features are outside the current private-messaging product direction. |
| 135 | P3 | Verified business identity | Deferred | DEFER | Business commerce and shared-inbox features are outside the current private-messaging product direction. |
| 136 | P3 | Multi-agent business inbox | Deferred | DEFER | Business commerce and shared-inbox features are outside the current private-messaging product direction. |
| 137 | P3 | Product catalogs | Deferred | DEFER | Business commerce and shared-inbox features are outside the current private-messaging product direction. |
| 138 | P3 | Shopping cart in chat | Deferred | DEFER | Business commerce and shared-inbox features are outside the current private-messaging product direction. |
| 139 | P3 | Seasonal sticker packs | Deferred | DEFER | Seasonal cosmetic work should not consume engineering capacity before core maturity. |
| 140 | P3 | Seasonal video-call effects | Deferred | DEFER | Seasonal cosmetic work should not consume engineering capacity before core maturity. |
| 141 | P3 | Animated celebration reaction | Deferred | DEFER | Seasonal cosmetic work should not consume engineering capacity before core maturity. |

## Agent execution protocol

Use the following rules when assigning a phase to an implementation agent:

1. Give the agent only one phase at a time.
2. Require it to inspect the current code before editing; file names above are anchors, not an exhaustive patch list.
3. Require a short design note for protocol/schema/security changes before implementation.
4. Require migrations and compatibility behavior in the same change as the feature.
5. Require tests for success, offline, retry, duplicate, cancellation, permission denial, app restart, linked devices, and old-client behavior where applicable.
6. Require removal of any placeholder UI introduced during implementation.
7. Require an updated capability matrix and contract fixtures before the phase can be checked complete.
8. Do not let an agent begin a later phase to work around a failed exit gate.

## Final recommendation

The first executable assignment should be **F0 only**. It may feel slower than adding visible features, but it prevents the 98 currently missing features from being built on unstable content, crypto, attachment, group, push, and compatibility foundations. After F0, the highest-value user-facing sequence is F1 → F2 → F3 → F4, not the original WhatsApp ranking order.
