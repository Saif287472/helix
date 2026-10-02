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
(3 days) as `gave_up`; a failure that cannot pass ends the job as `failed`
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
