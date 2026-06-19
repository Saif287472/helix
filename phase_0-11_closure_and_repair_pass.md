Act as the senior software architect, application-security engineer, cryptography integration engineer, backend engineer, Flutter engineer, and test engineer responsible for completing the Helix foundation before Phase 12.

PROJECT ROOT
J:\Projects\helix

AUTHORITATIVE PLAN
HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md

PRIMARY OBJECTIVE
Perform a Phase 9–11 Closure and Repair Pass so Helix is genuinely ready to begin Phase 12 — Remote One-to-One Messaging MVP.

Do not begin Phase 12 product features yet.

Do not implement account setup screens, contact UI, conversation UI, normal message-composer UI, typing indicators, reactions, read receipts, or other Phase 12 functionality. You may create narrowly scoped internal integration harnesses, debug diagnostics, and startup/bootstrap screens only when they are required to prove that the Phase 9–11 foundations are actually connected.

CURRENT AUDIT CONCLUSION
Phases 0–7 are mostly sound. Phases 8–11 contain useful foundations but are overstated as complete.

The most important known problems are:

1. apps/helix_remote is still a placeholder shell.
2. RemoteCompositionRoot does not bind the actual Remote API, crypto, storage, synchronization, identity, session, and lifecycle resources.
3. The current “DoubleRatchetSession” is not a complete Double Ratchet implementation.
4. The current X3DH implementation does not adequately verify signed prekeys.
5. Decryption state may advance before ciphertext authentication succeeds.
6. Remote storage uses PRAGMA key without proving that a SQLCipher-enabled SQLite engine is actually loaded.
7. Plaintext message and pending-operation data may remain visible in the database file.
8. Remote storage has only an initial schema and does not yet prove migration, corruption recovery, backup, and lifecycle guarantees.
9. The sync gateway and sync engine do not strongly scope inbound events.
10. Inbound sync batches are not applied as one atomic transaction.
11. Only a small subset of Remote event types is processed.
12. Retry behavior does not implement genuine jitter and durable next-attempt scheduling.
13. Backend tests are not part of the canonical verification pipeline.
14. The export script does not reliably include services/, contracts/, and infra/.
15. CI does not provide sufficient evidence for all Phase 10 claims.
16. Local panic wipe may report success after a partial failure, and some file-deletion errors are swallowed.
17. The roadmap marks work complete where implementation or evidence is still incomplete.

NON-NEGOTIABLE RULES

1. Do not trust existing completion checkboxes. Verify every relevant claim against executable code and test evidence.
2. Do not mark an item complete because a Markdown document exists.
3. Do not mark an item complete because a class or interface exists.
4. Do not mark an item complete because a mocked unit test passes.
5. Do not weaken boundary checks, analyzers, security checks, signing checks, secret scans, or existing tests.
6. Do not copy or reuse Helix Local crypto, protocol, discovery, wipe, trust, session, or transport code for Helix Remote.
7. Do not create custom production cryptography from memory.
8. Prefer a mature, maintained, independently reviewed cryptographic implementation behind Helix-owned adapters.
9. If a security requirement cannot be implemented safely with the available reviewed libraries, mark it BLOCKED. Do not invent a protocol merely to check a box.
10. Do not make unsupported claims of forward secrecy, post-compromise security, encrypted storage, exactly-once processing, or independent security review.
11. Do not log plaintext messages, attachment contents, credentials, access tokens, refresh tokens, database keys, private keys, ratchet keys, recovery keys, or full fingerprints.
12. Do not silently catch security-sensitive failures.
13. Security-sensitive components must fail closed.
14. Keep Local and Remote data, keys, processes, identifiers, databases, caches, logs, and lifecycle operations isolated.
15. Keep every commit narrow and reversible.
16. Run targeted tests after each slice and the complete repository verification before completion.
17. Do not fabricate staging deployment, load-test, security-review, backup-restore, or CI evidence.
18. When an item requires human or external review, state that clearly and leave it blocked instead of claiming completion.
19. Preserve all working Local behavior.
20. Do not start Phase 12 until every readiness gate at the end of this prompt passes.

==================================================
STAGE 1 — CREATE AN HONEST CLOSURE BASELINE
==================================================

Before modifying implementation:

1. Read:
   - AGENTS.md
   - HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md
   - docs/adr/*
   - docs/security/remote_cryptographic_design_review.md
   - docs/security/KEY_LIFECYCLE.md
   - docs/security/IDEMPOTENCY.md
   - docs/security/LOG_REDACTION.md
   - docs/architecture/remote_backend_architecture.md
   - docs/architecture/remote_bounded_contexts.md
   - docs/architecture/remote_compatibility_policy.md
   - docs/product/remote/*
   - docs/release/REMOTE_BACKEND_INFRASTRUCTURE.md

2. Inspect all current source under:
   - apps/helix_remote/
   - packages/remote/
   - services/helix_remote_backend/
   - contracts/
   - infra/ if present
   - scripts/
   - tool/
   - .github/workflows/

3. Run and record the current baseline:
   - flutter pub get
   - flutter analyze
   - all Local tests
   - all Remote app tests
   - all Remote package tests
   - all backend tests
   - boundary checker
   - dependency graph
   - secret scan
   - contract tests
   - debug builds for both applications where the environment supports them

4. Create:
   docs/architecture/PHASE_9_11_CLOSURE.md

5. In that document, classify every Phase 9, Phase 10, and Phase 11 item as:
   - VERIFIED COMPLETE
   - PARTIALLY IMPLEMENTED
   - PLACEHOLDER
   - UNVERIFIED
   - BLOCKED
   - NOT STARTED

6. Each classification must contain:
   - implementation files
   - tests proving the behavior
   - integration level
   - remaining risk
   - required repair
   - CI evidence
   - manual evidence, when applicable

7. Temporarily change inaccurate completed checkboxes in the master plan back to unchecked or clearly annotate them as “closure in progress.”

Do not erase the historical work log. Append a corrective closure entry.

==================================================
STAGE 2 — CLOSE THE REMOTE CRYPTOGRAPHIC GATE
==================================================

HIGH-RISK FILES TO REVIEW

- packages/remote/helix_remote_crypto/lib/src/x3dh.dart
- packages/remote/helix_remote_crypto/lib/src/double_ratchet.dart
- packages/remote/helix_remote_crypto/lib/src/attachment_crypto.dart
- packages/remote/helix_remote_crypto/lib/src/backup_crypto.dart
- packages/remote/helix_remote_crypto/lib/src/group_encryption.dart
- packages/remote/helix_remote_crypto/lib/src/secure_key_storage.dart
- packages/remote/helix_remote_crypto/test/remote_crypto_test.dart
- docs/security/remote_cryptographic_design_review.md
- docs/security/KEY_LIFECYCLE.md

2.1 PROTOCOL IMPLEMENTATION DECISION

Create or update an ADR that records:

- the selected mature protocol implementation
- implementation/library name and version
- maintenance status
- supported platforms
- licensing
- interoperability expectations
- known limitations
- upgrade strategy
- vulnerability response strategy
- why a custom Helix-designed protocol was rejected
- which security properties are actually supported

The preferred architecture is:

Helix application/domain interfaces
        ↓
Helix Remote crypto adapter
        ↓
Maintained/reviewed protocol implementation

Do not expose third-party library types throughout the application.

If no suitable reviewed implementation supports the required Flutter/Android/Windows platforms, stop production protocol implementation and mark the cryptographic gate BLOCKED. You may build interfaces and test harnesses, but do not claim that Phase 9 is complete.

2.2 X3DH OR EQUIVALENT SESSION ESTABLISHMENT

The selected implementation or adapter must support and test:

- separate identity-signing key and identity key-agreement key where required
- signed prekey signature creation
- signed prekey signature verification before key agreement
- signed prekey ID
- signed prekey expiry and rotation
- one-time prekey ID
- atomic one-time prekey consumption
- behavior when no one-time prekey is available
- rejection of invalid or substituted signed prekeys
- rejection of malformed public keys
- domain-separated KDF inputs
- protocol/version binding
- initiator and recipient identity binding
- replay prevention for consumed prekey bundles
- prevention of accidental Local key reuse
- server never receiving private keys

Required negative tests:

- invalid signed-prekey signature
- changed signed-prekey bytes after signing
- wrong identity signing key
- expired signed prekey
- reused one-time prekey
- malformed key size
- all-zero or invalid public key
- mismatched protocol version
- downgrade attempt
- reflected initiator/recipient identities

2.3 DOUBLE RATCHET OR SELECTED PER-MESSAGE RATCHET

Do not retain a class called DoubleRatchetSession unless it implements the selected protocol’s required state machine.

Required behavior includes, either through a reviewed implementation or a correct adapter:

- root key evolution
- Diffie-Hellman ratchet steps
- sending chain and receiving chain
- ratchet public-key headers
- sending message number
- receiving message number
- previous sending-chain length
- bounded skipped-message-key storage
- out-of-order message delivery
- duplicate detection
- replay rejection
- configurable maximum skip limit
- safe session reset behavior
- key-change handling
- protocol version binding
- authenticated associated data binding identities, conversation, device IDs, and header metadata
- state persistence only after successful authenticated operations
- crash-safe session-state commits

CRITICAL FIX

Never advance or persist receiving-ratchet state before AEAD authentication succeeds.

Use this semantic order:

1. Derive candidate state in temporary memory.
2. Attempt authenticated decryption.
3. If authentication fails:
   - discard candidate state
   - keep the original persisted state unchanged
   - return a typed authentication failure
4. If authentication succeeds:
   - persist message and new ratchet state atomically
   - clear temporary key material where practical

Required tests:

- sequential messages
- bidirectional messages
- simultaneous sending
- out-of-order messages
- skipped keys
- duplicate message
- replayed message
- altered ciphertext
- altered nonce
- altered associated data
- altered header
- very large message-number jump
- maximum skipped-key limit
- authentication failure does not advance state
- process crash before state commit
- process crash after atomic commit
- device/session reset
- interoperability vectors from the selected implementation

2.4 ATTACHMENT CRYPTO

Verify or implement:

- random per-attachment content-encryption key
- unique nonce strategy
- authenticated encryption
- attachment ID and metadata binding
- streaming or chunked encryption for large files
- per-chunk integrity where applicable
- final manifest authentication
- no plaintext temporary files unless explicitly controlled
- safe interruption cleanup
- wrong-key and corruption failures
- key delivery separated from object storage
- no plaintext filename required by the server

Required tests:

- empty attachment
- small attachment
- large multi-chunk attachment
- interrupted encryption
- interrupted decryption
- altered chunk
- reordered chunk
- truncated object
- wrong key
- wrong attachment metadata
- nonce uniqueness across repeated operations

2.5 BACKUP CRYPTO

Do not claim encrypted backup readiness without:

- documented KDF
- KDF parameters
- random salt
- authenticated encrypted backup format
- format version
- rollback/downgrade protection
- recovery-key handling
- corruption detection
- no server possession of plaintext backup key
- restore test
- wrong-password/key test
- version-migration test

Phase 12 does not require complete backup UX, but Phase 9 checkboxes must reflect actual implementation rather than planned functionality.

2.6 SECURE KEY STORAGE

Implement Remote-only key storage that:

- uses helix_remote_v1_ or a documented later schema prefix
- never reads Local keys
- stores identity, device, database, and session secrets under distinct typed keys
- supports versioned migration
- supports rotation
- supports revocation
- supports deletion by exact Remote scope
- never calls unscoped deleteAll
- exposes no private keys to UI state
- contains no hardcoded key material
- fails closed when platform secure storage is unavailable

Add Android and Windows adapter tests where practical and manual verification instructions where automation is impossible.

2.7 SECURITY CLAIMS

Update:

- docs/product/PRIVACY_CLAIM_MATRIX.md
- docs/protocol/SECURITY_PROPERTIES.md
- docs/security/remote_cryptographic_design_review.md
- Remote product documentation

Only state a property as implemented when executable evidence supports it.

Any independent external review must remain BLOCKED until an actual independent reviewer has reviewed the exact implementation/version.

==================================================
STAGE 3 — MAKE REMOTE STORAGE VERIFIABLY ENCRYPTED
==================================================

HIGH-RISK FILES

- packages/remote/helix_remote_storage/lib/src/database.dart
- packages/remote/helix_remote_storage/test/remote_storage_test.dart
- packages/remote/helix_remote_storage/pubspec.yaml

3.1 SELECT A REAL ENCRYPTED DATABASE ENGINE

Do not assume that executing PRAGMA key against normal SQLite creates encryption.

Use a verifiable SQLCipher-capable implementation or another approved encrypted database engine that supports Android and Windows.

Requirements:

- document the exact native database engine
- document how Android and Windows load it
- verify cipher support at runtime
- query and validate cipher/version metadata
- fail startup when encryption support is unavailable
- fail startup when the database key is absent or invalid
- never silently fall back to plaintext SQLite

3.2 DATABASE KEY MANAGEMENT

- Generate a cryptographically random database key.
- Store it only in Remote secure storage.
- Never derive it from package ID, username, password, or static constants.
- Never log it.
- Never pass it through UI state.
- Support key versioning.
- Document key-loss behavior.
- Document database rekey behavior.
- Keep Local and Remote database keys permanently separate.

3.3 PHYSICAL ENCRYPTION TESTS

Add tests using unique sentinel values such as:

HELIX_REMOTE_PLAINTEXT_SENTINEL_<random>

After writing sentinel message text and pending-operation payloads:

- close the database
- checkpoint and inspect the main DB file
- inspect WAL and SHM files when present
- assert the sentinel byte sequence does not occur
- assert opening without a key fails
- assert opening with the wrong key fails
- assert opening with the correct key succeeds
- assert the runtime reports the expected encrypted database engine

Do not fake this test by searching only query results. Inspect physical bytes.

3.4 MIGRATIONS

Replace one-shot schema creation with a proper migration framework.

Required:

- explicit schema version
- ordered forward migrations
- migration transaction
- migration lock
- backup or recovery point before destructive migration
- failure recovery
- no silent partial schema
- test migration from every supported prior schema
- fresh database test
- repeated initialization test
- interrupted migration test
- unsupported future-version rejection
- downgrade policy
- corruption handling policy

3.5 SCHEMA AND CONSTRAINTS

Review the schema for:

- accounts
- devices
- contacts
- conversations
- conversation members
- message events
- revisions
- reactions
- receipts
- attachments
- groups
- call history
- sync cursors
- pending operations
- tombstones
- processed event IDs
- ratchet/session state references

Add:

- foreign keys
- unique constraints
- server-sequence constraints
- event-ID uniqueness
- operation-ID uniqueness
- idempotency-key uniqueness where needed
- appropriate indexes
- pagination indexes
- tombstone indexes
- pending-operation scheduling index
- safe cascades
- explicit deletion behavior

Do not put raw private keys in normal database tables.

3.6 CORRUPTION, BACKUP, AND RECOVERY

Implement and test:

- integrity check
- typed corruption error
- safe database quarantine
- no silent recreation that destroys recoverable history
- documented recovery decision
- backup test where applicable
- restore test
- failed restore test
- wrong-key restore test
- atomic replacement of restored DB
- cleanup of temporary backup files

3.7 DATABASE LIFECYCLE

- One database instance per Remote composition root.
- Explicit initialize.
- Explicit close/dispose.
- No hidden global singleton.
- No database access after disposal.
- Startup failure is typed and visible.
- App lifecycle tests prove clean shutdown and restart persistence.

==================================================
STAGE 4 — REBUILD SYNC FOR CORRECTNESS
==================================================

HIGH-RISK FILES

- packages/remote/helix_remote_sync/lib/src/sync_engine.dart
- packages/remote/helix_remote_sync/test/remote_sync_test.dart
- packages/remote/helix_remote_api/lib/api/realtime_envelope.dart
- packages/remote/helix_remote_api/lib/api/rest_client.dart
- contracts/remote-realtime/envelope.json
- contracts/remote-rest-openapi/openapi.yaml

4.1 STRONGLY SCOPE INBOUND FETCHES

The sync gateway must not fetch an unscoped event stream and then assign all events to a caller-supplied conversation.

Define an explicit scope such as:

- account/device global sync stream, where each event contains its authoritative entity/conversation ID; or
- conversation-scoped stream with conversationId included in the request.

The scope must be enforced by types and server contracts.

Never trust a UI-provided conversation ID to relabel server events.

4.2 ATOMIC INBOUND BATCH APPLICATION

Implement:

BEGIN TRANSACTION
  validate batch
  validate schema versions
  validate sequence ordering
  deduplicate event IDs
  apply all supported events
  persist tombstones
  update entity state
  update processed-event records
  update sync cursor
COMMIT

On any failure:

ROLLBACK

The cursor must never move beyond unapplied events.

Required crash/failure tests:

- failure on first event
- failure in middle of batch
- failure after final event but before cursor update
- duplicate batch
- overlapping batches
- reordered batch
- missing sequence
- sequence regression
- unknown event type
- unsupported schema version
- malformed payload
- database constraint failure

4.3 EVENT DISPATCH

Create typed handlers instead of stringly typed conditional logic.

At minimum, Phase 11 must correctly model and apply the foundational event types already claimed:

- message created
- message edited
- message deleted/tombstoned
- reaction added
- reaction removed
- delivery receipt
- read receipt
- conversation created
- membership changed
- attachment manifest event
- group metadata/membership event where Phase 11 schema claims it
- device revoked
- contact/block state where the sync model claims it
- sync marker/control event

Unknown-event policy:

- preserve compatibility
- do not crash the whole application
- do not silently interpret unknown payloads
- record only redacted diagnostics
- follow the documented compatibility policy
- never advance past a required unsupported event when doing so would corrupt state

4.4 DEDUPLICATION AND ORDERING

Implement and test:

- unique event ID
- authoritative server sequence
- monotonic cursor
- duplicate event suppression
- same event ID with different content rejection
- same sequence with different event ID rejection when prohibited
- out-of-order handling
- gap detection
- safe refetch/resume
- idempotent handlers
- deterministic materialized-state rebuilding

Clarify whether ordering is:

- global per account/device stream
- per conversation
- per mailbox
- another explicitly documented scope

The database and contracts must agree.

4.5 OUTBOUND OPERATION QUEUE

Pending operations require at least:

- operation ID
- idempotency key
- operation type
- encrypted or protected payload
- creation time
- updated time
- attempt count
- next_attempt_at
- status
- redacted error category
- dependency/reference IDs where needed

Do not calculate every retry from original creation time.

After each failure:

- increment attempt count
- compute new exponential delay
- apply real bounded jitter
- persist next_attempt_at
- persist a redacted error category
- release the transaction

Inject:

- Clock
- Random/jitter source
- retry policy

This makes behavior deterministic in tests.

Required tests:

- initial success
- transient failure
- permanent failure
- several sequential retries
- actual jitter boundaries
- process restart before retry
- operation survives restart
- operation not retried before next_attempt_at
- idempotent duplicate submission
- server accepted but client timed out
- server returns existing operation result
- dead-letter/manual-attention threshold
- cancellation or tombstoning of obsolete operations

4.6 EXACTLY-ONCE EFFECT, NOT EXACTLY-ONCE TRANSPORT

Use honest terminology:

- transport may deliver more than once
- operation IDs and idempotency keys produce exactly-once effect
- event IDs and atomic application suppress duplicate effects

Update documents and comments accordingly.

4.7 NETWORK AND LIFECYCLE

Implement and test:

- reconnect/resume
- app restart
- network loss during request
- network restoration
- authentication expiry
- refresh-token coordination
- foreground/background restrictions
- bounded background work
- cancellation on logout/device revocation
- no concurrent sync loops for the same scope
- synchronization mutex/lease
- stale worker prevention
- clean disposal

4.8 CLOCK SKEW

- Treat server timestamps as authoritative for server events.
- Use monotonic/local duration measurement for retry timing where practical.
- Never order security-sensitive events solely by client wall-clock time.
- Add clock-skew tests.

4.9 SYNC DIAGNOSTICS

Expose only:

- sync state
- last successful cursor
- redacted error category
- retry time
- queue length
- protocol version
- connection state

Never expose message plaintext, ciphertext, tokens, private keys, database keys, ratchet state, or complete identifiers.

==================================================
STAGE 5 — VERIFY AND COMPLETE THE REMOTE BACKEND
==================================================

FILES/DIRECTORIES

- services/helix_remote_backend/
- contracts/
- docs/architecture/remote_backend_architecture.md
- docs/release/REMOTE_BACKEND_INFRASTRUCTURE.md
- .github/workflows/
- scripts/verify.ps1
- scripts/verify.sh

5.1 FIRST MAKE THE BACKEND AUDITABLE

Update export_codebase_for_review.ps1 so it actually traverses and exports:

- services/
- contracts/
- infra/
- deploy/
- migrations/
- backend tests
- Dockerfiles
- compose files
- CI files
- configuration templates

Continue excluding:

- secrets
- actual .env files
- key material
- build output
- dependency caches
- generated output
- binaries

Add an exporter test or self-check that fails when expected top-level directories exist but are not included.

5.2 BACKEND CORE REQUIREMENTS

Verify or implement, without faking evidence:

Account/device:

- registration
- password/session authentication as approved
- access-token expiry
- refresh-token rotation
- refresh-token reuse detection
- token revocation
- device registration
- device listing
- device naming
- device revocation
- public key bundle publication
- signed prekey rotation
- atomic one-time prekey consumption
- brute-force controls
- credential-stuffing controls
- privacy-minimized audit events

Messaging substrate:

- conversation creation
- membership authorization
- ciphertext-only envelope storage
- no plaintext message field
- authoritative sequence allocation
- idempotent send
- offline mailbox
- acknowledgement
- cursor sync
- tombstone events
- transactional outbox
- mailbox quotas
- backpressure
- blocking enforcement
- rate limiting

Security:

- parameterized database queries
- input-size limits
- schema validation
- authenticated WebSocket
- origin/handshake policy where relevant
- TLS configuration
- secret injection
- no hardcoded production secret
- no private key storage
- no plaintext push payload
- no sensitive audit/log content
- explicit CORS policy
- secure error responses
- dependency vulnerability scanning

5.3 TRANSACTIONAL OUTBOX

Sending a message/event and creating its outbox record must occur in the same database transaction.

Required tests:

- transaction rollback
- worker retry
- worker crash after publish
- duplicate publish
- consumer deduplication
- dead-letter behavior
- poison message
- backpressure
- ordering preservation where required

5.4 IDEMPOTENCY

Enforce server-side uniqueness on idempotency keys or operation IDs in the correct scope.

Test:

- same key and same payload
- same key and different payload
- concurrent duplicate requests
- timeout after commit
- client retry
- response reconstruction
- retention/expiry of idempotency records

5.5 PREKEY CORRECTNESS

Test:

- publish valid bundle
- reject malformed bundle
- signed-prekey expiry
- atomic one-time prekey reservation/consumption
- two concurrent consumers cannot receive the same one-time prekey
- exhausted one-time prekeys
- device revocation invalidates availability
- server never receives private key material

5.6 BACKEND DATABASE MIGRATIONS

Add automated tests that:

- create fresh schema
- migrate each supported old schema
- reject unsupported future schema
- survive interrupted migration
- verify constraints/indexes
- run against the actual selected PostgreSQL version
- do not use only mocked/in-memory replacements

5.7 LOCAL DEVELOPMENT INFRASTRUCTURE

Provide a reproducible local development stack for the actual dependencies that Phase 10 claims, such as:

- PostgreSQL
- Redis when used
- object storage emulator when used
- backend
- migration runner
- health checks

No production credentials may be included.

5.8 BACKUP AND RESTORE

A checkbox is complete only when a real test demonstrates:

- backup creation
- restore into a clean environment
- integrity validation
- application startup after restore
- documented RPO/RTO assumptions
- encrypted backup handling
- access controls

5.9 LOAD BASELINE

Create a reproducible baseline covering at least:

- registration/authentication
- prekey fetch
- concurrent idempotent send
- cursor sync
- WebSocket connections if implemented

Record:

- tool
- scenario
- concurrency
- duration
- environment
- p50/p95/p99
- error rate
- bottlenecks
- date
- commit

Do not claim production capacity from a laptop baseline.

5.10 STAGING

Do not mark staging complete without actual deployment evidence.

If credentials or infrastructure are unavailable:

- leave staging as BLOCKED
- document exact deployment instructions
- ensure code/configuration is ready
- do not fabricate successful staging verification

==================================================
STAGE 6 — INTEGRATE THE REMOTE FOUNDATION INTO THE APP
==================================================

CURRENT TARGET FILES

- apps/helix_remote/lib/app/composition_root.dart
- apps/helix_remote/lib/main.dart
- apps/helix_remote/pubspec.yaml
- apps/helix_remote/test/
- packages/remote/*

6.1 APP DEPENDENCIES

Add explicit Remote-only dependencies required by the foundation:

- helix_remote_domain
- helix_remote_api
- helix_remote_crypto
- helix_remote_storage
- helix_remote_sync
- approved configuration/lifecycle dependencies

Do not import packages/local/**.

6.2 REMOTE COMPOSITION ROOT

RemoteCompositionRoot must own or explicitly compose:

- validated Remote environment/configuration
- secure key storage
- Remote database key provider
- encrypted Remote database
- REST client
- realtime client/gateway
- token/session store
- cryptographic protocol/session adapter
- synchronization engine
- connectivity/lifecycle coordinator
- typed clock/random sources where needed
- redacted diagnostics
- deterministic disposal

No resource should be constructed silently inside a controller.

No default constructor may silently select production infrastructure.

6.3 STARTUP SEQUENCE

Implement a clear startup state machine:

- configuration validation
- secure-storage availability
- database-key load/create
- encrypted database initialization
- migration
- corruption/integrity check
- session/token-state load
- sync engine initialization
- application ready

Failures must produce typed, safe states.

Never continue with plaintext storage or missing cryptographic dependencies.

6.4 DISPOSAL

Dispose in a safe order:

- stop synchronization
- close realtime connection
- cancel network requests
- flush or safely persist queue state
- close encrypted DB
- dispose clients
- release resources

Add tests proving:

- disposal is idempotent
- no callbacks occur after disposal
- two roots do not share state
- disposing one root does not affect another
- startup failure cleans partially created resources

6.5 PLACEHOLDER UI

Remove “Helix Remote Placeholder” as the only proof of application readiness.

Do not build Phase 12 user-facing messaging features yet.

Use a minimal foundation/bootstrap shell that can display only safe high-level states such as:

- initializing
- locked/not authenticated
- foundation ready
- startup failure with redacted error code

A debug-only diagnostics view may show:

- database engine/cipher available
- schema version
- sync engine idle
- API configuration present
- no Local package imports

Do not show secrets or message data.

6.6 INTEGRATION TESTS

Add tests that instantiate the actual Remote app composition and prove:

- encrypted database survives root disposal and recreation
- correct key reopens DB
- wrong key fails
- queued operation survives restart
- sync applies a real contract event
- cursor survives restart
- duplicate event has no duplicate effect
- Remote root never touches Local storage
- Local wipe does not alter Remote DB or keys
- Remote disposal does not alter Local state
- startup fails closed without encrypted database support
- app does not contain Local mDNS/discovery/wipe dependencies

==================================================
STAGE 7 — REPAIR LOCAL PANIC-WIPE RESULT SEMANTICS
==================================================

TARGET FILES

- apps/helix_local/lib/application/wipe/local_panic_wipe_orchestrator.dart
- packages/local/helix_local_storage/lib/data/database.dart
- apps/helix_local/test/phase6_test.dart
- related wipe tests

7.1 SUCCESS SEMANTICS

WipeResult.succeeded must be true only when:

- final phase is completed
- no required operation failed
- no sensitive artifact is known to remain

It must not be based only on an empty error list.

7.2 PARTIAL FAILURE

When any required wipe step fails:

- phase must be partialFailure
- succeeded must be false
- typed/redacted failure information must be preserved
- pending wipe marker must remain
- next startup must retry incomplete work
- repeated orchestrator calls must not return false success

7.3 FILE DELETION ERRORS

Do not silently swallow failures deleting:

- DB
- WAL
- SHM
- .part files
- cache
- temporary files
- logs
- diagnostics

Handle “file does not exist” as success.

Handle permission, lock, and I/O failures as visible partial failures.

7.4 REQUIRED TESTS

- successful wipe
- repeated successful wipe
- DB deletion failure
- WAL deletion failure
- SHM deletion failure
- secure-storage deletion failure
- notification cancellation failure
- partial failure followed by retry
- process restart after partial failure
- succeeded is false for partialFailure
- Remote test data remains unchanged
- no Remote request occurs
- no Remote directory or key is enumerated

==================================================
STAGE 8 — MAKE VERIFICATION AND CI AUTHORITATIVE
==================================================

8.1 CANONICAL VERIFY SCRIPTS

Update both:

- scripts/verify.ps1
- scripts/verify.sh

They must run, as applicable:

1. dependency resolution
2. formatting check
3. analyzer
4. boundary checks
5. circular dependency check
6. secret scan
7. release hardening checks
8. Local tests
9. Remote app tests
10. every Local package test
11. every Remote package test
12. backend unit tests
13. backend integration tests
14. contract serialization/compatibility tests
15. backend migration tests
16. encrypted DB physical-byte tests
17. sync transactional/crash tests
18. Local/Remote isolation tests
19. relevant debug builds
20. artifact/report generation

No important suite may be excluded merely because it is under services/.

8.2 CI WORKFLOW

Create clear CI jobs such as:

- architecture-and-secrets
- local-flutter
- remote-flutter
- remote-crypto
- remote-storage
- remote-sync
- remote-backend
- contract-compatibility
- platform-builds
- dependency-security

Use appropriate runner matrices when Android and Windows behavior differ.

CI must fail on:

- backend test failure
- migration failure
- plaintext DB sentinel detection
- boundary violation
- Local/Remote import violation
- contract incompatibility
- secret detection
- analyzer error
- release-signing misconfiguration
- unsupported crypto configuration

8.3 BUILD POLICY

Do not hide all builds behind an optional local environment variable in CI.

CI must build at least:

- Helix Local Android debug
- Helix Remote Android debug
- Helix Local Windows debug on a Windows runner
- Helix Remote Windows debug on a Windows runner

Release signing may remain in a protected release workflow requiring secrets.

8.4 DEPENDENCY AND VULNERABILITY CHECKS

Run supported dependency checks for:

- Flutter/Dart packages
- backend packages
- container images where used

Document unavoidable findings and fail on agreed critical/high-severity thresholds.

==================================================
STAGE 9 — DOCUMENTATION AND ROADMAP CORRECTION
==================================================

After implementation:

1. Update the master plan honestly.
2. Recheck every Phase 9, 10, and 11 item.
3. Mark an item complete only when:
   - production implementation exists
   - tests prove it
   - actual app/backend integration exists where required
   - CI executes those tests
   - documentation matches behavior
4. Leave external reviews and actual staging deployment blocked when not performed.
5. Do not reinterpret a requirement merely to mark it complete.
6. Update:
   - CHANGELOG_ARCHITECTURE.md
   - docs/architecture/CURRENT_STATE_*.md
   - docs/architecture/PHASE_9_11_CLOSURE.md
   - docs/security/*
   - docs/release/*
   - relevant ADRs
   - work log
7. Remove unsupported security claims.
8. Record migration and rollback instructions.
9. Record actual commands and outputs.
10. Record the exact commit used for final verification.

==================================================
MANDATORY TEST SCENARIOS
==================================================

The final test suite must include at least the following cross-component scenarios.

SCENARIO A — CRYPTO AUTHENTICATION FAILURE

1. Establish a valid Remote session.
2. Encrypt a message.
3. Corrupt ciphertext or authentication tag.
4. Attempt decryption.
5. Confirm failure.
6. Confirm receiving ratchet/session state is unchanged.
7. Decrypt the original valid message successfully.

SCENARIO B — OUT-OF-ORDER DELIVERY

1. Encrypt messages 1, 2, and 3.
2. Deliver 3, then 1, then 2.
3. Verify correct decryption under bounded skipped-key policy.
4. Replay message 2.
5. Verify replay rejection.

SCENARIO C — PHYSICAL DATABASE ENCRYPTION

1. Create encrypted Remote DB.
2. Write a unique plaintext sentinel.
3. Close and checkpoint.
4. Scan DB/WAL/SHM bytes.
5. Confirm sentinel is absent.
6. Confirm no-key and wrong-key opens fail.
7. Confirm correct-key open succeeds.

SCENARIO D — ATOMIC INBOUND SYNC

1. Prepare a three-event batch.
2. Force event 2 to fail.
3. Verify event 1 was rolled back.
4. Verify cursor did not advance.
5. Repair the failure.
6. Reapply the batch.
7. Verify all events and cursor commit once.

SCENARIO E — OUTBOUND TIMEOUT AFTER SERVER COMMIT

1. Send operation with a stable idempotency key.
2. Server commits but response is lost.
3. Client retries.
4. Server returns original result.
5. Verify only one message/event effect exists.

SCENARIO F — RESTART PERSISTENCE

1. Queue an outbound operation.
2. Dispose the composition root.
3. Recreate the app/root.
4. Verify operation remains pending.
5. Process it.
6. Restart again.
7. Verify it is not resent.

SCENARIO G — PRODUCT ISOLATION

1. Seed Local state.
2. Seed Remote DB and Remote secure keys.
3. Run Local panic wipe.
4. Verify Local sensitive state is gone.
5. Verify Remote DB and keys are unchanged.
6. Verify no Remote endpoint was called.

SCENARIO H — REMOTE STARTUP FAILURE

1. Remove or corrupt encrypted database support/key.
2. Start Remote.
3. Verify startup fails closed.
4. Verify no plaintext fallback DB is created.
5. Verify error output contains no secret.

SCENARIO I — BACKEND PREKEY CONCURRENCY

1. Store one one-time prekey.
2. Fetch it concurrently from two sessions.
3. Verify only one receives it.
4. Verify the other receives fallback/no-prekey behavior.
5. Verify the same one-time prekey is never issued twice.

SCENARIO J — CONTRACT COMPATIBILITY

1. Deserialize all current fixtures.
2. Deserialize an envelope with an unknown optional event.
3. Verify documented unknown-event handling.
4. Reject unsupported breaking schema.
5. Confirm Local protocol fixtures remain completely independent.

==================================================
FINAL VERIFICATION COMMANDS
==================================================

Use repository-appropriate commands, but the final completion report must show actual results for at least:

- dart format --output=none --set-exit-if-changed .
- flutter analyze
- dart run tool/check_boundaries.dart
- dart run tool/dep_graph.dart
- dart run tool/check_secrets.dart
- all Local tests
- all Remote app tests
- all Remote crypto tests
- all Remote storage tests
- all Remote sync tests
- all Remote API/contract tests
- all backend tests
- backend integration tests against real PostgreSQL where required
- migration tests
- encrypted DB physical-byte tests
- Local/Remote isolation tests
- Android debug builds for both apps
- Windows debug builds for both apps
- scripts/verify.ps1
- scripts/verify.sh where the environment supports it

Do not report “all tests pass” without reporting:

- suite name
- command
- test count where available
- skipped tests
- platform limitations
- blocked manual checks

==================================================
PHASE 12 READINESS GATE
==================================================

Helix is ready to begin Phase 12 only when all applicable items below are true:

[ ] Remote crypto uses an approved maintained implementation or the security gate is otherwise formally satisfied.
[ ] Signed-prekey verification is implemented and tested.
[ ] One-time prekey consumption is atomic.
[ ] Authenticated-decryption failure cannot advance ratchet state.
[ ] Replay, duplicate, skipped-key, out-of-order, and downgrade tests pass.
[ ] Security claims exactly match implementation.
[ ] Encrypted Remote DB engine is verified at runtime.
[ ] Plaintext sentinel is absent from DB, WAL, and SHM.
[ ] Wrong/no-key database access fails closed.
[ ] Database migrations and interruption recovery are tested.
[ ] Sync events are authoritatively scoped.
[ ] Inbound batches and cursor updates are atomic.
[ ] Event handlers cover the Phase 11 foundational event model.
[ ] Duplicate/reordered events do not corrupt state.
[ ] Outbound retry uses persisted next_attempt_at and real bounded jitter.
[ ] Idempotent server behavior is tested under lost responses.
[ ] Remote composition root binds actual Remote resources.
[ ] Remote app startup exercises actual storage and lifecycle integration.
[ ] Remote history/queue/cursor survive process recreation.
[ ] Backend tests are included in canonical verification.
[ ] Contract and migration tests are blocking CI gates.
[ ] Both app debug builds run in CI.
[ ] Local panic wipe cannot report false success.
[ ] Local panic wipe failures remain retryable and visible.
[ ] Local wipe leaves Remote data and keys unchanged.
[ ] Export tooling includes backend, contracts, and infrastructure source.
[ ] Master-plan statuses are accurate.
[ ] All remaining blockers are documented.
[ ] No Phase 12 functionality has been prematurely mixed into the closure work.

Do not declare “ready for Phase 12” if any security-critical item above remains unchecked.

==================================================
REQUIRED COMPLETION REPORT
==================================================

Provide the final report in this exact structure:

# Phase 9–11 Closure Report

## Overall Result
READY FOR PHASE 12 | NOT READY FOR PHASE 12

## Executive Summary
Briefly state what was repaired and what remains blocked.

## Phase Status
- Phase 9:
- Phase 10:
- Phase 11:
- Local wipe repair:
- CI and verification:

## Files Changed
Group by:
- Remote crypto
- Remote storage
- Remote sync
- Remote backend
- Remote app
- Local wipe
- Tooling/CI
- Documentation

## Security-Critical Changes
Explain:
- protocol/library decision
- key lifecycle
- database encryption proof
- ratchet rollback behavior
- prekey consumption
- logging/redaction
- product isolation

## Migrations
List:
- schema versions
- migration behavior
- rollback/recovery
- compatibility impact

## Tests and Evidence
For every suite:
- command
- result
- count
- platform
- evidence file

## Builds
- Local Android:
- Remote Android:
- Local Windows:
- Remote Windows:

## CI
List every blocking job and result.

## Remaining Blockers
Do not omit external-review, staging, platform, or infrastructure blockers.

## Phase 12 Readiness Checklist
Repeat every readiness-gate item with PASS, FAIL, or BLOCKED.

## Rollback
Provide exact rollback commit/tag and migration rollback/recovery instructions.

## Final Recommendation
State exactly one:
- APPROVED TO BEGIN PHASE 12
- NOT APPROVED TO BEGIN PHASE 12

Do not use “approved” unless every security-critical readiness requirement has passed.