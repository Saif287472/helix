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
| Account (`identity.accounts`) | account id (UUIDv7), account identity public key (AIK), phone_hash (HMAC-SHA-256 under the server's pepper), discovery index (pepper-keyed, null when the account opted out of discovery), `phone_last4`, `phone_sealed` (the full number the account's app reported, AES-256-GCM under `HELIX_PHONE_KEY`, ADR-030), `~Helix name`, status (active / suspended), created_at | Account directory and sign-in; the admin console shows the full number once the app reported it (only with `HELIX_PHONE_KEY`; else the last four digits). The number is the permanent identity; there is no plaintext number column, username or change-number flow | Until account deletion |
| Account password (`identity.passwords`) | Argon2id parameters and salt, a verifier (HMAC of the HKDF-derived auth key under a per-account salt), the identity key sealed under a password-derived key, failed_attempts, locked_until | Password sign-in on new devices and lockout. The password and the auth key's source never leave the device; the server compares in constant time | Until changed, identity-key rotation, or account deletion |
| Device (`identity.devices`) | device id, account id, name, platform, device public keys, the AIK-signed device certificate, status, `tokens_valid_after`, created_at, last_seen_on (a date, not a time), revoked_at and reason | Multi-device trust, session cut-off, delivery targets | Until account deletion (revoked devices keep their row for the security log) |
| Push token (`identity.push_tokens`) | device id, kind, token | Data-only wake-ups (`message`, `call`, `call_ended`, never content) | Until the device is revoked or the account deleted; never listed to other devices |
| Refresh tokens (`identity.refresh_tokens`) | SHA-256 of the token, device id, created, expiry, used and revoked marks | Device sessions: access token 15 minutes (a JWT, not stored), refresh token 60 days, rotated on every use; reuse ends the device's sessions | Expired rows are purged (about a week after expiry) |
| Phone challenges (`identity.phone_challenges`) | challenge id, phone_hash, purpose, a peppered hash of the six-digit code, the keyed discovery form, last four digits, attempts, expiry | One-time verification for sign-up, sign-in, recovery and password change. The code and the number are never stored in the clear; the raw number exists in memory while the code is texted | Expires after 10 minutes, purged after 2 days |
| Banned phones (`identity.banned_phones`) | phone_hash | Operator bans survive account deletion | Until the operator lifts the ban |
| Invites and recovery codes (`identity.invites`, `identity.recovery_codes`) | code hash, issuer (admin or self), created, expiry, redeemed_at and by whom, cancelled_at; recovery codes also the account id | Registration on personal servers; account recovery. Codes are shown once and stored only as hashes | Invites 7 days; `identity.purge_expired` (every 6 h) deletes an unredeemed invite 30 days past its expiry and a recovery code 1 day past its expiry or its use. Redeemed invites stay as the audit trail |
| Security events (`identity.security_events`) | account id, kind (new device, revoked, password changed, recovery used ...), device id and name, time | The "security events" list the person sees | Until account deletion |
| Short-lived auth state (ephemeral store) | verified-phone tokens, sign-in and link tokens, link state, device challenges (keyed by a random challenge id) | Multi-step sign-in and QR linking | Minutes (TTL), in an UNLOGGED table that is cleared by a crash |
| Limit markers (ephemeral store) | the password lockout of a number with no password (keyed by the peppered phone hash: failures and lock time); which accounts an account read the presence or profile of today (`people:seen:<reader>:<target>`); which target devices gave an account a one-time prekey this hour (`keys:otk:<account>:<device>`); which group changes bystander members were already told about (`grp:announce:<group>:<account>:<kind>`) | The decoy lockout (threat T-7), the distinct-people read budget, the one-time prekey rule and the coalescing of roster notices so an add/remove loop cannot re-fan-out every cycle | The lockout 25 hours, reads 1 day, prekeys 1 hour, announce markers 15 seconds (TTL); cleared by a crash |
| Send claims (ephemeral store) | one row per message id while it is being accepted (`msg:send:<sender account>:<sender device>:<id>`), then the answer that send gave: `accepted_at` and the accounts that blocked the sender — no recipients, no content | A retry that races the original cannot charge the budget or relay the batch twice, and a replay still says who blocked it | 2 minutes while running, 24 hours as an answer (TTL); cleared by a crash, and `messaging.sends` (7 days) decides delivery on its own |
| Parked ephemeral envelopes (ephemeral store) | the sealed envelope of one ephemeral (typing, call signal) send per online device (`msg:eph:<ref>:<device>`) | Live delivery to a device whose socket is on another node | 60 seconds (TTL); cleared by a crash; the content is ciphertext |
| Prekeys (`keys.signed_prekeys`, `keys.one_time_prekeys`) | device id, public prekeys and the AIK/DSK signature over the signed prekey | Start encrypted sessions with an offline device | One-time prekeys are deleted when handed out; all prekeys of a revoked device are purged |
| Mailbox (`messaging.mailbox`, hash-partitioned by device) | recipient device id, per-device sequence number, the sealed envelope (ciphertext), sender hint (sender account and device), created_at, expires_at | Offline delivery. One row per recipient device, including the sender's other devices | **Deleted when the device acknowledges it**; undelivered rows expire after 30 days |
| Device sequence and sends (`messaging.device_seq`, `messaging.sends`) | device id and next sequence; sending account and device, message id, accepted_at | Ordering and idempotent sends | Sequence while the device exists; send records 7 days |
| Profiles and privacy (`people.profiles`, `people.privacy`) | the profile blob as ciphertext (display name, about, avatar reference are inside it, sealed with the person's profile key), version; audience settings for phone discovery, presence and last seen | Showing people, privacy controls | Until changed or account deletion |
| Display names (`people.display_names`) | account id, the name the person gave themselves **in the clear**, updated_at | The admin console (ADR-030); contacts read the encrypted profile | Until changed or account deletion |
| Blocks and contacts (`people.blocks`, `people.contacts`) | account ids; for the `contacts` audience, the account ids of the uploaded phone-book matches (replace-all, at most 5,000) | Blocked senders and callers reach nobody and are told so: a blocked account that is online gets a live-only `block_change` frame (no row, no `seq`, nothing about who else is blocked), and any blocked account learns it from its next send's `blocked_by` or a refused offer, so it knows that, and roughly when, it was blocked; presence by audience. There are no contact requests | Until removal or account deletion |
| Discovery budget (`people.discovery_budget`) | account id, day (UTC), lookups used | The 5,000-per-day budget on phone-hash matching (the online oracle remains an accepted risk, threat T-5) | One row per account per UTC day; `people.purge_discovery` (daily) keeps today and yesterday and deletes the rest |
| Reports (`people.reports`) | reporter, reported account, category, an optional note the reporter types, status. No message content is attached | Abuse handling with the minimum evidence | Survives account deletion as the moderation record while open; deleted 180 days after it is resolved or dismissed |
| Media objects (`media.objects`; bytes in object storage) | random object id (never a content hash), owner account, kind, size, upload offset, expiry | Encrypted attachments, avatars and backup media. The server cannot link an object to a message. A profile photo (Part B E1) is one `persistent` object of the account: the id, key and digest that reach it live inside that person's encrypted profile blob, so who can read a picture is decided by who holds the profile key, not by the media row. | Attachments 30 days, backup media 90 days (refreshed by each full backup), avatars and group pictures until deleted (a replaced or removed photo is deleted by its owner's device). Quotas per account |
| Backups (`backup.history_backups`, `backup.full_backups`) | the encrypted history backup (at most 16 MiB) keyed by the AIK; the encrypted full-backup envelope (an opaque JSON, refused if it carries a recovery phrase, passphrase or backup key at any depth), versions | Client-owned encrypted restore; `GET /v1/backups/full/meta` also gives the full-backup row's `updated_at` to any device of the account (whether one exists and when it was made, with no envelope) | Replaced by a higher version; history backup deleted when the AIK changes; both removed with the account |
| Groups (`groups.groups`, `members`, `bans`, `invite_links`, `join_requests`) | group id, member account ids and roles, epoch, ban list, hashed invite links with encrypted previews (and, since 2026-10-20, the admin who made each), join requests, and the **encrypted** state blob (name, picture, description, settings under the group master key) | Roster authority and sender-key fan-out. The server sees who is in a group, not what it is called | Until the group is deleted or the member leaves or is removed |
| Calls (`calls.pending_calls`, `calls.call_metrics`) | call id, callee device, caller account and device, the sealed offer for an offline callee (up to 120 s); anonymous call-quality numbers | Ring offline devices, tune TURN. SDP, ICE candidates, caller names and audio/video are sealed pairwise and invisible to the server | Pending calls 120 s; metrics 90 days |
| Federation (`federation.settings`, `peers`, `remote_*`) | this server's signing key (a database dump therefore contains a private key), peer domains, keys and last seen; qualified ids (`uuid@domain`) of remote members and devices | Only when the operator turns federation on (off at cutover) | Peer cache 24 hours; remote rows while the group or relation exists |
| Operator (`admin.admins`, `admin.audit`, `admin.sign_in_failures`) | the Argon2id admin password hash and lockout counters; an audit row for every operator mutation (actor, action, target ids, time); failed sign-in counters by address | Operator accountability | Audit: one year (deleted daily); failure counters 2 days |
| Settings (`ops.settings`) | server name, maintenance flag, federation switch, allow-listed feature flags | Operator configuration | Until changed |
| Platform (`platform.idempotency`, `jobs`, `periodic_jobs`, `schema_migrations`, `rate_buckets`, `ephemeral`) | idempotency keys with the response sealed at rest; outbox jobs (push wake-ups, relays, purges) and dead letters; token-bucket counters keyed by principal or address (bundle fetches by requesting account and target account); schema versions and checksums | Retry safety, background work, limits | Idempotency 24 hours; a bucket until it is full again, one policy window after last use (a minute to a day; per-address buckets at most an hour); dead letters until the operator purges them |
| Logs (stdout and the optional `HELIX_LOG_FILE`) | JSON lines with a request id, route template, status, duration, redacted fields. Client addresses appear only as the rightmost-untrusted forwarded address. A device wake-up adds one `push` line per attempt (`component: push`, with the device id, the reason and the outcome: `sent`, `online`, `no_token`, `provider_off`, `failed`, `token_gone`) — the token itself never appears | Operations | Whatever the operator rotates; nothing here is in the database |
| App problem reports (`client_anomaly` log lines) | per entry: kind, where (error type, route template or engine step), the error's message and stack (whole from a debug build; trimmed, app frames only, from a release build; masked on the device and redacted again by the server), the device id, app version, platform, time, a repeat count and a request id for refused requests. Since 2026-10-23 also timings (launch to first frame and to engine ready, in milliseconds; slow-frame counts per quarter hour) and a memory-pressure note; since 2026-10-24 a `push.wake` note from the background wake, in counts (how many new messages it found, how many of them alerted, how many calls were pending) and the exception *type* of an account that could not be read. Never content, never a name or a number | Finding and fixing faults | Logs only, as above; never in the database |

## Minimization rules

- Server APIs store ciphertext or hashes wherever content evidence would be
  needed. Bodies, tokens, keys, codes, message content and full phone numbers are
  never logged (the logger redacts by field name and by value shape; a test pins
  it).
- Push is data-only. A wake-up carries the kind and a call id, never content;
  the app fetches and decrypts after waking. What the server keeps of it is one
  log line per attempt - the device, the reason and what became of it - and the
  app's background pass reports back the same way, in counts of what that one
  mailbox read found.
- The server identifies accounts by `phone_hash` and the keyed discovery index.
  The raw number is sent with each code request (so it can be hashed and passed
  to the SMS gateway, BulkSMSBD), with password sign-in and its parameters
  request, and when discovery is turned back on (`PrivacySettings.phone_number`);
  it is not stored from any of them.
  Phone discovery, once turned back on, needs the account's own number again.
- Phone-hash discovery (`POST /v1/people/discover`) needs authentication, is
  limited per device and capped at 5,000 matches a day; only volume is logged,
  never the hashes queried.
- The share link (`GET /u/{name}`) is the one public route that carries a
  person's `~name` in its URL. It stores nothing and answers nothing: every
  name, taken or not, gets the same static page, so asking it cannot list the
  server's names. The name reaches the server only as a request line — the
  application log records the route template (`/u/{name}`), while whatever
  front proxy logs the raw path is the operator's own retention. Whether the
  name exists is answered only by the authenticated
  `GET /v1/people/by-name/{name}`, which honours "Find me by ~name" and
  blocking and is rate-limited.
- A profile is read (`GET /v1/people/{account}/profile`) by a device that holds
  that person's profile key, which only a message from them can give it. The
  engine asks once when a stranger's key first arrives and at most once a day
  per person while it still has nothing to show, so the server learns who reads
  whose profile (its one-day distinct-people budget, above) and nothing about
  what was in it. A profile photo adds one media `GET` of that person's own
  `persistent` object per read.
- Client-side, device-local only: the phone-book names and numbers used to show
  people, and the whole message history, in the SQLCipher database. Renaming
  someone in Helix also writes the name to the phone's contacts, with the
  person's permission.
