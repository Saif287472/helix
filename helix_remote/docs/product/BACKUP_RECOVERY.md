# Helix Remote Backup and Recovery Contract

Status: Phase F2 implementation evidence
Date: 2026-06-25 (updated 2026-09 for password sign-in and the automatic
history backup)

## Current App Availability

- A fresh device signs in with phone number + password
  (`POST /api/v1/accounts/password/login`, see
  `docs/protocol/F1_MULTI_DEVICE_TRUST_DESIGN.md`). No trusted-device approval
  is needed; the device unlocks the account identity key from the
  password-wrapped copy and restores the automatic text history backup (below)
  before the app opens. Linking from an already trusted device still works as
  an alternative.
- The manual encrypted backup is restored only after sign-in, because backup
  download is authenticated and account-owned.
- Existing-session restore after app restart is separate: it uses locally stored
  credentials and refresh-token rotation, not user-entered recovery material.
- Manual release testing must cover password sign-in on a second device,
  history-backup restore, device link, backup download, decrypt, staging
  validation, replace-local-state restore, and service reconnect.

> Sign-in (2026-09-28): the app opens on a single Helix Global page (phone number, then password or SMS code, then name/terms for new accounts). A personal server is reached through the hidden advanced mode (three taps in the bottom-right corner reveal an "Advanced mode" button; a fourth opens it) or through a shared link `https://helix.agiletechbd.com/open#HLX-…`. Advanced mode has one code field that tells an invite (`HLX-INV-`) from a recovery code (`HLX-REC-`), then the same phone and password/SMS pages. A recovery code names the server and account; the phone number must match the account (`POST /accounts/recovery/lookup`). With a password it is an ordinary password sign-in - nothing is reset. Without one, or via "Forgot password", `POST /accounts/recovery/redeem` resets the account onto the new device (new identity key, all other devices signed out) and requires the SMS code whenever the server has an SMS provider.

## Implemented Behavior

- New devices sign in with the account password (no approval needed), or are
  linked from an existing active device through a pending device link request
  and an out-of-band verification code.
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

## Automatic Chat History Backup (Text Only)

Separate from the manual recovery-secret backup above, every account has an
automatic encrypted backup of its text history, so a device that signs in with
the password gets its chats back.

- Key: HKDF-SHA256 over the account identity private key, info
  `helix.remote.history-backup.v1` (`app/lib/app/history_backup_codec.dart`).
  Every device of the account holds that key (its own, or the one it unwrapped
  with the password), so nothing new has to be remembered.
- Format: JSON snapshot, gzip, AES-256-GCM with AAD bound to the identity public
  key. Text messages only; no media or attachments.
- Merge: each device downloads the stored copy, merges it with local history
  (union by message ID, the local copy wins, capped at 200,000 messages) and
  uploads the result, so any device may write it.
- Schedule: uploaded at most once a day at app start, or on demand from
  Settings > Account (`app/lib/app/composition_root/history_backup.dart`).
- Restore: on password sign-in, before the app opens.
- Server: `PUT` / `GET /api/v1/backups/history`, one row per account in
  `history_backups` (blob, size, identity public key), 16 MB limit (413 above
  it). The server cannot decrypt it. When the account identity rotates (SMS
  reset, recovery) the row is deleted, because nobody can decrypt it any more;
  account deletion removes it by cascade.

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

## What Can Be Recovered With The Password

- The account identity private key: the server stores a copy wrapped with a
  key derived from the password (Argon2id, then HKDF; AES-256-GCM, AAD bound to
  the identity public key). The server cannot unwrap it.
- Text chat history, from the automatic history backup.

## What Cannot Be Recovered

- The backend cannot recover a forgotten recovery phrase, passkey credential,
  client-side backup key, or password. Without the password, SMS-OTP sign-in on
  Helix Global (including "Forgot password") moves the account onto the new
  device with a new identity key: the other devices are signed out and the old
  wrapped key and history backup become undecryptable and are deleted.
- Media and attachments are not in the automatic history backup.
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
