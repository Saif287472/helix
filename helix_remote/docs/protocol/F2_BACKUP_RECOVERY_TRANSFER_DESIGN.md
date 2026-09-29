# F2 Backup, Recovery, And Transfer Design

Status: implemented for Phase F2. The recovery-secret backup below is still
current. Since 2026-09 a new device normally signs in with the account password
instead of trusted-device approval, and an automatic text-only history backup
exists alongside this one (see the last section). Schema numbers here are
historical (backend now 47, local 31).

## Capability And Versions

Phase F2 adds:

- `helix.remote.encrypted-backup-recovery.v2`
- `helix.remote.backup-media-objects.v1`
- `helix.remote.backend-schema.v21`

Backup envelopes, local snapshots, and attachment/media manifests are versioned
independently:

- Backup envelope: `version = 2`
- Snapshot: `snapshot_version = 2`
- Attachment manifest: `attachment_manifest_version = 1`
- Transfer archive: `archive_version = 1`

Legacy backup envelope v1 with `PBKDF2-HMAC-SHA256-100000` remains readable.
New backups are written with Argon2id using the current interactive profile
`Argon2id-v1-m8192-t2-p1`.

## Snapshot Scope

Snapshot v2 includes account records, devices, contacts, contact requests,
conversations, members, messages, receipts, revisions, attachment metadata,
groups, group epoch keys, group invites, call history, and tombstones.

Snapshot v2 explicitly excludes access tokens, refresh tokens, push tokens,
runtime locks, sync cursors, processed-event caches, pending operations,
quarantine rows, local prekey private material, trusted-device runtime cache,
and crypto-session chain state. Restores use `replace_local_state` semantics.

## Restore

The app decrypts backup envelopes client-side, validates the decoded snapshot,
restores it into an in-memory staging database, and only then applies it to the
active database. The active restore runs inside the existing savepoint; failed
validation, unsupported versions, wrong recovery secrets, and corrupted
ciphertext leave the previous local state intact.

After restore, tombstones are applied immediately so deleted messages remain
deleted even when an older backup is restored.

## Backup Media Objects

Encrypted attachment/media backup bytes are stored as independent opaque media
objects through:

- `POST /api/v1/backups/media`
- `GET /api/v1/backups/media/status/{objectId}`
- `PUT /api/v1/backups/media/{objectId}?offset=...`
- `GET /api/v1/backups/media/{objectId}`

Objects are account-owned, resumable, quota-limited, integrity-checked with
SHA-256, and retained with an explicit retention timestamp. The server stores
only ciphertext bytes and object metadata.

## Recovery Methods

The crypto package supports two backup-key wrapping paths:

- recovery-secret wrap using Argon2id-derived AES-GCM
- platform credential/passkey wrap using AES-GCM over platform-held key bytes

The server never receives recovery secrets, passkeys, unwrapped backup keys, or
platform credential material. The recovery-secret wrap remains present so
device loss does not permanently destroy backup access.

## Password-Wrapped Identity Key

`account_passwords.wrapped_identity_key` (backend migration 46) holds the account
identity private key encrypted with a wrap key the app derives from the
password (Argon2id m=19456 KiB, t=2, p=1, 64-byte output, split by HKDF into an
auth key that is sent and a wrap key that never leaves the device; AES-256-GCM,
AAD bound to the identity public key). `POST /api/v1/accounts/password/login`
returns it so a new device joins as the same account. Files:
`backend/lib/src/modules/auth/password.dart`, `app/lib/app/password_vault.dart`,
`app/lib/app/composition_root/password_auth.dart`. The row is deleted when the
identity key rotates.

## Automatic History Backup

A second, automatic backup holds text history only:
`PUT`/`GET /api/v1/backups/history`, stored in `history_backups` (backend
migration 47, 16 MB limit). Key = HKDF(identity private key,
`helix.remote.history-backup.v1`); gzip + AES-GCM with AAD bound to the
identity public key (`app/lib/app/history_backup_codec.dart`). Each device
merges (union by message ID, local wins, cap 200,000 messages) and uploads at
most daily at app start or on demand from Settings > Account; a password
sign-in restores it before the app opens. It carries no media and is deleted
server-side when the identity key rotates. See
`docs/product/BACKUP_RECOVERY.md`.

## Transfer Archive

Device-to-device migration exports a schema-neutral JSON archive containing a
versioned backup snapshot and chunk metadata. It deliberately avoids copying
the encrypted SQLite file directly so Android and Windows can exchange the same
portable archive format.
