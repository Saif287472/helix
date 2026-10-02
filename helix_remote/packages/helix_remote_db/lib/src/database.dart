import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
// Only for DriftRemoteException, which wraps errors from the database
// isolate (here: a failed key check in the setup callback).
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:helix_remote_db/src/daos/account_dao.dart';
import 'package:helix_remote_db/src/daos/conversations_dao.dart';
import 'package:helix_remote_db/src/daos/crypto_dao.dart';
import 'package:helix_remote_db/src/daos/inbox_dao.dart';
import 'package:helix_remote_db/src/daos/messages_dao.dart';
import 'package:helix_remote_db/src/daos/outbox_dao.dart';
import 'package:helix_remote_db/src/daos/people_dao.dart';
import 'package:helix_remote_db/src/daos/settings_dao.dart';
import 'package:helix_remote_db/src/opening.dart';
import 'package:helix_remote_db/src/tables/account.dart';
import 'package:helix_remote_db/src/tables/conversations.dart';
import 'package:helix_remote_db/src/tables/crypto.dart';
import 'package:helix_remote_db/src/tables/messages.dart';
import 'package:helix_remote_db/src/tables/people.dart';
import 'package:helix_remote_db/src/tables/settings.dart';
import 'package:helix_remote_db/src/tables/sync.dart';
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      throw UnsupportedError('no migration from schema $from to $to');
    },
  );

  /// Deletes every row of every table (sign-out and revocation wipe): keys,
  /// sessions, messages, people, settings, the outbox. The FTS index is
  /// emptied by the triggers on `messages`. The file stays, encrypted and
  /// empty, so the engine can be set up again on the same database.
  Future<void> wipeAll() => transaction(() async {
    for (final table in <TableInfo<Table, Object?>>[
      outboxOps,
      deferredActions,
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
