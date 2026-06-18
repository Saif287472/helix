# Helix Remote Threat Model

## 1. Trust Assumptions
- The central backend monolith is assumed untrusted for content. Message privacy must not depend on server integrity.
- S3-compatible attachment storage is assumed untrusted.
- Transport infrastructure (HTTPS/WebSockets) is secure, but routing metadata is exposed.

## 2. Threat Scopes & Mitigation Strategies

### T-1: Untrusted Backend Server
- **Description**: Compromised server operator attempting to read conversations or modify key directories.
- **Mitigation**: End-to-end encryption (E2EE) prevents server read. Key rotation warning detects if a user's prekeys are replaced without authorization.

### T-2: S3 Attachment Leakage
- **Description**: Public leak of the attachment storage bucket.
- **Mitigation**: Files are encrypted locally with random symmetric keys before upload. Opaque object IDs hide filenames.

### T-3: Traffic Analysis & Metadata Leakage
- **Description**: Sniffing server ingress to determine who is talking to whom.
- **Mitigation**: Connection metadata is minimized. Mailboxes purge messages instantly upon delivery. Push payloads contain only opaque synchronization triggers.

### T-4: Multi-Device Sync Impersonation
- **Description**: Maliciously adding an unauthorized device to a user's account.
- **Mitigation**: Device linking requires out-of-band verification from an existing active device.
