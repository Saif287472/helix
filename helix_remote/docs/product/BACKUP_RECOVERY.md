# Helix Remote Backup and Recovery Contract

Status: rewritten at Phase X (2026-10) for the v2 architecture. Formats are in
`docs/protocol/v2/CRYPTO_V2.md` section 13 (backups) and 2a (device linking); the code is
`packages/helix_remote_engine/lib/src/backup/` and the server's `backup` and `media` modules.
Cryptography here has not been externally reviewed.

## Where history comes from

The v2 server keeps **no message history** (ADR-028). A device that has just signed in gets
its chats back from exactly three places, and the app offers them in this order:

1. **Device-to-device transfer** from another of the person's devices (below).
2. **The automatic encrypted history backup** on the server (below), restored on a device
   that signs in with the password.
3. **The recovery backup**, a second backup sealed under a secret only the person holds.

Messages that arrive after a device is added reach it directly: every send is encrypted
for every active device of every member, including the sender's own other devices.

## Signing in on a new device

- Password sign-in (`POST /v1/auth/password/sign-in`, `docs/protocol/F1_MULTI_DEVICE_TRUST_DESIGN.md`
  for the trust reasoning): no approval is needed. The device unlocks the account identity key
  from the password-wrapped copy and offers to restore (the "restore" step after sign-in, which
  can be skipped).
- QR linking: the new device shows a code, an existing active device approves it
  (`POST /v1/devices/links/{link_id}/approve`, with a safety check), and the provisioning data
  travels through the server sealed. Each device registers its own keys, certified by the
  account identity key.
- Every other device gets a security event and a device-list signal and can revoke the new one.
- The app opens on one Helix Global page (phone number, then password or SMS code, then name and
  terms for new accounts). A personal server is reached through the hidden advanced mode (three taps
  in the bottom-right corner reveal an "Advanced mode" button; a fourth opens it) or a shared link
  `https://helix.agiletechbd.com/open#HLX-...`. A recovery code (`HLX-REC-`) names the server and
  the account; the phone number must match (`POST /v1/auth/recovery/lookup`).
  With a password it is an ordinary password sign-in. Otherwise, `POST /v1/auth/recovery/redeem`
  resets the account onto the new device (a new account identity key, every other device signed
  out) and requires the SMS code whenever the server has an SMS provider.

## Automatic history backup

- Key: HKDF over the account identity private key (`helix.v2.history-backup`), so every device of
  the account can write and read it and nobody else can. AES-256-GCM, gzip inside. The key is never
  stored or sent.
- Content: the text history, with references to media (not the media files themselves).
- Server: `PUT` / `GET /v1/backups/history`, one row per account, at most 16 MiB; the server keeps the
  highest version and refuses a lower one. The archive stops before the frame that would pass the
  limit, so the oldest messages drop out first, and the status says so.
- Merge: a restore adds what is missing and never replaces what is on the device; it is safe to run
  twice. A device that knows less never overwrites a backup that holds more (on a version conflict it
  downloads, merges and uploads on top). A device with an empty history uploads nothing.
- Schedule: once a day, or on demand from Settings > Backup. A "use mobile data" setting is enforced
  in the app at the one place a backup leaves the phone.
- The row is deleted when the account identity key rotates (SMS reset, recovery), because nobody can
  decrypt it any more, and with the account.

## Recovery backup (recovery secret)

- A second, user-secret backup envelope (v3: Argon2id, then a random backup key wrapped by the
  secret) sealed under a recovery secret of at least 20 characters. The app generates one (eight
  groups of four base32 characters, 160 random bits) or accepts a typed one, shows it once, and never
  stores, sends, copies or logs it. Helix cannot recover it.
- Server: `PUT` / `GET /v1/backups/full`. The envelope is refused if any key at any depth is
  `backup_key`, `passphrase` or `recovery_phrase`; its backup-kind media get a 90-day retention that
  each full backup refreshes.
- Session and prekey private state is never backed up. After a restore, peers' first messages fail to
  decrypt and trigger the session reset (CRYPTO_V2.md section 13a); the sender re-sends messages under
  24 hours old.

## Device-to-device transfer

One device sends its history to another of the same account over the server as sealed, resumable
chunks (`transfer_jobs`, the media transfer queue). The receiving device is asked first: offers wait
for the person (accept, decline, pause, resume); nothing downloads by itself.

## What can be recovered with the password

- The account identity private key: the server stores a copy wrapped with a key derived from the
  password (Argon2id, then HKDF; AES-256-GCM). The server cannot unwrap it.
- Text chat history, from the automatic history backup.

## What cannot be recovered

- The server cannot recover a forgotten password, a recovery secret or a backup key. Without the
  password, SMS sign-in on Helix Global (including "Forgot password") moves the account onto the new
  device with a new identity key: the other devices are signed out, and the old wrapped key and the
  history backup become undecryptable and are deleted.
- Media and attachments are not in the automatic history backup. Attachments also expire from the
  server after 30 days.
- Pending mailbox items for a revoked device are purged and are not recoverable for that device.
- Messages that were never part of a backup, or that expired from the mailbox before the device
  collected them (30 days), cannot be restored.
- Deleted messages stay deleted after restore when their tombstones are present. A restored old
  export outside the app sandbox is outside Helix Remote's deletion guarantees.
- Independent cryptographic review remains required before production claims exceed the evidence
  in this contract.
