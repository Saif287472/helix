# Helix Remote Product Contract

Helix Remote is a persistent, end-to-end encrypted messaging application that allows communication across the public internet.

## 1. Scope and Target
- **Purpose**: Internet-scale encrypted conversations, file sharing, contacts directory, and audio/video calling.
- **Audience**: Long-term remote collaboration and private user-to-user communications.
- **Infrastructure**: Supported by a modular monolith server running REST and WebSocket gateways.

## 2. Retention & Persistence Policy
- **Chat History**: Stored in a local Remote SQLCipher database on the device. Persists until the user explicitly deletes it.
- **Server Mailboxes**: Encrypted message envelopes are held temporarily in server queues for delivery to offline devices, then permanently deleted upon acknowledgment.
- **Attachments**: Ciphertext files stored securely in object storage (S3) and deleted once all referencing messages are deleted.
- **Account Deletion**: Purges account details, public prekeys, registered device details, active device mailboxes, backups, attachments, reports, and account-specific audit rows from the server directory. External recipient copies and user-exported files are outside deletion guarantees.

## 3. Cryptographic Identity
- **Centralized Prekeys**: Public keys and identity descriptors are uploaded to the server directory so remote peers can establish sessions offline.
- **Multi-Device Support**: Users can link multiple active devices under a single account identity.
