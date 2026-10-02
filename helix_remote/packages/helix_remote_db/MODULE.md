# helix_remote_db

The Helix Remote v2 local database (ADR-027, plan §6.2): drift over `sqlite3`
with the workspace SQLCipher hook (`hooks.user_defines.sqlite3.source:
sqlcipher`). Pure Dart, so the app, the FCM background isolate and the CLI can
all open it. May depend only on `helix_remote_domain` and
`helix_remote_protocol` (architecture test).

## Opening

- `HelixDb.open(file, key: DatabaseKey)` runs every statement on a drift
  background isolate (`NativeDatabase.createInBackground`). The setup
  callback checks that SQLCipher is loaded, applies the 32-byte key as a raw
  key (`PRAGMA key = "x'…'"`, no passphrase KDF), checks `cipher_status`,
  checks that the file decrypts, then turns on WAL and foreign keys.
- It **fails closed** with `DbEncryptionException`: SQLCipher missing or
  inactive, wrong key, or a plaintext file (never migrated: v2 starts from an
  empty database, plan D2). There is no unencrypted file mode.
- `HelixDb.inMemory({key})` is for tests; `HelixDb.withExecutor` is for the
  schema verifier.
- `DatabaseKey.toString()` is redacted; the key lives in the platform
  keystore and is never logged.

## Schema (version 2)

Times are `INTEGER` epoch milliseconds (`EpochMs`); enums are stored by name.

| Area | Tables |
|---|---|
| Account | `self_account` (one row), `self_devices` (linked-device list) |
| People | `people` (names, phone, profile, pinned AIK, verified, blocked), `person_devices` (DIK, DSK, certificate, trust; also this account's other devices) |
| Chats | `conversations` (with the summary columns `last_message_rowid/sort_key/at/preview`, `unread_count`, `mention_count`, `last_read_sort_key`), `conversation_members` |
| Messages | `messages` (decrypted once: `kind`, `body` text/caption, `payload` JSON for the rest of the content body, reply, status, edit/delete, disappearing, view-once), `message_reactions`, `message_receipts`, `attachments`, `messages_fts` (FTS5, external content, triggers in `fts.drift`) |
| Crypto | `identity` (one row), `sessions` (per device pair, slot 0 active + 5 previous), `prekeys`, `sender_keys` |
| Sync | `inbox_cursor` (one row), `processed_envelopes`, `outbox_ops`, `deferred_actions` (actions waiting up to 7 days for their target) |
| Groups (v2) | `groups` (title, role, roster `epoch`, encrypted state blob, the chat-list summary columns), `group_members` (the server's roster; `devices_json` is the member's device ids as JSON), `group_bans` |
| Calls (v2) | `call_log` (the fact and timings of a call; never SDP or ICE) |
| Transfers (v2) | `transfer_jobs` (durable, resumable attachment queue with a lease and a byte `offset`), `transfer_chunks` (device-to-device history chunks) |
| Settings | `settings` (typed through `Setting<T>`) |

Not here yet, by "tables arrive with the feature" (plan §3.8): `group_settings`
(a group's settings live in the encrypted `groups.state` blob until a feature
needs them queryable). `sender_keys` is here because the crypto store is built
with C2/C3.

Schema 2 (C4) is additive: `from1To2` (in `HelixDb.migration`, over the
generated `stepByStep`) creates the new tables and their indexes from the
frozen version-2 schema. `test/drift/helix/migration_test.dart` checks the
path and that schema-1 rows survive.

## Rules

- **Summary in the same transaction.** Every `MessagesDao` write that can
  change the chat list (insert, edit, delete for everyone, remove, expiry,
  mark read) updates the conversation summary inside its transaction.
  Nothing else writes the summary columns.
- **Keyset paging** on `(conversation_id, sort_key)` (unique index), never
  OFFSET. `sort_key` is `SortKey.of(sent_at, message_id)`: 12 hex digits of
  the author's epoch ms, `:`, the message id (CONTENT_V2.md §1).
- Messages are identified across devices by `(message_id, sender)`.
- Unread means `status = received`; `markReadUpTo` returns the messages it
  read, for receipts.
- Every list in the app is a watch query from here (`watchList`,
  `watchLatest`, `watchFrom`, `watchUnreadTotals`, `SettingsDao.watch`, …).
- Search input is reduced to words (letters, digits, marks), each quoted and
  used as a prefix, so FTS syntax in user input is never interpreted. The
  tokenizer keeps combining marks inside words (Bengali and other Indic
  scripts) and folds case for every script.
- One inbound envelope is one `transaction`: message row, summary, FTS,
  reactions/receipts and `processed_envelopes` together. Drift nests DAO
  transactions as savepoints.
- Only `opening.dart` and `database.dart` import `sqlite3` or
  `drift/native.dart` (architecture test). Callers outside this package
  never import drift; `Value` and the generated row and companion classes
  are exported from `helix_remote_db.dart`.
- `outbox_ops.last_error` holds an error code, never content. Nothing here
  logs.

## Added for the engine (Phase C3b)

No schema change; DAO methods only.

- `HelixDb.wipeAll()`: deletes every row of every table (sign-out and
  revocation); the FTS index follows through its triggers, the file stays
  usable.
- `OutboxDao.claimDueOrdered`: like `claimDue`, but an op is claimed only when
  no earlier op of the same conversation is still queued, so a chat's messages
  leave in order even while one backs off (failed ops do not block).
  `watchQueueMark` changes on every enqueue, retry, reschedule and
  completion, even when the count stays the same (the worker's wake-up).
  `byId`, `forMessage`.
- `MessagesDao.updatePayload` (poll votes, RSVPs) and `nextExpiryAt` (the
  disappearing-message timer).
- `PeopleDao.all` / `watchAll` in display order.
- Several `HelixDb` instances may coexist in one isolate (an engine per
  account in tests and the CLI): `open` and `inMemory` switch off drift's
  multiple-instance warning, because each has its own file or memory database.

## Added for C4 (schema 2)

- `GroupsDao`: `byId`, `all`/`watchAll` (newest activity first, archived
  split), `watch`, `upsert` (pass a full companion), `setArchived`, `setMuted`,
  `saveState`; roster `members`/`watchMembers`/`member`/`selfMembership`/
  `selfRole` (unknown or missing means `member`); `replaceRoster(groupId,
  members, epoch:)` is one transaction, refuses a roster older than the stored
  epoch (returns false) and never moves the epoch back; `saveMemberDevices`,
  `memberDevices`, `devicesByAccount`, `rosterDevices`, `rosterDigest` (the
  protocol `membersDigest` over the stored ids); `bans`, `isBanned`, `addBan`,
  `removeBan`; `forget`. `decodeDeviceIds` reads a stored list and answers
  empty for anything unreadable: a corrupt row must never widen an audience.
- `CallsDao`: `start`, `answered`, `end`, `byId`, `recent`/`watchRecent`,
  `watchWithPeer`, `unfinished`, `forget`; `durationSeconds` is measured from
  the answer, and `wasMissed` is true only for an unanswered incoming call.
- `TransfersDao`: `enqueueUpload`, `enqueueDownload` (one job per attachment;
  asking again returns the same job and leaves an in-flight one in flight),
  `enqueueStandalone` (one per `purpose`), `byId`/`byAttachment`/`byPurpose`,
  `pending`/`watchPending`, `due`, `claim(now, lease:)` (oldest due job under a
  lease; an expired lease is claimable again and keeps its `offset`),
  `setProgress` (null keeps the stored value), `markDone`, `fail` (linear
  backoff, gives up after `maxAttempts`, error code only), `remove` (also
  deletes the file). Chunks: `addChunk` (idempotent per sequence), `chunks`,
  `missingSequences` (null until a chunk fixes the total), `isComplete`,
  `assemble` (null on any gap or on chunks that disagree about the total),
  `dropTransfer`.
- `wipeAll` covers the new tables.

## Added for C4-M (media transfers)

No schema change; DAO methods only.

- `OutboxDao`: `enqueueHeld` (an op that keeps its place in its chat but is
  due in year 9999), `hold`, `release` (real payload, due now; false if not
  held), `heldOps`, `isHeld`. A held op blocks later ops of its chat in
  `claimDueOrdered` like any queued op.
- `TransfersDao`: `claim(kinds:)`, `renewLease`, `release` (hand a leased job
  back without counting an attempt), `reschedule` (retry later, progress kept,
  never gives up), `resetProgress`, `enqueueThumbnail` (never replaces a
  download job), `live`/`watchLive` (everything but done).
- `MessagesDao`: `attachmentById`, `setAttachmentPointer`,
  `setAttachmentThumbnail`, `removeAttachments`, `attachmentPaths` (every local
  file the rows name), `watchAttachmentCount`, `viewOnceWithMediaToConsume`
  (opened incoming, viewed outgoing).

## Regenerating

Generated code is committed: the `*.g.dart` parts, the schema dumps in
`drift_schemas/helix/`, and the schema helpers in
`test/drift/helix/generated/`.

```
cd packages/helix_remote_db
dart run tool/codegen.dart           # build_runner, make-migrations, schema helpers, format
dart run tool/codegen.dart --check   # the same, failing if anything changed
```

CI (`verify-linux`) and `scripts/verify.*` run the check; the governance
check asserts that CI does. It works from a clean checkout: `codegen.dart`
deletes the generated parts first and `build_runner` recreates them; there is
no placeholder step. `.gitattributes` keeps every file LF so the byte
comparison is stable on Windows.

If `build_runner` ends with an empty `E source_gen:combining_builder on
<file>:` error, `<file>` has a **syntax error** (for example `await` in a
function that is not `async`). drift_dev's own analysis tolerates it, and the
combining builder, which parses the library to stitch its `.g.dart` part in,
fails without a message. Fix the parse error (`dart analyze` shows it among the
noise from the missing parts), then run the tool again.

## Changing the schema

1. Change the tables, bump `HelixDb.schemaVersion`, and add the step to
   `HelixDb.migration` (`stepByStep` from the generated
   `database.steps.dart`; create each new table and index from the `schema`
   argument, parents first).
2. Run `dart run tool/codegen.dart`. It dumps the new version next to the
   old ones (never edit or delete a dump) and regenerates the helpers.
3. `test/drift/helix/migration_test.dart` already checks every path between
   dumped versions; add a data-integrity test for the new step there.
4. Update this file.
