# Helix Remote Product Contract

Status: rewritten at Phase X (2026-10) for the v2 architecture.

Helix Remote is a persistent, end-to-end encrypted messaging application that allows communication
across the public internet.

## 1. Scope and target
- **Purpose**: Internet-scale encrypted conversations, file sharing, a WhatsApp-style people list
  (anyone can message or call anyone who has not blocked them; there are no contact requests),
  groups, and audio/video calling (1:1; group calls are not built).
- **Audience**: Long-term remote collaboration and private user-to-user communications.
- **Infrastructure**: A stateless Dart server (REST and WebSocket) over PostgreSQL 17, organised as
  one module per area, run as one or more nodes behind a reverse proxy. Helix Global runs on the
  operator's PC; anyone can run a personal server.

## 2. Retention and persistence policy
- **Chat history**: stored in a local SQLCipher database on the device, decrypted once on arrival
  into structured rows. It persists until the person deletes it.
- **Server mailboxes**: encrypted message envelopes are held per recipient device until that device
  acknowledges them, then deleted; undelivered envelopes expire after 30 days. The server keeps no
  history and no conversation table.
- **Attachments**: ciphertext objects with random ids, on the server's local disk (or an S3-compatible
  store), expiring after 30 days. There is no server-side link between an object and a message.
- **Chat history backup**: an encrypted, text-only copy of the history, one per account, so a device
  signed in with the password can restore it; the server cannot read it (`BACKUP_RECOVERY.md`).
- **Account deletion**: purges the account, devices, prekeys, mailboxes, profile, backups, attachments
  and sessions from the server (`RETENTION_AND_DELETION.md`). External recipient copies and
  user-exported files are outside deletion guarantees.

## 3. Cryptographic identity
- **Prekeys**: public keys and certified device descriptors are uploaded to the server directory so
  peers can start sessions with an offline device.
- **Multi-device**: a person can have several active devices under one account identity key, added by
  password sign-in or by linking from an existing device. Each device has its own keys, certified by the
  account identity key; a session exists per (local device, remote device) pair.
- **Not externally reviewed**: no claim of audited cryptography is made until one exists
  (`PRIVACY_CLAIM_MATRIX.md`).
