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

### T-5: Phone-Hash Enumeration (Contacts Matching Oracle)
- **Description**: Phone numbers are hashed with a per-deployment HMAC salt before ever leaving a device (see ADR-017), but `POST /contacts/match` is inherently an oracle answering "is number X a Helix user on this server?" to any caller who can compute the same hash. A per-server salt does not stop an attacker who can call the unauthenticated `GET /contacts/discovery-salt` endpoint from precomputing a table against the roughly 10^10 E.164 keyspace for a given country code and then querying `/contacts/match` to test candidates. This is the same limitation pre-enclave Signal had, and is an **accepted, documented risk**, not a gap awaiting a fix.
- **Mitigation**: `/contacts/match` (unlike the salt endpoint) requires authentication - no anonymous calls. It is rate-limited per account (`contactsMatchDailyLimit`) and batch-capped (`contactsMatchBatchLimit`, `backend/lib/src/modules/contacts.dart`). Accounts can opt out of being matchable at all via `account_privacy.phone_discoverable`. Only match-request *volume* is logged, never the hashes themselves. Cross-server enumeration is not possible: each Helix Remote server has an independent salt, so a hash computed against one server's salt is meaningless against another's.

### T-6: OTP/Invite Code Interception (Explicit Placeholder, Not Real Delivery)
- **Description**: Phone verification codes and invite-redemption codes are returned directly in the HTTP response body and shown to the user via a self-fired local notification, rather than delivered out-of-band over SMS or a comparable channel. Anyone who can observe the HTTPS response (a compromised device, a debugging proxy with the user's consent, etc.) sees the code. This is an explicit, deliberate placeholder pending real SMS/push-based delivery, not a claim that this transport is secure - see the distinct on-screen caution next to the OTP step in the mobile app.
- **Mitigation**: Codes are single-use and short-lived (OTP challenges expire quickly; invite credentials expire after 7 days). OTP verification attempts are rate-limited per `phone_hash`. Registration binds the OTP and invite code into the signed registration transcript (`_registrationTranscriptV3`), so a leaked code cannot be replayed against a different account identity or invite without a fresh, correctly-signed transcript. This does not mitigate interception of the code itself before use - that gap is accepted until real out-of-band delivery ships.
