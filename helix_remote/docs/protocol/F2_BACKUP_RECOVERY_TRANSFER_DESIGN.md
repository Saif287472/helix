# F2 Backup, Recovery, And Transfer Design

Status: implemented for Phase F2.

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

## Transfer Archive

Device-to-device migration exports a schema-neutral JSON archive containing a
versioned backup snapshot and chunk metadata. It deliberately avoids copying
the encrypted SQLite file directly so Android and Windows can exchange the same
portable archive format.
