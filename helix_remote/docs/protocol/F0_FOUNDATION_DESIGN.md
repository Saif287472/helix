# F0 Foundation Design

> **Status: historical (v1 design).** This document records the v1 design and implementation. v1 was deleted at the Phase X cutover (SQLite backend, `helix_remote_storage`, `helix_remote_sync`, `helix_remote_groups`, per-conversation sessions); the last v1 commit is tagged `v1-final`. Schema numbers, file paths and endpoints below are v1. The v2 truth: [`v2/README.md`](v2/README.md) (REST, realtime, content, crypto, metadata). v2 has no capability-token negotiation: the contract is the `/v1` route catalog in `packages/helix_remote_protocol`.

Status: implemented baseline for Phase F0. The schema capabilities listed
below are the F0 baseline, not today's versions: the app's local database is at
`latestSchemaVersion` 31 (`packages/helix_remote_storage/lib/src/database/migrations.dart`)
and the backend at `PRAGMA user_version` 47 (`backend/lib/src/database/migrations.dart`).
`RemoteCapabilityRegistry` (`packages/helix_remote_domain/lib/domain/capabilities.dart`)
still stops at `local-storage-schema.v23` and `backend-schema.v24`.

## Capability Registry

Canonical capability names live in `helix_remote_domain` as
`RemoteCapability` and are exposed through `RemoteCapabilityRegistry.current()`.
The app, API parser, local storage docs, and backend schema notes use these
names as the compatibility boundary before enabling new protocol behavior.

Current baseline capabilities:

- `helix.remote.schema.v1`
- `helix.remote.realtime-envelope.v1`
- `helix.remote.content-envelope.v1`
- `helix.remote.content.text.v1`
- `helix.remote.content.attachment.v1`
- `helix.remote.x3dh-envelope.v1`
- `helix.remote.session-envelope.v2`
- `helix.remote.multi-device-trust.v1`
- `helix.remote.encrypted-backup-recovery.v2`
- `helix.remote.backup-media-objects.v1`
- `helix.remote.attachment-recipient-grants.v1`
- `helix.remote.local-storage-schema.v16`
- `helix.remote.backend-schema.v21`

## Message Content Envelope

New encrypted message plaintext is a JSON wrapper:

```json
{
  "type": "helix.remote.content-envelope.v1",
  "version": 1,
  "content_type": "helix.remote.content.text.v1",
  "content_version": 1,
  "payload": {}
}
```

Registered content types are text and attachment. Parsers continue to accept
legacy plaintext strings, legacy `helix.remote.text.v1` reply JSON, and legacy
`helix.remote.attachment.v1` attachment JSON so old local history remains
readable.

The X3DH/session envelope authenticated data binds message ID, conversation ID,
sender device ID, recipient device ID, protocol version, content-envelope
capability, and message counter.

## Crypto Persistence

Successful outbound sends run local message persistence, per-device envelope
generation, crypto-session counter updates, and outbox insertion in one SQLite
transaction. Secure-session failures roll back the transaction and then store a
local `SECURE_SESSION_UNAVAILABLE` row without enqueuing network send state.

At F0 the protocol was X3DH plus session-key reuse. Since then
`DoubleRatchetSession` (`packages/helix_remote_crypto/lib/src/double_ratchet.dart`)
added DH ratchet headers and skipped-message keys, and it is used for sends and
receives (`app/lib/app/remote_messaging_service/message_crypto.dart`). It has
not been independently reviewed, so no strong public claim is made.

## Attachment Grants

Attachment upload and resume remain uploader-only. After the uploader registers
an attachment reference for an existing message, the backend grants ciphertext
download access to every current account in that message conversation. Download
URL and file-stream endpoints accept either the owner or a recipient grant.
Unrelated accounts are denied.

Backup media uses account-owned encrypted object storage with resumable upload,
SHA-256 integrity checks, quota enforcement, and retention cleanup.
