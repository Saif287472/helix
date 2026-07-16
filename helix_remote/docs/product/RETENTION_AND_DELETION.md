# Helix Remote Retention and Deletion

Status: Phase 18 implementation evidence  
Date: 2026-06-19

## Retention Schedule

- Account/profile records: retained until profile edit or account deletion.
- Device records: retained until device revocation or account deletion.
- Contact/block records: retained until changed by the user or account deletion.
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
filesystem paths.

## External Copies

Files exported outside the app sandbox, OS-level backups, screenshots, and
recipient-held decrypted copies are outside Helix Remote deletion guarantees.
