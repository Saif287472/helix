# helix_remote_engine

The Helix Remote v2 messaging core (ADR-027, plan §6.3): everything between
the network and the UI that is not UI. **Pure Dart** (no Flutter, no
`dart:io`, no drift, no HTTP), built from injected pieces, with no globals,
so the app, the FCM background isolate, the CLI and tests each make their own
`Engine`.

Phase C3b delivered the **direct-chat core**. Groups, calls, attachment
transfers and backup are Phase C4 (see "Not here yet").

## Who may depend on it, and on what

- **Users:** the app's `application/` layer (A1+), the CLI
  (`helix_remote_cli`'s v2 entry), the admin console where it needs account
  logic (AD). Presentation never imports it (plan §6.4).
- **Depends on:** `helix_remote_protocol`, `helix_remote_crypto`
  (`lib/v2.dart` only), `helix_remote_api` (`lib/v2.dart` only),
  `helix_remote_db`, plus `crypto` (the discovery hash) and `meta`.
  `test/architecture_test.dart` applies `v2PackageRules`, forbids Flutter,
  `dart:io`, drift, sqlite3 and HTTP, forbids the v1 packages, and scans for
  `DateTime.now()`, `Random.secure()`, `SecureCryptoRandom()` and `print(`
  (the clock and randomness are injected; the engine logs nothing).

## Composition

```dart
final db = await HelixDb.open(file, key: key);                 // encrypted
final api = HelixApi(baseUrl: server, sessions: DbSessionTokenStore(db));
final engine = Engine(api: api, db: db, clock: DateTime.now,
    random: SecureCryptoRandom(), phoneBook: …);                 // injected
await engine.start();       // loads the identity; signed out -> waits
```

The caller owns `db` and `api` and closes them after `engine.close()`.
`Engine` exposes the services below, `status`/`statuses`
(`idle, signedOut, running, stopped, revoked`), `events`, `connection`
(the socket's state), and the headless calls `syncOnce()`, `drainOutbox()`
and `runMaintenance()`.

| Service | What it does |
|---|---|
| `account` | phone code, register (Global or personal server, password optional, SMS takeover), password sign-in, link as the new device (`beginLink` -> `NewDeviceLink`), device-key sign-in (wired as `HelixApi.auth.reauthenticate`) |
| `devices` | device list (watch), rename, revoke, revoke others, security events, approve another device's link (`approveLink`) |
| `chats` | chat list, messages, search (watch queries); send text/reply/mentions and the blob-free content types; react, edit, delete, vote, RSVP; mark read (read receipts), view-once, disappearing timer, pin/mute/archive/draft, retry a failed send or a failed action; the same for group chats (`group:<id>`) |
| `groups` | create, rename, description, picture, settings, add/remove members, roles, leave, ban/unban, delete, invite links (create, preview, join, revoke), join requests, refresh; see "Groups (Phase C4-G)" |
| `people` | phone-book discovery by salted hash (`PhoneBook` is injected), lookup by number or `~name`, profiles (encrypted: name, about line and picture - see "Profiles and the profile photo"), nickname (synced to own devices and written to the phone book), block/unblock, report (`report`), the profile's about line (`aboutOf`/`watchAbout`), safety number and verified flag, display-name order helper `PersonNaming` (a rename the phone accepted also updates the stored phone-book name) |
| `settings` | typed local settings (`EngineSettings`, any `Setting<T>`), server-side privacy, the `~Helix name` |
| `presence` | typing indicators in both directions (ephemeral) |
| `push` | push-token registration |

Lifecycle: `start({realtime, background})`. Signed in it starts the outbox
worker, housekeeping timers (`background`) and the WebSocket + inbound
pipeline (`realtime`). Signed out it waits and starts them by itself when
`account` finishes registering or signing in. A headless host passes neither
and calls `syncOnce()`: read the mailbox over REST, process, ack, then send
what that queued (delivered receipts, session resets); the `SyncSummary`
carries the `IncomingNotice`s a notification needs. `signOut()` stops the
workers, removes the device from the account on the server (best effort) and
**always wipes** the database: a device that kept its keys could sign itself
in again with its signing key.

## Layout

```
lib/helix_remote_engine.dart        public exports
lib/src/
  engine.dart                       Engine: wiring, lifecycle, revocation, sign-out
  context.dart                      EngineContext: api, db, clock, random, identity,
                                    per-device locks, event sink (one per Engine)
  config.dart                       EngineConfig (timers, limits; tests shorten them)
  events.dart                       EngineStatus, EngineEvent, IncomingNotice
  errors.dart                       EngineException family
  settings_keys.dart                EngineSettings (user) and EngineState (bookkeeping)
  maintenance.dart                  expiry timer, housekeeping, key upkeep schedule
  crypto/                           LocalIdentity, DbSessionStore/DbPrekeyStore,
                                    PeerDirectory (bundles, AIK pin, key change),
                                    PairwiseCrypto (manager glue, locks, commits)
  account/                          AccountService, DeviceService, KeyMaintenance,
                                    DbSessionTokenStore
  messaging/                        InboundProcessor, InboundRunner, ContentApplier,
                                    OutboxService, OutboxWorker, MessageSender,
                                    ContentCodec, MessageKinds
  features/                         ChatsService, PeopleService, PresenceService,
                                    SettingsService, PushService, PhoneBook
  groups/                           GroupsService, roster sync, sender keys, group
                                    send and inbound (see "Groups (Phase C4-G)")
  util/                             KeyedLock, Backoff, IdFactory/RandomAdapter, masking
```

## Inbound pipeline (plan §6.3)

`InboundRunner` feeds `InboundProcessor` from the WebSocket (`startRealtime`)
or the REST mailbox (`fetchOnce`); both share one serial queue and
`processed_envelopes` de-duplicates them.

1. **Dedupe:** `(envelope id, sender device)` in `processed_envelopes`; a
   replay is acked again and changes nothing.
2. **Decrypt** under the sender device's lock (`PairwiseCrypto.locked`, which
   also retries when another engine moved the stored state). The crypto layer
   returns the new session records; it never writes.
3. **Decode** `ContentMessage`. An unknown `type` or a newer `v` becomes a
   row whose kind the UI shows as "needs a newer version"; a body that does
   not parse is quarantined.
4. **Apply in ONE transaction** (`ContentApplier`): session records, the
   consumed one-time prekey, the message row (the DAO updates the chat
   summary and FTS), reactions, receipts, edits, deletes, poll votes, RSVPs,
   deferred actions that were waiting for this message, the queued
   `delivered` receipt, `processed_envelopes` and the cursor.
5. **Ack** after the commit: over the socket when connected (returns window
   credit), else REST. The cursor in `inbox_cursor` is the resume point.
   It only moves forward, except after a server restore: when the realtime
   client reports `cursorReset` (the cursor it resumed from was above the
   `hello`'s `seq_head`) or a mailbox page's `seq_head` is below the cursor
   it was asked from, `InboundRunner` resets it to 0
   (`InboxDao.resetCursor`, in the inbound queue) and processes the replay;
   `processed_envelopes` drops what was already handled. The realtime client
   resets its own cursor on that `hello` too.

Rules:

- **Quarantine, never block.** An envelope that cannot be read is quarantined
  and the stream goes on. Whether it is *shown* and whether the sender is
  asked to *repair* are two decisions, both from `QuarantinePolicy`
  (`messaging/quarantine_policy.dart`) so the direct and group pipelines cannot
  drift (AUD-12f-1). Shown: a placeholder row (`payload`: `{code, waiting,
  device}`) for what the user would have seen — the server's `urgent` flag;
  receipts, reactions, edits, deletes and votes go out non-urgent and get no
  row. Repaired: any curable failure, urgent or not — a lost or diverged
  session (no session, unknown prekey, used key, or an authentication failure,
  which after a restore looks the same as tampering) queues a `session_reset`
  op (CRYPTO_V2.md §13a): start a fresh session with that device (at most one
  per `resetCooldown`, however many messages failed) and send
  `decryption_error` (the failed envelope id) to the sender's account; the
  sender re-sends the message (under 24 h) over the new session and the real
  message replaces the placeholder. An action is not stored as a row, so a
  quiet action buys a new session now and its own re-send once the sender can
  rebuild one (AUD-12i-1). Identity failures (`untrusted_identity`) and
  unparseable payloads do not ask for a reset. A hostile server can use
  authentication failures to make a client start cooldown-limited sessions and
  request re-sends; it could drop the messages anyway.
- **Only a `TransientEngineException`** (no network while looking up an
  unknown sender's keys) holds the stream back, because acks are cumulative:
  the runner retries that envelope with backoff. Any other unexpected failure
  retries three times and then quarantines (`internal_error`).
- **Authorship is the server-attested sender.** Edits and deletes apply only
  when the sender is the target's author, within 15 minutes / 2 days of the
  target, and never when the action's own time is dated before the target (a
  negative difference would otherwise pass both windows - AUD-12c-2); the
  newest edit and the newest reaction win; a message cannot claim a time more
  than a minute in the future; content addressed to someone else (`conv.to` is
  not this account) is dropped.
- **Actions wait for their message** up to 7 days (`deferred_actions`).
- **Ephemeral envelopes** (typing) are decrypted (the ratchet moves and is
  committed), reported through `TypingEvent`, and never stored or acked. A
  *stored* typing envelope (the sender's flag is untrusted) is recorded like
  any other, so it is not delivered again on reconnect (AUD-12f-2).
- **Blocked senders** are decrypted and ignored (the ratchet must move).
- Call signals are acked and ignored until the calls feature lands. Group
  envelopes and group key material are handled by the group pipeline (see
  "Groups (Phase C4-G)" at the end).

## Outbound pipeline

A UI action is **one transaction**: the optimistic row (`status: pending`) and
an `outbox_ops` row (`send_content`, payload = the `ContentMessage` JSON plus
the audience). `OutboxWorker` has one wake-up path, the queue's change mark
(`OutboxDao.watchQueueMark`), plus a timer for the next retry. It claims due
ops oldest first, **one at a time per conversation** (a message backing off
holds back later ones of its chat; failed ops do not), and for each:

1. **Plan** (`MessageSender`): the audience's devices from `person_devices`;
   this account's other devices from `self_devices`; a never-seen peer is
   fetched once. A bundle fetched while planning is kept for starting the
   session (a fetch takes one one-time prekey from the recipient).
2. **Encrypt at send time, commit before sending:** one ciphertext per device;
   all new ratchet states are committed in one transaction before the request
   leaves (`PairwiseCrypto.encryptFor`). Everything that reads then writes a
   device pair's state holds that device's lock.
3. **POST** with the content id as request id (idempotency key). First sends
   use `request id == content id`, so a receiver that cannot decrypt can name
   the message.
4. **`device_list_stale`** (409): gone devices are dropped (their sessions are
   cleared, retired base keys kept), new ones fetched, and the plan is redone
   (`staleListRetries`), without counting as a failure.
5. **Outcome:** success completes the op and advances the status to `sent`
   (delivered/read come from receipts and only move forward); a retryable error
   (network, 5xx, 429 with `Retry-After`, quota) reschedules with exponential
   backoff; an op older than `outboxMaxAge` (30 days, the server's mailbox
   retention: a PC server that is off for days fails nothing) or refused for good
   (`forbidden`, `untrusted_peer`, `not_found`, …) fails, the message shows as
   failed and `SendFailedEvent` is emitted; `device_revoked` starts the
   revocation path; a dead session pauses the worker.

**Classification** (`classifyOpError`) is by error class, then by the server's
code or the engine's own `GroupFailure` reason - never by message text. A group
refusal this device cannot outgrow (`notAMember`, `notAllowed`, `badLink`,
`badMention`) gives up; one the world can still overtake (`noGroupKey`,
`versionConflict`) retries, and so does the server's `version_conflict`, which
is what an optimistic state write gets when someone moved first (the retry
re-reads the newer state; giving up on it left the group unreadable for
everyone - AUD-12b-1). A `NoSessionException` retries too: the session is one
bundle fetch away.

An op that gives up leaves a `failed` row. A `send_content` op has a message
under it, so the user gets a retry; a duty op (`group_rekey`, `session_reset`)
has none, and nothing in the UI would ever ask again. So housekeeping
re-derives the duty from the state (`GroupKeyDistributor.reconcileRekeyDuties`,
run by `MaintenanceService`): a group whose stored blob does not yet open under
the current epoch's key, for the member who owes that rotation (the first admin
by account id, the same rule the inbound path uses), gets its `group_rekey` op
back. The duty's idempotency key names the epoch (`rekey:<group>:<epoch>`), so
re-asking is cheap and a rotated group generates no op at all; a duty that keeps
failing is re-asked `GroupLimits.rekeyDutyRetries` times and then left failed for
an admin, because a pass that re-asked forever would be its own unbounded cost.
Asking by hand (`GroupsService.rotateKey`, a roster envelope) is never bounded.

An **action** op (reaction, edit, delete, vote, RSVP) has a message it is
about but delivers no message of its own, so `outbox_ops.message_rowid` stays
null and the target rides the payload (`target_rowid`, never
`message_rowid`, which would advance the message's own status). When one gives
up, the chat reads it back by conversation (`ChatsService.watchFailedActions`
/ `failedActions`): the target message draws the failure and a retry
(`retryAction(opId)` puts the same op back in the queue) while its own status
does not change. A new attempt at the same action on the same message
discards the superseded failed op first, so a stale failure line cannot
outlive the redo and its retry cannot re-send what the person has since
undone.

A message removed on this device takes its queued send with it:
`deleteForMe`, `clearChat`, `deleteChat` and a disappearing expiry drop the
message's pending and failed ops in the same transaction
(`OutboxDao.cancelForMessages`, wired into `MessagesDao.removeMessages` and
`clearConversation`), and `deleteForMe` also drops queued actions about those
messages. An in-flight op is left alone - its request may already be on the
wire. Deleting a pending message is therefore a cancel, never a delayed send
(AUD-12i-2).

Every visible send, action, edit, delete and `read` receipt also goes to this
account's own other devices (they get the same content; `conv.to` names the
peer). `delivered` receipts go to the author only. Retried sends re-encrypt
(a retry after a lost response consumes one more message key, which the
receiver skips).

## Trust and keys

- **AIK pinning:** the first AIK seen for an account is pinned in `people`.
  A bundle under another AIK is a **key change**: sessions with all of the
  account's devices are dropped first (retired base keys kept), then one
  transaction marks its devices `stale`, resets the verified flag and pins the
  new AIK, adds the local `system` row `safety_number_changed` to the chat, and
  `KeyChangedEvent` is emitted. Clearing before the commit is deliberate
  (AUD-12d-1: never a lock inside a transaction) and self-healing - a failure
  or a crash in between leaves the old pin, so the next fetch clears again. This
  account's own AIK never changes: a bundle claiming otherwise is refused
  (`UntrustedPeerException`).
- **Certificates** are checked on every bundle (`VerifiedAccountKeys`); one bad
  bundle fails the fetch, nothing is encrypted to an unverified key.
- **Prekeys** (`KeyMaintenance`): 1 signed + 100 one-time at registration or
  link; replenished by `prekeys_low` and a periodic status check (the new keys
  are stored **before** the upload); the signed prekey rotates after 7 days and
  the old private key is deleted 30 days after its successor; ids come from
  counters in `settings` and are never reused.
- **Linking:** this device as approver (`DeviceService.approveLink`: checks the
  code names this server, seals the AIK seed and profile key to the new device)
  and as the new device (`AccountService.beginLink` -> `NewDeviceLink`).
- **Revocation:** close code 4003, an `account_signal` naming this device,
  `device_revoked` on any call, or a failed device-key sign-in end the engine:
  workers stop, the session is forgotten, the database is wiped
  (`EngineConfig.wipeOnRevocation`, default on, per
  `remote_bounded_contexts.md`), then status `revoked`.

## Data conventions

- Conversation ids are `direct:<peer account>`. `messages.kind` is the content
  `type`, or `undecryptable` / `unsupported` (`MessageKinds`).
- `messages.body` is the searchable text or caption; `payload` is the rest of
  the content body as JSON (`ContentCodec`). Poll votes and RSVPs are kept in
  the poll/event message's payload under `votes` / `rsvps` (the schema has no
  vote tables).
- Outbox kinds: `send_content`, `session_reset`; the payload is the plaintext
  to encrypt at send time, `last_error` a code only.
- Sessions: `DbSessionStore` maps one `DeviceSessions` record onto the six
  `sessions` slots (slot 0: active session and retired base keys as JSON; 1-5:
  previous sessions). The record's `version` is the database revision it was
  read at: `save` writes only while that is still the stored one and throws
  `StaleSessionState` otherwise, so two engines on one database file cannot
  commit the same ratchet state (C-01). Every read-then-write goes through
  `PairwiseCrypto.locked` / `encryptFor`, which retry from what the winner
  committed - the retry must reload inside the attempt, never reuse a record
  loaded earlier. A cleared record is written as an empty one-slot record, not
  deleted, so the revision survives.
- **Locks outermost, transactions innermost** (AUD-12d-1). Drift serializes
  transactions on this engine's single connection, and `KeyedLock` is not
  re-entrant, so a task that opens a transaction and then waits for a device
  lock can wait forever (a send or an inbound apply holds the lock and queues
  its transaction behind that one), and a task can also wait for a lock it
  already holds. Nothing takes a device lock inside a transaction, and work
  that needs several devices' locks at once (`encryptFor`) takes them sorted and
  before its transaction. Clearing a device's sessions is one of those cases and
  takes no lock at all: the record's `version` is what makes the write safe, and
  the reload-and-clear again loop converges, so `PeerDirectory` can clear a
  session of the very device whose lock the caller holds (a prekey message from
  an account whose key just changed). `test/lock_order_test.dart` drives the two
  orders against each other and fails if they ever meet.
- Sender keys: `DbSenderKeyStore` does the same for this device's own sending
  key in a group (schema 4). `ownKey` remembers the revision it read; a commit
  of an `OwnSenderKeyWrite` lands only while that is still the stored one, and
  throws `StaleSenderKeyState` otherwise. `GroupMessageSender` then encrypts
  again from the stored key (nothing was sent), up to `staleAttempts` times; a
  refused "delivered" mark after a successful send is dropped, which only means
  a redistribution next time. Every own-key read and write runs under the
  group's send lock. Received keys save last-writer-wins at revision 0.
- Settings: `EngineSettings` (user-facing: read receipts, typing, default
  timer) and `EngineState` (session JSON, prekey counters, timestamps).
- Nothing in the engine logs. `maskPhone` and `shortId` are for hosts that
  print.

## Profiles and the profile photo (Part B E1, 2026-10-22)

A profile is one encrypted blob on the server (`EncryptedProfile`,
CRYPTO_V2.md §9) whose plaintext is `ProfileContent`: the display name, the
about line and a `MediaPointer` for the picture. It is sealed with the
account's profile key, and that key travels inside every message the account
sends — so a picture is readable by exactly the people this account has
messaged, and by nobody else: the server holds a random media id, a size and
ciphertext it cannot read.

- **Publishing** (`setOwnProfile(photoBytes:)`): the picture is encrypted with
  a fresh attachment key and uploaded as a `persistent` object (the server's
  own limits are 5 MiB an object and 50 MiB an account; this device refuses
  more than `PeopleService.maxPhotoBytes`), and its pointer goes into the
  profile. The pointer is remembered in the `people.photo:<account>` setting, so
  a later name-only save republishes the same picture instead of quietly
  dropping it, and an install that has never published reads the pointer back
  off the server first. `clearPhoto: true` publishes no pointer and deletes the
  object it used (best effort).
- **Reading** (`refreshProfile`): the pointer is fetched bounded by the size the
  pointer declares, checked against its digest and its length, then stored in
  `people.avatar_blob` — the one column every avatar in the app draws. A picture
  that cannot be fetched or does not check out is not stored, never fails the
  profile read, and stays remembered for the next refresh (which then needs no
  newer profile version). A profile with no picture clears the stored blob.
- **When it is read:** whenever the host asks (the app does it on a person's
  details page) and by the engine itself when a message arrives from a person
  whose profile this device has never read (`InboundHooks.onPeerProfile` and
  `profileNeedsRead`: at most one request per person per day while that is so).
  A picture someone changes later arrives with the next read of their profile.
- An account's *own* picture is not in `people` (that table is other people), so
  a host shows the one it holds itself; the engine keeps the published pointer,
  which is what a peer reads.

## Testing

- `test/support/fake_server.dart` is an in-memory Helix server behind an
  `http.Client` (identity, keys, messaging, links, device-key sign-in, people
  discovery and profiles) with the real server's device-list rule, per-device
  mailboxes and fault injection (`failNext`, `dropNext`, `loseResponseNext`);
  `peers.dart` builds engines on in-memory encrypted databases with a
  ticking test clock, and routes media to `test/support/fake_media.dart` when
  a test is given `Peers(media: ...)`. These cover the pipelines without
  Postgres.
- `test/lock_order_test.dart` holds a device lock in one task while another
  retires that device's sessions, in both orders, and fails on a timeout: the
  shape of AUD-12d-1. It builds an `EngineContext` over a test peer's database
  to drive `PeerDirectory` directly, the way `test/two_engines_test.dart` drives
  the session compare-and-set.
- End-to-end tests against the real in-process server are in
  `server/test/client/engine/` (the engine may not depend on the server): two
  engines over live sockets, a linked second device, offline catch-up,
  revocation, a stale device list, key change, §13a recovery, prekey top-up,
  signed-prekey rotation, a concurrency stress run, and the CLI.

## Not here yet (C4 and later) and open items

- Groups, calls, attachment transfers, history backup and device-to-device
  transfer, and recovery codes landed in Phase C4 (sections below).
  Still not built: **live-location updates** (only the `start` content
  becomes a row) and group calls (deferred from v2).
- **Profile key after password sign-in:** a device that signs in with only a
  password has no profile key (it travels by link provisioning or backup); it
  makes a new one on the first `setOwnProfile`.
- **Several isolates:** drift watch streams do not cross database instances.
  An FCM isolate writing the same file is invisible to the UI isolate's
  streams until they re-query; A1 decides between a shared drift isolate and
  a refresh on resume. Two engines *writing* the same file are now safe against
  each other (the session and own sender-key compare-and-sets, C-01) but the
  app still keeps them apart by lease: a `StaleSessionState` or
  `StaleSenderKeyState` that survives
  `staleAttempts` retries is the caller's problem (an inbound re-delivery, an
  outbox backoff), not a state to work around.
- **Contact-list upload** (`PUT /v1/people/contacts`, only for "contacts"
  audiences) is not wired; **profile-key rotation on block** is not done.


## Calls and account recovery (Phase C4-K)

### Calls (`lib/src/calls/`, `engine.calls`)

`CallsService` is the 1:1 call **state machine**; the media is not here. The
host gives it a `CallMediaFactory` (`engine.calls.mediaFactory`, or
`Engine(callMedia:)`), whose `CallMediaSession` is a pure-Dart interface over
one WebRTC peer connection (offer/answer as SDP strings, remote and local ICE
candidates, mute, camera, connection state, close). The Flutter calls package
implements it in Phase A3; `package:helix_remote_engine/testing.dart` has the
deterministic `FakeCallMediaFactory`.

- **Wire:** `CallSignalPayload` (protocol, REST_V2.md "calls"): `offer`,
  `answer`, `ice`, `ringing`, `end` with a reason, JSON sealed per recipient
  device through the pairwise session manager (`EngineCallSignaling` ->
  `MessageSender.sendSealed` -> `POST /v1/calls/{id}/signals`). An offer
  addresses every active device of the callee (the stale-list retry of the
  message path repairs an incomplete list); the answer, the ICE and the
  hang-up of an answered call go to the one device the call talks to.
- **Receiving:** a `call_signal` envelope is opened under the sender device's
  lock, the ratchet is committed, and the signal goes to the state machine; one
  that cannot be opened is dropped (ephemeral: no repair request, no
  placeholder row). The server's payload-less "answered/declined on another
  device" notice is honoured only from this account and only for a call that
  still rings here.
- **State:** one call at a time; `current` / `watchCurrent()` give a
  `CallSnapshot` (`CallPhase`: `calling`, `ringing`, `connecting`, `active`,
  `ended` with a `CallEnd`, then `null`). Actions: `startCall(peer, video:)`,
  `accept()`, `decline()`, `hangUp()` (cancel, decline or hang up, whichever
  fits), `setMuted`, `setCameraEnabled`. All run on one queue with the incoming
  signals. Failures are `CallFailedException(CallFailure)`.
- **Rules:** a second offer while in a call gets `busy` and is logged as
  missed; **glare** (both call at once) is settled the same way on both ends,
  the smaller call id survives and the loser's row is forgotten; a second
  answering device is told `answered_elsewhere`; `end` from a device the call
  is not bound to is ignored; ring timeout (`CallConfig.ringTimeout`, 60 s),
  connect timeout (30 s), media failure all end the call and tell the peer.
  Calling someone this user blocked throws `blocked`; a blocked caller's offer
  is dropped without a ring or a row; the server refuses a call from someone
  the callee blocked (`blocked`), which fails as `CallFailure.blockedByPeer`.
- **Blocked by someone:** `PeopleService.blocksMe` / `watchBlocksMe`, kept in
  `PersonState.blocksMe` (a setting, no schema change). Set by the server's
  `block_change` envelope, by `blocked_by` on a send (`MessageSender.send`)
  and by a refused offer; cleared by the unblock envelope, a send that
  reaches them or an offer that goes out. A message that reached nobody
  because everyone it was for blocked this account fails (`blocked`).
- **Pending calls:** an offer for a device that was offline waits on the server
  (TTL up to 120 s) and a high-priority push wakes it. `Engine.syncOnce()`
  (headless, FCM isolate) returns `SyncSummary.pendingCalls` (who is calling,
  until when) **without opening** them; opening moves the ratchet and the SDP
  must not be written down, so the running app rings them with
  `calls.fetchPending()`, which the engine also runs whenever the socket
  connects. An offer rings once (the call log remembers it); an expired offer,
  one the caller already cancelled and one from a blocked caller never ring.
- **Call log:** `call_log` rows (`direction`: `incoming|outgoing|missed`,
  `state`: `ringing|active|ended|declined|cancelled|unanswered|missed|failed|
  answered_elsewhere`) with the answer and end times; never SDP, ICE or a
  name. Watch it with `calls.watchLog()` / `watchLogWith(peer)`. The **caller's
  device** also posts the `call_log` content message to the chat (outcome and
  duration), so both sides' chats and the callee's other devices agree: a
  device that never saw the call ring writes the matching `call_log` row from
  that message (`CallLogMirror`), and only a *missed* call it never saw alerts
  (one `IncomingNotice` through `SyncSummary.notices`).
- **Events** (`Engine.events`): `IncomingCallEvent(CallSnapshot)` when a call
  rings here and `MissedCallEvent(IncomingNotice)` (`kind: 'missed_call'`,
  `messageId` = call id, `messageRowid` 0) when a call that rang here went
  unanswered.
- **Privacy:** SDP/ICE live only in memory for the length of a call, are never
  stored or logged (`toString` of the payloads and TURN credentials is
  redacted), and the engine sends no call metrics.
- **Shutdown:** `stop()`, revocation and `signOut()` end a live call (a hang-up
  is tried for `CallConfig.signalTimeout`). A foreground engine marks log rows
  left ringing/active by a crash as `failed` when it starts.

### Account recovery (`AccountService`)

`lookupRecoveryCode(code)` and `recoverWithCode(...)`: the lookup names the
account (additive `account_id` on `RecoveryLookupResponse`, REST_V2.md), the
engine makes a **new AIK**, certifies a new device under it for that account id
and redeems. With SMS configured the phone must be verified first
(`requestPhoneCode(purpose: recover)` then `verifyPhone`, pass the token), else
`SignInException(verificationRequired)` is thrown before anything is sent. The
server signs every other device out (they see revocation and wipe), deletes
the password and the history backup, and tells contacts about the key change,
which their engines pin and announce in the chat. An optional new password
wraps the new AIK as at registration. The old account's messages and sessions
are not recoverable this way (restore is the backup phase's job).
## Media transfers (Phase C4-M)

`lib/src/transfers/`. Attachments move through a **durable transfer queue**
(`transfer_jobs`, one job per attachment) worked by `TransferWorker`; the
outbound and inbound pipelines only write rows. The engine still does no file
I/O of its own: bytes go through an injected `BlobStore`, image and video
knowledge through an injected `MediaProcessor`, and the network through
`HelixApi.media`.

```dart
final engine = Engine(api: api, db: db, clock: …, random: …,
    blobs: AppBlobStore(dir),            // required for media; null = disabled
    mediaProcessor: AppMediaProcessor(), // optional; default reads image sizes
    transferConfig: const TransferConfig());
```

Without `blobs`, `engine.media.sendMedia` throws `StateError`, incoming
attachments stay `remote` and nothing is queued (existing hosts compile and
behave as before).

### Public API (`engine.media`: `MediaService`, `engine.transfers`: `TransfersService`)

| Call | What it does |
|---|---|
| `media.sendMedia(chatId, [MediaInput…], caption:, replyTo:, viewOnce:)` | 1-30 items (image, video, document, voice note with `waveform`, video note, gif; an "audio file" is a `document` with an audio mime). Returns the `pending` row at once |
| `media.forward(messageRowid, toChatId)` | reuses the uploaded object (same id and key, **no upload**) while the original is younger than `forwardReuseWindow` (20 days; the server keeps objects 30), else uploads again from the local copy; not for view-once |
| `media.watchMessage(rowid)` / `watchAttachment(id)` / `viewsOf(rowid)` | `AttachmentTransferView`: `phase` (`notDownloaded, queued, active, ready, failed`), `direction`, `bytesDone/bytesTotal/fraction` (ciphertext bytes), `failure` (`TransferFailure`), `lastError` while a retry waits, `localPath`, `thumbnailPath` |
| `media.retry(messageRowid)` / `retryAttachment(id)` | failed uploads again (and the held send), or the send itself, or failed downloads; `ChatsService.retrySend` delegates here for media messages |
| `media.cancel(attachmentId)` / `cancelSend(messageRowid)` | a download goes back to `notDownloaded`; cancelling an upload cancels the unsent message (rows, files, the queued send, the part-uploaded server objects) |
| `media.downloadNow(attachmentId)` | download on demand |
| `media.openLocalPath(id)` / `thumbnailPath(id)` | the file's `BlobStore` path, or null when it is not on this device |
| `media.consumeViewOnce(messageRowid)` | after the viewer closed: deletes files, keys and the pointers (`payload`); the sender's side does this by itself once the `viewed` receipt arrives |
| `media.storageUsage()` | `MediaStorageUsage`: downloaded bytes split into photos and videos (images, videos, video notes, GIFs), voice notes, and files (documents and kinds from a newer client), summed over attachments with a local copy; `totalBytes` adds the three |
| `media.biggestChats({limit = 5})` | `ChatStorageUsage` (conversation id, photos/videos bytes, files bytes) for chats with downloaded media, biggest first, ties by conversation id; voice notes are left out because a free-up does not offer them |
| `media.freeChatSpace(conversationId, FreeKind)` | `FreeKind.photosVideos` or `.documents`: deletes those `ready` downloads' files and thumbnails, clears their local paths and sets their attachments `remote`; messages, keys and pointers stay. Returns the bytes actually freed. Downloads again while the server keeps the object (30 days). Throws `StateError` without a `BlobStore` |
| `transfers.watchQueue()` / `retryFailed()` / `drain()` / `registerStandalone(purpose, handler)` | the queue as a whole; `drain()` runs everything due (headless hosts, tests) |
| `engine.drainTransfers()` | the same, from the engine |

Settings (`MediaSettings`, typed through `engine.settings`): the largest size
fetched automatically per kind, in bytes (`0` = only on request, `-1` =
always): images and gifs 10 MiB, voice notes 10 MiB, videos 0, documents 0.
Thumbnails are always fetched (a few KiB), except for view-once messages. The
engine does not know Wi-Fi from mobile data; the app changes these settings
when that changes.

### Sending

A send is one transaction: the message row (`pending`), one `attachments` row
per item (`uploading`, with its own random key and the local copy), one upload
job per item and one **held** outbox op (`OutboxDao.enqueueHeld`: pending,
due in year 9999, placeholder payload) that keeps the message's place in the
chat's order. Nothing sent later in that chat overtakes it
(`claimDueOrdered` sees a queued earlier op), and messages sent before it are
not held by it. The upload worker, per item:

1. uploads the thumbnail (its own small object and key; the pointer is stored
   on the attachment before the main upload starts);
2. **encrypts the file once** into a staging file (`HXS2` STREAM, 64 KiB
   chunks), so every resume sends the same bytes and the size for
   `POST /v1/media` is exact;
3. `POST /v1/media`; then chunks with `Upload-Offset` (after a failure `HEAD`
   says how far the server got; a 409 names the stored offset and the upload
   continues from it), or one presigned `PUT` of exactly `size` bytes for S3
   (non-resumable: a failure starts a new object; the whole ciphertext is read
   into memory for that request);
4. in **one transaction**: the pointer (object id, digest = SHA-256 of the
   ciphertext) goes on the attachment, the job is done, and, when it was the
   message's last item, the real `MediaBody` is written to the message's
   `payload` and the held op is **released** with the real content.

A terminal failure fails the attachment, the held op and the message and emits
`SendFailedEvent(errorCode)`; `retry` puts only the failed items back.
Nothing half-made is ever sent: a held op's payload does not decode as a
message, so even a mistaken retry ends as `bad_payload`.

### Receiving

`ContentApplier` creates the `attachments` rows (as before) and calls
`InboundMedia.onMessageStored` in the same transaction: within the policy the
file is queued (its thumbnail comes with it), otherwise only a `thumbnail`
job. The download is **ranged `GET`s** into a staging file from the stored
offset; the total length comes from the pointer's `size` and the file header's
chunk size, so nothing the server sends can make it longer than the sender
described (a different `Content-Range` total is `size_mismatch`); then the
**digest of the whole ciphertext is checked first** (`digest_mismatch`), then
the stream is decrypted into a plaintext staging file whose length must equal
`size` (`decrypt_failed`, `size_mismatch`), moved to a random name in the media
area, and the attachment row points at it in the same transaction that
completes the job.

### The worker

`TransferWorker` claims due jobs with a lease (`TransfersDao.claim`, by kind,
so uploads and downloads have separate limits: 2 and 3), renews it while a
job runs, records the offset after every chunk, and wakes on the queue's own
change stream plus a timer for the next retry (and a 1-minute idle poll for
jobs queued from another isolate). A failure that may pass (network, 5xx, 429
with `Retry-After`, 401) reschedules with exponential backoff (`Backoff`, 3 s
doubling to 5 min), **keeps the progress** and gives up only after `maxAge`
(30 days, like the outbox) as `gave_up`; a failure that cannot pass ends the job as `failed`
with a `TransferFailure` code (`quota_exceeded`, `too_large`, `file_missing`,
`digest_mismatch`, `decrypt_failed`, `size_mismatch`, `expired` (404 or 410:
past the server's 30 days), `rejected`, `gave_up`, `unknown`). A worker that
dies leaves a lease that runs out; the next claim resumes at the stored
offset. `stop()` hands running jobs back (pending, no attempt counted).
`registerStandalone` lets other features (group pictures, backup blobs) run
jobs without an attachment under their `purpose`; jobs of a purpose nobody
registered are left alone.

### Files

`BlobStore` (`namedPath`, `newPath`, `length`, `read(start, end)`,
`openWrite(keep:)`, `move`, `copy`, `delete`, `list`, `clear`; paths are
opaque) has two areas: `media` (what the UI opens) and `staging` (encrypted
bytes in transit, named by job id so they are found again after a restart).
The engine **copies** a file the user picked and never touches the original.
`MediaJanitor` keeps one rule, **a file lives as long as something points at
it**: it deletes store files that no attachment row and no live job refers to
(older than `sweepGrace`), so deleting a message, a disappearing timer, a
view-once consume, a cancelled send and a delete that died halfway all end the
same way. It runs when the attachment count drops, on a timer, at start and
from `media.sweep()` / `runMaintenance()`, and first calls
`MediaService.upkeep`: queued sends whose message was deleted are dropped (a
held op would hold the chat for good) and view-once media the recipient has
seen goes from the sender's device. `signOut` and revocation call
`BlobStore.clear()` before the database wipe.

### Seams for the other C4 features and the app

- **Groups:** `OutboundMedia._peerOf` is the one place that resolves a chat to
  its audience and `conv` (it throws `UnsupportedError` for a group
  conversation). The group send path supplies the audience there;
  `InboundMedia.onMessageStored(row)` is what a group message handler calls
  after inserting a media message.
- **App:** supply a `BlobStore` over the app's private directory (random
  names; `modifiedAt` must be the write time and `copy` must not keep the
  source's time) and a `MediaProcessor` (dimensions, duration, a thumbnail, a
  blurhash; a voice note's waveform comes with the input). Open files through
  `openLocalPath`; show `watchMessage` in the bubble.
- **Not done:** stickers (`StickerBody` has a `MediaPointer` but no row; the
  bubble is deferred to A2), link-preview images, a server route to extend an
  attachment's 30 days (none exists: an expired object fails as `expired` and
  a forward uploads again), per-network auto-download (the app flips the
  settings), a streaming presigned `PUT` (needs `MediaClient` to take a
  stream).

Tests: `test/transfers/` (unit, over `test/support/fake_media.dart`, an
in-memory media server with offsets, 409s, ranges, redirects, presigned
uploads and injectable faults) and `server/test/client/engine/media_test.dart`
(two engines on the real server).
## Groups (Phase C4-G)

Sender-key groups end to end (CRYPTO_V2.md §7 and §9, REST_V2.md "groups").
Code in `lib/src/groups/`; the public face is `Engine.groups`
(`GroupsService`), and group chats take the same `ChatsService` actions as
direct chats. Supersedes the Groups bullet of "Not here yet".

```
group_ids.dart          GroupIds (conversation id `group:<id>`), GroupLimits, notice kinds
group_keyring.dart      group master keys per epoch + GroupMeta, one `settings` row per entry;
                        sealing and opening the state blob (SealedBlobCipher.groupState)
sender_key_store.dart   SenderKeyStore over `sender_keys`; commits GroupCryptoWrites
group_roster.dart       GroupRosterSync: server roster -> groups / group_members / conversation;
                        stale-digest adoption; forgetting a group; the send roster and digest
group_sender.dart       GroupMessageSender: encrypt once, distribute, digest, stale retry
group_rekey.dart        GroupKeyDistributor: hand out the group key, rotate it (`group_rekey` op)
group_inbound.dart      GroupInbound: group_message, roster_change, sender_key_distribution, group_key
group_notices.dart      local `system` rows for roster changes
group_ops.dart          outbox kinds and payloads (`send_group_content`, `group_rekey`)
group_pipeline.dart     wiring (GroupPipeline implements the worker's GroupOutbox)
group_invite_links.dart `https://<server>/open#HLX-GRP-<b64url token>.<b64url preview key>`
groups_service.dart     GroupsService and its value objects
```

**Where the chat list comes from.** A group chat is a row in `conversations`
(`group:<group id>`: title, avatar, members, summary, unread and mention
counts), so the chat list reads one table (`ChatsService.watchChats`). The
`groups` table's own summary columns (`last_message_*`, `unread_count`,
`mention_count`) stay unused; `groups` holds the title, role, epoch and the
state blob, `group_members` the roster. A chat whose `groups` row is gone is a
group this account left or was removed from: read-only history. `groups.avatar`
and `conversations.avatar` hold the picture's `MediaPointer` JSON until the
transfer queue and the app resolve it.

**State kept in `settings`** (no schema change): one row per entry, so a write
is an upsert or a delete of exactly the entry it is about - `group.key.<id>.<epoch>`
(the group master keys, newest 4 epochs), `group.pending.<id>.<account>` (the
reason a member waits) and `group.explained.<id>.<account>`, and
`group.meta.<id>.{settings,description,home_server,avatar}` (the plain
`GroupSettings` and home server from the roster, the decrypted description
and picture pointer from the state). The whole-document shapes these replaced
(`group.keys.<id>`, `group.pending.<id>`, `group.explained.<id>`,
`group.meta.<id>`) are migrated on first read and dropped.

**Roster.** The server is the authority. `GroupRosterSync.refresh` reads
`GET /v1/groups/{id}` and replaces the roster in one transaction;
`replaceRoster` refuses an epoch older than the stored one (a late answer
cannot put a removed member back), and a refresh keeps each retained member's
cached device list. Member **devices** cannot be read from the group; they
come from the server's `device_list_stale` answer (every member's devices) and
are what the send digest is taken over. A roster change reaches a device as a
`roster_change` envelope: the group is read again, a notice row is written
(`group_created`, `member_added`, `member_removed`, `member_left`,
`role_changed`, `group_renamed`, `join_requested`, `you_were_removed`,
`group_deleted`; ids are the envelope id, so a replay adds nothing), a removed
member's sender keys are dropped, and `GroupMembershipLost` /
`GroupJoinRequested` are emitted. Removal, leave, ban and delete forget the
group (roster, keys, sender keys) and keep the chat. Bans are known only to the
device that made them: the server has no ban list to read.

**Writes that cannot drop each other** (AUD-12e-2). The per-entry rows above
exist because a confirm, an explanation, a roster apply and a rotation all
wrote the same documents. `confirm` read the pending map, a roster apply
inserted a member it held back, and the confirm then wrote the map it had
read: the member was released, permanently - the hold-back only marks accounts
new to the previous roster, so no later refresh re-holds them, and that gate is
the only defence against a server adding someone silently. Two rotations could
likewise lose an epoch key (the state sealed under it unreadable here), and
two metadata writers could restore an old description. Now each marker and
each key is its own row, and the metadata is split so the fields the server
states and the fields the state carries are written by disjoint rows. The
roster apply additionally re-reads the group row *inside* the transaction that
writes it: a state, title or description is only written when it is not older
than the stored one (a `setState` that landed in between wins), and a roster
older than the stored epoch writes nothing. A legacy-document migration that
interleaves with a live write can re-insert an entry it read before the
release landed; that errs toward withholding (the member waits again), never
toward releasing.

**Sending.** `ChatsService` writes the optimistic row and a
`send_group_content` op (`conversation_id = group:<id>`, so the chat's ops stay
in order, back off together and share the single wake-up path). The worker runs
`GroupMessageSender`: roster from the stored copy; one ciphertext through the
sender-key protocol (`SenderKeyGroupProtocol`), which creates or **rotates**
the key (member removed or left, a member's or this account's own device list
changed, 7 days, 10,000 messages; adding a member does not); pairwise
`sender_key_distribution` (own sessions, bundles fetched where there is none) to
the member devices without the key in the same request; the new key state and
the used ratchet states are committed before the request leaves; devices count
as holding the key only after the request succeeded. `device_list_stale` makes
the device adopt the lists (reading the group again when the accounts differ)
and re-plan, so a device added or removed mid-send, or a removal this device has
not heard of, is handled before anything leaves. Each attempt has its own HTTP
idempotency key (the ciphertext differs per attempt; the message id keeps the
delivery idempotent). Typing in a group is an ephemeral group send without
distributions.

**Receiving.** `group_message` envelopes are decrypted under the sending
device's sender key (signature first) and applied by the same `ContentApplier`
as direct chats in one transaction with the new key state. Only content that
came through the group send is accepted (membership and the send permission are
the server's checks); a pairwise group message is dropped, except receipts. The
sender must be in the stored roster (a refresh is tried first for an unknown
sender or group). Group `system` messages are dropped except `timer_changed`
from an admin; notices come from roster envelopes. **Quarantine:** an unreadable
group message becomes a visible placeholder when it is urgent; a missing sender
key or an authentication failure queues a `session_reset` op whatever its
urgency (a `decryption_error` to the sender, CRYPTO_V2.md §13a), and the sender
re-sends that message to the group with its sender key distributed again to the
device that asked (`redistribute`). A bad signature or a replay asks for nothing.

**Message features in groups.** Replies, reactions, edits, deletes, polls,
RSVPs and the disappearing timer go through the group send (not urgent for
actions). Mentions (`mention_count`, `IncomingNotice.mentionsMe`) must name
members. A group admin can delete anyone's message. Receipts go pairwise to
the author only; a group message is `delivered` / `read` / `viewed` when
**every** member that was in the group when it was sent has reported; groups
above `GroupLimits.receiptsMaxMembers` (64) send none.

**Creating a group** chooses the id and the first key on the device, seals the
state under it and stores the key, and only then calls `POST /v1/groups`. The
two kinds of failure are not alike: a refusal is an answer (no group, so the
key is forgotten), while silence is not. A create that committed but whose
answer was lost leaves this device holding the only copy of the key — the
members were never sent it and no other device can seal the state — so the
group is read back by that id and, if the server has it, the call finishes as
though the answer had arrived and the share still runs (AUD-12e-1). Only the
server's "no such group" justifies forgetting the key.

**Who gets the key follows the roster, not the response** (AUD-12e-3).
`addMembers` and `approveJoinRequest` share with the members the refreshed
roster lists as new, not with the accounts the one response happened to name:
an add that committed but whose answer was lost comes back as
`already_member`, and the retry of it names nobody — those are this account's
own adds, so they are explained before the roster is read (an account already
in the local roster is not, which would leave a marker for some later
addition to consume) and the retry shares with them. A member nothing explains
stays in `GroupTrust`'s pending set, which `share` removes from the audience,
so widening it cannot hand a key to someone the user has not confirmed.
`_afterRemoval` does the work that needs no server answer first — the removed
member's sender keys and the rotation duty, keyed by the epoch the removal's
own response named — and reads the roster back last: a device that is offline
after a removal still owes the rotation, and `rekey` re-reads the group when it
runs.

**Group master key (CRYPTO_V2.md §9).** Whoever adds a member sends them a
`group_key` (pairwise); the creator sends it to the first members; for a link
join, where the joiner added themselves, the first admin by account id does.
After a removal the remover (else the first admin, for a leave or a
server-side removal) runs the `group_rekey` op: a new key for the new epoch,
queued to every member, the state re-sealed under it with the optimistic
`expected_version` (the op retries on `version_conflict`, both from the writer
and from the server). The blob stays sealed under
the epoch it was written in, so opening tries the held epochs newest first. A
`group_key` is accepted from a member, never for an epoch the server has not
reached, and never replaces a key that opens the stored state with one that
does not. A newly linked device gets the keys from the account's other devices
(`GroupKeyDistributor.shareAllWithOwnDevices`, on the device-list change) and
reads the group list when sign-in finishes (`GroupsService.refreshAll`).

**Invite links.** `createInviteLink` seals the group's name, description and
picture with a fresh random preview key that only the link carries (in the
fragment); the server keeps the token's hash and the sealed preview.
`previewInvite` and `joinWithLink` take the link; an approval link answers
`JoinStatus.pending` and admins see `GroupJoinRequested`.

**Known limits.** The group state AAD binds the epoch, not the version (CRYPTO_V2.md
§14). A member that is not an admin can hand a new member a wrong key; the name
stays unreadable until an admin's key arrives. If the first admin never comes
online after a leave, nobody rotates the key (a rotation that fails or gives up
is asked again by housekeeping; `GroupsService.rotateKey` still does it by
hand). A device that has no key from a member can read that member's
messages only after the member's next send or a repair. Bans made on other
devices are not known. A create the read-back cannot see is still a dead end:
if the request is in flight when the read-back answers "no such group", the
key is forgotten and the create then commits, leaving a group that exists and
is nameless for everyone (AUD-12e-1 narrows this to that window; closing it
needs the server to be able to hand the state back to a member that can read
it).

## Chat screen reads (Phase A2a)

Additive helpers for the app's chat list and conversation: `chats.watchMessagesFrom`
(a live window from a sort key), `watchReactionsSince`, `watchAttachments`,
`findMessage(conversation, messageId)`, `clearChat` (messages go, the chat
stays) and `presence.watchAllTyping()` (who is typing, in every chat). The db
package gained the matching `MessagesDao.watchReactionsSince` and
`clearConversation`.

## Security review pass (2026-10-05)

What the independent review changed here (CRYPTO_V2.md section 14 has the
reasoning and the open items):

- **Re-send authorisation** (`messaging/apply.dart`, `_mayResend`): a direct
  message is re-sent only to the chat peer (not blocked) or an own device; a
  group message to an own device or a current, not banned, not blocked member
  with `joinedAt <= sentAt`. Others are ignored without an answer.
  Tests: `test/resend_authorisation_test.dart`, `server/test/client/engine/
  security_test.dart`.
- **Decode failures never stall**: any error decoding decrypted content or a
  sealed payload (pairwise or group) commits the session and quarantines as
  `bad_content` at once. `Engine.debugSendRaw` / `debugSendRawGroup` send
  crafted bytes in tests.
- **Hard wipe seam**: `Engine(hardWipe: ...)` (`HardWipe`) runs after
  `signOut` (and a wiping revocation) has deleted every row and vacuumed the
  database. The app closes the database, calls `destroyDatabaseFiles` and
  deletes the keystore key there.
- **Groups**: a stored state is never replaced by an older `stateVersion`
  (`RosterUpdate.stateRolledBack`); the version is in the state blob's AAD.
  Members the server adds that nothing explains are *pending*
  (`GroupTrust`, settings rows `group.pending.<id>.<account>` /
  `group.explained.<id>.<account>`):
  `GroupsService.pendingMembers`, `watchPendingMembers`, `confirmMember`;
  `GroupMemberUnconfirmed` event; `member_unconfirmed` notice (suggested
  text: "X was added by the server roster"; `fields.reason` is `unattributed`
  or `link_join`); no sender key (`GroupSendRoster.withheld`) and no group key
  go to them. `EngineConfig.trustLinkJoins` (default false) accepts members
  who join by themselves through a link.
- **Linking**: `NewDeviceLink.awaitApproval()` returns a `LinkProposal`
  (account id, masked phone, `~name`, key fingerprint) after the approval's
  certificate and link signature check out; `LinkProposal.accept()` registers
  the device, `reject()` keeps nothing. `complete({required confirm})` does
  both. There is no variant without the question.
- **Direct chats**: peers' `system` rows other than `timer_changed` are
  dropped; unknown types named like engine row kinds become `unsupported`
  (`MessageKinds.reserved`).
- **Account deletion**: `Engine.deleteAccount({password, verificationToken,
  phoneNumber})` proves ownership as the server accepts (password auth key,
  else a fresh phone verification token, else this device's signature over
  `deleteAccountSignatureBody(challenge)`), then wipes like `signOut`.
- **Privacy**: `SettingsService.setPrivacy` sends the account's own number
  (`phoneNumber`, else the one it registered with) when
  `discoverableByPhone` goes from off to on; with no number it throws
  `ArgumentError` before sending.
- **Backups**: recovery secrets are at least 20 characters;
  `BackupService.generateRecoverySecret()`. History transfers are off by
  default (`BackupOptions.autoTransferToNewDevices`, `autoAcceptTransfers`):
  the user starts (`sendHistory`) or accepts (`acceptOffer`) them. Gzip
  frames stop inflating at the frame limit. Every event of a history or full
  backup run carries `BackupProgress.total` — the messages a backup writes,
  counted before it starts (`SnapshotExporter.countToExport` hands
  `HistoryStore.backupableCount` the same filter as `included`, so the
  percentage the UI draws is against what the archive really holds), 0 until
  the count is made (Part B E4).
- Downloads pass the pointer's size bound to the API (`maxBytes`), and the
  new `ResponseTooLargeException` / `RangeNotHonoredException` end a transfer
  as a size mismatch.
- A key change also writes the safety-number notice into the group chats of a
  contact known only from groups.
