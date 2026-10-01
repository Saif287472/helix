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

## Schema (version 1)

Times are `INTEGER` epoch milliseconds (`EpochMs`); enums are stored by name.

| Area | Tables |
|---|---|
| Account | `self_account` (one row), `self_devices` (linked-device list) |
| People | `people` (names, phone, profile, pinned AIK, verified, blocked), `person_devices` (DIK, DSK, certificate, trust; also this account's other devices) |
| Chats | `conversations` (with the summary columns `last_message_rowid/sort_key/at/preview`, `unread_count`, `mention_count`, `last_read_sort_key`), `conversation_members` |
| Messages | `messages` (decrypted once: `kind`, `body` text/caption, `payload` JSON for the rest of the content body, reply, status, edit/delete, disappearing, view-once), `message_reactions`, `message_receipts`, `attachments`, `messages_fts` (FTS5, external content, triggers in `fts.drift`) |
| Crypto | `identity` (one row), `sessions` (per device pair, slot 0 active + 5 previous), `prekeys`, `sender_keys` |
| Sync | `inbox_cursor` (one row), `processed_envelopes`, `outbox_ops`, `deferred_actions` (actions waiting up to 7 days for their target) |
| Settings | `settings` (typed through `Setting<T>`) |

Not here yet, by "tables arrive with the feature" (plan §3.8): `groups`,
`group_members`, `group_settings`, `call_log` and `transfer_jobs` land in C4.
`sender_keys` is here because the crypto store is built with C2/C3.

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
check asserts that CI does.

## Changing the schema

1. Change the tables, bump `HelixDb.schemaVersion`, and add the step to
   `HelixDb.migration` (`stepByStep` from the generated
   `database.steps.dart` once it exists).
2. Run `dart run tool/codegen.dart`. It dumps the new version next to the
   old ones (never edit or delete a dump) and regenerates the helpers.
3. `test/drift/helix/migration_test.dart` already checks every path between
   dumped versions; add a data-integrity test for the new step there.
4. Update this file and AGENTS.md's schema version.
