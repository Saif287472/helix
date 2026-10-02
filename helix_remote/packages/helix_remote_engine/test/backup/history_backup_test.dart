import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/backup/archive.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/peers.dart' show fastConfig;
import 'support.dart';

/// The automatic history backup (CRYPTO_V2.md §13): what it holds, restore as
/// a merge, versions, size, and every way a bad backup is refused.
void main() {
  late BackupWorld world;
  late BackupPeer alice;
  const bobId = 'bbbbbbbb-0000-4000-8000-000000000001';

  setUp(() async {
    world = BackupWorld();
    alice = await world.register('alice', phone: '+8801711000001');
  });
  tearDown(() => world.dispose());

  Future<Uint8List> aikSeed(BackupPeer peer) async =>
      (await peer.db.cryptoDao.identityKeys())!.aikPrivate;

  /// The archive inside the stored backup, opened with [peer]'s account key.
  Future<List<JsonReader>> openStored(BackupPeer peer) async {
    final stored = world.remote.stored!;
    final plain = await HistoryBackupCrypto.open(
      identityKeySeed: await aikSeed(peer),
      accountId: peer.account,
      version: stored.version,
      data: stored.data,
    );
    return [
      for (final frame in ArchiveReader.frames(plain, gzip: gzip))
        ...ArchiveReader.records(frame),
    ];
  }

  Future<BackupException> failureOf(Future<Object?> action) async {
    try {
      await action;
    } on BackupException catch (e) {
      return e;
    }
    fail('expected a BackupException');
  }

  group('what a backup holds', () {
    test('history, and never a key', () async {
      await addHistory(alice, bobId, 6);
      final base = await alice.db.messagesDao.pageOlder(
        directConversationId(bobId),
      );
      await alice.db.messagesDao.setReaction(
        base.messages.first.localRowid,
        reactor: bobId,
        emoji: 'A',
        at: DateTime.utc(2026, 3, 2),
      );
      await alice.db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: '0192a4f0-0000-7000-8000-0000000000aa',
          conversationId: directConversationId(bobId),
          sender: bobId,
          outgoing: false,
          sortKey: SortKey.of(
            DateTime.utc(2026, 3, 5),
            '0192a4f0-0000-7000-8000-0000000000aa',
          ),
          sentAt: DateTime.utc(2026, 3, 5),
          receivedAt: DateTime.utc(2026, 3, 5),
          kind: 'media',
          status: MessageStatus.received,
          body: const Value('a photo'),
        ),
        media: [
          AttachmentsCompanion.insert(
            messageRowid: 0,
            position: 0,
            kind: 'image',
            mediaId: '11111111-1111-4111-8111-111111111111',
            mediaKey: Uint8List(32)..fillRange(0, 32, 7),
            digest: Uint8List(32)..fillRange(0, 32, 9),
            mime: 'image/jpeg',
            size: 1234,
            transfer: AttachmentTransfer.ready,
            localPath: const Value('/private/photo.jpg'),
          ),
        ],
      );

      final result = await alice.backup.backUpNow();
      expect(result.version, 1);
      expect(result.messages, 7);
      expect(result.truncated, isFalse);
      expect(world.remote.stored!.version, 1);

      final records = await openStored(alice);
      expect(records.first.string('t'), 'header');
      expect(records.first.string('kind'), 'history');
      expect(records.first.string('account'), alice.account);
      final types = [for (final r in records) r.string('t')];
      expect(types, isNot(contains('secrets')));
      expect(types.where((t) => t == 'msg'), hasLength(7));
      expect(types, contains('conv'));

      // The attachment is a reference with its key, never bytes or a path.
      final photo = records.firstWhere((r) => r.optString('kind') == 'media');
      final item = photo.objects('media', (j) => j).single;
      expect(item.string('id'), '11111111-1111-4111-8111-111111111111');
      expect(item.has('key'), isTrue);
      final text = records.map((r) => jsonEncode(r.json)).join('\n');
      expect(text, isNot(contains('/private/photo.jpg')));

      // None of this device's or this account's private keys, nor the
      // profile key, is anywhere in the archive.
      final identity = (await alice.db.cryptoDao.identityKeys())!;
      final profileKey = (await alice.db.accountDao.current())!.profileKey!;
      for (final secret in [
        identity.aikPrivate,
        identity.dikPrivate,
        identity.dskPrivate,
        profileKey,
      ]) {
        expect(text, isNot(contains(encodeBytes(secret))));
      }
      expect(text, isNot(contains('pkey')));
    });

    test('what must not come back stays out', () async {
      await addHistory(alice, bobId, 4);
      final chat = directConversationId(bobId);
      Future<void> add(
        String id,
        MessageStatus status, {
        String kind = 'text',
        ViewOnceState? viewOnce,
        DateTime? expiresAt,
        bool outgoing = true,
      }) => alice.db.messagesDao
          .insertMessage(
            MessagesCompanion.insert(
              messageId: id,
              conversationId: chat,
              sender: outgoing ? alice.account : bobId,
              outgoing: outgoing,
              sortKey: SortKey.of(DateTime.utc(2026, 4, 1), id),
              sentAt: DateTime.utc(2026, 4, 1),
              receivedAt: DateTime.utc(2026, 4, 1),
              kind: kind,
              status: status,
              body: Value('x $id'),
              viewOnceState: Value(viewOnce),
              expiresAt: Value(expiresAt),
            ),
          )
          .then((_) {});
      await add('a1', MessageStatus.pending);
      await add('a2', MessageStatus.failed);
      await add(
        'a3',
        MessageStatus.received,
        kind: 'undecryptable',
        outgoing: false,
      );
      await add(
        'a4',
        MessageStatus.received,
        viewOnce: ViewOnceState.opened,
        outgoing: false,
      );
      await add('a5', MessageStatus.sent, expiresAt: DateTime.utc(2020, 1, 1));
      await add('a6', MessageStatus.sent);

      await alice.backup.backUpNow();
      final ids = [
        for (final r in await openStored(alice))
          if (r.string('t') == 'msg') r.string('id'),
      ];
      expect(ids, contains('a6'));
      expect(ids, hasLength(5));
      for (final gone in ['a1', 'a2', 'a3', 'a4', 'a5']) {
        expect(ids, isNot(contains(gone)));
      }
    });

    test('with nothing to back up, nothing is uploaded', () async {
      final result = await alice.backup.backUpNow();
      expect(result.skipped, isTrue);
      expect(world.remote.historyPuts, 0);
    });
  });

  group('restore on another device', () {
    test('the same messages, summaries, unread counts and search', () async {
      await addHistory(alice, bobId, 30, prefix: 'hello world');
      const carol = 'cccccccc-0000-4000-8000-000000000002';
      await addHistory(alice, carol, 9, prefix: 'weekend plans');
      await alice.db.conversationsDao.setPinned(
        directConversationId(carol),
        DateTime.utc(2026, 5, 1),
      );
      await alice.db.conversationsDao.setDraft(
        directConversationId(bobId),
        'half a thought',
      );
      await alice.db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: bobId,
          updatedAt: DateTime.utc(2026, 3, 1),
          nickname: const Value('Bobby'),
          phoneNumber: const Value('+8801711000002'),
          identityKey: Value(Uint8List(32)..fillRange(0, 32, 5)),
          identityVerified: const Value(true),
        ),
      );
      await alice.backup.backUpNow();

      final second = await world.link(alice, 'alice2');
      final progress = <RestorePhase>[];
      final sub = second.backup.restoreProgress.listen(
        (p) => progress.add(p.phase),
      );
      final result = await second.backup.restoreHistory();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(result.version, 1);
      expect(result.added, 39);
      expect(result.existing, 0);
      expect(
        progress,
        containsAllInOrder([
          RestorePhase.downloading,
          RestorePhase.decrypting,
          RestorePhase.importing,
          RestorePhase.done,
        ]),
      );
      expect(await historyDigest(second), await historyDigest(alice));

      // The chat list, with its summary columns and pin.
      final chats = await second.db.conversationsDao.watchList().first;
      expect(chats.first.conversation.id, directConversationId(carol));
      final bobChat = await second.db.conversationsDao.byId(
        directConversationId(bobId),
      );
      final aliceBob = await alice.db.conversationsDao.byId(
        directConversationId(bobId),
      );
      expect(bobChat!.unreadCount, aliceBob!.unreadCount);
      expect(bobChat.lastMessagePreview, 'hello world 29');
      expect(bobChat.draft, 'half a thought');
      expect(bobChat.pinnedAt, isNull);

      // Search finds the same hits (the FTS index follows the inserts).
      final hits = await second.engine.chats.search('weekend');
      expect(hits, hasLength(9));
      expect(
        [for (final m in await second.engine.chats.search('hello wor')) m.body],
        unorderedEquals([
          for (final m in await alice.engine.chats.search('hello wor')) m.body,
        ]),
      );

      // The person: pinned identity key and nickname came across.
      final bob = await second.db.peopleDao.byAccount(bobId);
      expect(bob!.nickname, 'Bobby');
      expect(bob.identityVerified, isTrue);
      expect(bob.identityKey, Uint8List(32)..fillRange(0, 32, 5));
    });

    test('restoring twice changes nothing', () async {
      await addHistory(alice, bobId, 12);
      await alice.backup.backUpNow();
      final second = await world.link(alice, 'alice2');
      await second.backup.restoreHistory();
      final before = await historyDigest(second);
      final again = await second.backup.restoreHistory();
      expect(again.added, 0);
      expect(again.existing, 12);
      expect(await historyDigest(second), before);
    });

    test('merges with what the device already has: local wins, edits, '
        'deletes and read positions are taken', () async {
      final rows = await addHistory(
        alice,
        bobId,
        6,
        incoming: MessageStatus.read,
      );
      final chat = directConversationId(bobId);
      // On the backing-up device: message 3 was edited, message 1 deleted
      // for everyone, message 2 reacted to.
      await alice.db.messagesDao.editMessage(
        rows[3].localRowid,
        body: 'edited text',
        editedAt: DateTime.utc(2026, 3, 10),
      );
      await alice.db.messagesDao.deleteForEveryone(
        rows[1].localRowid,
        deletedAt: DateTime.utc(2026, 3, 11),
      );
      await alice.db.messagesDao.setReaction(
        rows[2].localRowid,
        reactor: bobId,
        emoji: 'B',
        at: DateTime.utc(2026, 3, 12),
      );
      await alice.backup.backUpNow();

      // The second device got some of them directly, as received.
      final second = await world.link(alice, 'alice2');
      await second.db.conversationsDao.ensureDirect(
        bobId,
        now: DateTime.utc(2026, 1, 1),
      );
      Future<MessageRow> copy(
        MessageRow m, {
        String? body,
        MessageStatus? status,
      }) => second.db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: m.messageId,
          conversationId: chat,
          sender: m.sender,
          outgoing: m.outgoing,
          sortKey: m.sortKey,
          sentAt: m.sentAt,
          receivedAt: m.receivedAt,
          kind: 'text',
          status:
              status ??
              (m.outgoing ? MessageStatus.sent : MessageStatus.received),
          body: Value(body ?? m.body),
        ),
      );
      final local1 = await copy(rows[1]);
      final local3 = await copy(rows[3]);
      final local5 = await copy(rows[5], body: 'local version');
      final local2 = await copy(rows[2]);
      await second.db.messagesDao.editMessage(
        local5.localRowid,
        body: 'local version',
        editedAt: DateTime.utc(2026, 3, 20),
      );
      await second.db.messagesDao.deleteForEveryone(
        local2.localRowid,
        deletedAt: DateTime.utc(2026, 3, 13),
      );

      final result = await second.backup.restoreHistory();
      expect(result.added, 2);
      expect(result.existing, 4);

      // Deleted in the backup: deleted here too.
      final m1 = await second.db.messagesDao.byRowid(local1.localRowid);
      expect(m1!.deletedAt, isNotNull);
      expect(m1.body, isNull);
      // A newer edit in the backup is applied.
      final m3 = await second.db.messagesDao.byRowid(local3.localRowid);
      expect(m3!.body, 'edited text');
      // The local newer edit and the local delete stay.
      final m5 = await second.db.messagesDao.byRowid(local5.localRowid);
      expect(m5!.body, 'local version');
      final m2 = await second.db.messagesDao.byRowid(local2.localRowid);
      expect(m2!.deletedAt, isNotNull);
      expect(
        await second.db.messagesDao.reactionsFor([local2.localRowid]),
        isEmpty,
      );
      // The backup device had read everything: so has this one now.
      final summary = await second.db.conversationsDao.byId(chat);
      expect(summary!.unreadCount, 0);
      expect(
        summary.lastMessageSortKey,
        (await alice.db.conversationsDao.byId(chat))!.lastMessageSortKey,
      );
    });
  });

  group('refusals', () {
    Future<void> stored() async {
      await addHistory(alice, bobId, 5);
      await alice.backup.backUpNow();
    }

    test('no backup', () async {
      final second = await world.link(alice, 'alice2');
      final e = await failureOf(second.backup.restoreHistory());
      expect(e.failure, BackupFailure.noBackup);
    });

    test('a backup that was not made under this account key', () async {
      final bob = await world.register('bob', phone: '+8801711000002');
      await addHistory(bob, alice.account, 4);
      await bob.backup.backUpNow();
      // The server hands Alice Bob's backup (or the AIK changed under it).
      final second = await world.link(alice, 'alice2');
      final e = await failureOf(second.backup.restoreHistory());
      expect(e.failure, BackupFailure.wrongKey);
      expect(await HistoryStore(second.db).messageCount(), 0);
    });

    test('tampered bytes, a swapped version and a truncated blob', () async {
      await stored();
      final second = await world.link(alice, 'alice2');
      final good = world.remote.stored!;

      final flipped = Uint8List.fromList(good.data)..[40] ^= 1;
      world.remote.stored = HistoryBackup(version: 1, data: flipped);
      expect(
        (await failureOf(second.backup.restoreHistory())).failure,
        BackupFailure.wrongKey,
      );

      // The version is part of the AEAD's associated data: the server cannot
      // present this backup as a newer one.
      world.remote.stored = HistoryBackup(version: 2, data: good.data);
      expect(
        (await failureOf(second.backup.restoreHistory())).failure,
        BackupFailure.wrongKey,
      );

      world.remote.stored = HistoryBackup(
        version: 1,
        data: Uint8List.fromList([1, 2, 3]),
      );
      expect(
        (await failureOf(second.backup.restoreHistory())).failure,
        BackupFailure.corrupt,
      );
      expect(await HistoryStore(second.db).messageCount(), 0);
    });

    test('a newer format and a newer archive version', () async {
      await stored();
      final second = await world.link(alice, 'alice2');
      final good = world.remote.stored!;
      world.remote.stored = HistoryBackup(
        version: 1,
        data: Uint8List.fromList(good.data)..[0] = 2,
      );
      expect(
        (await failureOf(second.backup.restoreHistory())).failure,
        BackupFailure.newerFormat,
      );

      // A well-formed (authentic) archive whose header names version 9.
      final writer = ArchiveWriter();
      writer
        ..add({
          't': 'header',
          'v': 9,
          'kind': 'history',
          'account': alice.account,
          'created': 1,
        })
        ..add({'t': 'future', 'x': 1});
      final data = await HistoryBackupCrypto.seal(
        identityKeySeed: await aikSeed(alice),
        accountId: alice.account,
        version: 5,
        plaintext: joinBytes(writer.finish()),
        random: SecureCryptoRandom(),
      );
      world.remote.stored = HistoryBackup(version: 5, data: data);
      expect(
        (await failureOf(second.backup.restoreHistory())).failure,
        BackupFailure.newerFormat,
      );
    });

    test('an archive for another account or another kind', () async {
      await stored();
      final second = await world.link(alice, 'alice2');
      Future<void> put(Map<String, Object?> header, int version) async {
        final writer = ArchiveWriter()..add(header);
        world.remote.stored = HistoryBackup(
          version: version,
          data: await HistoryBackupCrypto.seal(
            identityKeySeed: await aikSeed(alice),
            accountId: alice.account,
            version: version,
            plaintext: joinBytes(writer.finish()),
            random: SecureCryptoRandom(),
          ),
        );
      }

      await put({
        't': 'header',
        'v': 1,
        'kind': 'history',
        'account': bobId,
        'created': 1,
      }, 2);
      expect(
        (await failureOf(second.backup.restoreHistory())).failure,
        BackupFailure.accountMismatch,
      );
      // A transfer archive is not a history backup.
      await put({
        't': 'header',
        'v': 1,
        'kind': 'transfer',
        'account': alice.account,
        'created': 1,
      }, 3);
      expect(
        (await failureOf(second.backup.restoreHistory())).failure,
        BackupFailure.corrupt,
      );
      // No header at all.
      await put({'t': 'msg', 'id': 'x'}, 4);
      expect(
        (await failureOf(second.backup.restoreHistory())).failure,
        BackupFailure.corrupt,
      );
    });

    test('a history backup that smuggles in secrets is refused', () async {
      await stored();
      final second = await world.link(alice, 'alice2');
      final writer = ArchiveWriter()
        ..add({
          't': 'header',
          'v': 1,
          'kind': 'history',
          'account': alice.account,
          'created': 1,
        })
        ..add({
          't': 'secrets',
          'aik_seed': encodeBytes(Uint8List(32)),
          'aik': encodeBytes(Uint8List(32)),
        });
      world.remote.stored = HistoryBackup(
        version: 9,
        data: await HistoryBackupCrypto.seal(
          identityKeySeed: await aikSeed(alice),
          accountId: alice.account,
          version: 9,
          plaintext: joinBytes(writer.finish()),
          random: SecureCryptoRandom(),
        ),
      );
      expect(
        (await failureOf(second.backup.restoreHistory())).failure,
        BackupFailure.corrupt,
      );
    });

    test('an older backup than this device knows is a rollback', () async {
      await stored();
      final v1 = world.remote.stored!;
      await alice.backup.backUpNow();
      expect(world.remote.stored!.version, 2);
      world.remote.stored = v1;
      expect(
        (await failureOf(alice.backup.restoreHistory())).failure,
        BackupFailure.rolledBack,
      );
    });

    test('offline is reported and recorded, and the next try works', () async {
      await addHistory(alice, bobId, 3);
      world.remote.offline = 1;
      final phases = <BackupPhase>[];
      final sub = alice.backup.backupProgress.listen(
        (p) => phases.add(p.phase),
      );
      final e = await failureOf(alice.backup.backUpNow());
      expect(e.failure, BackupFailure.offline);
      final failed = await alice.backup.status();
      expect(failed.lastFailure, BackupFailure.offline);
      expect(failed.lastBackupAt, isNull);
      await alice.backup.backUpNow();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      final ok = await alice.backup.status();
      expect(ok.lastFailure, isNull);
      expect(ok.lastBackupAt, isNotNull);
      expect(ok.version, 1);
      expect(ok.messages, 3);
      expect(phases, contains(BackupPhase.failed));
      expect(phases.last, BackupPhase.done);
    });
  });

  group('versions across devices', () {
    test('a device that knows less merges the server backup before it '
        'uploads, so it never overwrites more history', () async {
      await addHistory(alice, bobId, 8, prefix: 'from one');
      await alice.backup.backUpNow();
      final second = await world.link(alice, 'alice2');
      const carol = 'cccccccc-0000-4000-8000-000000000002';
      await addHistory(second, carol, 5, prefix: 'from two');

      // The second device has never seen version 1: its v1 is refused, it
      // takes the server's backup, and uploads v2 on top.
      final result = await second.backup.backUpNow();
      expect(result.version, 2);
      expect(world.remote.stored!.version, 2);
      expect(await HistoryStore(second.db).messageCount(), 13);
      final ids = [
        for (final r in await openStored(alice))
          if (r.string('t') == 'msg') r.string('id'),
      ];
      expect(ids, hasLength(13));

      // The first device now catches up with the second one's history.
      final back = await alice.backup.restoreHistory();
      expect(back.added, 5);
      expect(await HistoryStore(alice.db).messageCount(), 13);
    });
  });

  group('size', () {
    test('a large history is paged, framed and restored whole', () async {
      final big = BackupWorld(pageSize: 7, frameBytes: 2000);
      addTearDown(big.dispose);
      final source = await big.register('big', phone: '+8801711000009');
      const chats = [
        'c1000000-0000-4000-8000-000000000001',
        'c2000000-0000-4000-8000-000000000002',
        'c3000000-0000-4000-8000-000000000003',
      ];
      for (final (i, chat) in chats.indexed) {
        await addHistory(source, chat, 400 + i * 50, prefix: 'page $i');
      }
      final total = await HistoryStore(source.db).messageCount();
      expect(total, 1350);

      final result = await source.backup.backUpNow();
      expect(result.messages, total);
      expect(result.truncated, isFalse);
      final plain = await HistoryBackupCrypto.open(
        identityKeySeed: await aikSeed(source),
        accountId: source.account,
        version: 1,
        data: big.remote.stored!.data,
      );
      final frames = ArchiveReader.frames(plain, gzip: gzip).toList();
      expect(
        frames.length,
        greaterThan(20),
        reason: 'written a frame at a time',
      );

      final fresh = await big.link(source, 'big2');
      final restored = await fresh.backup.restoreHistory();
      expect(restored.added, total);
      expect(await historyDigest(fresh), await historyDigest(source));
    });

    test(
      'over the size budget the oldest messages drop out, not the newest',
      () async {
        final small = BackupWorld(
          pageSize: 50,
          frameBytes: 4000,
          maxHistoryBytes: 30 * 1024,
          compress: false,
        );
        addTearDown(small.dispose);
        final source = await small.register('small', phone: '+8801711000008');
        await addHistory(
          source,
          bobId,
          1000,
          prefix: 'padding padding padding',
        );
        final result = await source.backup.backUpNow();
        expect(result.truncated, isTrue);
        expect(result.messages, lessThan(1000));
        expect(result.messages, greaterThan(100));
        expect(small.remote.stored!.data.length, lessThanOrEqualTo(30 * 1024));
        expect((await source.backup.status()).truncated, isTrue);

        final fresh = await small.link(source, 'small2');
        await fresh.backup.restoreHistory();
        final restored = await fresh.db.messagesDao.pageOlder(
          directConversationId(bobId),
          limit: 2000,
        );
        expect(restored.messages.last.body, 'padding padding padding 999');
        expect(
          restored.messages.first.body,
          isNot('padding padding padding 0'),
        );
      },
    );

    test('a server limit lower than expected halves the budget until it '
        'fits', () async {
      final raw = BackupWorld(compress: false);
      addTearDown(raw.dispose);
      final source = await raw.register('raw', phone: '+8801711000006');
      await addHistory(
        source,
        bobId,
        600,
        prefix: 'a fairly long line of text',
      );
      raw.remote.limit = 12 * 1024;
      final result = await source.backup.backUpNow();
      expect(result.truncated, isTrue);
      expect(result.messages, greaterThan(10));
      expect(raw.remote.stored!.data.length, lessThanOrEqualTo(12 * 1024));
    });
  });

  group('schedule', () {
    test('the daily backup runs when due, not before, and backs off after a '
        'failure', () async {
      final scheduled = await world.create(
        'sched',
        options: BackupOptions(
          gzip: gzip,
          autoBackup: true,
          autoAcceptTransfers: false,
          autoTransferToNewDevices: false,
          retryInterval: const Duration(hours: 1),
          remote: world.remote,
          relay: world.relay,
        ),
      );
      final challenge = await scheduled.engine.account.requestPhoneCode(
        '+8801711000007',
      );
      final verified = await scheduled.engine.account.verifyPhone(
        challenge.challengeId,
        '123456',
      );
      await scheduled.engine.account.register(
        verificationToken: verified.verificationToken,
        phoneNumber: '+8801711000007',
      );
      await addHistory(scheduled, bobId, 3);

      world.remote.offline = 1;
      await scheduled.engine.runMaintenance();
      expect(world.remote.historyPuts, 0);
      expect(
        (await scheduled.backup.status()).lastFailure,
        BackupFailure.offline,
      );

      // Within the retry interval nothing is attempted.
      await scheduled.engine.runMaintenance();
      expect(world.remote.historyPuts, 0);

      world.clock.advance(const Duration(hours: 2));
      await scheduled.engine.runMaintenance();
      expect(world.remote.historyPuts, 1);

      // Not again until a day has passed.
      world.clock.advance(const Duration(hours: 20));
      await scheduled.engine.runMaintenance();
      expect(world.remote.historyPuts, 1);
      world.clock.advance(const Duration(hours: 5));
      await scheduled.engine.runMaintenance();
      expect(world.remote.historyPuts, 2);
      expect(world.remote.stored!.version, 2);

      // Switched off, it stays off.
      await scheduled.backup.setAutoBackup(false);
      world.clock.advance(const Duration(days: 3));
      await scheduled.engine.runMaintenance();
      expect(world.remote.historyPuts, 2);
    });

    test('the status stream reports a backup as it lands', () async {
      await addHistory(alice, bobId, 3);
      final seen = <BackupStatus>[];
      final sub = alice.backup.watchStatus().listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await alice.backup.backUpNow();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      expect(seen.first.lastBackupAt, isNull);
      expect(seen.last.lastBackupAt, isNotNull);
      expect(seen.last.version, 1);
    });

    test('forgetting after an identity change clears the bookkeeping and the '
        'server copy', () async {
      await addHistory(alice, bobId, 3);
      await alice.backup.backUpNow();
      await alice.backup.forgetBackupState();
      expect(world.remote.stored, isNull);
      final status = await alice.backup.status();
      expect(status.version, isNull);
      expect(status.lastBackupAt, isNull);
      // The next backup starts again at version 1.
      expect((await alice.backup.backUpNow()).version, 1);
    });
  });

  test('engine defaults keep the engine usable without the feature', () {
    expect(fastConfig, isNotNull);
    expect(const BackupOptions().autoBackup, isTrue);
  });
}

Uint8List joinBytes(List<ArchiveFrame> frames) {
  final out = BytesBuilder();
  for (final f in frames) {
    out.add(f.bytes);
  }
  return out.takeBytes();
}
