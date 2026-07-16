# Helix Remote Metadata Inventory

Status: Phase 18 implementation evidence  
Date: 2026-06-19

| Category | Stored Fields | Purpose | Retention |
|---|---|---|---|
| Account | account_id, username, public identity key, status, created_at | Account directory and login | Until account deletion |
| Device | device_id, public key, device name, status, push token field, created_at, last_seen_at | Multi-device auth, sync, presence, push routing | Until device revocation or account deletion |
| Contacts | account_id, peer_account_id, nickname, status | Contact, block, and request state | Until removal/block change/account deletion |
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
