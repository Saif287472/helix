import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
// Only for DriftRemoteException, which wraps errors from the database
// isolate (here: a failed key check in the setup callback).
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:meta/meta.dart';
import 'package:helix_remote_db/src/daos/account_dao.dart';
import 'package:helix_remote_db/src/daos/calls_dao.dart';
import 'package:helix_remote_db/src/daos/conversations_dao.dart';
import 'package:helix_remote_db/src/daos/crypto_dao.dart';
import 'package:helix_remote_db/src/daos/groups_dao.dart';
import 'package:helix_remote_db/src/daos/inbox_dao.dart';
import 'package:helix_remote_db/src/daos/messages_dao.dart';
import 'package:helix_remote_db/src/daos/outbox_dao.dart';
import 'package:helix_remote_db/src/daos/people_dao.dart';
import 'package:helix_remote_db/src/daos/settings_dao.dart';
import 'package:helix_remote_db/src/daos/transfers_dao.dart';
import 'package:helix_remote_db/src/database.steps.dart';
import 'package:helix_remote_db/src/opening.dart';
import 'package:helix_remote_db/src/tables/account.dart';
import 'package:helix_remote_db/src/tables/conversations.dart';
import 'package:helix_remote_db/src/tables/crypto.dart';
import 'package:helix_remote_db/src/tables/groups.dart';
import 'package:helix_remote_db/src/tables/messages.dart';
import 'package:helix_remote_db/src/tables/people.dart';
import 'package:helix_remote_db/src/tables/settings.dart';
import 'package:helix_remote_db/src/tables/sync.dart';
import 'package:helix_remote_db/src/tables/transfers.dart';
import 'package:helix_remote_db/src/values.dart';

part 'database.g.dart';

/// The Helix Remote v2 local database (plan §6.2).
///
/// Open it with [HelixDb.open]: SQLCipher, WAL, and every statement on a
/// background isolate. Callers use the DAOs ([messagesDao],
/// [conversationsDao], …);
/// one inbound envelope's effects go in one [transaction].
@DriftDatabase(
  tables: [
    SelfAccount,
    SelfDevices,
    People,
    PersonDevices,
    Conversations,
    ConversationMembers,
    Messages,
    MessageReactions,
    MessageReceipts,
    Attachments,
    Identity,
    Sessions,
    Prekeys,
    SenderKeys,
    InboxCursor,
    ProcessedEnvelopes,
    OutboxOps,
    DeferredActions,
    TransferJobs,
    TransferChunks,
    Groups,
    GroupMembers,
    GroupBans,
    CallLog,
    Settings,
  ],
  include: {'fts.drift'},
  daos: [
    AccountDao,
    PeopleDao,
    ConversationsDao,
    MessagesDao,
    CryptoDao,
    InboxDao,
    OutboxDao,
    SettingsDao,
    GroupsDao,
    TransfersDao,
    CallsDao,
  ],
)
class HelixDb extends _$HelixDb {
  /// Over any drift executor; [open] and [inMemory] are the usual ways in.
  /// Tests use it with the schema verifier's connections.
  HelixDb.withExecutor(super.executor);

  /// The schema version. Bump it with a migration step, run
  /// `dart run drift_dev make-migrations`, and fill in the generated test
  /// (MODULE.md, "Changing the schema").
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: stepByStep(
      // Schema 2 (C4) added the group, call-log and transfer tables. It is
      // additive: nothing in schema 1 changes shape, so a device that was on
      // 1 keeps every row it had and finds the new tables empty. Entities are
      // created one by one from the frozen version-2 schema (not from the live
      // table classes, which a later version may change), parents first.
      from1To2: (m, schema) async {
        await m.create(schema.transferJobs);
        await m.create(schema.transferJobsState);
        await m.create(schema.transferChunks);
        await m.create(schema.transferChunksTransfer);
        await m.create(schema.groups);
        await m.create(schema.groupsList);
        await m.create(schema.groupMembers);
        await m.create(schema.groupMembersAccount);
        await m.create(schema.groupBans);
        await m.create(schema.callLog);
        await m.create(schema.callLogAt);
      },
    ),
  );

  /// Deletes every row of every table (sign-out and revocation wipe): keys,
  /// sessions, messages, people, settings, the outbox. The FTS index is
  /// emptied by the triggers on `messages`. The file stays, encrypted and
  /// empty, so the engine can be set up again on the same database.
  ///
  /// Deleting rows alone leaves their bytes in free pages and in the
  /// write-ahead log, so afterwards the log is checkpointed and truncated and
  /// the file is `VACUUM`ed (rebuilt without free pages), then checkpointed
  /// again: key material is not recoverable from the file (with
  /// `secure_delete`, set on every connection, as the second line). The
  /// complete answer is [destroyDatabaseFiles] plus destroying the
  /// keystore's [DatabaseKey]; see "Wiping" in `MODULE.md`.
  Future<void> wipeAll() async {
    await _deleteEverything();
    await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await customStatement('VACUUM');
    await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  Future<void> _deleteEverything() => transaction(() async {
    for (final table in <TableInfo<Table, Object?>>[
      outboxOps,
      deferredActions,
      transferChunks,
      transferJobs,
      processedEnvelopes,
      inboxCursor,
      messageReactions,
      messageReceipts,
      attachments,
      messages,
      conversationMembers,
      conversations,
      personDevices,
      people,
      senderKeys,
      prekeys,
      sessions,
      identity,
      selfDevices,
      selfAccount,
      groupBans,
      groupMembers,
      groups,
      callLog,
      settings,
    ]) {
      await delete(table).go();
    }
  });

  /// Opens (or creates) the encrypted database at [file].
  ///
  /// With [inBackground] (the default) every statement runs on a drift
  /// isolate, never on the caller's. Fails with [DbEncryptionException] if
  /// SQLCipher is not active, the key is wrong, or the file is plaintext; the
  /// database is never opened unencrypted.
  static Future<HelixDb> open(
    File file, {
    required DatabaseKey key,
    bool inBackground = true,
  }) async {
    _allowSeveralDatabases();
    refusePlaintextFile(file);
    final keyHex = keyHexOf(key);
    final executor = inBackground
        ? NativeDatabase.createInBackground(
            file,
            setup: (db) => setUpEncryptedConnection(db, keyHex, wal: true),
          )
        : NativeDatabase(
            file,
            setup: (db) => setUpEncryptedConnection(db, keyHex, wal: true),
          );
    final db = HelixDb.withExecutor(executor);
    try {
      await db.customSelect('SELECT 1').get();
    } on Object catch (error) {
      await db.close();
      final cause = error is DriftRemoteException ? error.remoteCause : error;
      if (cause is DbEncryptionException) throw cause;
      rethrow;
    }
    return db;
  }

  /// An *unencrypted* database file, for tests that read the file's bytes to
  /// prove that deleted values are overwritten. Never used by the app.
  @visibleForTesting
  static Future<HelixDb> openPlainFileForTesting(File file) async {
    _allowSeveralDatabases();
    final db = HelixDb.withExecutor(
      NativeDatabase(file, setup: setUpPlainFileConnection),
    );
    await db.customSelect('SELECT 1').get();
    return db;
  }

  /// An in-memory database for tests. Encrypted when [key] is given; nothing
  /// reaches disk either way.
  factory HelixDb.inMemory({DatabaseKey? key}) {
    _allowSeveralDatabases();
    final keyHex = key == null ? null : keyHexOf(key);
    return HelixDb.withExecutor(
      NativeDatabase.memory(
        setup: keyHex == null
            ? setUpPlainMemoryConnection
            : (db) => setUpEncryptedConnection(db, keyHex, wal: false),
      ),
    );
  }

  /// drift warns when a database class is instantiated twice in one isolate,
  /// because two instances over the same executor would race. Every
  /// [HelixDb] here has its own file or memory database (an engine per
  /// account in tests and in the CLI), so the warning is a false alarm.
  static void _allowSeveralDatabases() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }
}
