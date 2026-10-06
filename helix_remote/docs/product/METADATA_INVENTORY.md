# Helix Remote Metadata Inventory

Status: rewritten at Phase X (2026-10) for the v2 server (PostgreSQL, one schema
per module). The v2 design reasoning, and the comparison with the v1 server this
replaces, is in [`../protocol/v2/METADATA_V2.md`](../protocol/v2/METADATA_V2.md); the
list below is what the code stores (`server/lib/src/modules/*/migrations` and
`MODULE.md`). Nothing here has been externally reviewed.

The server keeps **no conversation graph and no message history**. A message is a
row in a per-device mailbox until that device acknowledges it (30 days at most).
Edits, reactions, receipts, deletes, replies, typing, view-once state and disappearing
timers are inside the encrypted content, so they are not server data at all.

| Category (schema.table) | Stored fields | Purpose | Retention |
|---|---|---|---|
| Account (`identity.accounts`) | account id (UUIDv7), account identity public key (AIK), phone_hash (HMAC-SHA-256 under the server's pepper), discovery index (pepper-keyed, null when the account opted out of discovery), `phone_last4`, `~Helix name`, status (active / suspended), created_at | Account directory and sign-in. The number is the permanent identity; there is no plaintext number, username or change-number flow. `phone_last4` is the last four digits only (the admin console never sees more) | Until account deletion |
| Account password (`identity.passwords`) | Argon2id parameters and salt, a verifier (HMAC of the HKDF-derived auth key under a per-account salt), the identity key sealed under a password-derived key, failed_attempts, locked_until | Password sign-in on new devices and lockout. The password and the auth key's source never leave the device; the server compares in constant time | Until changed, identity-key rotation, or account deletion |
| Device (`identity.devices`) | device id, account id, name, platform, device public keys, the AIK-signed device certificate, status, `tokens_valid_after`, created_at, last_seen_on (a date, not a time), revoked_at and reason | Multi-device trust, session cut-off, delivery targets | Until account deletion (revoked devices keep their row for the security log) |
| Push token (`identity.push_tokens`) | device id, kind, token | Data-only wake-ups (`message`, `call`, `call_ended`, never content) | Until the device is revoked or the account deleted; never listed to other devices |
| Refresh tokens (`identity.refresh_tokens`) | SHA-256 of the token, device id, created, expiry, used and revoked marks | Device sessions: access token 15 minutes (a JWT, not stored), refresh token 60 days, rotated on every use; reuse ends the device's sessions | Expired rows are purged (about a week after expiry) |
| Phone challenges (`identity.phone_challenges`) | challenge id, phone_hash, purpose, a peppered hash of the six-digit code, the keyed discovery form, last four digits, attempts, expiry | One-time verification for sign-up, sign-in, recovery and password change. The code and the number are never stored in the clear; the raw number exists in memory while the code is texted | Expires after 10 minutes, purged after 2 days |
| Banned phones (`identity.banned_phones`) | phone_hash | Operator bans survive account deletion | Until the operator lifts the ban |
| Invites and recovery codes (`identity.invites`, `identity.recovery_codes`) | code hash, issuer (admin or self), created, expiry, redeemed_at and by whom, cancelled_at; recovery codes also the account id | Registration on personal servers; account recovery. Codes are shown once and stored only as hashes | Invites 7 days; expired unredeemed rows are purged after 30 days, redeemed rows stay as an audit trail |
| Security events (`identity.security_events`) | account id, kind (new device, revoked, password changed, recovery used ...), device id and name, time | The "security events" list the person sees | Until account deletion |
| Short-lived auth state (ephemeral store) | verified-phone tokens, sign-in and link tokens, link state, device challenges (keyed by a random challenge id) | Multi-step sign-in and QR linking | Minutes (TTL), in an UNLOGGED table that is cleared by a crash |
| Prekeys (`keys.signed_prekeys`, `keys.one_time_prekeys`) | device id, public prekeys and the AIK/DSK signature over the signed prekey | Start encrypted sessions with an offline device | One-time prekeys are deleted when handed out; all prekeys of a revoked device are purged |
| Mailbox (`messaging.mailbox`, hash-partitioned by device) | recipient device id, per-device sequence number, the sealed envelope (ciphertext), sender hint (sender account and device), created_at, expires_at | Offline delivery. One row per recipient device, including the sender's other devices | **Deleted when the device acknowledges it**; undelivered rows expire after 30 days |
| Device sequence and sends (`messaging.device_seq`, `messaging.sends`) | device id and next sequence; sending device, message id, accepted_at | Ordering and idempotent sends | Sequence while the device exists; send records 7 days |
| Profiles and privacy (`people.profiles`, `people.privacy`) | the profile blob as ciphertext (display name, about, avatar reference are inside it, sealed with the person's profile key), version; audience settings for phone discovery, presence and last seen | Showing people, privacy controls | Until changed or account deletion |
| Blocks and contacts (`people.blocks`, `people.contacts`) | account ids; for the `contacts` audience, the account ids of the uploaded phone-book matches (replace-all, at most 5,000) | Silent drop of blocked senders and callers; presence by audience. There are no contact requests | Until removal or account deletion |
| Discovery budget (`people.discovery_budget`) | account id, day, lookups used | The 5,000-per-day budget on phone-hash matching (the online oracle remains an accepted risk, threat T-5) | Daily counter |
| Reports (`people.reports`) | reporter, reported account, category, an optional note the reporter types, status. No message content is attached | Abuse handling with the minimum evidence | Survives account deletion as the moderation record until resolved |
| Media objects (`media.objects`; bytes in object storage) | random object id (never a content hash), owner account, kind, size, upload offset, expiry | Encrypted attachments, avatars and backup media. The server cannot link an object to a message | Attachments 30 days, backup media 90 days (refreshed by each full backup), avatars and group pictures until deleted. Quotas per account |
| Backups (`backup.history_backups`, `backup.full_backups`) | the encrypted history backup (at most 16 MiB) keyed by the AIK; the encrypted full-backup envelope (an opaque JSON, refused if it carries a recovery phrase, passphrase or backup key at any depth), versions | Client-owned encrypted restore | Replaced by a higher version; history backup deleted when the AIK changes; both removed with the account |
| Groups (`groups.groups`, `members`, `bans`, `invite_links`, `join_requests`) | group id, member account ids and roles, epoch, ban list, hashed invite links with encrypted previews, join requests, and the **encrypted** state blob (name, picture, description, settings under the group master key) | Roster authority and sender-key fan-out. The server sees who is in a group, not what it is called | Until the group is deleted or the member leaves or is removed |
| Calls (`calls.pending_calls`, `calls.call_metrics`) | call id, callee device, caller account and device, the sealed offer for an offline callee (up to 120 s); anonymous call-quality numbers | Ring offline devices, tune TURN. SDP, ICE candidates, caller names and audio/video are sealed pairwise and invisible to the server | Pending calls 120 s; metrics 90 days |
| Federation (`federation.settings`, `peers`, `remote_*`) | this server's signing key (a database dump therefore contains a private key), peer domains, keys and last seen; qualified ids (`uuid@domain`) of remote members and devices | Only when the operator turns federation on (off at cutover) | Peer cache 24 hours; remote rows while the group or relation exists |
| Operator (`admin.admins`, `admin.audit`, `admin.sign_in_failures`) | the Argon2id admin password hash and lockout counters; an audit row for every operator mutation (actor, action, target ids, time); failed sign-in counters by address | Operator accountability | Audit: operational retention; failure counters 2 days |
| Settings (`ops.settings`) | server name, maintenance flag, federation switch, allow-listed feature flags | Operator configuration | Until changed |
| Platform (`platform.idempotency`, `jobs`, `periodic_jobs`, `schema_migrations`, `rate_buckets`, `ephemeral`) | idempotency keys with the response sealed at rest; outbox jobs (push wake-ups, relays, purges) and dead letters; token-bucket counters keyed by principal or address; schema versions and checksums | Retry safety, background work, limits | Idempotency 24 hours; buckets 1 hour after last use; dead letters until the operator purges them |
| Logs (stdout and the optional `HELIX_LOG_FILE`) | JSON lines with a request id, route template, status, duration, redacted fields. Client addresses appear only as the rightmost-untrusted forwarded address | Operations | Whatever the operator rotates; nothing here is in the database |

## Minimization rules

- Server APIs store ciphertext or hashes wherever content evidence would be
  needed. Bodies, tokens, keys, codes, message content and full phone numbers are
  never logged (the logger redacts by field name and by value shape; a test pins
  it).
- Push is data-only. A wake-up carries the kind and a call id, never content;
  the app fetches and decrypts after waking.
- The server identifies accounts by `phone_hash` and the keyed discovery index.
  The raw number is sent once per code request, so it can be hashed and passed
  to the SMS gateway (BulkSMSBD); it is not persisted from that request.
  Phone discovery, once turned back on, needs the account's own number again.
- Phone-hash discovery (`POST /v1/people/discover`) needs authentication, is
  limited per device and capped at 5,000 matches a day; only volume is logged,
  never the hashes queried.
- Client-side, device-local only: the phone-book names and numbers used to show
  people, and the whole message history, in the SQLCipher database. Renaming
  someone in Helix also writes the name to the phone's contacts, with the
  person's permission.
