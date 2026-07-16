# F0 Foundation Design

Status: implemented baseline for Phase F0.

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

The current protocol remains X3DH plus session-key reuse. It is not documented
as a complete Double Ratchet until DH ratchet headers, skipped-message keys,
and independent review are added.

## Attachment Grants

Attachment upload and resume remain uploader-only. After the uploader registers
an attachment reference for an existing message, the backend grants ciphertext
download access to every current account in that message conversation. Download
URL and file-stream endpoints accept either the owner or a recipient grant.
Unrelated accounts are denied.

Backup media uses account-owned encrypted object storage with resumable upload,
SHA-256 integrity checks, quota enforcement, and retention cleanup.
