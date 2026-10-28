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
  days.** There is no server-side history and no conversation table. A device keeps at most its
  newest 10,000 undelivered envelopes; older ones go earlier (since 2026-10-09). With
  `HELIX_DEVICE_INACTIVE_DAYS` set, a device unused for that long is revoked and its mailbox purged
  (never an account's most recently used device).
- Attachments: 30 days from upload, or 90 days when the account had Orbit Premium at upload (ADR-035; the
  length is fixed at upload, so a plan that ends deletes nothing early) (backup media 90 days, refreshed by each full backup; avatars and
  group pictures until deleted). Objects have random ids and no link to a message, so there is no
  reference counting: deleting a message does not delete its object, and expiry does. The bytes go
  before the row: a file that cannot be deleted (held open by an antivirus scan) keeps its row and is
  tried again on the next run, and a weekly sweep (`media.sweep_orphans`) deletes stored bytes that
  have had no row for a day.
- Backups: the latest encrypted history backup and full backup, replaced by a higher version. The
  history backup is deleted when the account identity key rotates and with the account.
- Account password: until changed, the identity key rotates (the row is replaced or deleted), or the
  account is deleted.
- Sessions: refresh tokens are stored only as SHA-256 hashes and expire 60 days after issue, are
  revoked when rotated, when the device is signed out or revoked, or on account deletion. Access tokens
  (15 minutes) are not stored.
- Idempotency records 24 hours, send records 7 days, rate-limit buckets 1 hour after last use, call
  metrics 90 days, pending calls 120 seconds.
- Trial marker (ADR-035): the keyed phone hash `billing.trials_used` keeps so a number gets one trial stays
  after the account is deleted (like a banned number's hash); it holds no account id and no number. Per-account
  limit overrides expire on their date (`billing.expire_requests` removes them) and go with the account.
- Payment requests (ADR-035): a request nobody answers becomes `expired` after 7 days; every decided request is
  deleted one year after it was sent (`billing.expire_requests`, hourly). The subscription row, and any request,
  go with the account.
- Audit records (operator actions): one year, deleted daily (`admin.purge_audit`); the account ids in
  them outlive a deleted account by at most that year. Reports: kept while open, as the moderation
  record (they survive account deletion); deleted 180 days after the operator resolves or dismisses
  them (`people.purge_reports`, daily).
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
