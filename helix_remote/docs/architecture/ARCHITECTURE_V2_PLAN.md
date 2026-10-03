# Helix Remote Architecture v2 — Plan of Record

Status: **in progress — C4 done, next: A2 (chats, conversation, people), then A3** · Written 2026-09-30 · Owner: hasan

> **Authoritative copy:** this file on branch `architecture-v2` (worktree
> `J:\hx2`). The copy on `main` is a snapshot from before Phase 0.

This is the single plan for rebuilding Helix Remote so it can grow ~10× in
features and serve millions of users without another architecture change.
Every v2 session follows this document. **Do not start work that is not the
next unfinished phase in the tracker (§11), and do not change the target
architecture (§3–§6) without an entry in the change log (§12) that the user
approved in chat.**

Scope: `helix_remote/` only. **Nothing under `helix_local/` changes** — it is
a separate app. Root files (CI, root docs) are touched only where they concern
Remote, and their Local parts are left exactly as they are.

---

## 1. Decisions already made (2026-09-30, by the user)

| # | Decision |
|---|---|
| D1 | Backend database is **PostgreSQL**. SQLite is not used by the server at all in v2 (not even in tests — tests use a real Postgres). |
| D2 | **Clean slate.** There are no real users. Both databases start from a new baseline schema. No migration from app schema v32 or backend schema v48. Live Helix Global data is discarded at cutover (the user does that step). Phones reinstall. |
| D3 | App uses **Riverpod + drift**, organised as **feature modules**. |
| D4 | Work is **phased**, one phase at a time, each ending green and committed. |
| D5 | Product rules and security invariants in `AGENTS.md` carry over unchanged (English only, light theme only, screenshots allowed, no contact requests, WhatsApp-style people, sign-in on Helix Global with hidden advanced mode, 48 px targets, tooltips, password never leaves the device, etc.). |

## 2. Why (findings that drove the plan)

Measured on 2026-09-30 (app/lib 37k LOC, backend/lib 26k LOC).

**App**
- Messages are stored as ciphertext inside SQLCipher and **decrypted on every
  read**. The chat list decrypts one message per chat, and search decrypts up
  to 500 messages per chat. Edits and reactions are replayed from `revisions`
  at read time, with N+1 queries.
- All SQLite calls are **synchronous on the UI isolate**.
- There are **no reactive queries**. The UI re-fetches on broad
  `RemoteSyncChange` events and pages with `LIMIT/OFFSET`.
- 73 local tables. 59 of 252 storage methods are never called. There are dead
  screens (`GroupCallScreen`, `call_link_sheet`) and dead code
  (`account_runtime_registry`).
- God objects:
  - `RemoteMessagingService` (~4.3k LOC across 12 mixins) and
    `RemoteCompositionRoot` (~3.6k LOC across 8 mixins).
  - `HelixRemoteDatabase` is 18 mixins over one shared `_db`.
  - Screens reach into `messagingService.db` (41 call sites) and `restClient`
    directly.
- **Crypto:**
  - The app never performs a Diffie-Hellman ratchet step, only symmetric
    chain steps, so there is **no post-compromise security**.
  - Sessions are keyed per *conversation* × device pair.
  - Group messages are fanned out pairwise per device (`GroupSenderChain`
    exists but is unused).
  - Prekey replenishment is never wired.

**Backend**
- The whole DB API is synchronous (~660 call sites). Correctness *depends* on
  single-isolate SQLite: sequence allocation is read-then-write.
- Three transaction mechanisms. 16 repository methods issue a raw nested
  `BEGIN`.
- State that breaks with more than one node:
  - the WS registry, and `trySendToDevice` results that drive push decisions
  - ~10 in-memory rate limiters
  - login challenges
  - the S2S replay map
  - an outbox without claims or leases
  - blobs on local disk (`ObjectStorageAdapter` exists but is unused)
- `messages` and `device_events` are never deleted on ack. The mailbox quota
  counts rows that never go away.
- SQLite-only SQL, a Postgres adapter stub, and a migration framework
  (`lib/src/migrations.dart`) that production never uses.

## 3. Target architecture — principles

1. **Growth is additive.** A new feature is a new backend module, a new app
   feature folder, its own tables, and new content/event types. Core code
   does not change.
2. **Boundaries are enforced by tests,** not convention. There are import-rule
   tests on both sides (§8).
3. **The server is stateless.** Any node can serve any request. All shared
   state lives in Postgres (durable) or the ephemeral store (TTL). Nodes
   coordinate only through the event bus and the outbox.
4. **The server knows as little as possible.** Edits, reactions, receipts,
   deletes and replies are end-to-end encrypted *content*, not server routes.
   The server stores only *undelivered* ciphertext (mailbox) and deletes it on
   ack.
5. **Decrypt once.** A message is decrypted exactly once, on arrival, into
   structured rows. SQLCipher is the at-rest protection, as `PRODUCT_CONTRACT`
   and `PRIVACY_POLICY` already promise.
6. **One source of truth for the wire.** A shared `helix_remote_protocol`
   package defines every REST DTO, realtime frame, error code and content
   type. It is used by server, app, admin and CLI.
7. **Pure-Dart core.** Messaging logic (sessions, inbound pipeline, outbox,
   features) is a Flutter-free package. It runs in the UI app, in the FCM
   background isolate, in the CLI and in tests.
8. **Tables arrive with the feature that uses them.** No speculative schema.
9. **Every scaling component sits behind an interface** with a
   single-host implementation now and a scale-out implementation later
   (§4.6). Swapping an implementation is configuration, not architecture.

## 4. Server v2 (`helix_remote/server/`, package `helix_remote_server`)

It is built fresh beside the old `backend/`, which stays live and untouched
until cutover (§10). At cutover `backend/` is deleted.

### 4.1 Layout

```
server/
  bin/server.dart               entry: load config -> build platform -> modules -> serve
  bin/migrate.dart              run migrations only (deploy step)
  bin/admin_tool.dart           reset admin password etc.
  lib/src/platform/             no business logic
    config/                     typed, validated config from env (one class)
    db/                         Db, Tx interfaces; Postgres pool impl; migration runner
    http/                       pipeline, middleware, AppError -> response, auth context
    bus/                        EventBus (publish/subscribe across nodes)
    ephemeral/                  EphemeralStore (TTL keys: presence, challenges, WS routes)
    ratelimit/                  RateLimiter over a RateLimitStore
    outbox/                     transactional outbox + job runner (leases, SKIP LOCKED)
    blobs/                      ObjectStorage (local FS, S3-compatible), presigned URLs
    push/ sms/ turn/            provider interfaces + impls (moved from backend)
    observability/              JSON logs, request ids, /metrics (Prometheus text), health
    ids.dart clock.dart         UUIDv7, injectable clock
  lib/src/kernel/               shared types every module may use: ids, errors,
                                AuthContext, Page/cursor, Idempotency, events base
  lib/src/modules/<module>/
    module.dart                 implements HelixModule (below)
    api.dart                    the ONLY file other modules may import (facade + events)
    http/                       handlers, request/response mapping (DTOs from protocol pkg)
    application/                use cases; transactions start here
    domain/                     entities, rules
    data/                       Postgres repositories (this module's schema only)
    migrations/0001_init.sql …  this module's tables
    MODULE.md                   routes, tables, events, jobs, invariants
  test/                         per-module tests + architecture tests + e2e
```

```dart
abstract interface class HelixModule {
  String get name;                       // also its Postgres schema name
  List<Migration> get migrations;
  void routes(RouteRegistry r);          // public routes declared here, explicitly
  void subscriptions(EventBus bus);
  List<JobDefinition> get jobs;          // outbox handlers + periodic jobs
}
```

The server is a list of modules. **Public (unauthenticated) routes are
declared per module with `r.public(...)`**, which requires a rate-limit
policy argument. This replaces the `endsWith` list in `_authMiddleware`.
The architecture test prints the full public-route list, and a snapshot test
fails when it changes, so every new public route is a deliberate diff.

### 4.2 Modules

| Module (schema) | Owns |
|---|---|
| `identity` | accounts, devices, device linking, sessions/refresh tokens (**single mint point `issueDeviceSession`**), password auth (HKDF auth key only), phone OTP, invites, recovery codes, suspension/blocks by admin |
| `keys` | identity keys, signed prekeys, one-time prekeys, sender-key distribution bookkeeping; prekey-low events |
| `messaging` | conversations (direct), membership view, **mailbox**, send, ack, delivery events |
| `realtime` | WS gateway, connection routing, replay/flow control, presence and typing (ephemeral) |
| `people` | profiles, `~Helix name`, discovery (phone-hash match with budgets), user-to-user blocks, privacy settings, reports |
| `groups` | group roster authority, roles, invites, join links, moderation, group settings |
| `calls` | 1:1 signaling, pending calls, TURN credentials, call push wake |
| `group_calls` | rooms, participants, room keys, call links, scheduled calls |
| `media` | attachment upload/download (presigned), quotas, reference counts, GC |
| `backup` | encrypted backups, history backups, backup media |
| `federation` | S2S signing and verification, peer directory, outbound relay jobs, inbound S2S routes |
| `ops` | health, readiness, metrics, maintenance mode, feature flags, logs stream, telemetry |
| `admin` | operator console API (users, invites, recovery codes, reports, audit) |
| `compliance` | data export, account deletion orchestration, audit log |

Modules never join or write another module's tables. They talk through
`api.dart` facades (synchronous request/response) or through domain events on
the bus (asynchronous). **No foreign keys cross schemas.** Account deletion is
an `identity.account_deleted` event that every module handles by purging its
own rows, tracked to completion by `compliance`.

### 4.3 Database (PostgreSQL 17)

- **Driver and pool:** `package:postgres` v3 with a pool. `Db.tx((tx) async
  {...})` is the only way to write. Nested calls reuse the outer transaction.
  Repository methods take a `Tx`/`Session` and never open their own
  transaction.
- **Migrations:**
  - Per-module numbered SQL files.
  - The runner records `(module, version, checksum)` in
    `platform.schema_migrations`, refuses changed checksums, and runs under
    an advisory lock so only one node migrates.
  - Rules are **expand → migrate → contract**: never rename or drop in the
    same release that stops using a column.
  - This reuses the ideas in today's unused `backend/lib/src/migrations.dart`.
- **IDs:** UUIDv7 (time-ordered, index-friendly). Client-generated ids are
  used for client-created objects (messages, idempotent ops).
- **Sequences:** the per-device mailbox sequence comes from
  `UPDATE identity.devices SET next_seq = next_seq + $n RETURNING next_seq`
  inside the send transaction (row lock, correct under concurrency). No
  `MAX()+1`.
- **Time:** `timestamptz`. Payloads are `bytea`, never base64 text. JSON only
  as `jsonb` for genuinely schemaless data.
- **Partitioning:** the mailbox is hash-partitioned by `device_id` from day
  one (16 partitions). Audit and metrics tables are range-partitioned by
  month, with retention jobs that drop partitions.
- **Indexing rule:** every query in a repository has an index, verified by an
  `EXPLAIN` test for the hot paths (send, fetch mailbox, ack, auth lookup).

### 4.4 Messaging and delivery model (the core)

```
client A --POST /messages/send (one envelope per recipient device, idempotency key)-->
  messaging: validate membership + active devices (getActiveDevices; 409 on stale list)
  tx { allocate seq per device; insert mailbox rows; outbox(push if offline) }
  after commit: bus.publish(device.wake(device_ids))
realtime node holding B's socket: on wake -> read mailbox after cursor -> push frames
client B: decrypt -> store -> ack(seq) --> messaging deletes mailbox rows <= seq
```

- **Mailbox:**
  - Columns: `messaging.mailbox(device_id, seq, envelope bytea, sender_hint,
    created_at, expires_at)`.
  - One row per recipient device, including the sender's *other* devices
    (that is how multi-device sync works).
  - Deleted on ack. Undelivered rows expire after 30 days (job).
  - The per-device quota counts only undelivered rows.
- **One event stream per device.** Everything a device must receive arrives in
  the mailbox as a typed envelope: messages, encrypted control content,
  sender-key distributions, group roster changes and device-list changes.
  Today's separate `messages` + `device_events` tables become one table.
- **Server-visible envelope kinds:** only routing kinds (`message`,
  `roster_change`, `device_list_change`, `key_change`, `account_signal`).
  Edits, reactions, receipts, replies, deletes, polls, locations and so on
  are **inside** the encrypted content.
- **Typing and presence:** ephemeral WS frames through the bus and
  `EphemeralStore`. Never stored.
- **Live-or-push decision:** `realtime` keeps `device → node` routes in
  `EphemeralStore` with a heartbeat TTL. "Is B online?" is a route lookup, not
  a local-socket check. Offline → the outbox push job. Calls use the same
  lookup (replacing today's `trySendToDevice` result logic).
- **Idempotency:** every mutating request carries `Idempotency-Key`, and
  results are stored in `platform.idempotency` (24 h). Sends are also
  naturally idempotent on `(message_id, recipient_device)`.
- **History on a new device:** it comes only from device-to-device transfer
  or the encrypted history backup (F2). The server keeps no history.
  *Confirm in Phase 1 against F1/F2 docs; update them.*

### 4.5 Realtime protocol

- **Transport:** `GET /v1/ws`, with the subprotocol negotiated via
  `Sec-WebSocket-Protocol: helix.v1+json`. A future `helix.v1+cbor` is
  additive and needs no architecture change.
- **Frames:** `{t, id, seq?, body}`. Client acks, server replays after the
  cursor with a credit window (keeps today's flow-control idea), heartbeats,
  and `wake` hints. Unknown frame types are ignored and acked (keeps
  `remote_compatibility_policy.md` §2).
- **Auth:** the access token at upgrade, plus an `isDeviceActive` check.
  Revocation publishes `device.revoked` on the bus, and the node holding the
  socket closes it.

### 4.6 Scale-out seams (interfaces with a single-host impl now)

| Interface | Now (PC, single host) | Scale-out (config switch) |
|---|---|---|
| `EventBus` | Postgres `LISTEN/NOTIFY` | Redis Streams or NATS |
| `EphemeralStore` | Postgres `UNLOGGED` tables + TTL sweep | Redis |
| `RateLimitStore` | Postgres (token bucket, one statement) | Redis |
| `ObjectStorage` | local filesystem, served by the server | any S3-compatible store (MinIO, R2, S3) with presigned URLs + CDN |
| `MailboxStore` | Postgres partitioned table | same (read replicas, more partitions); a wide-column store at 10M+ DAU is the one deliberate escape hatch |
| `PushProvider`, `SmsProvider` | FCM, BulkSMSBD | + APNs, others |

Run topology now: Caddy → 1–2 server processes → Postgres on the same PC.
Later: a load balancer → N nodes → managed Postgres (primary + replicas) +
Redis + object storage. **The code is identical in both.** A test proves two
nodes behind one Postgres deliver messages and calls correctly (Phase S7).

*Honest limit:* a home PC cannot serve millions of users. The code will
scale; the hardware has to move to hosted infrastructure when real load
arrives. That is a deployment change, not an architecture change.

### 4.7 Cross-cutting

- **Errors:** `AppError(code, status, safeMessage)`, with codes defined in the
  protocol package. Nothing sensitive in messages.
- **Logs:** structured JSON with a correlation id, via the redacting logger
  (never passwords, tokens, keys, content, codes, full phone numbers — enforced
  by a log-redaction test).
- **Config:** one `ServerConfig.fromEnv` that validates and fails fast.
  Topology is `single_host` or `cluster`. Env var names are documented in the
  handoff doc. **The user edits `.env`; agents never do.**
- **Personal servers:** still a single `docker compose up` (server + Postgres
  + optional MinIO). Personal servers *requiring* Postgres is accepted.

## 5. Protocol and crypto v2

- **`helix_remote_protocol` package** (pure Dart, new):
  - REST DTOs, realtime frames, envelope kinds, content types (moved from
    `helix_remote_domain/message_content.dart`), error codes, and
    pagination/cursor types.
  - JSON codecs are hand-written or generated. Golden fixtures live in
    `contracts/`.
  - The OpenAPI file is rewritten for v1 of the new contract, and the
    route-parity test is kept.
- **REST path prefix:** `/v1/...`. Since there are no clients (D2), this is a
  contract reset, recorded in an ADR, not a deprecation.
- **Sessions:**
  - X3DH + a **full Double Ratchet** (DH ratchet steps, skipped-key limits),
    one session per **(local device, remote device)**, not per conversation.
  - The conversation id travels inside the encrypted content.
  - Prekey replenishment is wired: the server emits `keys.prekeys_low`, and
    the client uploads more.
- **Groups:**
  - **Sender Keys** (`GroupSenderChain`): O(1) encryption per message. Sender
    keys are distributed over pairwise sessions, and rotate on member removal
    or device change.
  - The server fans out one ciphertext per member device.
  - `GroupCryptoProtocol` is an interface so MLS can be added later without
    touching the engine.
- **Content types:** versioned, and `unknown → "This message needs a newer
  version of Helix"` placeholder, never a crash.
- **Rules:**
  - Crypto code changes need test vectors and a review note in
    `docs/security/remote_cryptographic_design_review.md`.
  - Never weaken verification to make something work.
  - Crypto remains *without external review* until one happens, and the docs
    keep saying so.

## 6. Client v2

### 6.1 Packages (dependency direction is strict, top depends on bottom)

```
app, admin, cli
   └─ helix_remote_engine      pure Dart: session manager, inbound pipeline, outbox,
   │                           transfer queue, feature services (chats, people, groups,
   │                           calls signaling state, backup, devices, settings)
   ├─ helix_remote_db          drift + SQLCipher, schema, DAOs, watch queries (pure Dart*)
   ├─ helix_remote_api         typed REST + WS clients, one client class per server module
   ├─ helix_remote_crypto      X3DH, Double Ratchet, Sender Keys, attachment/backup crypto
   ├─ helix_remote_protocol    wire DTOs, frames, content types, error codes
   └─ helix_remote_domain      entities and value types only
helix_remote_calls (WebRTC engine, Flutter)   helix_remote_ui (tokens, components, Flutter)
```

\* `helix_remote_db` uses `drift` + `sqlite3` (SQLCipher hook), with no Flutter
dependency, so the FCM background isolate and the CLI can open it.

These packages are **retired at cutover:** `helix_remote_storage`,
`helix_remote_sync` and `helix_remote_groups` (folded into engine), and the
REST implementation inside `app/lib/app/remote_rest_client.dart` (moves to
`helix_remote_api`).

### 6.2 Local database (drift, SQLCipher, background isolate)

- **Opening:** `NativeDatabase.createInBackground` with a setup callback that
  applies `PRAGMA key` and WAL. There is never a DB call on the UI isolate.
- **Schema v1 starting point** (tables land only with the phase that uses
  them):
  - `self_account`, `self_devices`
  - `people` (account_id, helix_name, phone_hash, phonebook_name, nickname,
    avatar_blob, blocked, updated_at) and `person_devices` (identity key,
    trust state)
  - `conversations` (id, kind, title, avatar, pinned_at, muted_until,
    archived, **last_message_id, last_message_at, last_message_preview,
    unread_count, mention_count**, draft, disappearing_seconds) and
    `conversation_members`
  - `messages` (local_rowid, message_id UUIDv7, conversation_id, sender,
    sender_device, **sort_key**, sent_at, received_at, kind, body,
    reply_to_id, forwarded, status, edited_at, deleted_at, expires_at,
    view_once_state)
    - `message_reactions`, `message_receipts`
    - `attachments` (blob id, key, digest, mime, size, dims, duration,
      blurhash, thumbnail path, local path, transfer state)
    - `messages_fts` (FTS5, external content)
  - `call_log`
  - groups: `groups`, `group_members`, `group_settings`
  - crypto: `identity`, `sessions` (per device pair), `prekeys`,
    `sender_keys`
  - sync: `inbox_cursor`, `processed_envelopes`, `outbox_ops`,
    `transfer_jobs`
  - `settings` (typed key/value)
- **Rules:**
  - Denormalised conversation summary columns are updated in the same
    transaction as the message write.
  - Keyset paging on `(conversation_id, sort_key)`.
  - Drift schema dumps are checked in, and every migration has a
    `drift_dev` migration test from the first release onward.
- **Generated code:** committed. CI fails if `build_runner` output is stale.

### 6.3 Engine pipelines

- **Inbound:** WS frame or HTTP fetch → `processed_envelopes` dedupe →
  decrypt (session / sender key) → decode content → **apply** (one drift
  transaction: message row + summary + reactions/receipts/edits + FTS) → ack.
  - A failure quarantines only that envelope, with a visible "couldn't
    decrypt" row. It never blocks the stream.
  - The same code runs in the FCM background isolate, which then shows the
    local notification.
- **Outbound:** a UI action → one drift transaction (optimistic row + `outbox_ops`)
  → the outbox worker encrypts at send time → REST with an idempotency key →
  status update.
  - Backoff, stale-device-list rebuild, and a single wake-up path for
    every enqueue. This fixes today's group ops that wait for an unrelated
    trigger.
- **Transfers:** an attachment upload/download queue with resume, presigned
  URLs, and thumbnails generated locally.

### 6.4 App (`helix_remote/app/lib`)

```
lib/
  main.dart                     zones, error reporting, platform init, ProviderScope
  core/                         providers for engine/db/api, go_router + deep links
                                (helix://, https://helix.agiletechbd.com/open#HLX-…),
                                lifecycle, notifications, push, app lock, platform channels
  features/<feature>/
    application/                Riverpod Notifiers/StreamProviders (UI state only)
    presentation/               screens + widgets (StatelessWidget/ConsumerWidget)
  shared/widgets/               cross-feature widgets built on helix_remote_ui
```

- **Features:** `sign_in` (Global default page; hidden advanced mode: 3 taps
  bottom-right 2 s apart, 4th opens; shared link), `home` (Chats/Calls/Settings
  swipe tabs), `chats`, `conversation`, `people` (search inside Chats and
  Calls), `calls`, `groups`, `settings`, `devices`, `backup`, `profile`.
- **Rules:**
  - Presentation imports only its own `application/`, `shared/`,
    `helix_remote_ui` and `helix_remote_domain`.
  - Never `helix_remote_db`, `_api`, `_crypto` or `_engine` directly
    (enforced by test).
  - Every list is a `StreamProvider` over a drift watch query.
- **Performance budgets** (tests):
  - chat list with 5k chats builds in under 16 ms per frame
  - conversation open with 100k messages in the DB shows its first page in
    under 150 ms
  - 1,000-message burst without dropped frames (keeps
    `phase4_performance_budget_test`)

## 7. Carried-over invariants (must hold in v2; each has a test)

- **Security:**
  - The password never leaves the device (HKDF auth key only).
  - Sessions are minted in exactly one place.
  - Delivery uses active devices only.
  - Public routes are declared and rate-limited.
  - No secrets or content in logs.
  - No weakened signature or transcript checks.
- **Product:**
  - English literals, no l10n layer.
  - Light theme only; colours from theme/tokens.
  - Screenshots allowed (no FLAG_SECURE or display affinity).
  - `IconButton` tooltips; 48 px targets.
  - No contact requests; people naming order (phone-book name → nickname →
    number → `~Helix name`); renaming writes to phone contacts.
  - Three swipe tabs.
  - Sign-in rules as above.
- **Every test in `docs/security/REGRESSION_TEST_MATRIX.md`** has a v2
  equivalent before cutover. The matrix is updated to point at it.
- **Deployment:**
  - Agents never stop or restart the live server and never edit live
    DB/`.env`.
  - No APK builds unless asked.

## 8. Guardrails (how drift is prevented)

1. **Architecture tests** (fail CI):
   - Server: modules import only other modules' `api.dart`. No `dart:io` File
     use outside `platform/blobs`. No SQL outside `data/`. The public-route
     snapshot.
   - Client: the package DAG in §6.1. Presentation import rules. No `sqlite3`
     or `drift` import outside `helix_remote_db`. No `http`/`WebSocket`
     outside `helix_remote_api`.
2. **Every module and feature has its `MODULE.md`/`FEATURE.md`,** updated in
   the same commit as the code.
3. **This file's tracker (§11)** is updated at the end of every phase (status,
   date, commit, test counts).
4. **ADRs:** Phase 0 writes the ADRs. A change to §3–§6 needs a new ADR plus
   a change-log entry (§12) approved by the user.
5. **Gate per phase:** `dart analyze`/`flutter analyze` clean, all tests green,
   `dart format` on changed files, docs updated, one commit on the v2 branch.

## 9. Where the work happens

- **Branch:** `architecture-v2`, in a **git worktree at a short path**
  (`J:\hx2`). Production keeps running from the main checkout
  (`J:\Projects\helix`) on `main`, untouched.
- **Scope:** the new server is built in `helix_remote/server/` (parallel to
  `backend/`). The client stack is new packages. The app's `lib/` is rebuilt
  in place on the branch in phase A1, with the old `lib/` deleted from the
  branch; `main` keeps it for reference.
- **`main` still receives urgent fixes** to the live v1 during the rebuild,
  and those fixes are not ported unless the plan's feature needs them.

## 10. Phases

Each phase ends with its gate (§8.5). "User step" items are things only the
user does.

### Phase 0 — Decisions, tooling, guardrails
- **ADRs:**
  - 025 Postgres + stateless nodes (supersedes the implementation parts of
    ADR-019)
  - 026 server module architecture
  - 027 client architecture (drift + Riverpod + engine)
  - 028 protocol v2 contract reset (mailbox, E2EE control content,
    device-pair sessions, Sender Keys)
  - 029 guardrails
- **Dependencies:** entries in `DEPENDENCY_RISK_REGISTER.md` and a lockfile
  policy check for `postgres`, `drift`, `drift_dev`, `build_runner`,
  `flutter_riverpod`, `go_router`, and an S3 client (or a small SigV4 signer).
- **Worktree + branch.** CI: add a Postgres 17 service container for the v2
  server job, and add v2 jobs alongside the v1 ones. Local Postgres helper
  script for tests (`HELIX_TEST_DATABASE_URL`).
- **Architecture-test harness** (empty rules that later phases fill in).
- **User step:** install PostgreSQL 17 on the PC (native Windows installer
  recommended), and create role `helix` plus databases `helix` and
  `helix_test`.

### Phase P1 — Protocol v1 (new contract) and `helix_remote_protocol`
- **Spec:**
  - REST surface per module (new `openapi.yaml`)
  - realtime frames
  - envelope kinds
  - encrypted content types (text, media, reply, edit, reaction, receipt,
    delete, poll, location, contact, sticker, system)
  - errors, pagination, idempotency
- **Crypto spec:** the device-pair Double Ratchet with DH steps, Sender Keys
  distribution and rotation, prekey lifecycle, and the safety-number/identity
  change UX hooks.
- **Confirm the F1/F2 history model** (§4.4). Update the F1, F2, F3, F4 and
  F5 protocol docs, `DATA_FLOW`, `METADATA_INVENTORY` and
  `PRIVACY_CLAIM_MATRIX` (the server now sees less).
- **The package itself:** DTOs + codecs + golden fixtures + tests.
- **User checkpoint:** review the metadata and crypto changes before S1.

### Phase S1 — Server platform
- Config; the Postgres pool and `Db`/`Tx`; the migration runner; the HTTP
  pipeline and middleware; `RouteRegistry` with public-route declarations.
- `EventBus` (LISTEN/NOTIFY + in-memory), `EphemeralStore`, `RateLimiter`,
  outbox and job runner (leases, `SKIP LOCKED`, retries, DLQ), `ObjectStorage`
  (FS + S3), push/SMS/TURN providers, observability, health.
- Test harness: a fresh schema per test file on `helix_test`.

### Phase S2 — `identity` + `keys`
- Registration, password sign-in (HKDF key, lockout), phone OTP, invites,
  recovery codes, device linking, refresh rotation with reuse detection,
  `issueDeviceSession`, suspension and admin blocks.
- Prekeys and bundles, prekey-low events.

### Phase S3 — `messaging` + `realtime`
- Conversations and membership; mailbox send, fetch, ack and expiry; quotas;
  stale-device 409.
- WS gateway with routes in `EphemeralStore`, wake via the bus, replay with
  credits, typing and presence, and revocation closing sockets.
- Push via the outbox.
- `EXPLAIN` tests on hot paths.

### Phase S4 — `people` + `media` + `backup`
- Profiles, discovery match with budgets (keeps the documented T-5 oracle
  risk), blocks, privacy, reports.
- Presigned attachments with reference counts and GC; backups, history
  backups and backup media.

### Phase S5 — `groups` + `calls` + `group_calls`
- Roster authority, roles, invites, join links and moderation, with roster
  events into mailboxes.
- 1:1 call signaling over the bus, pending calls, TURN credentials and push
  wake.
- Group call rooms, links and scheduled calls, only if the app will ship them
  in A3. Otherwise they are deferred and listed in §13.

### Phase S6 — `federation` + `ops` + `admin` + `compliance`
- S2S signing and verification, the replay cache in `EphemeralStore`, and
  outbox relay jobs; home-server group authority.
- Ops and admin APIs, maintenance mode and feature flags; account deletion
  orchestration via events.
- Delivered as S6a (ops, admin, compliance), S6b (federation: identity,
  signing, 1:1 messages, keys, calls) and S6c (group federation).

### Phase S7 — Server hardening
- Two-node end-to-end test: messages, calls and revocation across nodes.
- Load harness for authenticated send/receive (k6 or a Dart tool): record p50
  and p95 at 1k simulated devices on the PC.
- Security review pass (`/security-review`). Docs: handoff and operability.

### Phase C1 — `helix_remote_db`
- The drift schema v1 subset needed by the engine; the background isolate;
  SQLCipher (wrong-key failure and no-plaintext tests, carried from P2-01).
- FTS5; watch queries; keyset paging; migration test scaffolding.

### Phase C2 — `helix_remote_crypto` v2
- The full Double Ratchet with DH steps and skipped-key caps.
- Device-pair sessions, Sender Keys, prekey replenishment logic.
- Test vectors, and cross-checks against the spec in P1.

### Phase C3 — `helix_remote_api` + `helix_remote_engine` (messaging core)
- Typed clients per server module, and the WS client.
- Session manager; inbound and outbound pipelines; direct chats with all
  content types; people; devices; settings.
- **Rebuild the CLI on the engine.** End-to-end tests: two CLI clients plus a
  linked second device through server v2.

### Phase C4 — Engine: groups, calls state, media transfers, backup
- Sender Keys groups end to end; call signaling state for the calls package;
  the transfer queue; history backup and restore; device-to-device transfer.

### Phase A1 — App shell
- The new `lib/` skeleton: Riverpod, go_router, deep links, lifecycle,
  app lock, notifications, and the FCM background handler running the engine.
- Sign-in flow with all its rules; the home tabs shell.
- Rule tests carried over: tokens, tooltips, targets, screenshots allowed,
  the English-only scan.

### Phase A2 — Chats + conversation + people
- The WhatsApp-level chat list and conversation.
- Composer, replies, reactions, edit and delete, receipts, media, voice
  notes, search (FTS).
- People search in Chats and Calls; contact info; the rename-writes-to-phone
  behaviour.
- Performance budget tests.

### Phase A3 — Calls + groups + settings + devices + backup + profile
- 1:1 calls: full-screen incoming, foreground service, audio routing.
- Groups UI and all settings pages. Device management; backup and restore;
  profile.

### Phase AD — Admin console on the new admin API

### Phase X — Cutover
- **Delete** `helix_remote/backend/`, `helix_remote_storage`,
  `helix_remote_sync` and `helix_remote_groups`, plus old tests and dead docs.
- **Update** AGENTS.md (repo map, schema versions), CI, `scripts/verify.*`,
  the security docs, the regression matrix and the handoff doc.
- Merge `architecture-v2` into `main`.
- **User steps:** create the production DB, add the new `.env` lines (listed
  exactly by the agent), stop the old backend, run `bin/migrate.dart`, start
  the new server, update Caddy if the upstream changes, and reinstall the
  app on phones.

## 11. Tracker

| Phase | Status | Date | Commit | Notes |
|---|---|---|---|---|
| 0 Decisions, tooling | **done** | 2026-10-01 | Phase 0 commit on `architecture-v2` | ADRs 025–029. `helix_remote_architecture_rules` (20 tests). `server/` skeleton (7 tests: architecture rules plus a Postgres 17 smoke test that is green against the local DB). `postgres 3.5.17` locked (lockfile additions only). Postgres 17 service on CI `verify-linux` with `HELIX_REQUIRE_TEST_DATABASE=1`. Verify scripts cover `server/`. Local role and DBs created by the user. Known pre-existing failure: governance check (3 stale screen-capture controls, identical on `main`). |
| P1 Protocol | **done** (review pending) | 2026-10-01 | P1 commit on `architecture-v2` | `docs/protocol/v2/` (REST, realtime, content, crypto, metadata, review checklist). `helix_remote_protocol` with 63 tests: route catalog (126 routes, public-route snapshot, doc coverage), DTOs for every module except admin, envelopes, frames, sealed payloads, content model, padding, UUIDv7. 9 golden fixtures in `contracts/v2/fixtures/`. |
| S1 Server platform | **done** | 2026-10-01 | S1 commit on `architecture-v2` | Async `Db`/`Tx` over a Postgres pool (afterCommit hooks, constraint mapping, serialization retries, LISTEN/NOTIFY). Checksummed per-module migrations under an advisory lock. Postgres event bus, UNLOGGED ephemeral store, one-statement token buckets. Outbox and job runner with SKIP LOCKED leases, backoff, dead letters and dedupe. Cluster-safe periodic jobs. Local and S3 (SigV4) object storage. A route registry checked against the protocol catalog (public routes need limits). Pipeline with request ids, trusted-proxy IPs, global limits, maintenance mode, error mapping and security headers. Idempotency keys, redacting JSON logs, Prometheus metrics, typed config, module system, `HelixServer`, the `ops` health module, `bin/server.dart`, `bin/migrate.dart`. 57 server tests on Postgres, including two-node checks (jobs never double-run, rate limits shared, bus across connections, second server on the same DB). |
| S2 identity + keys | **done** | 2026-10-01 | S2 commit on `architecture-v2` | Identity serves all 28 routes. Phone codes are peppered and hashed (5 tries, per-number limits, configurable resend gap). Invites. Registration verifies the AIK certificate and DSK proof. Explicit `replace_existing` replaces the v1 SMS takeover. Password sign-in returns decoy parameters, uses an HMAC verifier and has a doubling lockout; sign-in tokens are single-use. QR linking uses a provisioning relay with a private poll token. Device-key challenge sign-in. JWT key ring (15-minute access tokens with a millisecond cut-off); refresh rotation with reuse detection that commits before failing. Recovery codes rotate the AIK. Device revocation, revoke-others, `~Helix names` with staff-like names blocked, security events, push tokens, suspended principals. In-transaction hooks for other modules. Keys module: signed and one-time prekeys, SKIP LOCKED bundle hand-out, low-prekey signal, revocation purge. 79 server tests on Postgres, including two-node checks, the single-mint-point architecture test and route parity. |
| S3 messaging + realtime | **done** | 2026-10-01 | S3 commit on `architecture-v2` | Mailbox hash-partitioned 16 ways. Row-locked per-device seq with pending quota. Two-statement unnest fan-out. Idempotent sends. Exact device-list checks (`device_list_stale` details). Block-policy hook. Ephemeral delivery via ephemeral store + bus. Cumulative ack deletes; 30-day expiry. Data-only push wake jobs (FCM HTTP v1 port, token pruning) coalesced per pending device. Account-signal, device-list and prekeys-low envelopes for own devices. WebSocket gateway: subprotocol check, hello, replay with a 100-envelope credit window, live wake across nodes, supersede (4008, cross-node), revoke (4003), idle (4010), routes with TTL refresh, tracked tasks for clean shutdown. 97 server tests on Postgres, including a two-node socket delivery; stable over repeated parallel runs. |
| S4 people + media + backup | **done** | 2026-10-01 | S4 commit on `architecture-v2` | People: encrypted profiles (versioned), privacy audiences with an uploaded contact list, blocks enforced as messaging's block policy, salted-hash discovery with a 5,000/day budget, `~name` lookup, presence and last-seen by audience (minute granularity), reports, account purge. Media: random-id objects in three kinds with size limits, quotas and expiry; resumable local uploads (offset conflicts, size caps) or presigned S3; ranged downloads or 302 to presigned GET; expiry and abandoned-upload sweeps; account purge job. Backup: versioned history backup deleted on AIK change; full backup envelope refusing secrets at any depth and refreshing its media retention. 110 server tests, stable over repeated parallel runs. |
| S5 groups + calls | **done** | 2026-10-01 | S5 commit on `architecture-v2` | Groups: roster authority with owner/admin/member roles and permission settings; group-add privacy; removal, leave and ban bump the epoch with owner succession; hashed invite links with encrypted previews; approval join requests announced to admins; optimistic state blob; non-members get 404; sender-key fan-out guarded by a member-device digest (stale returns every device), with distributions stored first; roster-change envelopes. Calls: sealed signals, live to online devices, pending plus call push for offline ones, complete device lists for offers, blocks, answered-elsewhere stops other devices ringing (ephemeral end plus call_ended push), pending fetch, coturn REST TURN credentials, metrics. Group calls deferred. 123 server tests. |
| S6 federation + ops + admin | **done** (S6a, S6b, S6c) | 2026-10-01 | S6a, S6b and S6c commits on `architecture-v2` | S6a: ops serves server info (with allow-listed feature flags), legal documents, opt-in crash telemetry (redacted log line, never stored), admin-only metrics, Android asset links and the `/open` page (`HLX-INV/REC/GRP`). Operator settings (name, maintenance, federation switch, flags) live in `ops.settings`, cached per node and invalidated over the bus; maintenance mode is wired into the pipeline. Admin module: first-run setup or `HELIX_ADMIN_PASSWORD` seed, Argon2id on an isolate, lockout, 12-hour `helix.admin` tokens on the shared key ring (audience-separated from device tokens), password change ends other sessions; accounts (paged, filtered, last 4 digits only), suspend, ban, delete, device revoke, recovery codes, invites, reports, audit log for every mutation, config, flags, logs and a live log WS, purge. Compliance: snapshot export with one section per module (`ProvidesAccountExport`) and confirmed self-deletion through identity's hooks. Session cut-offs compared at millisecond precision. 137 server tests, 66 protocol tests. S6b: federation module with an Ed25519 server identity, `/.well-known/helix-server`, peers trusted through their domain (TLS) with a 24-hour cache, rotation re-fetch and a negative cache, an SSRF guard (link-local always refused; loopback and private unless allowed), an allow list and an operator switch. Signed S2S requests (`s2sSigningInput`, ±5 min skew, single-use signatures). Qualified `uuid@domain` addresses in sends, key fetches, blocks and call signals; foreign senders, blockees and callers stored qualified (migrations 2 in messaging, people, calls). Message relay is synchronous with stale lists qualified, and is queued with retries while a peer is down. Remote key bundles, live call-signal relay, inbound S2S routes. 149 server tests (two-server federation tests on one Postgres) and 70 protocol tests. |
| S6c group federation | **done** | 2026-10-01 | S6c commit on `architecture-v2` | Home-server authority for groups with members on other servers. Members, bans and join requests store `uuid@domain`; every S2S payload is rendered in the receiving server's frame. Remote members' route calls are proxied as S2S actions through the same operation code. Snapshot and roster-change syncs are versioned and queued per server; their answers carry members' devices (for the digest) and accounts refused by the member's own server's privacy and existence checks. Group messages fan out per server through queued jobs. Member servers cache snapshots, list remote groups, report device changes and leave on account deletion. Invite tokens name group and home. 157 server tests (8 two-server group tests), 72 protocol tests. |
| S7 Server hardening | **done** | 2026-10-02 | S7 commit on `architecture-v2` | Two-node end-to-end test (18 tests: messages, calls, revocation, sign-out, admin actions, supersede, groups, jobs across two nodes on one Postgres). Load harness `server/tool/load.dart` (Dart isolates, real registration): 1k devices at 50 sends/s gave send p50/p95 18/320 ms and delivery 18/351 ms with no loss; one node tops out near 80 sends/s on this PC (bound by DB round trips; `HELIX_DB_POOL_SIZE` now configurable). It found and fixed a pool deadlock (presence read inside the send transaction; the ephemeral store has its own pool, nested `Db.tx` joins the outer one) and job ticks that crashed the process. Security review: 17 findings (1 high, 7 medium, 9 low), all fixed with tests: credentials and S2S header checks before bodies are read plus a per-node body budget and JSON depth caps; rightmost-untrusted `X-Forwarded-For` (`X-Real-IP` only when configured); federated group syncs and fan-outs re-check local accounts' privacy, blocks and sender membership; no redirects and IPv4-embedded IPv6 classified in the SSRF guard with pinned connections; message-id replay scoped per sending device; password change shares the sign-in lockout; sign-out, refresh reuse and token expiry close sockets (4001) on every node; per-IP admin lockout; S3 PUTs sign content length; device challenges keyed by a random id; call state scoped to participants; send, upgrade, frame (64 KiB, 4029) and call-metric limits; idempotent responses encrypted at rest; malformed input answers 400. Operability: `V2_SERVER_HANDOFF.md` (env table, draft cutover checklist), `V2_OPERABILITY.md`, `HELIX_LOG_FILE`, one boolean parser, exit 78 on config errors, `HELIX_METRICS_TOKEN` with dead-letter and backlog gauges, LISTEN reconnect with `platform.resync`. `ephemeral_store.dart` had been hidden by a Flutter `.gitignore` rule and is now tracked. 229 server tests, 72 protocol tests. |
| C1 helix_remote_db | **done** | 2026-10-02 | C1 commit on `architecture-v2` | `helix_remote_db` on drift 2.34.0 + SQLCipher, pure Dart. Opens on a background isolate with a fail-closed key check (cipher loaded, `cipher_status`, file decrypts; never opens plaintext), raw 32-byte key, WAL. Schema 1: self account/devices, people + person devices, conversations (summary columns) + members, messages with reactions, receipts, attachments and FTS5 (external content, triggers, Unicode tokenizing), identity, device-pair sessions, prekeys, sender keys, inbox cursor, processed envelopes, outbox ops, deferred actions, typed settings. Groups, call log and transfer jobs land in C4. Summary updated in the same transaction as the message, keyset paging both ways, watch queries, outbox leases. Generated code committed; `tool/codegen.dart --check` in CI and the verify scripts; schema dump v1 and migration test scaffold; the package is pinned to LF endings so the check is stable on Windows. P2-01 wrong-key and no-plaintext tests carried over; 100k-message first page under 150 ms. 42 db tests, 20 rules tests. |
| C2 crypto v2 | **done** | 2026-10-02 | C2 commit on `architecture-v2` | `helix_remote_crypto/lib/v2.dart`, pure Dart, v1 files unchanged until X. AIK device certificates, per-device-pair X3DH, full Double Ratchet with DH steps and skipped-key caps (1,000 per chain, 2,000 per session, 30 days), a session manager with simultaneous-initiation convergence, §13a resets and a replay guard, Sender Keys behind `GroupCryptoProtocol` with rotation, prekey replenishment policy, safety numbers, password-wrapped AIK, attachment STREAM v2, backup envelope v3 and history backup, provisioning, sealed group-state and profile blobs. State is returned, never written: the engine commits it in its own transaction before sending. Known-answer tests (RFC 5869/7748/8032), byte-layout cross-checks against CRYPTO_V2, golden vectors, tamper/replay/out-of-order property tests. 70 v2 tests (132 in the package with v1). Not externally reviewed. |
| C3a api clients | **done** | 2026-10-02 | C3a commit on `architecture-v2` | `helix_remote_api/lib/v2.dart` beside v1 (v1 retires at X): `HelixApi` with one typed client per device-facing module, `HelixAdminApi` with `AdminClient` on its own token transport, a `RealtimeClient` (hello and replay, credit-window acks, idle detection, jittered reconnect, the REALTIME_V2 close-code policy, states and envelope streams), and a transport with single-flight token refresh, idempotency keys, retries only where safe (public POSTs never retry), `Retry-After`, cancellation and a sealed typed error hierarchy. Presigned and redirect URLs never get the bearer token; no tokens or bodies in exceptions. Route-parity test (every non-S2S route has exactly one client method). Hand-rolled WebSocket upgrade in `io_socket.dart` to tell 401 from 403. 185 new api tests (231 with v1) and 15 integration tests against an in-process v2 server in `server/test/client/` (237 server tests). |
| C3b engine core + CLI | **done** | 2026-10-02 | C3b commit on `architecture-v2` | `helix_remote_engine` (pure Dart): `Engine(api, db, clock, random, config, phoneBook)` with start/stop, `syncOnce` (headless, returns `IncomingNotice`s for the FCM isolate), `drainOutbox`, maintenance and sign-out; services for account/devices/chats/people/settings/presence/push returning futures and drift watch streams. Registration, password and QR-link sign-in, prekey upkeep and signed-prekey rotation, per-device-pair sessions committed before send, stale device list rebuild, key-change trust state, §13a recovery, dedupe and quarantine, the transactional apply (message + summary + reactions/receipts/edits/deletes/timers + FTS), the outbox worker with backoff and per-conversation ordering. v2 CLI `helix_v2` (register, login, link, chats, send, read, fetch, watch, contacts, devices, `--json`; the db key comes from `HELIX_DB_KEY` or a key file; phone numbers masked). db DAO additions only. 88 engine, 13 CLI, 49 db tests; 22 engine end-to-end tests on the in-process server (two engines both ways, linked device, offline catch-up, revocation, stale list, key change, §13a, prekey top-up, stress, CLI exchange); 272 server tests. Open for C4/A1: groups, calls, media, backup; recovery needs `account_id` on the lookup response; multi-isolate drift stream visibility. |
| C4 engine: groups, media, backup | **done** | 2026-10-03 | C4 commits on `architecture-v2` (`a6258cb` db schema 2, `75956e0` K, `7851096` M, `4e912de` B, `84575a7` G) | Built as four parallel pieces and merged. **db schema 2** (a real drift migration with a step-by-step `from1To2`, schema dump v2): `groups`, `group_members` (cached device lists), `group_bans`, `call_log`, `transfer_jobs`, `transfer_chunks`, three DAOs; the codegen failure that blocked it was a missing `async` (`combining_builder` reports syntax errors with an empty message). **Groups**: Sender Keys groups end to end (create, rename, state versions with conflict retry, members, roles, bans, invite links, join requests, key rotation on removal and device change, digest and stale-device recovery, group chats on the direct-chat pipelines, federated members). **Calls**: the 1:1 call state machine, call log, pending-call fetch, a `CallMediaSession` seam for the Flutter calls package (A3), `CallSignalPayload` sealed signals; **account recovery** through an additive `account_id` on `RecoveryLookupResponse`. **Media**: a durable leased resumable transfer queue over a `BlobStore` seam, attachment content types, integrity checks, cancellation. **Backup**: history backup, restore, full-backup envelope and device-to-device transfer. Tests: engine 265, db 121, api 232, protocol 74, rules 20, app 61, full server suite green (end-to-end tests for calls, recovery, media, backup and groups, including a two-server group). Not built: group calls (deferred), live-location updates. Review items: the `groups` summary columns are unused (the chat list reads `conversations`); only agent K's reviewed logic has a written report — groups, media and backup were integrated on test evidence. |
| A1 App shell | **done** | 2026-10-02 | A1 commit on `architecture-v2` | The v2 `app/lib/` replaces the v1 tree (146 files deleted from this branch; `main` keeps them): `main.dart` owns the zone, the error handler, the FCM background-handler registration and the one `MaterialApp.router`; `core/` holds the wiring only - `engine/` (`HelixRuntime` owning db+api+engine for one server, the `RuntimeFactory` seam, `serverUrlProvider`, engine status mapped to `AppAuthState`, sign-out and the typed destructive reset), `router/` (go_router, the redirect, deep-link routing), `links/` (`HelixDeepLink` and the `HLX-INV-`/`HLX-REC-` codecs carried over from v1), `platform/` (`AppPaths`, `SecureKeyStore` for the 32-byte SQLCipher key, `ServerUrlStore`, `DevicePhoneBook`), `lifecycle/` (resume reconnects and syncs), `security/` (app lock and `AppSettings`), `notifications/`, `push/`. The FCM background handler builds its own engine and calls `syncOnce` with no socket and no timers; the payload is only a wake-up, never content. Sign-in is one controller (`features/sign_in/application/`) plus five stateless pages: the Global page opens by default with no back button and no host-your-own copy, personal servers stay behind the hidden corner (3 taps within 2 s, a 4th opens) and a shared link, and every user-facing string comes from `sign_in_copy.dart` rather than an exception. The home shell is three swipeable kept-alive tabs; every list is a `StreamProvider` over an engine watch query mapped to `helix_remote_ui` value objects. A new `test/architecture_test.dart` enforces the §8.1 client rules (presentation imports only its own application, shared, ui and domain; features do not import features; no v1 package; no sqlite/drift or http outside their owners; the two logging sites report an exception type only). Carried-over rule tests re-created over the new layout in `test/product_rules_test.dart` (tokens, tooltips, no clamped scaling, screenshots allowed, English-only scan added from the admin suite, light theme only, Android manifest expectations) with `accessibility_test.dart`, `sign_in_flow_test.dart`, `deep_link_test.dart`, `performance_budget_test.dart` and the on-device corner test in `integration_test/`. 61 app tests pass; `flutter analyze` and `dart format` are clean. Riverpod 3.4.3 and go_router 18.0.2 resolved as Phase 0 registered them. Not in A1, and left honest rather than stubbed: the conversation, people search, groups, calls, media, backup and the settings pages are A2/A3, so the Calls tab is an empty state. Two review items for A2: the optional sign-up password lives on the name page for now, and the chat list shows a conversation title rather than the full people-naming order. Earlier UI groundwork: UI groundwork landed early (2026-10-02, commit `9f1eaa2`): stateless chat, conversation, composer and general components with view models in `helix_remote_ui`, a gallery, and accessibility, performance and rule tests (182 pass, 5 golden tests skipped off Linux). The four new golden baselines still need generating on Linux (`flutter test test/chat_components_golden_test.dart --update-goldens`). Sticker, poll, event and live-location bubbles are deferred. A1/A2 consume it. |
| A2 Chats + conversation + people | not started | | | |
| A3 Calls, groups, settings, … | not started | | | |
| AD Admin console | **done** | 2026-10-02 | AD commit on `architecture-v2` | `helix_remote/admin` rebuilt on `HelixAdminApi` only (v1 admin client and screens removed): first-run setup, two-step sign-in with lockout and 12 h expiry notice, change password, device App lock, overview (health, maintenance, federation switch, flags, activity incl. dead jobs and backlog), accounts (paged, search by name or last 4 digits, suspend, ban, delete by typing DELETE, device revoke, recovery code shown once), invites, reports, audit log, live server log, settings and purge. `ChangeNotifier` controllers, token in secure storage, plain `http://` refused except for the local machine. Fixed the api transport so a 401 `invalid_credentials` (wrong current password) no longer ends an admin session. 174 admin tests, 13 integration tests in `server/test/client/`. A new admin APK is needed to try it (not built); `flutter run -d windows` in `helix_remote/admin` works for a quick look. |
| X Cutover | not started | | | |

Phase order: 0 → P1 → S1 → S2 → S3 → (S4, S5, S6a–c in any order) → S7.
C1 and C2 may run once P1 is done. C3 needs S3. A1 needs C3. X comes last.

## 12. Change log (plan changes approved by the user)

| Date | Change | Approved in |
|---|---|---|
| 2026-10-02 | A1: the app depends on `helix_remote_engine` and reads everything through a `RuntimeFactory` seam, so no test opens a keystore, a database file or a socket; `runtimeProvider` is rebuilt (and the old runtime closed) when the server changes. `presentation/` may import only its own feature, `shared/`, `helix_remote_ui` and `helix_remote_domain` - the Settings tab reads one `SettingsTabModel` instead of `serverUrlProvider`, and sign-out is a `SignOutAction` in the application layer. Drift watch streams do not cross isolates (the open A1 item): the FCM isolate writes the same file the UI isolate has open, so its changes reach the UI on the next query, not live; the app reconciles with `syncOnce` on resume. The FCM handler is registered before `runApp` and runs a headless engine. v2 `PhoneVerifyResponse` carries `hasPassword` and `account_id`, so the sign-in order is phone → SMS → (password \| name) rather than v1's lookup-then-decide; the optional sign-up password is on the name page for now. `helix_code.dart`, `deep_link.dart` and `link_channel.dart` are carried over unchanged from v1 (one fix: a `join?invite=` link now yields the bare origin instead of a URL with a trailing `?#`). Riverpod 3.4.3 and go_router 18.0.2 as registered in Phase 0; `cryptography_flutter` is not needed (crypto v2 has `SecureCryptoRandom`). Group calls stay deferred. | this session (autonomous run) |
| 2026-09-30 | Plan created (D1–D5). | this session |
| 2026-10-02 | C3b: the engine requests a §13a re-send after authentication failures of user-visible messages (the `urgent` flag); receipts, reactions, edits, deletes, votes, typing and `decryption_error` are sent non-urgent and get no placeholder, repair request or push; one fresh session per device per 10 minutes at most. `decryption_error` names the failed envelope id; re-sends use a new request id (the server de-duplicates by sending device and id). `signOut` always wipes the local db and revokes the device. The db package gained DAO methods only. The server's `test/client/` may import engine, db, crypto and CLI packages. Review items: reset requests triggered by authentication failures (a hostile server can make a client start cooldown-limited sessions); recovery lookup lacks `account_id` (fixed in C4); drift watch streams do not cross isolates (A1 decides). | this session (autonomous run) |
| 2026-10-03 | C4: db schema version 2 (`groups`, `group_members`, `group_bans`, `call_log`, `transfer_jobs`, `transfer_chunks`; `group_settings` stays inside the encrypted state blob). New protocol DTO `CallSignalPayload` (sealed call signals) and an additive `account_id` on `RecoveryLookupResponse` (the code is a 256-bit bearer secret and the redeem still needs phone verification; lookups stay rate-limited and answer only `valid: false` for bad codes). Headless sync lists pending calls without opening the offer. Media, backup and group history use injected seams (`BlobStore`, `MediaProcessor`, `CallMediaSession`) so the engine stays pure Dart. Group-state AAD, one-time-prekey use on unknown-sender lookup and password normalisation stay open review items from C2. | this session (autonomous run) |
| 2026-10-02 | AD: the admin console keeps `ChangeNotifier` state (Riverpod in §6.4 applies to the app only) and depends only on protocol, api and ui. A client 401 with `invalid_credentials` is a wrong password, not a token rejection. Browsers cannot send an `Authorization` header on a WebSocket, so the web admin log polls every 3 s. The console refuses plain `http://` except for the local machine. v1 admin features with no v2 admin route are dropped (backup trigger, support bundle, push/SMS/TURN probe cards, latency probe). | this session (autonomous run) |
| 2026-10-02 | C3 is split into C3a (API clients, done) and C3b (engine and CLI). The v2 API is a new library (`lib/v2.dart`) beside v1 until A1/X. The server's tests may import `helix_remote_api` under `test/client/` only. | this session (autonomous run) |
| 2026-10-02 | C2: CRYPTO_V2 §9 derived the group-state and profile blob nonce from the key, which reuses the GCM nonce across versions; v2 uses `key = HKDF(secret, info, 32)`, a random 12-byte nonce, format `u8(1) ‖ nonce ‖ ct`, and padded plaintext (AADs unchanged). Ambiguities resolved in CRYPTO_V2 §14: prekey messages are checked against the sender device's certified identity; a previous session that decrypts is promoted; dropped sessions' base keys are remembered against replay; federated accounts bind only their UUID bytes; backup v3 and history-backup layouts defined. Open review items: the group-state AAD binds the epoch but not the state version (server rollback within an epoch); looking up an unknown sender's identity via `GET /v1/keys` consumes a one-time prekey; passwords are not Unicode-normalised. | this session (autonomous run) |
| 2026-10-02 | C1: drift/drift_dev 2.34.0 and build_runner 2.15.1 instead of 2.35.0/2.16.1 (drift_dev 2.35 needs an analyzer that conflicts with Flutter 3.44's pinned `test_api`). Schema additions beyond §6.2: `deferred_actions` (CONTENT_V2 §3 keeps early actions up to 7 days), `people.phone_number` and the pinned AIK, and message columns `payload`, `outgoing`, `mentions_me`, `reply_to_author`; the summary column is `last_message_rowid`. Generated code is excluded from the coverage gate. | this session (autonomous run) |
| 2026-10-02 | S7 hardening changes to the contract: close code `4503` (server going away / could not deliver) replaces `1001`, which WebSocket libraries cannot send; `4001` also covers token expiry and ended sessions (a socket lives at most one access-token lifetime); `4004` when an account is suspended while connected (read-only reconnect allowed); `4029` for more than 20 upgrades per device in 10 minutes or frames beyond a burst of 300 at 30/s; client messages are capped at 64 KiB; REST acks return socket credit. `DeviceChallengeResponse`/`DeviceSignInRequest` carry a required `challenge_id`. Message-id idempotency is per sending device (messaging migration 3). A home server no longer fans a member's group message back to that member's own server; a member server delivers its own members once the home accepts, and refuses home fan-outs naming its own accounts as sender. A new local member of a remote group needs a join request made through their own server (`remote_joins`, groups migration 3) or a legitimate adder in the snapshot. S2S clients never follow redirects; inbound S2S key fetches share the per-target limit. Limits: password change shares the sign-in lockout (10/hour), admin sign-in locks per IP with a global cap of 100, call metrics 100/day, sends 5/s per device and 10/s per account. New env: `HELIX_DB_POOL_SIZE`, `HELIX_MAX_INFLIGHT_BODY_BYTES`, `HELIX_TRUST_X_REAL_IP`, `HELIX_METRICS_TOKEN`; `HELIX_LOG_FILE` now works. The ephemeral store uses its own small pool. Full-backup envelopes keep the 64 MiB cap but are limited to 32 levels and 100,000 JSON values. Review items: password change does not end other sessions; dumps contain the federation private key; restoring an older DB can rewind `device_seq`. | this session (autonomous run) |
| 2026-10-01 | Parallel tracks allowed: phases with no dependency between them (per the phase-order line under §11) run side by side in agents, each in its own worktree and branch, and are still committed one phase per commit on `architecture-v2`. S7, C1 and C2 run together first. Replaces "one phase at a time, no parallel phase tracks" in §13. | this session (user: use agents side by side) |
| 2026-10-01 | S6c: group S2S payloads are rendered in the receiver's frame (`Frame`); S2S actions answer 200 with the operation's own status and body inside. New DTOs `S2SGroupAction(Result)`, `S2SGroupSync(Response)` and `S2SGroupMessage`. Adding a remote account is optimistic: its own server may refuse it in the sync answer, and the home then removes it. Invite tokens become `grp_<secret>.<group id>@<home>` when federation is installed. | this session (autonomous run) |
| 2026-10-01 | S6b: federation trust root is the peer domain's TLS certificate (`/.well-known/helix-server`, cached 24 h, re-fetched on a failed signature); there is no directory server. Accounts on other servers are `AccountAddress` `uuid@domain`, with the domain being the public base URL's authority. Foreign ids are stored qualified as `text` through migration 2 in messaging, people and calls. S2S signing input is `helix-s2s-v1\|server\|ts_ms\|METHOD\|path?query\|b64(sha256(body))`. Message relays are synchronous and fall back to an outbox retry while a peer is down; call relays are synchronous only. New env: `HELIX_FEDERATION_ENABLED`, `HELIX_FEDERATION_ALLOW`, `HELIX_FEDERATION_ALLOW_PRIVATE`, `HELIX_FEDERATION_HTTP` (dev only). Group federation moves to a new phase S6c. Remote profiles and presence have no S2S route in the catalog (review item). | this session (autonomous run) |
| 2026-10-01 | S6 split into S6a (ops, admin, compliance) and S6b (federation), committed separately. Admin DTOs added in `modules/admin.dart`; `ServerInfo` gains optional `features`; `AccountExport` DTO. Feature flags are an allow-list (`crash_reporting_upload`, `minimal_analytics`, `group_calls`). The admin password is sent to the server over TLS and stored as Argon2id (user passwords still never leave the device). First-run admin setup stays public as in v1, with `HELIX_ADMIN_PASSWORD` as the safe alternative (flagged for review). Reports survive account deletion as the moderation record. | this session (autonomous run) |
| 2026-10-01 | S5: `RosterChangeKind.join_requested` added (admins only). For group sends, `device_list_stale.missing` carries every current member device (the server sees only the client's digest). Group messages are not filtered by personal blocks. | this session (autonomous run) |
| 2026-10-01 | S4: local-storage upload targets are server-relative paths (no dependence on a correct public base URL). The router puts HEAD routes before GET routes (shelf_router lets GET answer HEAD). Presence `contacts` audiences use an opt-in uploaded contact list. | this session (autonomous run) |
| 2026-10-01 | S3: the server keeps no conversation graph, so `device_list_change` and `key_change` go to the account's own devices only; peers learn from `device_list_stale` and from AIKs in bundles (CRYPTO_V2 §2 updated). Push is a platform service with data-only wake-ups (`{t: message\|call\|call_ended}`). Ephemeral envelopes are parked in the ephemeral store, with a bus pointer, because NOTIFY payloads are capped. New close code `4010` for idle. Presence routes live in `kernel/presence.dart`, which breaks the messaging↔realtime cycle. | this session (autonomous run) |
| 2026-10-01 | S2: `PhoneVerifyResponse` gains an optional `account_id` (additive) so `replace_existing` registrations can certify the device. The platform DB interface `Session` is renamed `SqlSession` (it clashed with the protocol DTO). BulkSMSBD is called by POST instead of GET, keeping the API key out of URLs; this must be confirmed against the real gateway at cutover. Generic crypto helpers live in `server/lib/src/kernel/crypto.dart`. | this session (autonomous run) |
| 2026-10-01 | S1: migrations are Dart constants (`List<Migration>` per module), not `.sql` files, so they compile into the server binary. Tests isolate by a random **schema prefix** instead of a database per test, because the `helix` role has no CREATEDB. Push, SMS and TURN providers move to the phases that use them (S2 SMS, S3 push, S5 TURN), so no unused code is ported early. | this session (autonomous run) |
| 2026-10-01 | P1: the Dart route catalog plus `REST_V2.md` replaces a hand-maintained v2 OpenAPI file (a test keeps them in sync). Product docs (`METADATA_INVENTORY`, `PRIVACY_CLAIM_MATRIX`, `DATA_FLOW`, F1–F5) keep describing v1 until cutover. `METADATA_V2.md` and the v2 protocol docs hold the v2 truth and are folded in at Phase X. Admin DTOs move to S6/AD, and S2S payload details to S6. | this session (autonomous run) |
| 2026-10-01 | Group calls deferred from v2. S3 signing via `aws_signature_v4`. Autonomous run through AD, one phase at a time; P1 checkpoint becomes review-later. | this session |
| 2026-10-01 | §13 recommendations accepted (history, locked chats, native Postgres). Phase 0: v2 CI coverage goes into the existing `verify-linux`/`verify-windows` jobs instead of separate jobs. `helix_remote_architecture_rules` is a test-only package (`testOnlyPackages`), importable only from `test/`. | this session |

## 13. Open questions (resolve in the named phase, record the answer here)

On 2026-09-30 the user accepted the recommendations ("continue as your
recommendation"):

- **Resolved — history:** a new device gets history only through
  device-to-device transfer or the encrypted history backup. There is no
  server history (ADR-028).
- **Resolved — locked chats:** the lock is a UI gate plus hiding the chat
  from the list and from notifications. There is no extra key beyond
  SQLCipher.
- **Resolved — Postgres:** it runs natively on the PC, as the existing
  `postgresql-x64-17` service. The `helix` role and the `helix` and
  `helix_test` databases come from `server/tool/setup_local_postgres.ps1`,
  which the user runs. Agents never handle Postgres passwords.
- **Resolved 2026-10-01 — group calls:** deferred from v2. The `group_calls`
  module and its UI are not built in S5/A3. The design keeps room for them:
  room keys travel as E2EE content, and the `calls` signaling routes stay
  generic.
- **Resolved 2026-10-01 — S3:** `aws_signature_v4` signs requests to any
  S3-compatible store. The local-filesystem `ObjectStorage` ships first.

### Cutover decisions (2026-10-02, answered by the user)

- **Federation:** off at cutover (single server). It can be switched on later
  from the admin console.
- **Admin setup:** `HELIX_ADMIN_PASSWORD` in `.env`, not the public first-run page.
- **Uploads:** local disk next to the server, backed up with the database.
- **Merge:** merge `architecture-v2` into `main` keeping every commit, and
  tag the last v1 commit (`v1-final`).
- **SMS:** v2 calls BulkSMSBD by POST. The user tests one real code on
  cutover day; if the gateway refuses it, switch back to GET.
- **TURN:** `start-turn.ps1` reads the secret from the new server's `.env`
  (same secret, so calls keep working). It must change before Phase X
  deletes `backend/`.
- **Phones:** same app id and signing key. Uninstall the old app, then
  install the new one (old chats cannot carry over).
- **Rollback:** the user wants no rollback plan (no real users, fix forward).
  The `v1-final` tag still exists as a by-product of the merge.

### Autonomous run (2026-10-01)

The user is away and asked for the phases to continue without them:
- **One phase at a time**, no parallel phase tracks (superseded on 2026-10-01:
  independent phases may run in parallel agents, see §12).
- **Every phase through AD.** Phase X (cutover) waits for the user.
- **P1 review:** proceed, review later. Every P1 design choice is marked
  *pending user review* in the P1 docs. Changes the user asks for on review
  become change-log entries.
