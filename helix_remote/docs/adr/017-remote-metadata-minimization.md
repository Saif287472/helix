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
- Phone numbers are never stored or logged in plaintext, server- or client-side.
  Only `phone_hash` (HMAC-SHA256 over the E.164 number, keyed by a per-deployment
  discovery salt) ever crosses the wire or lands in a database row; see
  `backend/lib/src/phone_hash.dart` and `app/lib/app/phone_hashing.dart`.
- The discovery salt itself is not secret (it is served unauthenticated from
  `GET /contacts/discovery-salt` because signup needs it pre-account), but it
  must never be logged either, since a logged salt plus a logged hash would let
  a log reader reverse small phone-number ranges by brute force.
- OTP codes and invite codes must never appear in logs. The explicit placeholder
  design (the code is returned once in the HTTP response body and shown via a
  local notification - see `docs/product/THREAT_MODEL.md` T-6) makes this more
  important, not less: logging the code would be a second, persistent copy of a
  secret that was already deliberately given a narrow, one-shot exposure.
- `/contacts/match` request handlers log match-request *volume* only, per
  account, for abuse monitoring - never the phone hashes being matched.

## Consequences
- Protects users from server-compromise leaks.
- Aligns backend development with high-privacy guidelines.
