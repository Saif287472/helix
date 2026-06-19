Act as the senior software architect, Flutter engineer, Dart backend engineer, application-security engineer, cryptography-integration engineer, database engineer, and test engineer responsible for closing and repairing Helix Phases 12-20 as a student-buildable two-application project.

PROJECT ROOT
J:\Projects\helix

AUTHORITATIVE INPUTS
- AGENTS.md
- HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md
- HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN_PART_2_REMAINING.md
- phase_0-11_closure_and_repair_pass.md
- docs/architecture/PHASE_9_11_CLOSURE.md
- all current source, contracts, tests, scripts, and architecture documents in the repository

PRIMARY OBJECTIVE
Perform a Phase 12-20 Closure and Repair Pass so that Helix Local and Helix Remote are genuinely buildable, runnable, testable student applications on Android and Windows.

The target is not publication or production readiness. The target is a correct, connected, maintainable development build that can be run on multiple Android and Windows devices and manually exercised by the student after the code pass is complete.

FINAL ALLOWED RESULT
Use exactly one of these final results:
- READY FOR STUDENT DEVICE VALIDATION
- NOT READY FOR STUDENT DEVICE VALIDATION

Do not use "production ready", "release ready", "enterprise ready", "security audited", or similar wording.

==================================================
STUDENT SCOPE OVERRIDE
==================================================

This closure pass intentionally removes production-only obligations from Phases 12-20.

EXCLUDE ALL OF THE FOLLOWING FROM REQUIRED WORK
- production deployment
- staging deployment
- cloud infrastructure provisioning
- Kubernetes, Terraform, or production container orchestration
- app-store or Microsoft Store publication
- release signing or certificate acquisition
- signed Android or Windows artifacts
- production monitoring dashboards
- production SLO, on-call, status-page, or cost-management processes
- production rollback execution
- production secrets and access-role review
- penetration testing
- independent cryptographic review
- external mobile security review
- external backend security review
- external compliance certification
- real push-provider integration
- real TURN-provider purchase or regional infrastructure
- multi-region, high-availability, or disaster-recovery infrastructure
- claims based on real internet scale, carrier networks, or production traffic

These exclusions must not be reported as blockers for this student closure pass.

PRESERVE BUT DE-SCOPE HISTORICAL FILES
Existing release, staging, production, external-review, and governance documents may remain as historical or future reference. Do not spend closure time improving them. Do not allow them to block the default local verification command.

The default verification path for this closure must be student/developer focused. Release-only checks may remain in separately named optional scripts, but they must not be required by the normal local closure gate.

==================================================
CURRENT AUDIT CONCLUSION
==================================================

Phases 12-20 are not closed.

The repository contains a substantial amount of useful domain, storage, backend, cryptographic-primitive, synchronization, attachment, call-orchestration, group, backup, privacy, and test code. However, many phase checkboxes overstate the actual integration level.

The main problem is that implemented pieces are not connected into complete application workflows.

The most important confirmed problems are:

1. The Helix Remote Flutter screen is an in-memory demonstration. Contacts and messages are held in local widget lists and actions mutate UI state instead of calling Remote services.
2. RemoteCompositionRoot currently wires only secure key storage, the Remote database, and RemoteSyncEngine. It does not compose authentication, REST transport, WebSocket transport, token storage, concrete SyncGateway, message protection, messaging, attachments, calls, groups, backups, privacy/account deletion, or lifecycle coordination.
3. Fresh-install startup fails because the composition root requires an existing `db_key`, but no normal application bootstrap generates and stores the first key.
4. `HelixRemoteRestClient` is an abstract interface with no concrete implementation.
5. `SyncGateway` has no production implementation and no production WebSocket client feeds the sync engine.
6. `RemoteMessageProtector` is not connected to a real session/key lifecycle in the app.
7. Backend realtime messages do not consistently use the required `RemoteRealtimeEnvelope` shape. The backend emits raw maps such as `type: message`, while the client parser requires `event_id`, `schema_version`, `timestamp`, `type`, and `payload`, and recognizes `chat_message` instead of `message`.
8. The client stores one global sync cursor, while backend message sequencing is conversation/device-envelope oriented. Repeated sequence values across conversations can cause legitimate unseen events to be rejected or skipped.
9. The OpenAPI document, backend route mounting, request models, response models, and abstract client API are not one authoritative contract.
10. Phase 12 UI controls are not backed by persistence, networking, authentication, encryption, or synchronization.
11. The Remote app does not depend on or instantiate the Remote calls and groups packages.
12. The Remote calls package has an abstract engine but no concrete Remote WebRTC engine. A comment claims a production implementation exists when it does not.
13. `RemoteCallService.acceptIncomingCall()` passes an empty offer SDP to `createAnswer`, so a real WebRTC engine cannot answer an incoming call.
14. Attachment endpoints authenticate the request but do not consistently authorize the authenticated account/device against the requested attachment or message reference.
15. Content-addressed attachment IDs are globally derived from ciphertext hash and stored under one global primary key, allowing cross-account ownership collision or replacement unless ownership is included in the identity model.
16. The client stores raw attachment key and IV material in a database field named `encrypted_key`.
17. Attachment key delivery silently sends the raw key when no per-device encryptor is supplied. A security-sensitive production path must not have that fallback.
18. Attachment preparation, upload, download verification, and backend hashing read large remaining content or entire files into memory, despite resumable/streaming claims.
19. Temporary attachment names can expose the original filename and cleanup is not guaranteed on every success, cancellation, and failure path.
20. Group encryption is incomplete. A deterministic placeholder key can be used when no encryption-key provider is supplied.
21. Group key rotation increments an epoch or sends a marker but does not prove real new key generation and per-device encrypted key distribution.
22. Client group administration methods optimistically mutate local state without enforcing caller role, valid role values, last-admin rules, or server-confirmed authorization.
23. Group and newer event types are not consistently present in the realtime envelope supported-type list and contract schema.
24. Device linking, multi-device restore, backup upload/download, recovery, and account-deletion workflows exist mainly as backend or library primitives and are not wired into the Flutter app.
25. Remote account deletion does not yet prove coordinated local database, secure-storage, token, session, and cache cleanup while leaving Helix Local untouched.
26. Operability work is primarily documentation, metrics endpoints, simulated provider flags, and tests. It does not provide a reliable local developer backend lifecycle, durable event catch-up, database integrity tooling, or a student backup/restore command.
27. Outbox and background-worker paths contain broad catches or silent failure handling that can hide actionable defects.
28. The default verification scripts currently execute release/governance checks that are outside this student closure scope.
29. Current tests are valuable but are predominantly unit and in-memory integration tests. They do not prove that the actual Flutter app, concrete client transport, backend routes, persistence, encryption adapter, and realtime recovery work together.
30. Completion evidence often treats a class, interface, mock, Markdown document, or test-double behavior as proof of an end-to-end feature.

==================================================
CONFIRMED STRENGTHS TO PRESERVE
==================================================

Do not discard working foundations unnecessarily.

Preserve and build on:
- strict Local/Remote package boundaries
- separate application IDs and storage namespaces
- existing Local app behavior and tests
- Remote storage schema and migration foundation
- processed-event deduplication foundation
- pending-operation queue foundation
- ciphertext-only server message storage intent
- signed-prekey verification and authentication-failure rollback already repaired in the Phase 0-11 closure
- Remote domain model separation
- attachment encryption primitives
- backup encryption primitives
- call state machine and history abstractions
- group metadata and membership persistence foundation
- backend contact, privacy, report, audit, and deletion modules where their behavior is correct
- secret scan, dependency boundary checks, analyzer, formatting, and ordinary unit/integration tests

Do not perform unrelated rewrites of Helix Local.

==================================================
NON-NEGOTIABLE RULES
==================================================

1. Do not trust a checked task in the plan. Verify source wiring and executable behavior.
2. A class or interface alone is not a completed feature.
3. A mocked unit test alone is not a completed application workflow.
4. A document alone is not executable evidence.
5. A UI element that only mutates widget state is not an implemented backend feature.
6. Do not weaken Local/Remote isolation, crypto validation, authentication, authorization, input validation, secret scanning, boundary checks, or existing passing tests.
7. Do not copy Local LAN transport, discovery, trust, wipe, or crypto infrastructure into Remote.
8. Do not invent or overclaim cryptographic properties.
9. For this student closure, wire and test the existing authenticated encryption/session primitives, but describe their exact limitations honestly. Do not call the current symmetric chain a complete Double Ratchet if it is not one.
10. Remote database encryption at rest is not a student-closure blocker when the required cross-platform database engine is unavailable. Remove false encryption claims and keep sensitive key material out of the ordinary database wherever practical.
11. Never store or log plaintext message bodies, file contents, passwords, access tokens, refresh tokens, database keys, private keys, attachment keys, backup keys, recovery phrases, or full identity fingerprints in logs.
12. Security-sensitive dependencies must fail closed. Do not use raw-key, plaintext, no-auth, or no-authorization fallback behavior outside explicit test doubles.
13. Do not catch and discard security, persistence, synchronization, or cleanup errors without typed reporting or durable retry state.
14. All concrete infrastructure must be composed explicitly in RemoteCompositionRoot or a clearly owned feature composition module.
15. The application must have one authoritative account/session state and one deterministic lifecycle.
16. All backend endpoints must enforce both authentication and resource authorization.
17. All state-changing operations must be idempotent or have documented duplicate behavior.
18. All durable inbound changes must be replayable after disconnect and restart.
19. WebSocket delivery is only a fast path. Correctness must come from a durable catch-up API/event store.
20. Keep commits and repair slices narrow, testable, and reversible.
21. Do not delete historical evidence. Append a correction explaining the new status.
22. Do not add production, staging, publishing, signing, pentest, or external-review work back into this closure.

==================================================
TARGET DEVELOPMENT ARCHITECTURE
==================================================

Implement one complete local-development path:

Helix Remote Flutter UI
    -> feature controllers/view models
    -> Remote application services
    -> concrete authenticated REST client
    -> concrete realtime client plus durable catch-up gateway
    -> local-development Dart backend
    -> backend database and attachment storage

Message content path:

plaintext only in the sending UI/service memory
    -> RemoteMessageProtector encrypts per recipient device
    -> only ciphertext crosses REST/WebSocket and reaches backend storage
    -> recipient sync persists ciphertext
    -> recipient protector authenticates/decrypts for presentation

Correct realtime model:

state-changing backend transaction
    -> write domain change
    -> write durable account/device event envelope in same transaction
    -> optional WebSocket fast delivery
    -> client fetches envelopes after its durable cursor
    -> client applies batch atomically
    -> client advances cursor only after successful apply

Use one authoritative event envelope everywhere:
- event_id
- schema_version
- timestamp
- type
- server_sequence
- payload
- optional request_id
- optional idempotency_key
- optional correlation_id

Use one monotonic sequence scope. The recommended student implementation is a durable per-device event stream with a monotonically increasing sequence for each recipient device. Do not mix a single client cursor with per-conversation sequence numbers.

==================================================
STAGE 0 - CREATE AN HONEST PHASE 12-20 BASELINE ✅ Done
==================================================

Before changing code:

1. Read the authoritative inputs and relevant source under:
   - apps/helix_remote/
   - packages/remote/
   - services/helix_remote_backend/
   - contracts/
   - apps/helix_local/ only where isolation regression could occur
   - scripts/
   - tool/
   - tests

2. Run every currently available local check and record the exact result:
   - `flutter pub get`
   - `dart format --output=none --set-exit-if-changed apps packages services tool`
   - `flutter analyze`
   - boundary checks
   - dependency-cycle check
   - secret scan
   - Local tests
   - Remote app tests
   - every Remote package test
   - backend tests

3. Do not run or require release signing, staging, publishing, deployment, or external-review checks.

4. Create:
   `docs/architecture/PHASE_12_20_CLOSURE.md`

5. Classify every Phase 12-20 task with one of:
   - VERIFIED END TO END
   - VERIFIED COMPONENT ONLY
   - PARTIAL
   - DISCONNECTED
   - PLACEHOLDER
   - DEFECTIVE
   - OUT OF STUDENT SCOPE
   - NOT STARTED

6. For every classification record:
   - implementation files
   - production/development wiring path
   - tests
   - missing integration
   - security or data-integrity risk
   - repair task

7. Correct inaccurate checkboxes or annotate them as closure-in-progress. Keep the historical implementation evidence and append a correction instead of rewriting history.

STAGE 0 EXIT GATE
- No Phase 12-20 task remains classified only from its checkbox.
- Every end-to-end claim names its concrete UI -> service -> transport -> backend -> database path.
- The baseline clearly separates component code from runnable application behavior.

==================================================
STAGE 1 - REPAIR REMOTE BOOTSTRAP, CONFIGURATION, AND COMPOSITION ✅ Done
==================================================

TARGET FILES
- apps/helix_remote/lib/app/composition_root.dart
- apps/helix_remote/lib/main.dart
- apps/helix_remote/pubspec.yaml
- new Remote bootstrap/config/session files as needed
- apps/helix_remote/test/

1.1 DEVELOPMENT CONFIGURATION

Add a typed Remote development configuration containing at least:
- REST base URI
- WebSocket URI
- backend host mode
- request timeout
- reconnect policy
- database directory
- attachment cache/temp directory
- diagnostic logging level with content redaction

Support these student run modes without source edits:
- Windows app and backend on the same PC
- Android emulator connecting to the host PC
- physical Android device connecting to a backend over the same LAN
- another Windows device connecting over the same LAN

Do not hardcode one machine IP. Accept `--dart-define` values and provide a development settings screen or clearly documented local override.

1.2 FIRST-RUN DATABASE KEY

Replace the impossible fresh-install flow.

Required behavior:
1. Read the Remote database key from Remote-prefixed secure storage.
2. If absent on a true first run, generate a cryptographically random key.
3. Persist it to Remote secure storage.
4. Open the Remote database with the same key reference.
5. On later runs, reuse it.
6. If a database exists but its required key is missing, fail with a typed recovery/reset state. Do not silently generate a new key for an existing database.

Because cross-platform SQLCipher is currently unavailable, do not claim that the file is encrypted at rest. Keep the key lifecycle ready for a future encrypted engine, and keep high-value private key material in secure storage instead of ordinary SQLite.

1.3 COMPLETE COMPOSITION ROOT

RemoteCompositionRoot must explicitly own and dispose:
- Remote configuration
- secure key storage
- database
- session/token store
- concrete REST client
- concrete realtime client
- concrete SyncGateway
- sync engine
- identity/prekey service
- message protector/session store
- RemoteMessagingService
- RemoteAttachmentService
- RemoteCallService and concrete Remote call engine
- RemoteGroupService
- backup/recovery service
- privacy/account lifecycle service
- connectivity/reconnect coordinator
- typed clock, ID generator, and random sources where needed

No feature service may be instantiated only in tests.

1.4 STARTUP STATE MACHINE

Implement typed states such as:
- loading configuration
- opening secure storage
- first-run initialization
- opening database
- restoring session
- unauthenticated
- authenticated and syncing
- ready
- recoverable failure
- reset required

The app must show a safe screen for each state instead of crashing before `runApp`.

1.5 DISPOSAL

Dispose in a deterministic order:
- stop feature subscriptions and timers
- stop realtime reconnect
- stop sync/outbound workers
- end active call media
- close HTTP/WebSocket resources
- close database
- dispose secure/key services

Required tests:
- first run succeeds
- second run reuses key and data
- existing database plus missing key fails safely
- partial startup failure cleans created resources
- dispose is idempotent
- no callback occurs after disposal
- two roots share no mutable state

STAGE 1 EXIT GATE
- A fresh Helix Remote debug install reaches an unauthenticated setup screen.
- The actual feature services are reachable from the composition root.
- The app no longer depends on manually pre-seeding `db_key`.
- The app no longer uses disconnected in-memory sample contacts/messages as its primary data source.

==================================================
STAGE 2 - MAKE THE REMOTE CONTRACT EXECUTABLE ✅ Done
==================================================

TARGET FILES
- contracts/remote-rest-openapi/openapi.yaml
- contracts/remote-realtime/envelope.json
- packages/remote/helix_remote_api/
- services/helix_remote_backend/lib/src/server_impl.dart
- all backend modules
- contract tests

2.1 SELECT ONE AUTHORITATIVE CONTRACT

Reconcile all route prefixes, methods, request fields, response fields, status codes, ID types, and error bodies.

Known mismatch areas include:
- registration and login routes
- devices routes and duplicated `/devices` mounting
- account/device ID types
- login challenge flow
- token refresh
- contact routes
- message send/sync/delete/edit/reaction routes
- attachment upload/download/reference routes
- group routes
- call signaling and TURN-development routes
- backup routes
- privacy/export/delete routes

2.2 CONCRETE REST CLIENT

Implement a concrete `HelixRemoteRestClient` using `dart:io` HttpClient or one approved HTTP package.

It must provide:
- base URI handling
- JSON encoding/decoding
- typed API exceptions
- authentication header injection
- one coordinated token refresh attempt
- cancellation/disposal
- request timeout
- idempotency key header/body handling
- no secret-bearing logs

Do not let each feature build ad hoc URLs independently. Route attachment and other existing direct HTTP code through the concrete API boundary or focused typed clients owned by the same transport layer.

2.3 CONTRACT TESTS

Add tests that run the actual backend router in-process and invoke it through the concrete client.

Verify at least:
- registration/challenge/login/refresh
- device list/revoke
- prekey upload/fetch/consume
- contact request lifecycle
- direct conversation creation
- message send and catch-up
- attachment upload/status/download/reference
- call signal
- group create/invite/membership change
- backup upload/download
- privacy export/account deletion

Contract tests must fail when OpenAPI examples or serialization fixtures drift from handlers.

STAGE 2 EXIT GATE
- No abstract API method used by the app lacks a concrete implementation.
- Backend routes and client routes agree.
- IDs and status codes are consistent.
- Contract tests exercise handlers, not only JSON fixtures.

==================================================
STAGE 3 - REPAIR REALTIME EVENTS, DURABLE CATCH-UP, AND CURSORS ✅ Done
==================================================

This is a critical data-integrity stage.

3.1 ONE ENVELOPE FORMAT

Create one backend event-envelope builder and use it for messages, receipts, contacts, profiles, privacy, presence, groups, calls, device revocation, attachment lifecycle events where required, and sync markers.

Raw feature maps must not be sent directly over WebSocket.

3.2 DURABLE DEVICE EVENT STREAM

Add a durable event table or equivalent that stores at least:
- recipient account ID
- recipient device ID
- monotonic device sequence
- event ID
- schema version
- event type
- timestamp
- payload JSON/ciphertext fields
- creation time
- optional expiry for ephemeral hints

Write durable events in the same transaction as the domain change.

Use WebSocket as a low-latency hint carrying the same envelope. The client must still recover the event through REST after a missed WebSocket.

3.3 CURSOR RULES

Use a cursor scoped exactly like the server sequence.

Recommended:
- one cursor per Remote recipient device stream
- sequence starts at 1 and increases monotonically for that device
- the same event delivered to two devices may have different device-stream sequences but the same stable event ID when semantically appropriate

Do not use conversation sequence as a global account/device cursor.

3.4 CLIENT APPLY RULES

The sync engine must:
- sort by sequence
- reject malformed envelopes safely
- deduplicate by event ID
- apply a batch in one database transaction
- advance the cursor only after all applicable writes succeed
- roll back cursor and writes together on failure
- record unknown future events without crashing
- never persist ephemeral typing or call media content
- allow duplicate delivery without duplicate domain effects
- detect true gaps and trigger catch-up rather than silently skipping

3.5 REALTIME CLIENT

Implement a concrete WebSocket client with:
- authenticated connect
- bounded exponential backoff with deterministic/testable jitter
- one active reconnect loop
- heartbeat/timeouts
- lifecycle pause/resume handling
- event envelope parsing
- handoff to the same sync/apply pipeline
- no message content logs

3.6 TESTS

Required tests:
- events from two conversations with overlapping conversation sequence values
- missed WebSocket followed by REST catch-up
- duplicate WebSocket plus REST event
- restart with stored cursor
- malformed event
- unknown higher schema version
- batch failure rollback
- gap detection
- device revocation
- group and contact events
- call signal remains ephemeral
- no cursor advance on failed apply

STAGE 3 EXIT GATE
- A single global cursor is no longer compared against per-conversation sequence numbers.
- Every durable Remote change can be recovered after disconnect and restart.
- Realtime and catch-up use the same envelope parser and application path.

==================================================
STAGE 4 - PHASE 12 CLOSURE: COMPLETE ONE-TO-ONE MESSAGING ✅ Done
==================================================

Phase 12 must become one real vertical slice before later phases are called complete.

4.1 AUTHENTICATED APP FLOW

Replace sample setup controls with real flows:
- create/register development account
- issue login challenge
- sign challenge with the device identity
- receive/store access and refresh tokens
- restore session after restart
- logout clears Remote tokens/session state only

4.2 CONCRETE MESSAGE PROTECTOR

Implement the app-facing `RemoteMessageProtector` adapter using the existing Remote crypto/session primitives.

Required behavior:
- fetch and validate recipient device bundles
- establish a per-device encrypted session
- encrypt separately for every active recipient device and the sender's linked devices as required
- authenticate/decrypt before committing receive state
- persist session state safely
- reject tamper, replay, wrong identity, and malformed packets
- expose typed failures

Do not claim full Double Ratchet properties not implemented by the current protocol. Rename misleading types or documentation where needed.

4.3 REAL DATA-DRIVEN UI

Split the large demo `main.dart` into feature screens/controllers.

At minimum implement:
- account/session screen
- contact/conversation list from database streams or refreshable queries
- direct conversation screen
- message composer
- delivery state
- read receipt setting
- typing state
- edit
- reaction add/remove
- delete for self
- delete for everyone according to one non-caller-controlled product policy
- local decrypted search
- pagination
- error/retry state

Remove initial hardcoded `bob` contact and sample encrypted-message text.

4.4 OUTBOUND QUEUE

Make all durable outbound operations flow through one queue and concrete gateway.

Required behavior:
- stable operation ID and idempotency key
- durable next-attempt timestamp
- bounded retry
- typed permanent versus transient failure
- manual retry for failed operations
- one worker at a time
- restart-safe processing
- operation completion only after server acceptance

4.5 RECEIPTS, EDITS, REACTIONS, AND DELETE

Implement matching backend routes/events for every client operation.

Verify:
- sender ownership for edit/delete
- conversation membership
- edit window or explicit no-window policy
- reaction add and remove
- delete-for-self remains device/account scoped as designed
- delete-for-everyone creates durable tombstones
- stale messages do not reappear after restart or resync

4.6 PHASE 12 TESTS

Add an in-process development integration test with:
- one backend
- Alice device A
- Alice device B when multi-device foundation permits
- Bob device
- concrete REST client
- concrete sync gateway
- real database files in temporary directories
- real message protector adapter

Prove:
- registration/login
- contact/conversation establishment
- encrypted send
- backend does not store plaintext
- Bob receives and decrypts
- offline Bob catches up
- both clients restart and retain correct history
- duplicate send is idempotent
- edit/reaction/delete sync
- block prevents delivery

PHASE 12 EXIT GATE
- Persistent one-to-one messaging works through the actual app services across separate client instances and restarts.
- The server path and test database contain ciphertext, not message plaintext.
- UI state is loaded from real services/storage.
- There is no required Local package import.

==================================================
STAGE 5 - PHASE 13 CLOSURE: CONTACTS, PRIVACY, PRESENCE, AND SAFETY ✅ Done
==================================================

5.1 REMOVE CONTACT LIFECYCLE BYPASS

Review any direct `/add` or equivalent endpoint. A contact must become accepted only through the approved request/accept flow unless an explicit symmetric invite design is implemented.

5.2 SERVER-AUTHORITATIVE RULES

Enforce on the backend:
- username normalization and uniqueness
- reserved-name policy
- request quota
- duplicate request behavior
- blocked-user behavior
- cannot request self
- accept/reject/cancel ownership
- privacy-based search visibility
- presence and last-seen visibility
- minimal report evidence

Client validation may improve UX but cannot be the authority.

5.3 MULTI-DEVICE EVENTS

Contact, block, privacy, profile, and username changes must create durable events for all active devices on the account and affected peers where appropriate.

5.4 GROUP BLOCKING POLICY

Define and implement one explicit rule for blocked users in shared groups. At minimum:
- direct contact requests and direct messages are blocked
- group membership does not silently bypass backend authorization
- UI clearly handles hidden/visible group content according to the chosen policy
- tests cover both directions

5.5 CLIENT UI

Wire real screens for:
- pending incoming/outgoing requests
- accept/reject/cancel
- contacts
- remove/block/unblock
- username change
- privacy settings
- profile update
- report flow

PHASE 13 EXIT GATE
- Contact and privacy state survives restart and synchronizes to another device instance.
- Blocking is enforced by the backend, not just UI.
- Group-specific block behavior is tested.

==================================================
STAGE 6 - PHASE 14 CLOSURE: ATTACHMENTS AND FILES ✅ Done
==================================================

This stage contains security-critical authorization and key-lifecycle repairs.

6.1 RESOURCE AUTHORIZATION

For every attachment route, verify the authenticated account/device may act on the resource.

Required checks:
- upload status: owner or explicitly authorized participant
- upload bytes: owner of the upload session
- download URL/file: member of a conversation/message referencing the file
- register reference: sender owns the message and may attach that file
- lifecycle/delete: authorized owner or retention process only

Never authorize by knowing `file_id` alone.

6.2 ATTACHMENT IDENTITY

Do not use one global ciphertext hash as both deduplication hash and ownership identity.

Use one safe design such as:
- opaque random attachment ID plus separate ciphertext hash, or
- account-scoped composite identity

Prevent one account from replacing or claiming another account's object row.

6.3 KEY STORAGE AND DELIVERY

- Remove the raw-key fallback in `buildKeyDeliveryPackage`.
- Require an injected per-device key wrapper.
- Store only encrypted per-device key packages or secure-storage references in SQLite.
- Do not store raw attachment key/IV material in a field merely named `encrypted_key`.
- Bind key packages to attachment ID, conversation ID, sender identity, recipient device ID, algorithm version, and integrity metadata.
- Verify removed/revoked devices do not receive new attachment keys.

6.4 STREAMING AND BOUNDS

Refactor to bounded streaming:
- encrypt input incrementally or with a bounded temporary-file strategy
- upload fixed-size chunks
- validate server offset exactly
- handle retry without resending the entire remainder in one request
- hash incrementally
- download to ciphertext temp file
- verify hash/authentication before exposing plaintext
- decrypt with bounded memory where supported

Enforce maximum size both before and during streaming. Do not trust Content-Length alone.

6.5 TEMP AND CACHE SAFETY

- use opaque random temp names
- do not include plaintext filenames in server object paths or temp ciphertext names
- clean temp files on success, failure, cancellation, logout, and account deletion
- validate save paths against traversal
- never overwrite an unrelated file silently
- cache eviction must not delete server history

6.6 TESTS

Required negative tests:
- account B cannot query/upload/download account A attachment
- unauthorized message reference
- hash collision/duplicate hash across accounts
- offset behind/ahead mismatch
- file grows beyond declared size
- corrupted ciphertext
- wrong key package
- revoked device key request
- interrupted upload/download resume
- cancellation cleanup
- large file stays within defined memory bound

PHASE 14 EXIT GATE
- No attachment endpoint relies only on authentication.
- No raw attachment key fallback remains.
- Large attachment processing is bounded and restart-safe.

==================================================
STAGE 7 - PHASE 15 CLOSURE: REMOTE AUDIO AND VIDEO CALLS ✅ Done
==================================================

For student scope, calls must work against configurable STUN and optional locally supplied TURN settings. No purchased provider or carrier-NAT certification is required.

7.1 IMPLEMENT THE ACTUAL ENGINE

Create `RemoteWebRtcCallEngine` using `flutter_webrtc` and keep it separate from the Local engine.

It must implement:
- peer connection creation
- configured ICE servers
- offer/answer
- remote description
- ICE candidates
- local audio/video tracks
- remote renderer streams
- mute
- speaker
- camera enable/disable
- camera swap
- ICE restart
- renderer/media disposal
- quality stats sampling without content

Do not copy Local private-IP candidate filtering into Remote.

7.2 FIX INCOMING SDP LIFECYCLE

Store the inbound offer SDP with the pending call state. `acceptIncomingCall()` must pass the real offer SDP to `createAnswer`.

Reject accept when no valid pending offer exists.

7.3 SIGNALING

Wire RemoteCallSignalingGateway through the concrete transport and unified envelope.

Required behavior:
- authenticate sender
- authorize target device/account
- preserve call ID and sender identity
- validate signal type and bounded SDP/candidate size
- deduplicate or safely tolerate repeated signals
- route online over WebSocket
- store only minimal offline incoming-call hint if used

7.4 CALL UI

Implement actual Remote call screens/overlay:
- outgoing ringing
- incoming accept/decline
- audio controls
- video controls
- local/remote renderer
- camera swap
- network/reconnect state
- end reason

7.5 TESTS

Keep state-machine unit tests, and add:
- fake-engine test proving actual offer SDP reaches createAnswer
- concrete-engine smoke test where platform support permits
- two local client instances through backend signaling
- call signal missed/reconnect behavior
- duplicate offer/candidate handling
- media cleanup after decline/end/dispose
- no media bytes in database/logs

PHASE 15 EXIT GATE
- A concrete engine exists and is composed in the app.
- Incoming calls answer with the original offer SDP.
- Remote call UI is connected to RemoteCallService.
- No real provider, production TURN, or external network certification is required.

==================================================
STAGE 8 - PHASE 16 CLOSURE: REMOTE GROUPS ✅ Done
==================================================

8.1 REMOVE PLACEHOLDER GROUP KEYS

Delete deterministic fallback keys such as `key_<group>_epoch_0`.

A group operation requiring encryption must fail closed when the group-key service is unavailable.

8.2 REAL GROUP KEY LIFECYCLE

Implement:
- random group sender/group key generation
- key ID and epoch
- encrypted key package for every active member device
- key acknowledgment/state
- rotation on member removal, device revocation, and explicit compromise/reset
- no new key package for removed member/device
- old-history policy clearly defined
- persistence of encrypted key state or secure-storage references

A `group_key_updated` marker without new protected key material is not key rotation.

8.3 AUTHORIZATION AND INVARIANTS

Backend is authoritative for:
- creator/admin/member roles
- invite permission
- join approval
- group update
- role change
- member removal
- group delete

Validate role values. Prevent:
- non-admin administration
- removing/demoting the final admin without ownership transfer or group deletion
- duplicate membership corruption
- removed member sending/receiving new group events
- blocked-user policy bypass

Client optimistic state must be reversible and must not present a server-rejected action as final.

8.4 DURABLE GROUP EVENTS

Group create, invite, join, role, metadata, membership, key epoch, message, and delete events must be part of the durable device event stream and recognized by the envelope schema/client supported-type set.

On group deletion or removal, clean or tombstone local group state consistently. Do not leave an active stale conversation.

8.5 TESTS

Required tests:
- non-admin rejected
- invalid role rejected
- final-admin invariant
- removed member cannot decrypt new messages
- newly added member receives the defined history scope only
- device revocation rotates/distributes correctly
- duplicate invite/membership events
- offline group catch-up
- group deletion clears active local state
- blocking policy in shared group

PHASE 16 EXIT GATE
- Group encryption has real random keys and per-device delivery.
- Membership changes alter actual cryptographic access, not only an epoch number.
- Authorization is enforced server-side.

==================================================
STAGE 9 - PHASE 17 CLOSURE: DEVICES, BACKUP, AND RECOVERY ✅ Done
==================================================

9.1 DEVICE MANAGEMENT SERVICE AND UI

Wire:
- list devices
- identify current device
- link request
- verification/approval
- complete link
- revoke device
- lost-device flow

Use typed device IDs consistently across OpenAPI, backend, client, storage, and UI.

Pending link records and challenges must have:
- expiry
- one-time use
- attempt limit
- account binding
- device-key binding
- replay rejection

9.2 DEVICE REVOCATION

Revocation must:
- reject future authentication/refresh
- close or reject realtime connection
- stop receiving new per-device events and key packages
- invalidate pending link sessions for that device
- create durable revocation events for remaining devices
- trigger appropriate direct/group key lifecycle actions

9.3 BACKUP SERVICE

Build one app-facing backup service that:
- exports a versioned Remote snapshot from local storage
- excludes tokens and transient caches
- encrypts the backup client-side
- uploads opaque ciphertext through the concrete client
- downloads and authenticates before restore
- validates account/version/schema binding
- restores atomically into a clean temporary database or transaction
- leaves the existing database unchanged on failed restore

9.4 RECOVERY UX

Implement student-appropriate screens for:
- create backup
- show last backup state
- restore backup
- wrong key/passphrase error
- incompatible/corrupt backup error
- device revocation/lost device

Do not display or log recovery secrets after the explicit user step.

9.5 TESTS

Required tests:
- link challenge expiry/replay
- unauthorized link completion
- revoke current/other device policy
- revoked device cannot refresh or sync
- encrypted backup round trip
- corrupt/wrong-key backup leaves current DB intact
- restore into fresh client instance
- restored data can continue syncing without duplication
- backup contains no access/refresh token or plaintext private key

PHASE 17 EXIT GATE
- Device and backup features are usable through the actual app.
- Restore is atomic and failure-safe.
- Revoked devices stop receiving new events and key material.

==================================================
STAGE 10 - PHASE 18 CLOSURE: CODE-LEVEL PRIVACY, DELETION, AND ABUSE SAFETY ✅ Done
==================================================

Do not perform or require penetration tests, external audits, compliance certification, app-store submission, or production access review.

10.1 KEEP ONLY CODE-VERIFIABLE REQUIREMENTS

Close these through executable code/tests:
- authenticated privacy export
- privacy-minimized report data
- redacted audit logging
- plaintext-free notification/outbox payloads
- account deletion authorization
- server-side account purge
- local Remote logout/reset/delete cleanup
- Local unaffected by every Remote destructive action
- no cross-product storage/key deletion

10.2 ACCOUNT DELETION ORCHESTRATION

Implement one app service that:
1. re-authenticates or confirms the destructive action
2. requests server deletion
3. handles retry/partial response safely
4. stops sync and realtime
5. clears Remote access/refresh tokens
6. clears Remote identity/session/attachment/backup secrets according to contract
7. deletes Remote database and Remote caches
8. returns to first-run state
9. never touches Local storage or Local secure keys

10.3 STRUCTURED DELETION

Replace brittle deletion such as SQL `LIKE '%accountId%'` against opaque JSON payloads. Add structured ownership/recipient columns or parse/migrate data deterministically.

Use foreign keys/cascades where safe and explicit deletion ordering where cross-account records require policy decisions.

10.4 AUDIT AND ERROR RESPONSES

- Do not return raw exception text to clients for ordinary server errors.
- Map exceptions to stable safe error codes.
- Keep detailed local development diagnostics server-side with redaction.
- Do not swallow cleanup errors; aggregate them into a typed result.

10.5 TESTS

Required tests:
- account A cannot export/delete account B
- deletion invalidates tokens and WebSocket
- deletion removes account-owned records and attachment objects
- shared records follow documented semantics
- local client cleanup removes only Remote namespace
- Helix Local data survives Remote deletion/reset
- report and audit payloads contain no prohibited content
- no raw stack/exception text in API response

PHASE 18 EXIT GATE
- Code-level privacy and deletion behavior is proven locally.
- External review tasks are marked OUT OF STUDENT SCOPE, not BLOCKED.

==================================================
STAGE 11 - PHASE 19 CLOSURE: LOCAL DEVELOPMENT RELIABILITY ✅ Done
==================================================

Replace production-operability claims with a reliable local/student backend target.

11.1 LOCAL BACKEND LIFECYCLE

Provide documented commands or VS Code tasks to:
- initialize the backend database
- start backend on localhost or LAN bind address
- configure JWT/TURN-development secrets without committing them
- choose attachment storage directory
- run an integrity check
- create a local backup
- restore a local backup into a separate directory
- cleanly stop the server

Do not require Docker, cloud services, Redis, PostgreSQL, or object storage unless the current implementation actually needs them.

11.2 DATABASE RELIABILITY

Add code/test support for:
- schema version check
- foreign-key enforcement
- startup integrity/quick check
- migration transaction
- backup copy/checkpoint correctness for the actual database engine
- restore validation before replacing active data
- corruption error state

11.3 WORKERS AND RETRIES

Repair outbox/background workers:
- `start()` is idempotent
- only one timer/loop runs
- persisted next-attempt time is honored
- bounded exponential backoff and injectable jitter
- transient/permanent failure distinction
- clear failed/DLQ inspection and retry API for development
- no broad silent catch
- clean stop/dispose

A boolean `providerAvailable` simulation may remain only as a test fake, not the application transport implementation.

11.4 CONNECTION STABILITY

Add deterministic tests for:
- reconnect storm limit
- one reconnect loop per device
- backend restart
- client network loss/recovery
- duplicate reconnect events
- sync catch-up after outage
- attachment interruption
- outbox recovery after process restart

11.5 LOCAL CAPACITY SAFETY TESTS

Do not claim production capacity. Add bounded local stress tests, optional in the normal quick suite, for:
- many queued messages
- several conversations with overlapping sequences
- attachment quota
- many group events
- reconnect attempts
- database pagination

Assert correctness, bounded queue behavior, and no unbounded memory growth where measurable.

PHASE 19 EXIT GATE
- A student can start, stop, back up, restore, and inspect the local backend.
- Restart and disconnect do not lose accepted durable events.
- Worker failures remain visible and recoverable.

==================================================
STAGE 12 - PHASE 20 CLOSURE: DEVELOPER VERIFICATION ONLY ✅ Done
==================================================

Phase 20 is redefined for this closure as local development verification and product isolation.

12.1 DEFAULT VERIFICATION SCRIPT

Create or update a student-focused command such as:
- `scripts/verify_student.ps1`
- `scripts/verify_student.sh`

It must run only code-based checks:
- formatting
- analyzer
- architecture boundaries
- dependency cycles
- secret scan
- Local tests
- Remote app tests
- all Remote package tests
- backend tests
- contract tests
- migration tests
- Local/Remote isolation tests

Remove release signing, staging, production deployment, release governance, external-review, and pentest checks from the required default closure path.

Existing release scripts can remain optional and untouched unless they break debug development.

12.2 DEBUG BUILDS

Where the development environment supports them, verify only unsigned/debug development builds:
- Helix Local Android debug APK
- Helix Remote Android debug APK
- Helix Local Windows debug build
- Helix Remote Windows debug build

Do not require release mode, signing material, installer packaging, or publishing.

12.3 CROSS-PRODUCT AUTOMATED ISOLATION

Add automated tests proving:
- distinct app IDs and native namespaces
- distinct database filenames/directories
- distinct secure-storage prefixes
- Local imports no Remote package
- Remote imports no Local package
- Local wipe orchestration cannot resolve a Remote path/key
- Remote logout/delete cannot resolve a Local path/key
- Local has no Remote REST/WebSocket dependency
- Remote starts no Local mDNS/UDP discovery
- separate attachment/cache directories
- two composition roots share no mutable state

12.4 ACTUAL APP SMOKE TESTS

Replace placeholder widget tests with state-driven tests using injected real/fake-at-boundary services.

Test:
- first-run state
- authenticated state
- conversation list from repository
- send action reaches service
- sync event updates UI
- logout/reset state
- startup failure state

Do not assert only that static text or a demo contact appears.

12.5 OPTIONAL MANUAL CHECKLIST OUTPUT

The agent may generate `docs/testing/STUDENT_DEVICE_CHECKLIST.md` for the user to perform later. This document is not executable evidence and must not be used to mark code complete.

It may cover:
- two Android devices
- Android plus Windows
- two Windows devices
- app restart
- offline/reconnect
- attachment interruption
- voice/video call
- Local and Remote installed together

PHASE 20 EXIT GATE
- All required code checks pass locally.
- Both apps can produce debug builds where the toolchain is available.
- Release/staging/external checks are not part of the student closure gate.

==================================================
STAGE 13 - CLEAN UP PLAN CLAIMS AND DOCUMENTATION ✅ Done
==================================================

1. Update `HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN_PART_2_REMAINING.md` with an appended closure correction.
2. Do not delete the old implementation evidence.
3. Change or annotate overstated checkboxes based on the new classification.
4. Update misleading comments, including claims that a concrete Remote call engine exists when only an interface exists.
5. Update the Remote app pubspec/README description so it no longer says "placeholder" after real integration is complete.
6. Update realtime contract enums and compatibility fixtures.
7. Remove unsupported wording such as:
   - complete Double Ratchet
   - encrypted database at rest
   - production TURN
   - cross-network verified
   - complete multi-device recovery
   - complete group key rotation
   when the corresponding executable behavior is not present.
8. Preserve future production documents but label them future/out-of-scope for the student closure where necessary.
9. Add one final closure entry to the architecture changelog.

==================================================
REQUIRED TEST ARCHITECTURE
==================================================

Use four levels of evidence.

LEVEL 1 - UNIT
- validation
- state machines
- crypto adapters
- serialization
- retry math
- authorization policy

LEVEL 2 - COMPONENT
- database migrations
- repository behavior
- backend module handlers
- attachment streaming
- WebRTC engine adapter with platform fakes where needed

LEVEL 3 - IN-PROCESS INTEGRATION
- actual backend router
- concrete REST client
- concrete realtime/catch-up gateway
- temporary backend/client databases
- real application services
- real envelope serialization

LEVEL 4 - APP INTEGRATION
- composed RemoteCompositionRoot
- first-run bootstrap
- authentication/session restore
- message send/receive UI state
- restart and sync
- logout/delete isolation

Do not use Level 1 evidence to declare a Level 4 feature complete.

==================================================
MANDATORY SECURITY AND DATA-INTEGRITY TESTS
==================================================

At minimum add or retain tests for:
- invalid/expired login challenge
- refresh token replay/rotation
- revoked device
- invalid signed prekey signature
- consumed prekey replay
- tampered message ciphertext
- receive-state rollback after authentication failure
- duplicate message operation
- cross-conversation sequence overlap
- sync batch rollback
- attachment IDOR attempts
- attachment cross-account hash collision
- raw attachment-key fallback prohibited
- non-admin group change
- removed group member key exclusion
- wrong backup key
- corrupt restore leaves current data intact
- account deletion affects only Remote
- logs and API errors contain no prohibited content

==================================================
REQUIRED COMPLETION COMMANDS
==================================================

Run from the project root where supported:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed apps packages services tool
flutter analyze
dart run tool/check_boundaries.dart
dart test tool/boundary_test.dart
dart run tool/dep_graph.dart
dart run tool/check_secrets.dart
.\scripts\verify_student.ps1
```

Also run the Unix student script if maintained:

```bash
./scripts/verify_student.sh
```

Run debug builds only when the current machine has the required Flutter platform toolchain:

```powershell
cd apps\helix_local
flutter build apk --debug
flutter build windows --debug

cd ..\helix_remote
flutter build apk --debug
flutter build windows --debug
```

Do not fail the code closure merely because one platform SDK is not installed. Report `NOT RUN - TOOLCHAIN UNAVAILABLE` honestly. A compilation error on an installed toolchain is a failure.

==================================================
PHASE-BY-PHASE READINESS CHECKLIST
==================================================

PHASE 12
- [ ] Fresh install works.
- [ ] Real authentication/session restore works.
- [ ] Concrete REST and realtime clients are composed.
- [ ] Actual E2EE adapter is used by messaging.
- [ ] UI is data-driven, not sample-list driven.
- [ ] Offline catch-up and restart work.
- [ ] Edit/reaction/receipt/delete operations match backend events.
- [ ] End-to-end in-process test passes.

PHASE 13
- [ ] Request lifecycle has no direct-add bypass.
- [ ] Backend enforces quotas/privacy/blocking.
- [ ] Multi-device contact/privacy events are durable.
- [ ] Group blocking behavior is defined and tested.
- [ ] Actual screens use the service/backend.

PHASE 14
- [ ] Every resource route has ownership/membership authorization.
- [ ] Attachment IDs cannot collide across accounts.
- [ ] No raw attachment key fallback exists.
- [ ] Key packages are per-device encrypted.
- [ ] Streaming and cleanup are bounded and tested.

PHASE 15
- [ ] Concrete Remote WebRTC engine exists.
- [ ] Incoming offer SDP is retained and used.
- [ ] Service, signaling, engine, and UI are composed.
- [ ] Media is disposed reliably.
- [ ] Local engine remains unchanged.

PHASE 16
- [ ] No deterministic group key fallback exists.
- [ ] Actual key material rotates and is redistributed.
- [ ] Server enforces roles and final-admin rules.
- [ ] Removed members/devices cannot receive new keys.
- [ ] Group events are durable and syncable.

PHASE 17
- [ ] Device linking is app-accessible and replay-safe.
- [ ] Revocation invalidates auth and future delivery.
- [ ] Backup upload/download/restore is wired.
- [ ] Restore is atomic and failure-safe.
- [ ] Recovery UI exists.

PHASE 18
- [ ] Export/deletion authorization passes.
- [ ] Remote local cleanup is complete and isolated.
- [ ] Structured deletion replaces payload substring matching.
- [ ] Audit/outbox/error responses are content-safe.
- [ ] External review tasks are OUT OF STUDENT SCOPE.

PHASE 19
- [ ] Local backend lifecycle commands exist.
- [ ] Integrity, backup, and restore utilities work locally.
- [ ] Workers are single-instance, durable, and observable.
- [ ] Reconnect/restart/catch-up tests pass.
- [ ] No production SLO/deployment evidence is required.

PHASE 20
- [ ] Student verification scripts pass.
- [ ] Release-only checks are outside the default gate.
- [ ] Debug build results are reported honestly.
- [ ] Automated cross-product isolation passes.
- [ ] Placeholder widget tests are replaced.

==================================================
STOP CONDITIONS
==================================================

Stop and return `NOT READY FOR STUDENT DEVICE VALIDATION` when any of these remain:
- Remote app cannot start on a fresh install.
- UI still uses hardcoded sample contacts/messages as the functional data path.
- no concrete REST client or SyncGateway is composed.
- realtime/catch-up contracts remain incompatible.
- global cursor still consumes conversation-local sequences.
- message protector is a no-op or raw plaintext adapter.
- attachment endpoints allow cross-account access.
- raw attachment keys can be used as a fallback.
- no concrete Remote call engine exists while Phase 15 is claimed complete.
- deterministic group key fallback remains.
- backup restore can corrupt or replace current data before validation.
- Remote account cleanup can touch Local state.
- analyzer, boundary, secret, migration, contract, or integration tests fail.

==================================================
REQUIRED FINAL REPORT
==================================================

Provide the final report in exactly this structure:

# Phase 12-20 Closure Report

## Overall Result
READY FOR STUDENT DEVICE VALIDATION | NOT READY FOR STUDENT DEVICE VALIDATION

## Executive Summary
State what was connected, repaired, and still incomplete.

## Scope Applied
Confirm that production, staging, deployment, publishing, signing, pentest, and external-review work was excluded.

## Baseline Findings
List the original disconnected, defective, placeholder, and overstated areas.

## Phase Status
- Phase 12:
- Phase 13:
- Phase 14:
- Phase 15:
- Phase 16:
- Phase 17:
- Phase 18:
- Phase 19:
- Phase 20:

For each phase use:
- VERIFIED END TO END
- VERIFIED COMPONENT ONLY
- PARTIAL
- DISCONNECTED
- PLACEHOLDER
- DEFECTIVE
- OUT OF STUDENT SCOPE
- NOT STARTED

## Critical Repairs
Group by:
- Remote bootstrap/composition
- contracts/transport
- realtime/sync
- messaging/crypto
- contacts/privacy
- attachments
- calls
- groups
- devices/backups
- deletion/isolation
- local backend reliability
- developer verification

## Files Changed
List all created, modified, moved, and deleted files.

## Database Migrations
For every client/backend migration state:
- version
- schema change
- forward behavior
- failure rollback
- compatibility impact
- test evidence

## Contract Changes
List REST and realtime changes and compatibility fixtures.

## Security-Critical Changes
Explain:
- authentication/session lifecycle
- key lifecycle
- message protection limitations
- attachment authorization/key delivery
- group key rotation
- device revocation
- backup/restore validation
- log/error redaction
- Local/Remote isolation

## Tests and Evidence
For every suite include:
- command
- result
- test count
- platform
- integration level

## Debug Builds
- Local Android debug:
- Remote Android debug:
- Local Windows debug:
- Remote Windows debug:

Use PASS, FAIL, or NOT RUN - TOOLCHAIN UNAVAILABLE.

## Student Device Checks Remaining
List only manual checks the student must perform after the code pass. Do not treat them as completed evidence.

## Remaining Code Blockers
List only code/toolchain problems. Do not list production, staging, publishing, signing, pentest, or external review.

## Updated Phase Checklist
Repeat every item in the phase-by-phase readiness checklist with PASS or FAIL.

## Final Recommendation
State exactly one:
- READY FOR STUDENT DEVICE VALIDATION
- NOT READY FOR STUDENT DEVICE VALIDATION

Do not approve the project merely because unit tests pass. Approval requires the actual Remote app composition and at least one complete in-process end-to-end messaging flow through concrete transport, backend, storage, encryption adapter, sync, and restart.
