import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;
import 'generated/schema_v7.dart' as v7;

/// Migration tests against the checked-in schema dumps (plan §6.2: every
/// migration has a drift_dev test from the first release onward).
///
/// When the schema changes: bump `HelixDb.schemaVersion`, add the step to
/// `HelixDb.migration`, run `dart run tool/codegen.dart`, and add a
/// data-integrity test below for the new step (see MODULE.md).
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the current schema version has a dump', () {
    final db = HelixDb.inMemory();
    addTearDown(db.close);
    expect(GeneratedHelper.versions.last, db.schemaVersion);
    expect(
      File(
        'drift_schemas/helix/drift_schema_v${db.schemaVersion}.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('a fresh database matches the latest dump', () async {
    final latest = GeneratedHelper.versions.last;
    final schema = await verifier.schemaAt(latest);
    final db = HelixDb.withExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latest);
  });

  // Every upgrade path between dumped versions, oldest to newest.
  final versions = GeneratedHelper.versions;
  for (final (i, from) in versions.indexed) {
    for (final to in versions.skip(i + 1)) {
      test('migrates from $from to $to', () async {
        final schema = await verifier.schemaAt(from);
        final db = HelixDb.withExecutor(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, to);
      });
    }
  }

  test('2 to 3 keeps every session row and gives it revision 0', () async {
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    await old.customStatement(
      "INSERT INTO sessions (peer_account_id, peer_device_id, slot, state, "
      "created_at, updated_at) VALUES ('bob', 'd1', 0, x'7b7d', 1000, 1000)",
    );
    await old.customStatement(
      "INSERT INTO sessions (peer_account_id, peer_device_id, slot, state, "
      "created_at, updated_at) VALUES ('bob', 'd1', 1, x'7b7d', 1000, 1000)",
    );
    await old.close();

    final db = HelixDb.withExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);

    final rows = await db.cryptoDao.sessionsWith('bob', 'd1');
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.slot), [0, 1]);
    expect(rows.every((r) => r.version == 0), isTrue);
    expect(rows.first.createdAt.millisecondsSinceEpoch, 1000);
    // The revision is usable: the first compare-and-set from revision 0
    // lands, and a second write from the same revision is refused.
    final k = Uint8List.fromList([1, 2, 3]);
    expect(
      await db.cryptoDao.saveSessions(
        'bob',
        'd1',
        [k],
        now: DateTime.utc(2026, 10, 9),
        expectedVersion: 0,
      ),
      isTrue,
    );
    expect(
      await db.cryptoDao.saveSessions(
        'bob',
        'd1',
        [k],
        now: DateTime.utc(2026, 10, 9),
        expectedVersion: 0,
      ),
      isFalse,
    );
  });

  test('3 to 4 keeps every sender key and gives it revision 0', () async {
    final schema = await verifier.schemaAt(3);
    final old = v3.DatabaseAtV3(schema.newConnection());
    for (final (account, dist) in [('me', 'k1'), ('bob', 'k2')]) {
      await old.customStatement(
        'INSERT INTO sender_keys (group_id, account_id, device_id, dist_id, '
        "state, created_at, updated_at) VALUES ('g1', '$account', 'd1', "
        "'$dist', x'7b7d', 1000, 1000)",
      );
    }
    await old.close();

    final db = HelixDb.withExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);

    for (final account in ['me', 'bob']) {
      final rows = await db.cryptoDao.senderKeysOf(
        groupId: 'g1',
        account: account,
        device: 'd1',
      );
      expect(rows.single.version, 0);
      expect(rows.single.createdAt.millisecondsSinceEpoch, 1000);
    }
    // The revision is usable: the first compare-and-set from revision 0
    // lands, and a second write from the same revision is refused.
    SenderKeysCompanion own() => SenderKeysCompanion.insert(
      groupId: 'g1',
      accountId: 'me',
      deviceId: 'd1',
      distId: 'k1',
      state: Uint8List.fromList([1]),
      createdAt: DateTime.utc(2026, 10, 9),
      updatedAt: DateTime.utc(2026, 10, 9),
    );
    expect(
      await db.cryptoDao.saveOwnSenderKey(own(), expectedVersion: 0),
      isTrue,
    );
    expect(
      await db.cryptoDao.saveOwnSenderKey(own(), expectedVersion: 0),
      isFalse,
    );
  });

  test('4 to 5 keeps every job at claim revision 0, makes a purpose unique and '
      'adds the delete tombstones', () async {
    final schema = await verifier.schemaAt(4);
    final old = v4.DatabaseAtV4(schema.newConnection());
    await old.customStatement(
      'INSERT INTO transfer_jobs (kind, purpose, state, next_attempt_at, '
      "created_at) VALUES ('upload', 'group_avatar', 'pending', 1000, 1000)",
    );
    await old.close();

    final db = HelixDb.withExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 5);

    // The job is where it was, and the new column starts where a first claim
    // expects. Nothing reads it until the claim token is wired (S4).
    final job = await db.transfersDao.byPurpose('group_avatar');
    expect(job!.kind, 'upload');
    expect(job.state, TransferState.pending);
    expect(job.version, 0);

    Future<void> standalone(String purpose, int at) => db.customInsert(
      'INSERT INTO transfer_jobs (kind, purpose, state, next_attempt_at, '
      'created_at) VALUES (?, ?, ?, ?, ?)',
      variables: [
        Variable.withString('upload'),
        Variable.withString(purpose),
        Variable.withString('pending'),
        Variable.withInt(at),
        Variable.withInt(at),
      ],
    );
    await standalone('full_backup', 2000);
    // One job per purpose, from the step that adds the index onwards.
    expect(() => standalone('full_backup', 3000), throwsA(anything));

    // The tombstones are new, empty, and keyed by what they name.
    expect(
      await db.customSelect('SELECT * FROM delete_tombstones').get(),
      isEmpty,
    );
    Future<void> tomb(String kind, String target, String author) =>
        db.customInsert(
          'INSERT INTO delete_tombstones (kind, target_id, author_id) '
          'VALUES (?, ?, ?)',
          variables: [
            Variable.withString(kind),
            Variable.withString(target),
            Variable.withString(author),
          ],
        );
    await tomb('message', 'm1', 'bob');
    await tomb('message', 'm1', 'carol');
    await tomb('conversation', 'direct:bob', '');
    expect(
      ((await db.customSelect('SELECT * FROM delete_tombstones').get())
          .map((r) => r.data['target_id'])
          .toList()
        ..sort()),
      ['direct:bob', 'm1', 'm1'],
    );
    // One message of one author is one fact, not two.
    expect(() => tomb('message', 'm1', 'bob'), throwsA(anything));
  });

  test('5 to 6 keeps every message and chat, and none starts starred, pinned or '
      'a favourite', () async {
    final schema = await verifier.schemaAt(5);
    final old = v5.DatabaseAtV5(schema.newConnection());
    await old.customStatement(
      "INSERT INTO conversations (id, kind, created_at) "
      "VALUES ('direct:bob', 'direct', 1000)",
    );
    await old.customStatement(
      'INSERT INTO messages (message_id, conversation_id, sender, outgoing, '
      "sort_key, sent_at, received_at, kind, body, status) VALUES ('m1', "
      "'direct:bob', 'bob', 0, 'k1', 1000, 1000, 'text', 'hello', 'received')",
    );
    await old.close();

    final db = HelixDb.withExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 6);

    final chat = await db.conversationsDao.byId('direct:bob');
    expect(chat, isNotNull);
    expect(chat!.favouriteAt, isNull);
    final message = (await db
        .customSelect(
          'SELECT local_rowid FROM messages WHERE message_id = ?',
          variables: [Variable.withString('m1')],
        )
        .getSingle());
    final row = await db.messagesDao.byRowid(message.read<int>('local_rowid'));
    expect(row!.body, 'hello');
    expect(row.starredAt, isNull);
    expect(row.pinnedAt, isNull);

    // The columns take writes, and the indexes that find them exist.
    await db.customStatement(
      'UPDATE messages SET starred_at = 2000, pinned_at = 3000',
    );
    await db.customStatement('UPDATE conversations SET favourite_at = 4000');
    final starred = await db.messagesDao.byRowid(row.localRowid);
    expect(
      starred!.starredAt,
      DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );
    expect(
      starred.pinnedAt,
      DateTime.fromMillisecondsSinceEpoch(3000, isUtc: true),
    );
    expect(
      (await db.conversationsDao.byId('direct:bob'))!.favouriteAt,
      DateTime.fromMillisecondsSinceEpoch(4000, isUtc: true),
    );
    final indexes =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index'",
                )
                .get())
            .map((r) => r.read<String>('name'));
    expect(indexes, containsAll(['messages_starred', 'messages_pinned']));
  });

  test('6 to 7 keeps every chat and adds empty, working chat lists', () async {
    final schema = await verifier.schemaAt(6);
    final old = v6.DatabaseAtV6(schema.newConnection());
    await old.customStatement(
      "INSERT INTO conversations (id, kind, created_at) "
      "VALUES ('direct:bob', 'direct', 1000)",
    );
    await old.close();

    final db = HelixDb.withExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 7);

    expect(await db.conversationsDao.byId('direct:bob'), isNotNull);
    expect(await db.conversationsDao.lists(), isEmpty);
    await db.conversationsDao.createList('l1', 'Work', DateTime.utc(2026));
    await db.conversationsDao.addToList('l1', 'direct:bob');
    expect(await db.conversationsDao.listMembers(), hasLength(1));
    final indexes =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index'",
                )
                .get())
            .map((r) => r.read<String>('name'));
    expect(indexes, contains('chat_list_members_chat'));
  });

  test('7 to 8 keeps every chat, and none starts locked', () async {
    final schema = await verifier.schemaAt(7);
    final old = v7.DatabaseAtV7(schema.newConnection());
    await old.customStatement(
      "INSERT INTO conversations (id, kind, created_at) "
      "VALUES ('direct:bob', 'direct', 1000)",
    );
    await old.close();

    final db = HelixDb.withExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 8);

    final chat = await db.conversationsDao.byId('direct:bob');
    expect(chat, isNotNull);
    expect(chat!.lockedAt, isNull);
    await db.conversationsDao.setLocked('direct:bob', DateTime.utc(2026));
    expect(
      (await db.conversationsDao.byId('direct:bob'))!.lockedAt,
      DateTime.utc(2026),
    );
  });

  test(
    '1 to 2 keeps every schema-1 row and adds empty, working C4 tables',
    () async {
      final schema = await verifier.schemaAt(1);
      final old = v1.DatabaseAtV1(schema.newConnection());
      await old.customStatement(
        "INSERT INTO people (account_id, helix_name, updated_at) "
        "VALUES ('bob', 'Bob', 1000)",
      );
      await old.customStatement(
        "INSERT INTO conversations (id, kind, created_at) "
        "VALUES ('direct:bob', 'direct', 1000)",
      );
      await old.customStatement(
        "INSERT INTO settings (key, value, updated_at) VALUES ('k', '5', 1000)",
      );
      await old.close();

      final db = HelixDb.withExecutor(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);

      // Nothing from schema 1 moved or was lost.
      expect((await db.peopleDao.byAccount('bob'))?.helixName, 'Bob');
      expect(await db.conversationsDao.byId('direct:bob'), isNotNull);
      expect(await db.settingsDao.get(const Setting<int>('k', 0)), 5);

      // The C4 tables exist, are empty and accept writes (foreign keys and
      // indexes included).
      expect(await db.groupsDao.all(), isEmpty);
      expect(await db.callsDao.recent(), isEmpty);
      expect(await db.transfersDao.pending(), isEmpty);
      await db.groupsDao.upsert(
        GroupsCompanion.insert(
          id: 'g1',
          title: 'Team',
          role: 'owner',
          createdAt: DateTime.utc(2026, 10, 2),
        ),
      );
      expect((await db.groupsDao.byId('g1'))?.title, 'Team');
    },
  );
}
