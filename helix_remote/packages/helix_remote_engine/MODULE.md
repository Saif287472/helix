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
| `chats` | chat list, messages, search (watch queries); send text/reply/mentions and the blob-free content types; react, edit, delete, vote, RSVP; mark read (read receipts), view-once, disappearing timer, pin/mute/archive/draft, retry a failed send; the same for group chats (`group:<id>`) |
| `groups` | create, rename, description, picture, settings, add/remove members, roles, leave, ban/unban, delete, invite links (create, preview, join, revoke), join requests, refresh; see "Groups (Phase C4-G)" |
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

## Groups (Phase C4-G)

Sender-key groups end to end (CRYPTO_V2.md §7 and §9, REST_V2.md "groups").
Code in `lib/src/groups/`; the public face is `Engine.groups`
(`GroupsService`), and group chats take the same `ChatsService` actions as
direct chats. Supersedes the Groups bullet of "Not here yet".

```
group_ids.dart          GroupIds (conversation id `group:<id>`), GroupLimits, notice kinds
group_keyring.dart      group master keys per epoch + GroupMeta (settings, description) in `settings`;
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

**State kept in `settings`** (no schema change): `group.keys.<id>` (epoch to
group master key, newest 4 epochs) and `group.meta.<id>` (the plain
`GroupSettings`, the decrypted description and picture pointer, home server).

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
group message becomes a visible placeholder; a missing sender key or an
authentication failure also queues a `session_reset` op (a `decryption_error`
to the sender, CRYPTO_V2.md §13a), and the sender re-sends that message to the
group with its sender key distributed again to the device that asked
(`redistribute`). A bad signature or a replay asks for nothing.

**Message features in groups.** Replies, reactions, edits, deletes, polls,
RSVPs and the disappearing timer go through the group send (not urgent for
actions). Mentions (`mention_count`, `IncomingNotice.mentionsMe`) must name
members. A group admin can delete anyone's message. Receipts go pairwise to
the author only; a group message is `delivered` / `read` / `viewed` when
**every** member that was in the group when it was sent has reported; groups
above `GroupLimits.receiptsMaxMembers` (64) send none.

**Group master key (CRYPTO_V2.md §9).** Whoever adds a member sends them a
`group_key` (pairwise); the creator sends it to the first members; for a link
join, where the joiner added themselves, the first admin by account id does.
After a removal the remover (else the first admin, for a leave or a
server-side removal) runs the `group_rekey` op: a new key for the new epoch,
queued to every member, the state re-sealed under it with the optimistic
`expected_version` (retried on `version_conflict`). The blob stays sealed under
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
online after a leave, nobody rotates the key (`GroupsService.rotateKey` does it
by hand). A device that has no key from a member can read that member's
messages only after the member's next send or a repair. Bans made on other
devices are not known.
