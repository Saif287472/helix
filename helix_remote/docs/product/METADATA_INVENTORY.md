# Helix Remote Metadata Inventory

Status: Phase 18 implementation evidence  
Date: 2026-06-19 (updated 2026-09: passwords, sessions, history backup)

| Category | Stored Fields | Purpose | Retention |
|---|---|---|---|
| Account | account_id, phone_hash (HMAC-SHA256), `phone_last4` display hint, public identity key, status, created_at | Account directory and login; phone number is the fixed, permanent identity - there is no plaintext username field and no change-number flow. `phone_last4` (historical column name) holds the account's phone number, for the admin console, account security and spam protection | Until account deletion |
| Account Password | kdf_params (Argon2id cost), kdf_salt, auth_hash (salted SHA-256 of the HKDF-derived auth key), auth_hash_salt, wrapped_identity_key (identity private key sealed with a key derived from the password), identity_public_key, failed_attempts, locked_until, created_at, updated_at (`account_passwords`) | Password sign-in on new devices and lockout; the password itself is never sent or stored | Until changed, identity-key rotation, or account deletion (cascade) |
| Refresh Tokens | SHA-256 of the token, account_id, device_id, expiry, revoked flag (`refresh_tokens`) | Device sessions: access token 1 h (not stored), refresh token 60 days sliding, rotated on every refresh | Until expiry, revocation, device sign-out, or account deletion |
| Chat History Backup | blob (gzip + AES-GCM ciphertext, text messages only), size_bytes, identity_public_key, updated_at (`history_backups`) | Automatic encrypted text-history restore on a device signed in with the password | Replaced on each upload; deleted on identity-key rotation or account deletion (cascade) |
| Device | device_id, public key, device name, status, push token field, created_at, last_seen_at | Multi-device auth, sync, presence, push routing | Until device revocation or account deletion |
| Phone OTP Challenges | challenge_id, phone_hash, code_hash (unsalted SHA-256 of the six-digit code), purpose, attempts, created_at, expires_at, consumed_at | One-time verification for sign-up, SMS sign-in, and password changes; the raw code itself is never stored, only its hash | Expires after 10 minutes, consumed on use |
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
- The server identifies accounts only by the salted `phone_hash`. The raw
  phone number is sent to the server once per OTP request
  (`POST /api/v1/accounts/phone/otp/request`) so it can be checked against the
  hash and passed to the SMS gateway (BulkSMSBD) for delivery; it is not
  persisted from that request (registration stores the number in
  `phone_last4`, above). OTP and invite codes are stored only as hashes and
  never logged (see ADR-017's phone/OTP/invite redaction addendum).
- `POST /contacts/match` (the phone-hash lookup endpoint) requires
  authentication and is rate-limited/batch-capped per account; only
  match-request volume is logged, never the hashes queried.
