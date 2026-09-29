# ADR 017: Remote Metadata Minimization and Privacy Logging

Status: accepted  
Date: 2026-06-19  

## Context
Centralized messaging backends are vulnerable to target tracking and data leaks. Minimizing the metadata stored on servers is key to protecting user privacy.

## Decision
Enforce strict server-side metadata minimization:
- The server stores only active mailboxes for offline delivery; once a message is delivered and acknowledged, it is purged from the server queue.
- IP addresses, connection logs, and message routing paths must not be logged permanently.
- Production server logs must pass a redaction filter preventing plaintext content, account identifiers, and key fingerprints from appearing in traces.

### Phone identity, OTP, and invite redaction (added with the phone/invite/contacts-sync overhaul)
- Phone numbers are never stored or logged in plaintext on the server. Only
  `phone_hash` (HMAC-SHA256 over the E.164 number, keyed by a per-deployment
  discovery salt) lands in a database row; see `backend/lib/src/phone_hash.dart`
  and `app/lib/app/phone_hashing.dart`. The one exception on the wire is the
  OTP request (`POST /api/v1/accounts/phone/otp/request`): its body carries the
  raw `phone_number` next to `phone_hash` so the server can check the hash and
  hand the number to the SMS gateway (BulkSMSBD) for delivery. It is used
  transiently and never persisted from that request. Registration stores the
  account's phone number in `accounts.phone_last4` (historical column name)
  for the admin console, account security and spam protection; identity and
  matching still use only `phone_hash`.
- The discovery salt itself is not secret (it is served unauthenticated from
  `GET /contacts/discovery-salt` because signup needs it pre-account), but it
  must never be logged either, since a logged salt plus a logged hash would let
  a log reader reverse small phone-number ranges by brute force.
- OTP codes and invite codes must never appear in logs. The OTP is delivered
  only by SMS (BulkSMSBD) and is never returned in an HTTP response; a server
  without a configured SMS provider refuses OTP requests with 503
  (`backend/lib/src/modules/auth/phone_otp.dart`). The server stores only a
  SHA-256 of the code. SMS-gateway error bodies go to the server log only,
  because they can contain the API key.
- `/contacts/match` request handlers log match-request *volume* only, per
  account, for abuse monitoring - never the phone hashes being matched.

## Consequences
- Protects users from server-compromise leaks.
- Aligns backend development with high-privacy guidelines.
