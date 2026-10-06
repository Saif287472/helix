# Helix Remote Retention and Deletion

Status: rewritten at Phase X (2026-10) for the v2 server (Postgres, one schema per module).
The table-by-table inventory with fields is `METADATA_INVENTORY.md`; this file is the retention and
deletion contract. The v1 version is in git history (tag `v1-final`).

## Retention schedule

- Account and profile records: until the person edits them or deletes the account. The profile
  itself is ciphertext.
- Device records: until the account is deleted. A revoked device keeps a row (status, time, reason)
  but loses its session, push token and prekeys immediately.
- Phone codes (challenges): expire after 10 minutes, purged after 2 days; the code is stored only as a
  peppered hash.
- Invites: valid 7 days; unredeemed expired rows are purged after 30 days. Redeemed invites stay as an
  audit trail (a hash and the redeeming account id; no phone number or code). Recovery codes: valid
  48 hours; expired rows purged.
- Contacts and blocks: until changed by the person or the account is deleted. Phone-book names are
  device-local only and never sent to the server.
- **Message mailbox rows: deleted when the device acknowledges them; undelivered rows expire after 30
  days.** There is no server-side history and no conversation table.
- Attachments: 30 days from upload (backup media 90 days, refreshed by each full backup; avatars and
  group pictures until deleted). Objects have random ids and no link to a message, so there is no
  reference counting: deleting a message does not delete its object, and expiry does.
- Backups: the latest encrypted history backup and full backup, replaced by a higher version. The
  history backup is deleted when the account identity key rotates and with the account.
- Account password: until changed, the identity key rotates (the row is replaced or deleted), or the
  account is deleted.
- Sessions: refresh tokens are stored only as SHA-256 hashes and expire 60 days after issue, are
  revoked when rotated, when the device is signed out or revoked, or on account deletion. Access tokens
  (15 minutes) are not stored.
- Idempotency records 24 hours, send records 7 days, rate-limit buckets 1 hour after last use, call
  metrics 90 days, pending calls 120 seconds.
- Audit records (operator actions) and reports: operational retention. Reports survive account deletion
  as the moderation record until resolved.
- Logs: JSON lines on stdout and an optional file (`HELIX_LOG_FILE`); rotation is the operator's.

## Account deletion

`DELETE /v1/account` (the compliance module) needs fresh proof of ownership: the current password,
or a fresh verification of the account's phone number, or, for an account with neither, a device-key
signature. A session token alone deletes nothing. On success it publishes `identity.account_deleted`
and every module purges its own rows, so no foreign key spans schemas:

- identity: the account, its devices, refresh tokens, push tokens, password, recovery codes and
  security events; keys: prekeys; messaging: mailbox rows addressed to its devices; people: profile,
  privacy, blocks, contacts and the discovery entry; media: its objects (the bytes too); backup: both
  backups; groups: its memberships (with owner succession) and requests.
- Not deleted: the phone-hash ban list (an operator ban survives), reports the account filed or is the
  subject of, and the operator's audit rows that name its ids. Redeemed-invite rows keep the redeeming
  account id.

The app then wipes its local database, keys and attachment cache.

## External copies

Files exported outside the app sandbox, OS-level backups, screenshots, and recipient-held decrypted
copies are outside Helix Remote's deletion guarantees. Disappearing messages and view-once content are
enforced by the recipient's app; a person can still screenshot them.
