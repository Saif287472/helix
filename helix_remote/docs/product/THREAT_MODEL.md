# Helix Remote Threat Model

## 1. Trust Assumptions
- The central backend monolith is assumed untrusted for content. Message privacy must not depend on server integrity.
- Attachment storage (encrypted blobs on the server's local filesystem, `HELIX_REMOTE_ATTACHMENTS_DIR`) is assumed untrusted.
- Transport infrastructure (HTTPS/WebSockets) is secure, but routing metadata is exposed.

## 2. Threat Scopes & Mitigation Strategies

### T-1: Untrusted Backend Server
- **Description**: Compromised server operator attempting to read conversations or modify key directories.
- **Mitigation**: End-to-end encryption (E2EE) prevents server read. Key rotation warning detects if a user's prekeys are replaced without authorization.

### T-2: Attachment Storage Leakage
- **Description**: Leak of the server's attachment storage directory.
- **Mitigation**: Files are encrypted locally with random symmetric keys before upload. Opaque object IDs hide filenames.

### T-3: Traffic Analysis & Metadata Leakage
- **Description**: Sniffing server ingress to determine who is talking to whom.
- **Mitigation**: Connection metadata is minimized. Mailboxes purge messages instantly upon delivery. Push payloads contain only opaque synchronization triggers.

### T-4: Multi-Device Sync Impersonation
- **Description**: Maliciously adding an unauthorized device to a user's account.
- **Mitigation**: Two paths add a device. (1) Device linking requires out-of-band verification (six-digit code, 10-minute TTL) from an existing active device. (2) Password sign-in (`POST /api/v1/accounts/password/login`) needs only the phone number and password - no OTP and no approval - so the password alone is enough to add a device. It is limited by the per-account lockout (5 wrong attempts lock for 15 minutes, doubling up to 24 hours) and per-IP rate limits, and every other active device gets a durable "new sign-in" event plus a `new_sign_in` push, and can sign the new device out (`/devices/revoke`, `/devices/revoke-others`).
- **Residual risk**: on Helix Global, whoever controls the phone number (e.g. a SIM swap) can sign in by SMS OTP. That path rotates the account identity onto the new device and signs every other device out, so it is visible to the user and to contacts (identity key change), but it is not prevented.

### T-5: Phone-Hash Enumeration (Contacts Matching Oracle)
- **Description**: Phone numbers are hashed with a per-deployment HMAC salt before ever leaving a device (see ADR-017), but `POST /contacts/match` is inherently an oracle answering "is number X a Helix user on this server?" to any caller who can compute the same hash. A per-server salt does not stop an attacker who can call the unauthenticated `GET /contacts/discovery-salt` endpoint from precomputing a table against the roughly 10^10 E.164 keyspace for a given country code and then querying `/contacts/match` to test candidates. This is the same limitation pre-enclave Signal had, and is an **accepted, documented risk**, not a gap awaiting a fix.
- **Mitigation**: `/contacts/match` (unlike the salt endpoint) requires authentication - no anonymous calls. It is rate-limited per account (`contactsMatchDailyLimit`) and batch-capped (`contactsMatchBatchLimit`, `backend/lib/src/modules/contacts.dart`). Accounts can opt out of being matchable at all via `account_privacy.phone_discoverable`. Only match-request *volume* is logged, never the hashes themselves. Cross-server enumeration is not possible: each Helix Remote server has an independent salt, so a hash computed against one server's salt is meaningless against another's.

### T-6: OTP/Invite Code Interception
- **Description**: The phone verification code is delivered by SMS (BulkSMSBD). Anyone who can read the user's SMS (SIM swap, SMS interception, malware with SMS access) can use the code. The code is **never** returned in an HTTP response: a server without a configured SMS provider refuses OTP requests with 503 (`backend/lib/src/modules/auth/phone_otp.dart`). Invite codes (personal servers only; Helix Global has none) are shared by the inviter out of band.
- **Mitigation**: OTP codes are six digits, single-use, expire after 10 minutes, allow 5 verification attempts per challenge, and at most 5 requests per hour per `phone_hash`; the server stores only a SHA-256 of the code. Invite credentials expire after 7 days. Registration binds the OTP and invite into the signed registration transcript (`_registrationTranscript` in `backend/lib/src/modules/auth/registration.dart`), so a leaked code cannot be replayed against a different account identity. Interception of the SMS itself is not mitigated (see the T-4 residual risk).

### T-7: Offline Password Guessing From A Stolen `account_passwords` Table
- **Description**: An attacker who copies the server database gets, per account, the Argon2id salt and parameters, a salted SHA-256 of the HKDF-derived auth key, and the password-wrapped identity private key. They can test password guesses offline, without the lockout.
- **Mitigation**: Each guess costs one full Argon2id run (default m=19456 KiB, t=2, p=1; the server refuses weaker parameters) plus HKDF before it can be compared with the stored hash or tried against the wrapped key, and salts are per account. The password itself is never sent or stored. Residual risk: a weak password can still be found offline; a successful guess yields the account identity private key.

### T-8: Stolen or intercepted recovery code
- **Description**: An administrator's recovery code (`HLX-REC-…`, single use, 48 hours) reaches someone other than the account owner, e.g. a forwarded chat message.
- **Mitigation**: The code alone signs nobody in. The phone number must be the account's, and then either the account password (ordinary sign-in, nothing reset) or - for the destructive reset - the SMS code sent to that number, whenever the server has an SMS provider. Lookups are rate limited per IP and never spend the code; a wrong SMS code does not burn it. Shared links carry the code in the URL fragment, which the browser does not send to the server.
- **Residual risk**: On a server without SMS the code plus the phone number is enough to reset the account, as before; its administrator should deliver codes privately.
