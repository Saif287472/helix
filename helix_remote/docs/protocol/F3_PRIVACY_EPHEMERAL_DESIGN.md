# F3 Privacy Controls And Ephemeral Content

> **Status: historical (v1 design).** This document records the v1 design and implementation. v1 was deleted at the Phase X cutover (SQLite backend, `helix_remote_storage`, `helix_remote_sync`, `helix_remote_groups`, per-conversation sessions); the last v1 commit is tagged `v1-final`. Schema numbers, file paths and endpoints below are v1. The v2 truth: [`v2/CONTENT_V2.md`](v2/CONTENT_V2.md): disappearing timers and view-once state travel inside the encrypted content, so the server never sees them. Locked chats are not built in v2.

Status: Phase F3 implementation evidence
Date: 2026-06-25

## Capabilities

- `helix.remote.privacy-controls.v1`
- `helix.remote.ephemeral-content.v1`
- `helix.remote.local-storage-schema.v16`

## Local Privacy State

Schema v16 stores app-lock policy, notification preview policy, silence-unknown
call policy, secret-code attempt rate limits, per-conversation locked/hidden
state, disappearing timers, and advanced chat privacy flags in the encrypted
database.

Locked chats are hidden from normal conversation lists and search, redacted in
notification previews, and excluded from backup snapshots unless a future
explicit locked-vault backup mode is implemented. Secret-code verification uses
a verifier only, rate-limits failed attempts, and never logs secret values.

## Ephemeral Content

Outgoing text and attachment plaintext can carry an authenticated `privacy`
object inside `helix.remote.content-envelope.v1`. The local message row stores
only enforcement metadata:

- `expires_at`
- `retention_deadline`
- `view_once`
- `view_once_opened_at`
- `keep_in_chat`

Outbound operations may include `retention_deadline` for server retention. The
deadline contains no plaintext message content.

Expired messages and opened view-once messages are tombstoned and removed before
history reads and backup export. Keep-in-chat prevents expiry only when explicitly
set.

## Enforcement Sources

- App lock, strict preset, notification preview, locked-chat vault, default
  disappearing policy, and privacy checkup: `PrivacyScreen` +
  `RemotePrivacyRepository`
- Per-chat disappearing and advanced privacy metadata:
  `RemoteMessageSending`
- Expiry, view-once consumption, search exclusion, and tombstones:
  `RemoteHistoryReceipts` + `RemotePrivacyRepository`
- Backup exclusions: `RemoteBackupsRepository`
- Attachment export blocking: `ConversationScreen` attachment export path +
  `RemoteMessagingService.canExportAttachment`
- Silence Unknown Callers: `RemoteCallService.processInboundSignal`
- Search discoverability, presence, and last-seen enforcement:
  backend `ContactsModule` and `BackendContactsRepository`

## Platform Limits

Helix does not block screenshots or screen recording on any screen (the
per-screen FLAG_SECURE / Windows display-affinity protection was removed on
2026-09-30 because people need to screenshot chats). Disappearing messages and
view-once content can therefore be captured by the recipient; no UI claims
otherwise.
