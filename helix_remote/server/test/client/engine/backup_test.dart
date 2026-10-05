import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart' show settle, testEngineConfig;

/// History backup, restore, the full backup and device-to-device transfer
/// with real engines on the in-process server (Phase C4-B).
void main() {
  group('engine backup', skip: databaseTestSkipReason, () {
    late Harness h;
    late _World world;

    const password = 'correct horse battery staple';
    const secret = 'a long recovery secret nobody guesses';

    setUp(() async {
      h = await Harness.start();
      world = _World(h);
    });
    tearDown(() async {
      await world.dispose();
      await h.stop();
    });

    group('history backup and restore', () {
      test('an account with history backs up and a fresh device restores '
          'the same messages, summaries and search', () async {
        final alice = await world.register(
          'alice',
          aliceNumber,
          password: password,
        );
        final bob = await world.register('bob', bobNumber);
        final chat = directConversationId(bob.account);
        await alice.engine.chats.openDirect(bob.account);

        await alice.engine.chats.sendText(chat, 'hello one');
        final two = await alice.engine.chats.sendText(chat, 'hello two');
        final oops = await alice.engine.chats.sendText(chat, 'oops hello');
        await bob.waitFor(alice, 'oops hello');
        await bob.engine.chats.sendText(
          directConversationId(alice.account),
          'hi back from bob',
        );
        await bob.engine.chats.sendText(
          directConversationId(alice.account),
          'weekend plans?',
        );
        await alice.waitFor(bob, 'weekend plans?');

        // An edit, a reaction, a delete for everyone and a read receipt.
        await alice.engine.chats.edit(two.localRowid, 'hello two edited');
        await alice.engine.chats.deleteForEveryone(oops.localRowid);
        final theirs = await alice.waitFor(bob, 'hi back from bob');
        await alice.engine.chats.react(theirs.localRowid, 'A');
        await bob.engine.chats.markRead(directConversationId(alice.account));
        await settle(() async {
          final rows = await alice.messages(bob);
          expect(
            rows
                .where((m) => m.outgoing && m.deletedAt == null)
                .every((m) => m.status == MessageStatus.read),
            isTrue,
          );
          expect(rows.where((m) => m.deletedAt != null), hasLength(1));
          expect(rows.any((m) => m.body == 'hello two edited'), isTrue);
        });

        final result = await alice.engine.backup.backUpNow();
        expect(result.version, 1);
        expect(result.messages, 5);
        expect((await alice.api.backup.history())!.version, 1);

        // A fresh device signs in with the password and restores.
        final alice2 = await world.signIn('alice2', aliceNumber, password);
        expect(await HistoryStore(alice2.db).messageCount(), 0);
        final restored = await alice2.engine.backup.restoreHistory();
        expect(restored.added, 5);

        expect(await alice2.digest(bob), await alice.digest(bob));
        final c1 = (await alice.db.conversationsDao.byId(chat))!;
        final c2 = (await alice2.db.conversationsDao.byId(chat))!;
        expect(c2.lastMessageSortKey, c1.lastMessageSortKey);
        expect(c2.lastMessagePreview, c1.lastMessagePreview);
        expect(c2.unreadCount, c1.unreadCount);
        expect(c2.unreadCount, 2);
        expect(
          [for (final m in await alice2.engine.chats.search('hello')) m.body],
          unorderedEquals([
            for (final m in await alice.engine.chats.search('hello')) m.body,
          ]),
        );
        expect(
          (await alice2.engine.chats.search('weekend')).single.body,
          'weekend plans?',
        );
        final people = await alice2.db.peopleDao.byAccount(bob.account);
        expect(people!.identityKey, isNotNull, reason: 'the pinned key');

        // Restoring again changes nothing; the restored device keeps
        // receiving new messages directly.
        final again = await alice2.engine.backup.restoreHistory();
        expect(again.added, 0);
        await bob.engine.chats.sendText(
          directConversationId(alice.account),
          'after the restore',
        );
        await alice2.waitFor(bob, 'after the restore');
      });

      test('two devices write the one backup: the one that knows less merges '
          'before it uploads', () async {
        final alice = await world.register(
          'alice',
          aliceNumber,
          password: password,
        );
        final bob = await world.register('bob', bobNumber);
        await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(
          directConversationId(bob.account),
          'from device one',
        );
        await bob.waitFor(alice, 'from device one');
        await alice.engine.backup.backUpNow();

        final alice2 = await world.signIn('alice2', aliceNumber, password);
        final carol = await world.register('carol', '+8801711000003');
        await alice2.engine.chats.openDirect(carol.account);
        await alice2.engine.chats.sendText(
          directConversationId(carol.account),
          'from device two',
        );
        await carol.waitFor(alice2, 'from device two');

        // Device two never saw version 1: its upload is refused, it merges
        // version 1 and uploads version 2 with both histories.
        final result = await alice2.engine.backup.backUpNow();
        expect(result.version, 2);
        expect((await alice2.api.backup.history())!.version, 2);
        expect(
          await alice2.engine.chats.search('from device one'),
          hasLength(1),
        );

        final back = await alice.engine.backup.restoreHistory();
        expect(back.version, 2);
        expect(
          await alice.engine.chats.search('from device two'),
          hasLength(1),
        );
      });

      test('the maintenance pass uploads the automatic backup', () async {
        final alice = await world.register(
          'alice',
          aliceNumber,
          options: world.options(autoBackup: true),
        );
        final bob = await world.register('bob', bobNumber);
        await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(
          directConversationId(bob.account),
          'scheduled',
        );
        await bob.waitFor(alice, 'scheduled');
        expect(await alice.api.backup.history(), isNull);
        await alice.engine.runMaintenance();
        expect((await alice.api.backup.history())!.version, 1);
        final status = await alice.engine.backup.status();
        expect(status.lastBackupAt, isNotNull);
        expect(status.lastFailure, isNull);
        // Not again within the interval.
        await alice.engine.runMaintenance();
        expect((await alice.api.backup.history())!.version, 1);
      });

      test(
        'the server refuses a stale version and keeps the newer backup',
        () async {
          final alice = await world.register('alice', aliceNumber);
          final bob = await world.register('bob', bobNumber);
          await alice.engine.chats.openDirect(bob.account);
          await alice.engine.chats.sendText(
            directConversationId(bob.account),
            'x',
          );
          await alice.engine.backup.backUpNow();
          await alice.engine.backup.backUpNow();
          expect((await alice.api.backup.history())!.version, 2);
          await expectLater(
            alice.api.backup.putHistory(
              HistoryBackup(version: 1, data: Uint8List(64)),
            ),
            throwsA(
              isA<ApiException>().having(
                (e) => e.code,
                'code',
                ErrorCode.versionConflict,
              ),
            ),
          );
          expect((await alice.api.backup.history())!.version, 2);
        },
      );
    });

    group('device-to-device transfer', () {
      test(
        'a password-linked second device receives the history by itself',
        () async {
          final alice = await world.register(
            'alice',
            aliceNumber,
            password: password,
            options: world.options(autoTransfer: true),
          );
          final bob = await world.register('bob', bobNumber);
          final chat = directConversationId(bob.account);
          await alice.engine.chats.openDirect(bob.account);
          await alice.engine.chats.sendText(chat, 'before the laptop');
          await bob.waitFor(alice, 'before the laptop');
          await bob.engine.chats.sendText(
            directConversationId(alice.account),
            'bob before the laptop',
          );
          await alice.waitFor(bob, 'bob before the laptop');
          final profileKey = (await alice.db.accountDao.current())!.profileKey;

          // The laptop signs in with the password; nobody approves anything.
          final laptop = await world.signIn(
            'laptop',
            aliceNumber,
            password,
            options: world.options(autoTransfer: true),
          );
          expect(
            (await laptop.db.accountDao.current())!.profileKey,
            isNull,
            reason: 'a password sign-in has no profile key',
          );

          await settle(() async {
            expect(await laptop.engine.chats.search('laptop'), hasLength(2));
          }, timeout: const Duration(seconds: 30));
          expect(await laptop.digest(bob), await alice.digest(bob));
          // The profile key came with the transfer.
          expect(
            (await laptop.db.accountDao.current())!.profileKey,
            profileKey,
          );

          // The laptop answered; the phone removes the relay objects.
          final relayIds = await alice.outgoingRelayIds();
          expect(relayIds, isNotEmpty);
          await settle(() async {
            await alice.engine.runMaintenance();
            expect(await alice.outgoingRelayIds(), isEmpty);
          }, timeout: const Duration(seconds: 20));
          for (final id in relayIds) {
            await expectLater(
              alice.api.media.download(id),
              throwsA(
                isA<ApiException>().having(
                  (e) => e.code,
                  'code',
                  ErrorCode.notFound,
                ),
              ),
            );
          }
          final offers = await laptop.engine.backup.offers();
          expect(offers.single.phase, HistoryTransferPhase.done);

          // Both keep working after the transfer.
          await laptop.engine.chats.sendText(chat, 'sent from the laptop');
          await bob.waitFor(laptop, 'sent from the laptop');
          await alice.waitFor(bob, 'sent from the laptop');
        },
      );

      test('a large history moves in segments through the real relay, with '
          'a gap resumed', () async {
        final alice = await world.register(
          'alice',
          aliceNumber,
          password: password,
          options: world.options(
            compress: false,
            segmentBytes: 20000,
            frameBytes: 6000,
          ),
        );
        final bob = await world.register('bob', bobNumber);
        await alice.engine.chats.openDirect(bob.account);
        await _addHistory(alice, bob.account, 700, prefix: 'segment text');
        final laptop = await world.signIn('laptop', aliceNumber, password);
        await settle(() async {
          expect((await alice.engine.devices.refresh()).length, 2);
        });

        final id = await alice.engine.backup.sendHistory();
        final relayIds = await alice.outgoingRelayIds();
        expect(relayIds.length, greaterThan(5), reason: 'several segments');
        await settle(() async {
          expect((await laptop.engine.backup.offers()), hasLength(1));
        });

        // The relay loses a segment (a gap): the transfer cannot be applied,
        // nothing is half-imported, and the offer ends as expired.
        await alice.api.media.delete(relayIds[2]);
        await expectLater(
          laptop.engine.backup.acceptOffer(id),
          throwsA(
            isA<BackupException>().having(
              (e) => e.failure,
              'failure',
              BackupFailure.expired,
            ),
          ),
        );
        expect(await HistoryStore(laptop.db).messageCount(), 0);
        expect(
          (await laptop.engine.backup.offers()).single.phase,
          HistoryTransferPhase.failed,
        );

        // Sending again gives a fresh transfer, which completes.
        final second = await alice.engine.backup.sendHistory();
        await settle(() async {
          final offers = await laptop.engine.backup.offers();
          expect(offers.map((o) => o.transferId), contains(second));
        });
        final result = await laptop.engine.backup.acceptOffer(second);
        expect(result.added, 700);
        expect(await laptop.digest(bob), await alice.digest(bob));
        expect(
          (await laptop.engine.chats.search('segment', limit: 1000)).length,
          700,
        );
      });

      test('a linked device (QR) can take the history too', () async {
        final alice = await world.register('alice', aliceNumber);
        final bob = await world.register('bob', bobNumber);
        await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(
          directConversationId(bob.account),
          'qr history',
        );
        await bob.waitFor(alice, 'qr history');
        final tablet = await world.link(alice, 'tablet');
        await settle(() async {
          expect((await alice.engine.devices.refresh()).length, 2);
        });
        final id = await alice.engine.backup.sendHistory(
          devices: [tablet.device],
        );
        await settle(() async {
          expect(await tablet.engine.backup.offers(), hasLength(1));
        });
        final result = await tablet.engine.backup.acceptOffer(id);
        expect(result.added, 1);
        expect(await tablet.engine.chats.search('qr history'), hasLength(1));
      });
    });

    group('full backup', () {
      test(
        'create, upload, download and restore with the recovery secret',
        () async {
          final alice = await world.register(
            'alice',
            aliceNumber,
            password: password,
          );
          final bob = await world.register('bob', bobNumber);
          await alice.engine.chats.openDirect(bob.account);
          await alice.engine.chats.sendText(
            directConversationId(bob.account),
            'in the full backup',
          );
          await bob.waitFor(alice, 'in the full backup');

          final result = await alice.engine.backup.createFullBackup(
            recoverySecret: secret,
            mediaIds: const ['55555555-5555-4555-8555-555555555555'],
          );
          expect(result.version, 1);
          final stored = (await alice.api.backup.full())!;
          expect(stored.mediaIds, ['55555555-5555-4555-8555-555555555555']);
          expect(jsonEncode(stored.envelope), isNot(contains(secret)));

          final alice2 = await world.signIn('alice2', aliceNumber, password);
          await expectLater(
            alice2.engine.backup.restoreFullBackup(
              recoverySecret: 'the wrong secret entirely',
            ),
            throwsA(
              isA<BackupException>().having(
                (e) => e.failure,
                'failure',
                BackupFailure.wrongKey,
              ),
            ),
          );
          final restored = await alice2.engine.backup.restoreFullBackup(
            recoverySecret: secret,
          );
          expect(restored.result.added, 1);
          expect(restored.identityMatches, isTrue);
          final aik = (await alice.db.cryptoDao.identityKeys())!;
          expect(restored.secrets!.identityKeySeed, aik.aikPrivate);
          expect(
            restored.secrets!.profileKey,
            (await alice.db.accountDao.current())!.profileKey,
          );
          expect(await alice2.engine.chats.search('full backup'), hasLength(1));
        },
      );

      test(
        'the server refuses an envelope that carries a secret field',
        () async {
          final alice = await world.register('alice', aliceNumber);
          for (final field in FullBackup.forbiddenFields) {
            await expectLater(
              alice.api.backup.putFull(
                FullBackup(
                  backupId: '66666666-6666-4666-8666-666666666666',
                  version: 1,
                  envelope: {
                    'format': 'helix.v2.backup',
                    'nested': [
                      {field: 'x'},
                    ],
                  },
                ),
              ),
              throwsA(
                isA<ApiException>().having(
                  (e) => e.code,
                  'code',
                  ErrorCode.invalidField,
                ),
              ),
              reason: field,
            );
          }
          expect(await alice.api.backup.full(), isNull);
        },
      );
    });

    group('identity key change', () {
      test('the history backup is deleted with the old key; the full backup '
          'still opens with the recovery secret', () async {
        final alice = await world.register(
          'alice',
          aliceNumber,
          password: password,
        );
        final bob = await world.register('bob', bobNumber);
        await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(
          directConversationId(bob.account),
          'before the takeover',
        );
        await bob.waitFor(alice, 'before the takeover');
        await alice.engine.backup.backUpNow();
        await alice.engine.backup.createFullBackup(recoverySecret: secret);
        final accountId = alice.account;
        final oldIdentity = (await alice.db.cryptoDao.identityKeys())!;
        final oldKey = Uint8List.fromList(oldIdentity.aikPublic);
        final oldSeed = Uint8List.fromList(oldIdentity.aikPrivate);
        expect(await alice.api.backup.history(), isNotNull);

        // Someone (the owner, on a new phone, with only SMS) takes the
        // number over under a new identity key.
        final fresh = await world.create('alice-new');
        final challenge = await fresh.engine.account.requestPhoneCode(
          aliceNumber,
        );
        final verified = await fresh.engine.account.verifyPhone(
          challenge.challengeId,
          h.sms.lastCodeFor(aliceNumber),
        );
        await fresh.engine.account.register(
          verificationToken: verified.verificationToken,
          accountId: verified.accountId,
          replaceExisting: true,
          phoneNumber: aliceNumber,
        );
        expect(fresh.account, accountId);
        final newKey = (await fresh.db.cryptoDao.identityKeys())!.aikPublic;
        expect(newKey, isNot(oldKey));

        // Nobody can open the history backup any more: the server removed it.
        expect(await fresh.api.backup.history(), isNull);
        await expectLater(
          fresh.engine.backup.restoreHistory(),
          throwsA(
            isA<BackupException>().having(
              (e) => e.failure,
              'failure',
              BackupFailure.noBackup,
            ),
          ),
        );
        // The old device was revoked (and wiped) by the takeover.
        await settle(() async {
          expect(alice.engine.status, EngineStatus.revoked);
        });

        // The full backup is keyed by the recovery secret, so it survives.
        final restored = await fresh.engine.backup.restoreFullBackup(
          recoverySecret: secret,
        );
        expect(restored.result.added, 1);
        expect(restored.identityMatches, isFalse, reason: 'a new identity key');
        expect(restored.secrets!.identityKey, oldKey);
        expect(
          await fresh.engine.chats.search('before the takeover'),
          hasLength(1),
        );

        // Bookkeeping starts over under the new key, and the next history
        // backup opens with it.
        await fresh.engine.backup.forgetBackupState();
        final result = await fresh.engine.backup.backUpNow();
        expect(result.version, 1);
        final data = (await fresh.api.backup.history())!;
        final opened = await HistoryBackupCrypto.open(
          identityKeySeed:
              (await fresh.db.cryptoDao.identityKeys())!.aikPrivate,
          accountId: fresh.account,
          version: data.version,
          data: data.data,
        );
        expect(opened, isNotEmpty);
        await expectLater(
          HistoryBackupCrypto.open(
            identityKeySeed: oldSeed,
            accountId: fresh.account,
            version: data.version,
            data: data.data,
          ),
          throwsA(isA<DecryptionFailedException>()),
        );
      });
    });
  });
}

/// Alice's own engine plus the helpers the tests read it with.
final class _User {
  _User(this.name, this.db, this.api, this.engine);

  final String name;
  final HelixDb db;
  final HelixApi api;
  final Engine engine;

  String get account => engine.accountId!;
  String get device => engine.deviceId!;

  Future<void> dispose() async {
    await engine.close();
    await api.close();
    await db.close();
  }

  /// The chat with [peer], oldest first.
  Future<List<MessageRow>> messages(_User peer) async =>
      (await db.messagesDao.pageOlder(
        directConversationId(peer.account),
        limit: 100000,
      )).messages;

  /// Waits for [peer]'s text [text] to show up here.
  Future<MessageRow> waitFor(_User peer, String text) async {
    late MessageRow found;
    await settle(() async {
      final match = (await messages(
        peer,
      )).where((m) => m.body == text && m.deletedAt == null);
      expect(match, isNotEmpty, reason: '$name has no "$text"');
      found = match.first;
    }, timeout: const Duration(seconds: 20));
    return found;
  }

  /// What two devices must agree on about a chat: identity, text, state,
  /// reactions.
  Future<List<String>> digest(_User peer) async {
    final out = <String>[];
    for (final m in await messages(peer)) {
      final reactions = await db.messagesDao.reactionsFor([m.localRowid]);
      out.add(
        '${m.messageId}|${m.sender}|${m.body}|${m.status.name}|${m.kind}'
        '|${m.deletedAt != null}|${m.editedAt != null}'
        '|${[for (final r in reactions) '${r.reactor}:${r.emoji}']}',
      );
    }
    return out;
  }

  /// Relay object ids of the transfers this device still tracks (read from
  /// the engine's ledger setting).
  Future<List<String>> outgoingRelayIds() async {
    final text = await db.settingsDao.get(
      const Setting<String?>('backup.transfers.out', null),
    );
    if (text == null) return const [];
    final all = jsonDecode(text) as Map<String, Object?>;
    return [
      for (final entry in all.values)
        ...((entry! as Map<String, Object?>)['media']! as List).cast<String>(),
    ];
  }
}

/// Engines on the in-process server with backup options of the test's choice.
final class _World {
  _World(this.h);

  final Harness h;
  final List<_User> _users = [];

  BackupOptions options({
    bool autoBackup = false,
    bool autoTransfer = false,
    bool compress = true,
    int segmentBytes = 4 * 1024 * 1024,
    int frameBytes = 256 * 1024,
  }) => BackupOptions(
    gzip: compress ? gzip : null,
    autoBackup: autoBackup,
    autoTransferToNewDevices: autoTransfer,
    autoAcceptTransfers: autoTransfer,
    segmentBytes: segmentBytes,
    frameBytes: frameBytes,
  );

  Future<_User> create(String name, {BackupOptions? options}) async {
    final key = DatabaseKey.generate();
    final db = HelixDb.inMemory(key: key);
    final api = HelixApi(
      baseUrl: h.server.baseUri,
      sessions: DbSessionTokenStore(db),
      clientName: 'backup-test/$name',
    );
    final engine = Engine(
      api: api,
      db: db,
      clock: DateTime.now,
      random: SecureCryptoRandom(),
      config: testEngineConfig,
      backupOptions: options ?? this.options(),
    );
    final user = _User(name, db, api, engine);
    _users.add(user);
    await engine.start();
    return user;
  }

  Future<_User> register(
    String name,
    String number, {
    String? password,
    BackupOptions? options,
  }) async {
    final user = await create(name, options: options);
    final challenge = await user.engine.account.requestPhoneCode(number);
    final verified = await user.engine.account.verifyPhone(
      challenge.challengeId,
      h.sms.lastCodeFor(number),
    );
    await user.engine.account.register(
      verificationToken: verified.verificationToken,
      phoneNumber: number,
      password: password,
    );
    expect(user.engine.status, EngineStatus.running);
    return user;
  }

  /// A new device of the account at [number], signed in with [password].
  Future<_User> signIn(
    String name,
    String number,
    String password, {
    BackupOptions? options,
  }) async {
    final user = await create(name, options: options);
    await user.engine.account.signInWithPassword(
      phoneNumber: number,
      password: password,
      deviceName: name,
    );
    return user;
  }

  /// A QR-linked device of [existing].
  Future<_User> link(_User existing, String name) async {
    final fresh = await create(name);
    final link = await fresh.engine.account.beginLink();
    final done = link.complete();
    await existing.engine.devices.approveLink(link.code);
    await done.timeout(const Duration(seconds: 20));
    return fresh;
  }

  Future<void> dispose() async {
    for (final user in _users.reversed) {
      try {
        await user.dispose();
      } on Object {
        // Already closed.
      }
    }
    _users.clear();
  }
}

/// Inserts [count] text messages straight into [user]'s database.
Future<void> _addHistory(
  _User user,
  String peer,
  int count, {
  String prefix = 'message',
}) async {
  final start = DateTime.utc(2026, 3, 1);
  for (var i = 0; i < count; i++) {
    final mine = i.isEven;
    final sentAt = start.add(Duration(seconds: i));
    final id =
        '0192a4f0-0000-7000-8000-${(0xb000 + i).toRadixString(16).padLeft(12, '0')}';
    await user.db.messagesDao.insertMessage(
      MessagesCompanion.insert(
        messageId: id,
        conversationId: directConversationId(peer),
        sender: mine ? user.account : peer,
        outgoing: mine,
        sortKey: SortKey.of(sentAt, id),
        sentAt: sentAt,
        receivedAt: sentAt,
        kind: 'text',
        status: mine ? MessageStatus.delivered : MessageStatus.received,
        body: Value('$prefix $i'),
      ),
    );
  }
}
