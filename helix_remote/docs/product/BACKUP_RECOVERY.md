# Helix Remote Backup and Recovery Contract

Status: Phase F2 implementation evidence
Date: 2026-06-25

## Current App Availability

- Fresh-device recovery is link-first: a new device must be approved by an
  already trusted device, then it can restore the encrypted backup after login.
- The setup UI must not accept a recovery phrase before device trust is
  established because backup download is authenticated and account-owned.
- Existing-session restore after app restart is separate: it uses locally stored
  credentials and refresh-token rotation, not user-entered recovery material.
- Manual release testing must cover device link, backup download, decrypt,
  staging validation, replace-local-state restore, and service reconnect.

## Implemented Behavior

- New devices are linked from an existing active device through a pending device
  link request and an out-of-band verification code.
- A linked device registers its own device public key and must pass the normal
  challenge-login flow before it can access authenticated APIs.
- Active conversation sends require separate ciphertext envelopes for each
  active recipient device, including the sender's other active devices.
- Device revocation marks the device inactive, revokes refresh tokens, records a
  revocation reason, and rejects future access-token use through backend
  middleware.
- Lost-device response revokes the device, revokes refresh tokens, records the
  `LOST_DEVICE` reason, and purges pending mailbox entries for that device.
- Client backup snapshots are versioned independently from backup envelopes and
  attachment manifests. Backup envelope v2 uses Argon2id and AES-256-GCM.
  Legacy PBKDF2 envelope v1 remains readable for compatibility.
- Encrypted backup media objects are uploaded as opaque account-owned
  ciphertext streams with SHA-256 integrity checks, resumable offsets, quotas,
  and retention timestamps.
- Backup upload rejects `backup_key`, `passphrase`, and `recovery_phrase`
  fields. Backup keys are derived client-side and are not recoverable by the
  server.
- Message deletion marks existing backups as requiring a fresh client-side
  encrypted upload. Restores apply message tombstones so deleted messages from
  older snapshots are filtered locally.

## Recovery Phrase and Passkey Policy

- Recovery secrets must be user-owned and must not be sent to the backend.
- Current executable policy accepts either a recovery secret of at least 16
  characters or a phrase with at least 6 non-empty words.
- Backup envelopes record the KDF name, version, and parameters so future
  clients can reject unsupported formats instead of silently restoring
  ambiguous data.
- Backup keys may be wrapped by a platform credential/passkey key and by a
  recovery-secret fallback. Neither wrap exposes the raw backup key to the
  backend.

## What Cannot Be Recovered

- The backend cannot recover a forgotten recovery phrase, passkey credential, or
  client-side backup key.
- The backend cannot decrypt, search, repair, or selectively edit encrypted
  backup payloads.
- Messages or attachments that were never included in an encrypted client backup
  cannot be restored from backup.
- Pending mailbox items for a lost or revoked device are intentionally purged and
  are not recoverable for that device.
- Deleted messages must remain deleted after restore when their tombstones are
  present. If a user restores an old exported file outside the app sandbox, that
  external copy is outside Helix Remote deletion guarantees.
- Independent cryptographic review remains required before production claims
  exceed the implementation evidence in this contract.
