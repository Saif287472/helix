# Helix Remote Bounded Contexts

This document defines the 18 bounded contexts that form the domain model for Helix Remote. In contrast to Helix Local (which uses short-lived RAM-only storage), Helix Remote is designed as a persistent, multi-device distributed system.

---

## 1. Account (P8-001)
*   **Domain Model**: 
    *   `Account` (Entity): Unique account ID, username (canonicalized and hash-scoped), primary public identity key, registration timestamp, account status (Active, Suspended, Pending Deletion).
*   **Operations**:
    *   `RegisterAccount(username, clientPublicIdentityKey)`
    *   `GetAccountProfile(username)` -> Account
*   **Persistence Rules**:
    *   Server: Persistent database row in the `accounts` table.
    *   Client: Scoped local database table for active accounts.
*   **Multi-Device Sync Implications**:
    *   An account is the parent scope for all devices. Linked devices are managed as sub-resources of the account.

## 2. Device (P8-002)
*   **Domain Model**:
    *   `Device` (Entity): Unique device ID (integer assigned by server per account), device name (user-defined), device public key (Ed25519/X25519), push registration token (FCM/APNS), device status (Active, Revoked).
*   **Operations**:
    *   `LinkDevice(accountToken, devicePublicKey, deviceName)` -> Device
    *   `ListDevices(accountId)` -> List<Device>
*   **Persistence Rules**:
    *   Server: `devices` table with foreign key `account_id`.
    *   Client: Stores own device ID and public key in secure storage; caches active sibling devices in local database.
*   **Multi-Device Sync Implications**:
    *   Each device must be independently targetable for ciphertext message delivery (fan-out model). Sibling devices must keep a synchronized list of other devices on the account.

## 3. Key Directory and Prekeys (P8-003)
*   **Domain Model**:
    *   `PreKeyBundle` (Value Object): Device identity key, signed prekey (with server signature), one-time prekeys (OTKs) list.
*   **Operations**:
    *   `UploadPreKeys(deviceId, signedPreKey, oneTimePreKeys)`
    *   `GetPreKeyBundle(targetAccountId, targetDeviceId)` -> PreKeyBundle
*   **Persistence Rules**:
    *   Server: `prekeys` table storing active OTKs, signed prekey, and identity keys. OTKs are deleted atomically on retrieval.
    *   Client: Private keys remain inside secure storage; public prekey states tracked in memory before upload.
*   **Multi-Device Sync Implications**:
    *   Key directory allows asynchronous E2EE session setup (Signal Double Ratchet protocol). Sibling devices maintain independent sessions with recipient devices.

## 4. Contact / Friend Relationship (P8-004)
*   **Domain Model**:
    *   `Contact` (Entity): Peer account ID, local nickname, status (PendingSent, PendingReceived, Accepted, Blocked).
*   **Operations**:
    *   `SendContactRequest(targetUsername)`
    *   `AcceptContactRequest(requestId)`
    *   `RemoveContact(contactId)`
*   **Persistence Rules**:
    *   Server: `contacts` table (composite key: `account_id`, `peer_account_id`).
    *   Client: Cached in local `contacts` table.
*   **Multi-Device Sync Implications**:
    *   Friend status changes are synchronized via the operation queue to ensure all sibling devices reflect identical contact list states.

## 5. Conversation (P8-005)
*   **Domain Model**:
    *   `Conversation` (Entity): Unique conversation ID (UUID), type (OneToOne, Group), conversation key metadata (encrypted for each device), title, created timestamp, last activity sequence.
*   **Operations**:
    *   `CreateConversation(type, participantAccountIds)` -> Conversation
    *   `GetConversationList()` -> List<Conversation>
*   **Persistence Rules**:
    *   Server: `conversations` and `conversation_participants` tables.
    *   Client: Local `conversations` table.
*   **Multi-Device Sync Implications**:
    *   Conversation creation and participant membership must sync across all client devices.

## 6. Message Event (P8-006)
*   **Domain Model**:
    *   `MessageEvent` (Entity): Unique event ID (UUID), conversation ID, sender account ID, sender device ID, recipient device ID, ciphertext payload, server sequence number, client timestamp.
*   **Operations**:
    *   `SendMessage(conversationId, recipientDeviceCiphertexts)`
    *   `FetchMessageHistory(conversationId, cursor, limit)` -> List<MessageEvent>
*   **Persistence Rules**:
    *   Server: `messages` table storing encrypted ciphertext envelopes (ephemerally or persistently based on server retention policy).
    *   Client: Decrypted locally and stored in the encrypted local database.
*   **Multi-Device Sync Implications**:
    *   Messages are fanned out to all active devices of all participants. Monotonically increasing `server_sequence` numbers per conversation are used to order messages and detect gaps.

## 7. Receipt / Reaction / Edit / Delete Event (P8-007)
*   **Domain Model**:
    *   `MessageUpdateEvent` (Entity): Target message ID, event type (DeliveryReceipt, ReadReceipt, Reaction, Edit, Delete), update payload (e.g. reaction emoji, edited ciphertext, deleted tombstone), server sequence.
*   **Operations**:
    *   `SendReceipt(messageId, type)`
    *   `ReactToMessage(messageId, emoji)`
    *   `EditMessage(messageId, newCiphertext)`
    *   `DeleteMessage(messageId)`
*   **Persistence Rules**:
    *   Server: Appended as updates to the event log.
    *   Client: Updates the local message record and flags it.
*   **Multi-Device Sync Implications**:
    *   Read/delivery status and edits are broadcast to all devices of participants. Client filters duplicate receipts and resolves edits using client-side clocks and monotonic sequences.

## 8. Attachment (P8-008)
*   **Domain Model**:
    *   `AttachmentManifest` (Value Object): Opaque file ID, size, encrypted file hash, media MIME type, client-side encryption key/IV (never stored on server).
*   **Operations**:
    *   `RequestUploadUrl(fileSize, fileHash)` -> PreSignedUploadUrl
    *   `RequestDownloadUrl(fileId)` -> PreSignedDownloadUrl
*   **Persistence Rules**:
    *   Server: Opaque metadata row in `attachments` table; binary ciphertext blob stored in S3 object storage.
    *   Client: Scoped file paths in local app-cache folder; manifest cached in local DB.
*   **Multi-Device Sync Implications**:
    *   The file encryption key is passed within the encrypted message envelope. Only devices receiving the message envelope can decrypt the downloaded attachment.

## 9. Group and Membership (P8-009)
*   **Domain Model**:
    *   `Group` (Entity): Conversation ID, group name, avatar URI, group public key.
    *   `Membership` (Entity): Account ID, role (Owner, Admin, Member), joined sequence number.
*   **Operations**:
    *   `CreateGroup(name, members)` -> Group
    *   `UpdateMemberRole(groupId, targetAccountId, newRole)`
*   **Persistence Rules**:
    *   Server: `groups` and `group_memberships` tables.
    *   Client: Scoped local `groups` table.
*   **Multi-Device Sync Implications**:
    *   Admin changes and role updates are event-sourced. Sibling devices sync the membership state via the central operation log.

## 10. Call Session and Call History (P8-010)
*   **Domain Model**:
    *   `CallSession` (Value Object): Call ID, conversation ID, initiator account ID, WebRTC offer/answer, ICE candidates, call status.
    *   `CallHistoryEntry` (Entity): Call ID, conversation ID, direction (Incoming, Outgoing, Missed), start time, duration.
*   **Operations**:
    *   `InitiateCall(conversationId)` -> CallSession
    *   `SendCallSignal(callId, type, candidateOrSdp)`
*   **Persistence Rules**:
    *   Server: Signaling tokens are ephemeral; call history metadata is persisted in `call_history` table.
    *   Client: Local call history cached in `call_history` table.
*   **Multi-Device Sync Implications**:
    *   Call alerts ring all active devices of the recipient. Once a device accepts the call, a "Cancel/AcceptedElsewhere" signal is pushed to the other devices.

## 11. Presence (P8-011)
*   **Domain Model**:
    *   `PresenceStatus` (Value Object): Account ID, status (Online, Offline, Idle), custom status text, last active timestamp, typing state (conversation specific).
*   **Operations**:
    *   `PublishPresence(status)`
    *   `SubscribeToPresence(targetAccountIds)`
*   **Persistence Rules**:
    *   Server: RAM only (Redis cache). Never persisted to disk.
    *   Client: Kept in memory; never persisted to local SQLite.
*   **Multi-Device Sync Implications**:
    *   Typing state and presence are routed via high-speed, ephemeral WebSocket channels. Typing status times out automatically.

## 12. Notification Registration (P8-012)
*   **Domain Model**:
    *   `NotificationToken` (Value Object): Device ID, provider (FCM, APNS), token string, locale, active sandbox flag.
*   **Operations**:
    *   `RegisterPushToken(deviceId, provider, token)`
    *   `UnregisterPushToken(deviceId)`
*   **Persistence Rules**:
    *   Server: `push_registrations` table.
    *   Client: Device secure storage.
*   **Multi-Device Sync Implications**:
    *   Each device registers its own push token. Server triggers push notifications independently for each target device.

## 13. Sync Cursor and Operation Queue (P8-013)
*   **Domain Model**:
    *   `SyncCursor` (Entity): Device ID, conversation ID (or global scope), last synchronized server sequence number.
*   **Operations**:
    *   `GetSyncEvents(sinceSequence)` -> List<MessageEvent>
    *   `CommitSyncCursor(sequence)`
*   **Persistence Rules**:
    *   Server: `device_sync_cursors` table.
    *   Client: Local cursor tracking.
*   **Multi-Device Sync Implications**:
    *   Crucial for multi-device catchup. When a device reconnects, it sends its latest cursor sequence to fetch missed messages from the server mailbox.

## 14. Device Revocation (P8-014)
*   **Domain Model**:
    *   `RevocationRecord` (Value Object): Revoked device ID, timestamp, cryptographic proof of revocation signature.
*   **Operations**:
    *   `RevokeDevice(targetDeviceId, signature)`
*   **Persistence Rules**:
    *   Server: Updates `devices` status to Revoked; archives revocation proof in `device_revocations` audit log.
    *   Client: Deletes session keys associated with the revoked device.
*   **Multi-Device Sync Implications**:
    *   Active devices are notified immediately via WebSocket of the revocation to prevent sending further ciphertext messages targetable to the revoked device.

## 15. Backup / Recovery (P8-015)
*   **Domain Model**:
    *   `EncryptedBackup` (Entity): Backup ID, account ID, cipher text metadata, key derivation version, data payload.
*   **Operations**:
    *   `UploadBackup(encryptedPayload, metadata)`
    *   `DownloadBackup()` -> EncryptedBackup
*   **Persistence Rules**:
    *   Server: `account_backups` metadata table; payload stored in object storage.
    *   Client: Key derived client-side via PBKDF2/Argon2 from the recovery passphrase; never sent to server.
*   **Multi-Device Sync Implications**:
    *   Backup can be restored on a new device to recover conversation history. Sibling devices are notified that a restore took place.

## 16. Abuse Prevention and Blocking (P8-016)
*   **Domain Model**:
    *   `BlockRecord` (Entity): Account ID, blocked account ID, timestamp.
*   **Operations**:
    *   `BlockUser(targetAccountId)`
    *   `UnblockUser(targetAccountId)`
*   **Persistence Rules**:
    *   Server: `user_blocks` table.
    *   Client: Cached in local SQLite.
*   **Multi-Device Sync Implications**:
    *   Block lists are synchronized to all sibling devices immediately to drop unsolicited incoming signals.

## 17. Account / Data Deletion (P8-017)
*   **Domain Model**:
    *   `DeletionRequest` (Value Object): Account ID, verification token, deletion schedule timestamp.
*   **Operations**:
    *   `RequestAccountDeletion(verificationToken)`
*   **Persistence Rules**:
    *   Server: Marks account for deletion; background worker deletes database entries, attachments, and backups after the retention window closes.
    *   Client: Local client triggers self-wipe of all persistent folders.
*   **Multi-Device Sync Implications**:
    *   Triggers immediate logout/wipe commands to all active devices linked to the account.

## 18. Operational Audit (P8-018)
*   **Domain Model**:
    *   `AuditLogEntry` (Entity): Event ID, timestamp, account ID, device ID, action (e.g. login, device_added, password_changed, keys_rotated), client IP (redacted after retention), user agent.
*   **Operations**:
    *   `GetSecurityLogs()` -> List<AuditLogEntry>
*   **Persistence Rules**:
    *   Server: Append-only audit table. Never logs plaintext message content or cryptographic keys.
    *   Client: Stores own security audit log in database.
*   **Multi-Device Sync Implications**:
    *   Security log updates are synchronized so users can audit device logins from any active client.
