# Helix Remote Metadata Inventory

Status: Phase 18 implementation evidence  
Date: 2026-06-19

| Category | Stored Fields | Purpose | Retention |
|---|---|---|---|
| Account | account_id, phone_hash (HMAC-SHA256, never plaintext), public identity key, status, created_at | Account directory and login; phone number is the fixed, permanent identity - there is no plaintext username field and no change-number flow | Until account deletion |
| Device | device_id, public key, device name, status, push token field, created_at, last_seen_at | Multi-device auth, sync, presence, push routing | Until device revocation or account deletion |
| Phone OTP Challenges | challenge_id, phone_hash, code_hash (salted, not plain SHA-256), purpose, attempts, created_at, expires_at, consumed_at | One-time verification during registration; the raw code itself is never stored, only its hash | Short-lived; expires quickly, consumed on use |
| Invite Credentials | invite_id, invite_code_hash, server_address, issuer_type (ADMIN/SYSTEM_GLOBAL), issuer_label, status, created_at, expires_at, redeemed_at, redeemed_by_account_id | Self-hosted admin-issued and Helix Global auto-issued registration gating | Permanent audit trail - rows are never deleted; `EXPIRED` is derived at read time from `expires_at`, not swept |
| Contacts | account_id, peer_account_id, nickname, status | Contact, block, and request state | Until removal/block change/account deletion |
| Phone-Book Name Overrides (device-local only) | peer_account_id, phone_book_name, updated_at | Client-side display-name override learned from contacts sync; never leaves the device, never synced to the server or other devices | Until contacts re-sync or app data reset |
| Privacy | search_discoverable, presence_visibility, last_seen_visibility, profile_version | User privacy controls | Until changed or account deletion |
| Conversations | conversation_id, type, title, members, roles, server sequence | Message routing and history sync | Until conversation/group deletion or account deletion |
| Messages | message_id, conversation_id, sender_account_id, sender_device_id, recipient_device_id, ciphertext, sequence, timestamp | Offline mailbox and sync | Until delivery cursor/deletion/account deletion |
| Attachments | opaque file_id, owner account, size, ciphertext hash, uploaded bytes, status | Encrypted attachment storage | Until no message reference or account deletion |
| Backups | backup_id, version, KDF, salt, key hint, opaque encrypted data, deletion watermark | Client-owned encrypted backup/restore | Until replaced or account deletion |
| Reports | reporter, subject, category, reason code, context hash, status | Abuse handling with minimum necessary evidence | Until resolved retention policy or account deletion |
| Audit | redacted client IP, redacted user-agent marker, action, account/device IDs, timestamp | Security/admin accountability | Operational retention; account rows deleted on account deletion |

## Minimization Rules

- Server APIs store ciphertext or hashes where content evidence is required.
- Push outbox rejects keys such as `plaintext`, `message_text`, `body`,
  `filename`, `backup_key`, `passphrase`, `recovery_phrase`, and `token`.
- Audit logging redacts user-agent and stores only masked IP values.
- Phone numbers are never stored in plaintext anywhere, client or server -
  only the salted `phone_hash`. OTP and invite codes are stored only as
  hashes, never in plaintext, and never logged (see ADR-017's phone/OTP/
  invite redaction addendum).
- `POST /contacts/match` (the phone-hash lookup endpoint) requires
  authentication and is rate-limited/batch-capped per account; only
  match-request volume is logged, never the hashes queried.
