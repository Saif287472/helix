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
| `chats` | chat list, messages, search (watch queries); send text/reply/mentions and the blob-free content types; react, edit, delete, vote, RSVP; mark read (read receipts), view-once, disappearing timer, pin/mute/archive/draft, retry a failed send |
| `people` | phone-book discovery by salted hash (`PhoneBook` is injected), lookup by number or `~name`, profiles (encrypted), nickname (synced to own devices and written to the phone book), block/unblock, safety number and verified flag, display-name order helper `PersonNaming` |
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
  util/                             KeyedLock, Backoff, IdFactory/RandomAdapter, masking
```

## Inbound pipeline (plan §6.3)

`InboundRunner` feeds `InboundProcessor` from the WebSocket (`startRealtime`)
or the REST mailbox (`fetchOnce`); both share one serial queue and
`processed_envelopes` de-duplicates them.

1. **Dedupe:** `(envelope id, sender device)` in `processed_envelopes`; a
   replay is acked again and changes nothing.
2. **Decrypt** under the sender device's lock (`PairwiseCrypto.runLocked`).
   The crypto layer returns the new session records; it never writes.
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

Rules:

- **Quarantine, never block.** An envelope that cannot be read becomes a
  visible `undecryptable` row (`payload`: `{code, waiting, device}`) and the
  stream goes on. When it is a user-visible message (the server's `urgent`
  flag; receipts, reactions, edits and other control content go out
  non-urgent and have nothing to re-send) and the failure is a lost or
  diverged session (no session, unknown prekey, used key, or an
  authentication failure, which after a restore looks the same as tampering)
  a `session_reset` op is queued (CRYPTO_V2.md §13a): start a fresh session
  with that device (at most one per `resetCooldown`, however many messages
  failed) and send `decryption_error` (the failed envelope id) to the sender's
  account; the sender re-sends the message (under 24 h) over the new session
  and the real message replaces the placeholder. Identity failures
  (`untrusted_identity`) and unparseable payloads do not ask for a reset. A
  hostile server can use authentication failures to make a client start
  cooldown-limited sessions and request re-sends; it could drop the messages
  anyway.
- **Only a `TransientEngineException`** (no network while looking up an
  unknown sender's keys) holds the stream back, because acks are cumulative:
  the runner retries that envelope with backoff. Any other unexpected failure
  retries three times and then quarantines (`internal_error`).
- **Authorship is the server-attested sender.** Edits and deletes apply only
  when the sender is the target's author, within 15 minutes / 2 days of the
  target; the newest edit and the newest reaction win; a message cannot claim
  a time more than a minute in the future; content addressed to someone else
  (`conv.to` is not this account) is dropped.
- **Actions wait for their message** up to 7 days (`deferred_actions`).
- **Ephemeral envelopes** (typing) are decrypted (the ratchet moves and is
  committed), reported through `TypingEvent`, and never stored or acked.
- **Blocked senders** are decrypted and ignored (the ratchet must move).
- Group content (`group_message`, sender keys, group `conv`) and call
  signals are acked and ignored in C3b.

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
   backoff; an op older than `outboxMaxAge` or refused for good
   (`forbidden`, `untrusted_peer`, `not_found`, …) fails, the message shows as
   failed and `SendFailedEvent` is emitted; `device_revoked` starts the
   revocation path; a dead session pauses the worker.

Every visible send, action, edit, delete and `read` receipt also goes to this
account's own other devices (they get the same content; `conv.to` names the
peer). `delivered` receipts go to the author only. Retried sends re-encrypt
(a retry after a lost response consumes one more message key, which the
receiver skips).

## Trust and keys

- **AIK pinning:** the first AIK seen for an account is pinned in `people`.
  A bundle under another AIK is a **key change**: sessions with all of the
  account's devices are dropped (retired base keys kept), its devices are
  marked `stale`, the verified flag resets, the new AIK is pinned, a local
  `system` row `safety_number_changed` is added to the chat and
  `KeyChangedEvent` is emitted. This account's own AIK never changes: a
  bundle claiming otherwise is refused (`UntrustedPeerException`).
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
  previous sessions).
- Settings: `EngineSettings` (user-facing: read receipts, typing, default
  timer) and `EngineState` (session JSON, prekey counters, timestamps).
- Nothing in the engine logs. `maskPhone` and `shortId` are for hosts that
  print.

## Testing

- `test/support/fake_server.dart` is an in-memory Helix server behind an
  `http.Client` (identity, keys, messaging, links, device-key sign-in, people
  discovery and profiles) with the real server's device-list rule, per-device
  mailboxes and fault injection (`failNext`, `dropNext`, `loseResponseNext`);
  `peers.dart` builds engines on in-memory encrypted databases with a
  ticking test clock. These cover the pipelines without Postgres.
- End-to-end tests against the real in-process server are in
  `server/test/client/engine/` (the engine may not depend on the server): two
  engines over live sockets, a linked second device, offline catch-up,
  revocation, a stale device list, key change, §13a recovery, prekey top-up,
  signed-prekey rotation, a concurrency stress run, and the CLI.

## Not here yet (C4 and later) and open items

- **Groups** (sender keys, group state, roster envelopes), **calls**
  (signaling state), **attachment transfers** (media rows are stored with
  `transfer: remote`; sending media needs the transfer queue), **history
  backup and device-to-device transfer**, **live-location updates**
  (only the `start` content becomes a row).
- **Recovery codes:** the API exists, but `RecoveryLookupResponse` carries no
  account id and a device certificate must name the account, so the client
  cannot build the redeem request without a verified phone. Needs an additive
  `account_id` on the lookup response (spec change) or the A1 flow through
  `PhoneVerifyResponse.accountId`.
- **Profile key after password sign-in:** a device that signs in with only a
  password has no profile key (it travels by link provisioning or backup); it
  makes a new one on the first `setOwnProfile`.
- **Several isolates:** drift watch streams do not cross database instances.
  An FCM isolate writing the same file is invisible to the UI isolate's
  streams until they re-query; A1 decides between a shared drift isolate and
  a refresh on resume.
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
  is dropped without a ring or a row; the server drops a call from someone the
  callee blocked silently, so that caller sees an ordinary unanswered call.
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
