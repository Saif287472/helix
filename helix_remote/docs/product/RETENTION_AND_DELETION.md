# Helix Remote Retention and Deletion

Status: Phase 18 implementation evidence  
Date: 2026-06-19

## Retention Schedule

- Account/profile records: retained until profile edit or account deletion.
- Device records: retained until device revocation or account deletion.
- Phone OTP challenges: short-lived - expire quickly and are marked consumed
  on use; never retained as a standing record of a user's phone activity.
- Invite credentials: retained permanently as an audit trail (admin-issued and
  Helix-Global-auto-issued alike) regardless of redemption or expiry - rows
  are never deleted, and `EXPIRED` status is derived at read time rather than
  swept. This is an intentional exception to "delete when no longer needed":
  the record is the audit trail, not user content, and contains no phone
  number or invite code (only the invite's hash and, once redeemed, the
  redeeming account ID).
- Contact/block records: retained until changed by the user or account deletion.
- Phone-book name overrides: device-local only, never sent to or retained by
  the server; retained on-device until the next contacts re-sync overwrites
  them or the app's local data is reset.
- Message mailbox rows: retained for device sync until cursor/deletion/account
  deletion. Message payloads are ciphertext-only in supported server APIs.
- Attachments: encrypted objects remain while referenced by messages; orphan and
  unreferenced cleanup is implemented by the attachment lifecycle helpers.
- Backups: the latest opaque encrypted backup is retained until replaced or
  account deletion. Message deletion marks a backup as requiring reupload.
- Audit records: retained for security accountability with redacted IP/user-agent
  fields. Account-specific rows are removed by account deletion.

## Account Deletion Behavior

The account deletion endpoint requires the authenticated user to send
`DELETE <account_id>`. On success it removes:

- Account row and profile data.
- Registered devices, pending link requests, revocation records, refresh tokens,
  prekeys, and device mailboxes.
- Contacts, contact requests, privacy settings, reports, attachments, backups,
  and account-specific audit rows.

The endpoint does not delete Local product data and does not touch arbitrary
filesystem paths. It also does not touch `invite_credentials` rows: if the
deleted account redeemed an invite, that invite's `redeemed_by_account_id`
continues to reference the now-deleted account ID rather than being nulled
out or removed. This is an intentional gap in cascade coverage for the sake
of the permanent invite audit trail (see above) - unlike the Audit category,
whose account-specific rows are removed by account deletion.

## External Copies

Files exported outside the app sandbox, OS-level backups, screenshots, and
recipient-held decrypted copies are outside Helix Remote deletion guarantees.
