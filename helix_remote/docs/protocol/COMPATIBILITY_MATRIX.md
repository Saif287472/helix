# Protocol Compatibility Matrix

Status: F11 account/platform expansion baseline, with 2026-09 additions
(password sign-in, history backup).

> Current schema versions (2026-09): app local database `latestSchemaVersion`
> 31 (`packages/helix_remote_storage/lib/src/database/migrations.dart`, v31 adds
> `local_identity`); backend `PRAGMA user_version` 47
> (`backend/lib/src/database/migrations.dart`; v46 `account_passwords`, v47
> `history_backups`). The capability names below stop at local v26 / backend
> v32 in this list and at local v23 / backend v24 in
> `RemoteCapabilityRegistry`; neither has been advanced since.

F0 freezes the Remote baseline around:

- App/local storage schema: `helix.remote.local-storage-schema.v26`
- Backend schema: `helix.remote.backend-schema.v32`
- Realtime envelope: `helix.remote.realtime-envelope.v1`
- Encrypted content envelope: `helix.remote.content-envelope.v1`
- Text content: `helix.remote.content.text.v1`
- Attachment content: `helix.remote.content.attachment.v1`
- Voice-note content: `helix.remote.content.voice-note.v1`
- Instant-video content: `helix.remote.content.instant-video.v1`
- Captioned media content: `helix.remote.content.media-with-caption.v1`
- Media collection content: `helix.remote.content.media-collection.v1`
- Rich media pipeline: `helix.remote.rich-media-pipeline.v1`
- Poll content: `helix.remote.content.poll.v1`
- Event content: `helix.remote.content.event.v1`
- Location content: `helix.remote.content.location.v1`
- Collaboration content: `helix.remote.collaboration-content.v1`
- Sticker content: `helix.remote.content.sticker.v1`
- Personalization: `helix.remote.personalization.v1`
- Multi-account runtime: `helix.remote.multi-account-runtime.v1`
- Proxy diagnostics: `helix.remote.proxy-diagnostics.v1`
- Platform expansion: `helix.remote.platform-expansion.v1`
- X3DH establishing envelope: `helix.remote.x3dh-envelope.v1`
- Session reuse envelope: `helix.remote.session-envelope.v2`
- Multi-device trust: `helix.remote.multi-device-trust.v1`
- Backup recovery: `helix.remote.encrypted-backup-recovery.v2`
- Backup media objects: `helix.remote.backup-media-objects.v1`
- Privacy controls: `helix.remote.privacy-controls.v1`
- Ephemeral content: `helix.remote.ephemeral-content.v1`
- Messaging productivity: `helix.remote.messaging-productivity.v1`
- Local search index: `helix.remote.local-search-index.v1`
- Contact links: `helix.remote.contact-links.v1`
- Attachment recipient grants:
  `helix.remote.attachment-recipient-grants.v1`

Capability names are defined by `RemoteCapability` in
`packages/helix_remote_domain`.

Stage 3 moves protocol code into `lib/protocol/` without changing the wire
format. Current protocol version remains `2.2`. (This paragraph and the
"Version 2.2 Frames", "Unknown-Frame Behavior" sections below describe the
Helix Local LAN protocol, not Helix Remote.)

## F1 Device Trust Compatibility

All routes are under `/api/v1`. Device linking uses:

- `POST /accounts/devices/link/request-new`
- `POST /accounts/devices/link/verify`
- `POST /accounts/devices/link/reject`
- `POST /accounts/devices/link/complete-new`

Legacy `/accounts/devices/link/request` and `/complete` remain mounted for old
clients, but clients that support `helix.remote.multi-device-trust.v1` should
use the fresh-device request and signed completion flow.

## Password Sign-In Compatibility

Backend schema v46 adds `account_passwords`. Routes:

- `POST /accounts/password/params` (public)
- `POST /accounts/password/login` (public)
- `POST /accounts/password/verify` (public)
- `GET /accounts/password`, `POST /accounts/password` (session)
- `POST /accounts/devices/revoke-others` (session)

Password KDF parameters travel with each account (`kdf_params`: `alg`
`argon2id`, `memory_kib`, `iterations`, `parallelism`, `length`), so future
clients can raise the cost; the server refuses `memory_kib` below 19456 and any
`length` other than 64. The login transcript is versioned
(`helix.remote.password-login.v1`). There is no capability token for password
support. `POST /messages/send` answers 409 `device_list_stale` with
`missing_device_ids`; clients must refetch bundles and rebuild the send.

## History Backup Compatibility

Backend schema v47 adds `history_backups`. Routes: `PUT /backups/history` and
`GET /backups/history` (session; 16 MB limit, 413 above it). The blob is an
opaque, versioned envelope (`v: 1`, key info `helix.remote.history-backup.v1`)
the server never parses.

## F2 Backup Compatibility

New backups use envelope version 2 with `Argon2id-v1-m8192-t2-p1`, snapshot
version 2, attachment manifest version 1, and transfer archive version 1.
Clients continue to read legacy envelope version 1 with
`PBKDF2-HMAC-SHA256-100000`.

Backup media objects use `/backups/media*` routes and are account-owned opaque
ciphertext streams with SHA-256 integrity checks.

## F3 Privacy And Ephemeral Compatibility

Local storage schema v16 adds privacy metadata to conversations and messages:
locked/hidden chat state, per-chat disappearing timers, advanced export/save/
forward/media-save flags, message expiry, delivery-retention deadline,
view-once/opened state, and keep-in-chat override.

Encrypted content payloads may include a `privacy` object inside the authenticated
content envelope. Servers may see only `retention_deadline` on outbound
operations; they do not receive plaintext expiry reasons, locked-chat state, or
view-once media plaintext.

Clients that do not support `helix.remote.ephemeral-content.v1` must ignore
unknown `privacy` payload keys but continue to render the decrypted content.

## F4 Messaging Productivity Compatibility

Local storage schema v17 adds device-scoped read state, favorites, custom
conversation lists, a local-only decrypted search index, safe link preview
cache metadata, and replay-protected signed contact links. Search terms and
plaintext index rows remain on the device.

Clients that do not support `helix.remote.messaging-productivity.v1` continue
to read conversations and messages, but they ignore favorites, custom lists,
unread summaries, contact-link replay state, and local search sections.

## F5 Rich Media Compatibility

Local storage schema v18 adds media drafts, shared media playback state, and
transfer policy rows for background/retry/expiry handling. Rich media messages
remain normal encrypted content envelopes that carry encrypted attachment
manifests plus authenticated local metadata such as caption, waveform samples,
duration, media kind, thumbnail references, and collection item manifests.

Clients that support only `helix.remote.content.attachment.v1` must ignore the
new rich-media content types rather than attempting to render partial plaintext.
Servers continue to store and route opaque encrypted message envelopes and
attachment object references only.

## F9 Collaboration And Location Compatibility

Local storage schema v21 adds local poll vote aggregation, event RSVP state,
encrypted local reminders, and live-location session/update lifecycle rows.
Poll, event, and location messages are normal encrypted content envelopes; vote,
RSVP, reminder, and live-location update records are idempotent local or
encrypted event rows and do not require server plaintext.

Clients that do not support `helix.remote.collaboration-content.v1` must ignore
unknown poll/event/location content while continuing to sync ordinary messages.

## F10 Personalization Compatibility

Local storage schema v22 adds theme preferences, temporary encrypted About
notes, profile image cache metadata, sticker packs, and sticker records.
Sticker messages use `helix.remote.content.sticker.v1` inside the encrypted
content envelope and continue to reference encrypted attachment objects.

Clients without `helix.remote.personalization.v1` ignore personalization rows
and unknown sticker content while preserving ordinary message history.

## F11 Account And Platform Compatibility

Local storage schema v23 adds device-local account runtime profiles, proxy
profiles, and platform capability profiles. These rows are excluded from
conversation backup snapshots because they contain local runtime paths, secure
storage namespaces, notification channels, and secret references.

Clients without `helix.remote.multi-account-runtime.v1` must not attempt to run
multiple accounts in one process. Clients without
`helix.remote.proxy-diagnostics.v1` may connect directly but must not log proxy
credentials. Clients without `helix.remote.platform-expansion.v1` should hide
unsupported desktop/tablet controls rather than rendering broken UI.

## Phone Identity, OTP, and Invite Compatibility

Registration is **v3-only**; v2 (username-based) was hard-removed, not kept
alongside as a legacy path. `POST /accounts/register` rejects any request
where `registration_version` is not exactly `3` - there is no negotiation or
fallback. Clients older than this overhaul cannot register against a current
backend at all; this is an intentional hard cut (see the overhaul's Phase 5
decision), not an oversight, since there were no real users on v2 at the time
of the cut.

v3 registration requires `phone_hash`, `otp_code`, and `invite_code` (personal
servers only; Helix Global takes no invite but requires `tos_version`) in place
of v2's `username`, and the registration transcript
(`helix.remote.registration.v3` in the signed payload) binds all three plus
the account/device key material together, so a signature cannot be replayed
against a swapped invite or OTP. There is no v2 compatibility shim on the
local storage side either - schema v25 drops the local `accounts.username`
mirror column outright, since it never had a uniqueness constraint locally
and no meaningful data could exist there pre-launch.

Contacts phone-hash matching (`POST /contacts/match`, `GET
/contacts/discovery-salt`) and invite-credential issuance/lookup
(`POST/GET /ops/invites`, `GET /accounts/invite/lookup`, `POST
/accounts/invite/auto-issue`) are new REST surfaces, not realtime-envelope
capabilities - they are not gated by `RemoteCapability` negotiation the way
message content types are, since they sit outside the messaging protocol
proper.

## F0 Content Compatibility

New encrypted message plaintext MUST use:

```json
{
  "type": "helix.remote.content-envelope.v1",
  "version": 1,
  "content_type": "helix.remote.content.text.v1",
  "content_version": 1,
  "payload": {}
}
```

Receivers MUST continue to parse legacy bare text, legacy
`helix.remote.text.v1` reply JSON, and legacy `helix.remote.attachment.v1`
attachment JSON.

## Version 2.2 Frames

| Type | Hex | Frame | Required behavior |
|---|---:|---|---|
| request | `0x01` | `RequestFrame` | Required |
| accept | `0x02` | `AcceptFrame` | Required |
| reject | `0x03` | `RejectFrame` | Required |
| cancel | `0x04` | `CancelFrame` | Required |
| identity | `0x05` | `IdentityFrame` | Required |
| identity_ack | `0x06` | `IdentityAckFrame` | Required |
| capability | `0x07` | `CapabilityFrame` | Required |
| chat_message | `0x08` | `ChatMessageFrame` | Required |
| chat_ack | `0x09` | `ChatAckFrame` | Optional |
| keepalive | `0x0A` | `KeepaliveFrame` | Required |
| close | `0x0B` | `CloseFrame` | Required |
| profile_update | `0x0C` | `ProfileUpdateFrame` | Optional |
| busy | `0x0D` | `BusyFrame` | Required |
| version_mismatch | `0x0E` | `VersionMismatchFrame` | Required |
| typing_indicator | `0x10` | `TypingIndicatorFrame` | Optional |
| read_receipt | `0x11` | `ReadReceiptFrame` | Optional |
| reaction | `0x12` | `ReactionFrame` | Optional |
| file_transfer | `0x13` | `FileTransferFrame` | Capability-gated |
| edit_message | `0x14` | `EditMessageFrame` | Optional |
| delete_message | `0x15` | `DeleteMessageFrame` | Optional |
| wipe | `0x16` | `WipeFrame` | Required |
| file_probe | `0x17` | `FileProbeFrame` | Capability-gated |
| file_resume | `0x18` | `FileResumeFrame` | Capability-gated |
| file_complete | `0x19` | `FileCompleteFrame` | Capability-gated |
| file_cancel | `0x1A` | `FileCancelFrame` | Capability-gated |
| ephemeral_media | `0x1B` | `EphemeralMediaFrame` | Capability-gated |
| group_control | `0x1C` | `GroupControlFrame` | Capability-gated |
| group_message | `0x1D` | `GroupMessageFrame` | Capability-gated |

## Unknown-Frame Behavior

- Unknown optional frames may be ignored only after a redacted diagnostic event
  exists for that path.
- Unknown required or critical frames must reject the operation/session with a
  protocol error.
- Current legacy decoder fails closed on unknown frame type with
  `ProtocolException`.

## Upgrade Policy

- Bump minor for backward-compatible optional frame additions.
- Bump major for incompatible decoding or semantic changes.
- Envelope support requires capability negotiation and a dual-codec migration.
