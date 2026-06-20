# Helix Remote Backup and Recovery Contract

Status: Phase 17 implementation evidence  
Date: 2026-06-19

## Current App Availability

- Fresh-device account restore is not available from the Remote setup screen in
  the current build.
- The setup UI must not accept a recovery phrase, restore code, passkey, or
  backup secret until the full device-link and backup-restore workflow is wired
  end to end.
- Existing-session restore after app restart is separate: it uses locally stored
  credentials and refresh-token rotation, not user-entered recovery material.
- Manual release testing must treat fresh-device restore as unavailable unless a
  later phase updates this contract and adds executable app-level evidence.

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
- Client backup snapshots are versioned and are intended to be encrypted before
  upload. The backend stores only opaque encrypted backup data plus metadata
  required for compatibility and user key hints.
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
- Backup envelopes record the KDF name and version so future clients can reject
  unsupported formats instead of silently restoring ambiguous data.

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
- Production database-at-rest encryption and independent cryptographic review
  remain externally blocked as documented in the master plan. Do not describe
  this Phase 17 slice as production-reviewed cryptography.
