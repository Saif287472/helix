# Helix Remote — Core Feature Roadmap

> **Notice:** The WhatsApp-inspired feature roadmap (141 features) is officially deprecated and archived. Helix is **not** trying to be WhatsApp, and we are not implementing business features, payments, stories/status updates, channels, or communities. 
>
> Helix is a secure, private, self-hosted, and federated communication platform. The development focus is strictly on the **20 features that matter**.

---

## The 20 Features That Matter

### Core Security & Authentication
1. **Secure Registration & Auth**: Signed-challenge registration and JWT-based authentication (access/refresh tokens).
2. **Multi-Device Support**: Secure device enrollment, linking, and background state synchronization.
3. **Encrypted Local Storage**: SQLCipher-encrypted SQLite database on client devices for message storage.
4. **Opaque Push Notifications**: Minimal, metadata-blind push payloads (FCM/APNs) that wake the client to fetch messages.
5. **Encrypted Database Backup**: Backup and restore of client message history using a local recovery key.

### Messaging Workflows
6. **1-on-1 Text Messaging**: Core E2E-encrypted chat.
7. **Media Sharing**: Secure transfer of images and documents.
8. **Voice Messages**: Recording, sending, and playing audio notes.
9. **Group Messaging**: Group chat creation, administration, and secure member invites.
10. **Real-time Status**: Presence state (online/offline) and typing indicators.
11. **Message Status**: Sent, delivered, and read receipts.
12. **Message Editing**: Editing messages with a clean version history.
13. **Message Deletion**: Support for "delete-for-me" and "delete-for-everyone".
14. **Replies & Forwarding**: Basic message threads and simple message forwarding.
15. **Contacts Management**: Adding users by display name/username and blocking/unblocking contacts.
16. **Client-Side Search**: Full-text indexing of conversations using SQLite FTS5.

### Voice & Video Calling
17. **1-on-1 Voice & Video Calls**: WebRTC calling.

### Platform Compliance & Operations
18. **GDPR Privacy Compliance**: Self-service data export and complete account deletion.
19. **Custom Client Theming**: Material 3 theme engine, accent colors, AMOLED dark mode, and localization.
20. **Server Health & Diagnostics**: Server-side `/health` and `/ops` endpoints for monitoring.
