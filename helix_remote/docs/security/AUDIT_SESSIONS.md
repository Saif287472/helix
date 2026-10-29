# Audit sessions

How to audit Orbit (Helix Remote) with an agent that cannot hold the whole
codebase: **19 slices** (E4 and U1 split further, so 23 sessions at most), each bounded (about 2,000 to 12,000 lines of
code) with its own concern and prompt. Run them in separate sessions, give each
the **common brief** first, and bring the reports back; every finding is
checked against the code before anything is fixed.

Scope of a "line" below: Dart under `lib/`, generated code excluded.
`helix_local/` is a separate dormant app and is never audited.

## How to use

1. Start a fresh session per audit. Paste the **common brief**, then the
   session's prompt.
2. Ask for the report in the **report format** below, as Markdown.
3. Bring back the whole report. A finding without a file and line, or without a
   traced path from a real input to a wrong result, is treated as a lead, not a
   bug, and checked first.
4. Suggested order: S1, C1, S2, E1, S5, A1, then the rest. The first six hold
   the most security weight.

## Common brief (paste first, every session)

```
You are auditing one slice of "Orbit" (repo name Helix Remote): a privacy-focused,
end-to-end encrypted messenger. Dart/Flutter workspace in helix_remote/: a shelf
server over PostgreSQL, a pure-Dart protocol package, a pure-Dart engine over a
drift + SQLCipher local database, and a Flutter app. Read /AGENTS.md first.

Rules:
- READ ONLY. Do not change files, run the server, or touch any deployment.
- Never read or print: helix_remote/server/.env, keystores, anything listed in
  docs/security/FORBIDDEN_FILES.md, or docs/codebase/ (a code dump; ignore it).
  If you meet a secret, say where it is, not what it is.
- Stay inside your slice. Where the slice calls code outside it, read that code
  only enough to know its contract, and list it under "Needs another slice".
- The design intent is in the docs named in your slice. A finding is a place
  where the CODE departs from the DOCUMENTED intent, or where the intent itself
  is unsafe. Say which.
- Report only what you can show. For each finding trace a realistic path: who
  sends what, which line accepts it, what goes wrong. Do not report style,
  naming, missing comments, or "could be hardened" without a concrete attack or
  failure. Do not report the same root cause twice.
- Known, already accepted gaps (do not report them as new): the crypto has had no
  external review; colluding accounts can use a TURN credential without an
  answer (relay-side accounting is not built); group messages and calls are not
  held on a key change (direct messages are); phone-side attachment files are
  not encrypted by the app (Android storage encryption and SQLCipher for the
  database apply); the second media session of a voice/video switch is untested
  on devices.

Report format (Markdown), one block per finding, most severe first:

### F-<n> <one-line title>
- Severity: Critical | High | Medium | Low   (Critical = remote compromise of
  messages, keys, accounts or money without user action)
- Confidence: Confirmed (traced end to end) | Likely | Lead (needs checking)
- Where: path:line (and every other place that matters)
- Intent: the doc or invariant it breaks, or "unsafe by itself"
- Path: step by step, input -> line -> result
- Evidence: the exact code (a few lines) and any test that does or does not
  cover it
- Fix: the smallest change that closes it, and what test would pin it
- Needs another slice: yes/no and where

End with: "Checked and fine" (a short list of the things you looked at hard and
found sound, so we know what was covered), "Not covered" (anything in the slice
you did not get to), and "Needs another slice".
```

## Slices

### S1. Server: identity, sessions, accounts (about 4,900 lines)

Files: `server/lib/src/modules/identity/` (all), `server/lib/src/kernel/`
(jwt, crypto, presence).
Read: `identity/MODULE.md`, `docs/protocol/v2/REST_V2.md` (auth sections),
`docs/protocol/F1_MULTI_DEVICE_TRUST_DESIGN.md`, `docs/product/THREAT_MODEL.md`.

```
Slice S1: the server's identity module and kernel (sign-up, phone verification,
password sign-in, device linking, recovery codes, sessions, refresh tokens,
account deletion, SMS, lockouts).
Concerns, in order:
1. Authentication bypass: every route that mints or refreshes a session
   (issueDeviceSession is meant to be the only mint point), token type/audience
   confusion, refresh rotation and reuse detection, tokens_valid_after cut-offs,
   races between refresh and sign-out.
2. Account takeover paths: phone verification (code entropy, attempts, reuse,
   expiry), "replace existing" registration, recovery codes (issue, redeem,
   expiry, single use), password reset, device linking approval and its tokens.
3. Lockout and rate-limit logic: can a lock be bypassed by changing identifier
   or address, or abused to lock out a victim? Is anything counted after the
   check instead of before?
4. Enumeration and information leaks: do responses, timing or error codes
   reveal whether a number or account exists?
5. Secrets handling: password-derived auth key storage (Argon2id parameters,
   comparison in constant time), phone number storage (keyed hash and sealed
   value), logging of anything sensitive.
6. Authorization of every route (who may call it, with which token audience).
7. SQL: parameterisation, tag types, injection, multi-statement transactions
   that should be atomic.
```

### S2. Server: messaging, realtime, keys, people, federation (about 4,000 lines)

Files: `modules/messaging/`, `modules/realtime/`, `modules/keys/`,
`modules/people/`, `modules/federation/`, `platform/bus/`, `platform/ephemeral/`.
Read: the MODULE.md of each, `docs/protocol/v2/` (REST, realtime, metadata).

```
Slice S2: message delivery, the WebSocket layer, prekey/key directory, people
(blocks, discovery) and federation between servers.
Concerns:
1. Delivery rules: only the recipient's ACTIVE devices get anything; exact device
   list or 409 device_list_stale; revoked devices get nothing; per-device
   payload isolation (can one device's payload reach another?).
2. Authorization on every route and WebSocket frame: can account A read, ack,
   delete or subscribe to account B's mailbox, keys, presence or blocks?
3. WebSocket: origin and auth at upgrade, token expiry while connected,
   supersede and revocation closing sockets, frame size limits, slow-client
   memory growth, fan-out across nodes (bus) leaking events to the wrong node.
4. Federation (server-to-server): signature and timestamp verification, replay,
   key pinning and key-change handling, SSRF through peer discovery, trusting a
   peer's claims about accounts, rate limits on remote key fetches.
5. Contact discovery: hash oracle, enumeration, rate limits, what the server
   learns.
6. Prekey handling: one-time prekey exhaustion or theft, signed prekey
   validation, certificate checks done on the server.
7. Metadata: anything stored or logged that docs/product/METADATA_INVENTORY.md
   does not list.
```

### S3. Server: groups, media, backup, compliance (about 4,400 lines)

Files: `modules/groups/`, `modules/media/`, `modules/backup/`,
`modules/compliance/`, `platform/blobs/`, `platform/storage/`.

```
Slice S3: group state, uploads and downloads, backup storage, data export and
deletion.
Concerns:
1. Group authority: role checks on every mutation (add, remove, promote, change
   info, links), optimistic versioning, can a removed member still send, read
   state or use an invite link, join-by-link approval and expiry, link
   revocation races, the 1,024-member cap.
2. Media: upload ownership, resumable upload range handling (overlap, gaps,
   negative or huge ranges), size and quota enforcement (including plan limits),
   content-type handling, download authorization (presigned URLs: scope, expiry,
   reuse), path traversal in the local blob store, S3 key construction,
   retention purge deleting something still referenced.
3. Backup: only the owner can read or delete; size limits; what is stored
   unencrypted (it should be only ciphertext); replacing or deleting another
   device's backup.
4. Export and deletion: does deletion really remove (or mark for purge) every
   table that holds the account, including call, billing and audit rows? Does
   export include only the account's own data?
5. Resource exhaustion: unbounded bodies, many small uploads, quota bypass by
   racing requests.
```

### S4. Server: platform (about 5,200 lines)

Files: `server/lib/src/platform/` (config, db, http, jobs, observability,
push, ratelimit), `server/bin/`.
Read: `platform/PLATFORM.md`, `docs/operations/V2_OPERABILITY.md`,
`docs/operations/V2_SERVER_HANDOFF.md`.

```
Slice S4: the server platform (HTTP pipeline, rate limits, database layer,
migrations, jobs/outbox, logging and metrics, push, config).
Concerns:
1. HTTP pipeline: header handling (X-Forwarded-For and X-Real-IP trust, trusted
   proxy logic), request size and slow-body limits, CORS, security headers,
   error responses leaking internals, route registration (r.public requires a
   policy; is anything public that should not be?), method/route confusion.
2. Rate limiting: keys (can a client choose its own key?), fail-open on store
   errors, per-IP vs per-account, bypass by header or IPv6 rotation, cost of the
   limiter itself.
3. Database layer: SQL parameter tag handling, transaction timeouts, pool
   exhaustion, migration runner (checksums, ordering, locks, what happens on a
   partial failure), idempotency-key storage (sealed responses, replay across
   principals).
4. Logging: the redacting logger really redacts (tokens, phone numbers, codes,
   message content, URLs with credentials); log files and metrics endpoints
   protected.
5. Jobs/outbox: exactly-once claims, poisoned jobs, dead letters, push payloads
   (content-free), provider credentials handling.
6. Config: every secret fails closed when missing or weak; dangerous modes
   (HELIX_DEV_MODE, federation over http) cannot be on in production.
```

### S5. Server: billing, calls, admin, ops (about 5,500 lines)

Files: `modules/billing/`, `modules/calls/`, `modules/admin/`, `modules/ops/`.
Read: `docs/adr/035-plans-and-entitlements.md`,
`docs/adr/036-call-time-is-metered-at-the-relay.md`,
`docs/product/ORBIT_PREMIUM_PLAN.md`, `admin/MODULE.md`.

```
Slice S5: plans and manual payments, call time metering and TURN credentials,
the operator (admin) API, ops endpoints.
Concerns:
1. Money and entitlements: can a client claim Premium or minutes it did not earn
   (client-supplied plan data, replayed payment requests, duplicate TrxIDs,
   approving the same request twice, negative or huge amounts, plan override
   abuse, race between approve and expire)? Ledger arithmetic: reservations,
   settlement, refunds, the voice/video switch (two pools), claims expiring,
   rounding, integer overflow, concurrent calls drawing the same minutes.
2. TURN credentials: scope (call id, role, group/room binding), lifetime equals
   reserved time, secrets per relay, can a credential be reused for another
   call, can a non-party obtain one, can credentials be minted without call time.
3. Admin API: every action behind admin auth AND (for risky ones) a step-up
   token; audit row for every mutation in the same transaction; admin setup
   local-only; sign-in lock shared; token/key derivation; log stream auth
   re-check; what a stolen session token alone can do.
4. Ops endpoints: metrics and anomaly/crash upload protections, abuse of the
   crash-report endpoint (size, flooding, content).
5. Calls module: signalling authorization (party checks), offer rate limits,
   pending-offer storage, blocked-caller handling, push content.
```

### C1. Crypto package (about 4,600 lines)

Files: `packages/helix_remote_crypto/lib/`.
Read: `docs/protocol/v2/CRYPTO_V2.md`,
`docs/security/remote_cryptographic_design_review.md` (it says the crypto has had
no external review).

```
Slice C1: the cryptography package (X3DH, Double Ratchet, Sender Keys, device
certificates, safety numbers, backup/recovery crypto, key derivation).
Concerns:
1. Conformance to docs/protocol/v2/CRYPTO_V2.md: every construction, label,
   info string, associated-data layout, and length. Report any divergence.
2. Primitive misuse: nonce/IV generation and reuse, key reuse across purposes,
   missing domain separation, unauthenticated encryption, MAC-then-decrypt
   order, constant-time comparisons, randomness source, KDF parameters.
3. Ratchet correctness: skipped-message-key limits and eviction (DoS and
   replay), out-of-order handling, state rollback, header encryption if used,
   one-time prekey consumption, session reset behaviour, replay of the initial
   message.
4. Sender Keys: chain handling, rotation after removal, signature checks on
   distribution messages, cross-group confusion.
5. Certificates and trust: AIK pinning, device certificate verification, what
   is bound (account id, device id, expiry), downgrade and substitution.
6. Backup/recovery crypto: parameters, domain separation, what an attacker with
   the server's copy can do offline.
7. Test vectors: which constructions have none, and which tests are weak.
Be conservative: say "Lead" unless you can show a concrete break.
```

### E1. Engine: sessions, inbound, outbound, trust (about 3,500 lines)

Files: `packages/helix_remote_engine/lib/src/crypto/`, `messaging/`,
`account/`, `util/`, and `features/people_service.dart`,
`features/settings_service.dart`.

```
Slice E1: the engine's message pipelines and trust decisions.
Concerns:
1. Inbound: every decrypt/apply path handles malformed, replayed, reordered,
   duplicate and hostile input without crashing, corrupting a session, or
   applying content the sender is not entitled to send (edits and deletes of
   someone else's message, system/engine-owned kinds, reactions, receipts,
   view-once, disappearing timers, forged "safety number changed" rows).
2. Outbound and outbox: idempotency, retry/backoff/give-up classification,
   message loss on crash, duplicate sends, ordering, the key-change hold
   (verified contact whose key changed must not receive direct messages until
   released; check every path that can still send to them).
3. Trust: AIK pinning on first use, key-change handling, device list staleness,
   revoked devices, self-account checks, what happens if the server returns
   another identity key.
4. Concurrency: lock order, deadlocks, transactions held across awaits, races
   between sign-out and in-flight work.
5. Information leaks: logs, exception messages, events carrying content.
```

### E2. Engine: groups (about 3,800 lines)

Files: `packages/helix_remote_engine/lib/src/groups/`.
Read: `docs/adr/034-*` (group calls) and the group sections of
`docs/protocol/v2/`.

```
Slice E2: group messaging in the engine (roster sync, sender keys, rekeying,
membership changes, invites, pending-member confirmation).
Concerns:
1. A hostile server or member: forged roster changes, member add/remove
   attribution (membership changes are not signed; list exactly what a hostile
   server can do), planting group keys, stale-roster sends.
2. Key lifecycle: rekey after removal (is a removed member really cut off, in
   every race), distribution to new members, sender key rollback, message
   decryption after removal, history exposure to new members.
3. Confirmation of unconfirmed members: can a server-added member read messages
   before the user confirms?
4. Authorization in the client: who may perform which group actions locally and
   how remote admin claims are checked.
5. Crash/retry safety of the group outbox ops.
```

### E3. Engine: calls (about 3,900 lines)

Files: `packages/helix_remote_engine/lib/src/calls/`,
`packages/helix_remote_calls/lib/`, `app/lib/features/calls/application/`,
`app/lib/core/calls/`.
Read: `docs/adr/034-*`, `docs/adr/036-*`.

```
Slice E3: call signalling, TURN use, group calls, call time, voice/video switch.
Concerns:
1. Signalling authenticity: who can inject offer/answer/ICE/end/switch signals
   for a call, call-id and device binding, answer by the wrong device, replay of
   an old offer, glare (both sides call each other), blocked callers.
2. Media security: SDP/DTLS fingerprint handling (is the fingerprint bound to
   the authenticated signalling channel?), relay-only policy, leaking IP
   addresses, ICE candidate handling.
3. State machine: every transition under races (hang-up during offer, switch
   during end, two switches, answer after timeout), timers left running,
   camera/microphone left on after any failure path, leaking resources.
4. Call time: client-side enforcement and warning, what happens when the
   credential expires mid-call, and the switch's second media session (known
   to be untested on devices; list the riskiest assumptions).
5. Group calls: the four-person cap, no late join, rejoin refusal for rooms the
   device left, call room binding to the group.
```

### E4. Engine: transfers, backup, restore, recovery (about 8,100 lines)

Split into two sessions if the agent struggles: E4a `transfers/` (3,900),
E4b `backup/` and `features/` backup-related files (4,200).
Read: `docs/product/BACKUP_RECOVERY.md`,
`docs/protocol/F2_BACKUP_RECOVERY_TRANSFER_DESIGN.md`.

```
Slice E4: attachments and device transfers (E4a) / backup, restore and account
recovery (E4b).
Concerns:
1. Attachment crypto: per-file keys, digest verification before use, size and
   type validation, thumbnails and previews decoded from untrusted bytes,
   resumable upload/download state, temp files and their cleanup.
2. Backup/restore: what is encrypted with which key, the recovery secret's
   entropy and handling, restore of attacker-controlled data (a malicious backup
   or server reply: can it plant keys, contacts, messages, settings, or a
   different identity?), partial restore failures, rollback, merging with
   existing data, and the "key change on restore" behaviour.
3. Device-to-device transfer and linking: the pairing secret, what a passive or
   active observer can do, token expiry, approval UX attack surface.
4. Local files: paths built from untrusted names, overwrites, world-readable
   temp files.
```

### D1. Local database and device storage (about 12,000 lines, mostly generated)

Files: `packages/helix_remote_db/lib/` (hand-written parts), `app/lib/core/platform/`
(storage, keys, secure storage, files), `app/lib/core/security/`.

```
Slice D1: the local encrypted database and how the device protects keys and
files.
Concerns:
1. Database key: generation, storage (Keystore / Windows credential store),
   backup exclusion, loss handling (never open a new key over old data),
   rotation, multi-account slots, what remains on disk after sign-out or
   account deletion.
2. Schema migrations: data loss, partial migration, downgrade, destructive
   steps, whether tests cover each step.
3. App lock: bypass by task switching, notifications, share targets, deep
   links, intents, widgets, accessibility, screenshots of locked content, lock
   during calls, cold start, time rollback.
4. Files: where decrypted attachments, voice notes, thumbnails and caches live,
   permissions, who else can read them (other apps, shared storage,
   MediaStore), cleanup on sign-out/delete.
5. Clipboard and share paths for secrets (recovery code, invite links).
6. Anything stored in plaintext that docs/product/PRIVACY_CLAIM_MATRIX.md says
   is protected.
```

### A1. App: sign-in, devices, backup UI, settings (about 8,900 lines)

Files: `app/lib/features/sign_in/`, `devices/`, `backup/`, `settings/`,
`profile/`, `plans/`, `app/lib/core/engine/`, `core/links/`, `core/push/`,
`core/notifications/`.

```
Slice A1: app flows that touch accounts and secrets, and the app's entry points
from outside (links, push, notifications).
Concerns:
1. Deep links and shared links (https://.../open#HLX-..., helix://, group
   links, contact links): parsing, spoofing, a link that names another server
   (the confirmation step), open redirects, link-triggered actions without
   confirmation, expiry checks.
2. Push and notifications: content-free wake-ups, previews only when the person
   turned them on and never on a locked screen, notification actions (reply)
   abuse, channel settings, notification content logged anywhere.
3. Sign-in and recovery UI: where passwords, codes and secrets are held in
   memory/state, logged, put in route parameters or restored state; wrong
   server selection (advanced mode) leading to credential exposure; TLS
   pinning off by default (as designed).
4. Settings that change security (privacy, app lock, devices, delete account,
   change password): do they require the right proof, can state be left half
   applied?
5. Plans/payments UI: trusting server-provided numbers shown to pay; copy
   handling; no client-side entitlement decisions that matter.
```

### A2. App: conversation, chats, people, groups, shared (about 11,500 lines)

Files: `app/lib/features/conversation/`, `chats/`, `people/`, `groups/`,
`home/`, `app/lib/core/chat/`, `core/people/`, `shared/`.

```
Slice A2: the messaging UI layer.
Concerns:
1. Privacy leaks: drafts, previews, search results, typing/read receipts
   respecting the settings, locked chats, disappearing and view-once messages
   (do they stay visible or recoverable through caches, screenshots of
   thumbnails, notifications, forwarding, copy, share, starred, search index,
   backups?), message info screens.
2. Rendering untrusted content: links, mentions, formatting, long text,
   contact cards, locations, polls, media metadata; link previews (fetched from
   where? SSRF/IP leak), file names.
3. Actions: edit/delete rules, forward, share-out, key-change hold dialog
   ("Send anyway") reachable only for held messages.
4. Phone-book sync: what is sent to the server (hashes only), when, and what
   is stored.
5. State bugs: stale providers across account switches, streams not keyed on
   the account, unbounded lists, memory growth, errors swallowed so the user is
   told something false (e.g. "sent" when not).
```

### U1. UI kit and screens: orbit_ui (about 50,000 lines; do NOT audit all of it)

Audit in three bounded passes: U1a `components/`, U1b `screens/chat` and
`screens/calls`, U1c all other `screens/`. Skip `compare` tooling and assets.

```
Slice U1: the Orbit UI package (models in, actions out).
Concerns:
1. Accessibility: semantics labels, tap targets of at least 48 px, text scaling
   at 2x, contrast from theme tokens, focus order, screen-reader order, motion
   reduction.
2. Correctness: overflow, unbounded layouts inside scrollables (a real bug of
   this kind was found in the country picker), keyboard insets, RTL, very long
   names, empty/loading/error states always reachable, double taps firing an
   action twice.
3. Safety of what it draws: no raw HTML, no network fetch inside the kit, no
   logging of model contents, theme packs that come from a server (values
   validated before use: colours, sizes, fonts, asset paths).
4. Hard-coded colours or per-screen capture blocking (both are forbidden by
   product rules).
```

### P1. Protocol and API client packages (about 13,800 lines)

Files: `packages/helix_remote_protocol/lib/`, `packages/helix_remote_api/lib/`,
`contracts/v2/fixtures/`.
Read: `docs/protocol/v2/*.md`.

```
Slice P1: the wire contract and the clients.
Concerns:
1. Contract drift: routes, bodies, error codes and status codes in the code vs
   docs/protocol/v2/REST_V2.md and the other protocol docs; fixtures vs DTOs.
2. Parsing robustness: every fromJson against hostile input (wrong types, huge
   numbers, deep nesting, duplicate keys, giant arrays, invalid UTF-8,
   out-of-range dates, negative sizes); limits applied before allocation.
3. Transport: retry rules (never retry non-idempotent calls without a key),
   token refresh races, redirects (credentials must not follow a redirect to
   another host), timeouts, response size limits, TLS pinning logic, header
   injection, logging of requests.
4. WebSocket client: reconnect storms, backoff, frame size, auth on reconnect,
   handling of server close codes.
5. Admin vs device audience separation in the client.
```

### M1. Admin console app (about 9,400 lines)

Files: `admin/lib/`, `admin/android/` (manifest, signing, proguard).

```
Slice M1: the operator console (Android and Windows).
Concerns:
1. Token and password handling: secure storage, never logged, cleared on
   sign-out, the step-up password dialog (kept only for the call), clipboard
   handling for recovery codes, device lock.
2. Server address handling: can the console be pointed (or tricked into
   being pointed) at a hostile server that then receives the admin password;
   cleartext HTTP; certificate handling.
3. Destructive actions (ban, delete, purge, grants): confirmation, double-submit,
   wrong-account targeting after list refresh.
4. Android build: release signing configuration (no secrets in the repo),
   manifest flags (backup, exported components, cleartext, debuggable),
   proguard rules.
```

### O1. Deployment and operations (scripts and config, about 3,000 lines)

Files: `deploy/` (windows, linux, coturn), `docker-compose.yml`,
`.github/`, `tool/`, `scripts/`.
Read: `docs/operations/VM_MIGRATION.md`, `docs/operations/GO_LIVE_CHECKLIST.md`.
None of these scripts has run on a real host yet.

```
Slice O1: the operator scripts and infrastructure config. They are untested on
real hosts, so read them as a careful reviewer would run them.
Concerns:
1. Script bugs that would fail or do harm on first run: quoting, set -e/pipefail
   gaps, wrong paths, unsafe rm, races between backup and server, permissions
   (secrets world-readable), ordering of stop/migrate/start, rollback paths.
2. Secrets: where they live, file modes, whether any appears in a process list,
   log, backup, or the repository; backup encryption (age) key handling;
   off-box copy requirement.
3. Network exposure: Postgres, coturn, metrics, admin routes reachable from the
   internet; Caddy config (TLS, headers, operator routes limited to named
   addresses); firewall rules (ufw) and the TURN relay range; coturn config
   (denied peers: private ranges, loopback, metadata addresses; the two relays'
   secrets differ; bandwidth cap on the voice relay; stale-nonce).
4. Windows and Linux twins stay equivalent (AGENTS.md portability rule).
5. CI and supply chain: workflow permissions, pinned actions, secrets exposure
   to forks, dependency policy checks, lockfile handling.
```

### D2. Claims versus code (documents, about 30 documents)

Files: `docs/product/` (THREAT_MODEL, PRIVACY_CLAIM_MATRIX, METADATA_INVENTORY,
PRIVACY_POLICY, RETENTION_AND_DELETION, DATA_FLOW, APP_STORE_PRIVACY),
`docs/legal/`, `docs/protocol/v2/METADATA_V2.md`,
`docs/operations/V2_OPERABILITY.md`.

```
Slice D2: are the product's written promises true? You may read any code you
need, one claim at a time.
For every claim in the privacy policy, terms, privacy claim matrix, threat model
and metadata inventory that can be checked in code (what the server stores, how
long, what is logged, what is sent to the server, what a hostile server can or
cannot do, deletion and retention, what is encrypted), mark it: True (cite the
code and a test), False (cite what actually happens), or Unproven (nothing
enforces it). Also list anything the code stores or sends that NO document
mentions. A false or missing claim is a High finding for a privacy product.
```

### T1. Test quality (optional, last)

Files: `server/test/`, `packages/*/test/`, `app/test/`.

```
Slice T1: do the tests protect what matters?
Find: tests that cannot fail (no assertion on the behaviour, mocks that return
what the test expects, assertions on log lines only), security invariants with no
test (list them from AGENTS.md "Security invariants" and the threat model),
timing-sensitive or order-dependent tests (the repo lists known flaky ones;
find others), and tests that skip silently without Postgres. Report the five
highest-value missing tests with a sketch of each.
```

## When the reports come back

Send each report as it finishes. For every finding I will: reproduce it from the
cited lines, mark it confirmed or not (an audit agent can be wrong, and a false
finding that "fixes" working code is a cost), fix confirmed ones with a test that
fails before and passes after, and keep a short running list of what each slice
covered so gaps are visible. Fixes that change the wire, the database schema, or
user-visible behaviour will be put to you before I make them.
