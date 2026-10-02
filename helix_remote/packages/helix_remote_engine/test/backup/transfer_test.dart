import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Device-to-device transfer over the media relay (F2, CONTENT_V2.md §4):
/// the sender exports in segments, the receiver fetches them as chunks,
/// detects gaps, imports in order and answers.
void main() {
  late BackupWorld world;
  late BackupPeer alice;
  late BackupPeer alice2;

  const bobId = 'bbbbbbbb-0000-4000-8000-000000000001';

  Future<void> start({
    int segmentBytes = 3000,
    int frameBytes = 1000,
    int messages = 60,
  }) async {
    world = BackupWorld(
      segmentBytes: segmentBytes,
      frameBytes: frameBytes,
      compress: false,
    );
    alice = await world.register('alice', phone: '+8801711000001');
    alice2 = await world.link(alice, 'alice2');
    await addHistory(alice, bobId, messages, prefix: 'transfer text');
  }

  tearDown(() => world.dispose());

  /// Alice offers; Alice2 receives the offer. Returns the transfer id.
  Future<String> offer() async {
    final id = await alice.backup.sendHistory();
    await alice.engine.drainOutbox();
    await alice2.engine.syncOnce();
    return id;
  }

  Future<BackupException> failureOf(Future<Object?> action) async {
    try {
      await action;
    } on BackupException catch (e) {
      return e;
    }
    fail('expected a BackupException');
  }

  /// The relay ids in upload order: segments first, the manifest last.
  List<String> uploaded() => world.relay.objects.keys.toList();

  test('history moves to the new device and the relay is cleaned up', () async {
    await start();
    final sender = <TransferPhase>[];
    final receiver = <TransferPhase>[];
    final s1 = alice.backup.transferProgress.listen((p) {
      if (p.role == TransferRole.sending) sender.add(p.phase);
    });
    final s2 = alice2.backup.transferProgress.listen((p) {
      if (p.role == TransferRole.receiving) receiver.add(p.phase);
    });

    final id = await offer();
    expect(uploaded().length, greaterThan(3), reason: 'several segments');
    final offers = await alice2.backup.offers();
    expect(offers, hasLength(1));
    expect(offers.single.transferId, id);
    expect(offers.single.phase, TransferPhase.waiting);
    expect(offers.single.fromDevice, alice.device);
    expect(await HistoryStore(alice2.db).messageCount(), 0);

    final result = await alice2.backup.acceptOffer(id);
    expect(result.added, 60);
    expect(await historyDigest(alice2), await historyDigest(alice));
    expect(
      (await alice2.engine.chats.search('transfer', limit: 100)).length,
      60,
      reason: 'search follows the import',
    );
    expect((await alice2.backup.offers()).single.phase, TransferPhase.done);
    // The chunks are gone once applied.
    expect(await alice2.db.transfersDao.chunks(id), isEmpty);

    // The answer reaches the sender, which removes the relay objects.
    await alice2.engine.drainOutbox();
    await alice.engine.syncOnce();
    expect(world.relay.objects, isNotEmpty);
    await alice.engine.runMaintenance();
    expect(world.relay.objects, isEmpty);
    await Future<void>.delayed(Duration.zero);
    await s1.cancel();
    await s2.cancel();
    expect(
      sender,
      containsAllInOrder([TransferPhase.preparing, TransferPhase.offered]),
    );
    expect(
      receiver,
      containsAllInOrder([
        TransferPhase.downloading,
        TransferPhase.importing,
        TransferPhase.done,
      ]),
    );
  });

  test('the relay holds only ciphertext; the profile key travels, the '
      'identity key never does', () async {
    await start(messages: 4);
    // A device that signed in with a password has no profile key.
    final row = (await alice2.db.accountDao.current())!;
    await alice2.db.accountDao.save(
      SelfAccountCompanion.insert(
        accountId: row.accountId,
        deviceId: row.deviceId,
        serverDomain: row.serverDomain,
        registeredAt: row.registeredAt,
        profileKey: const Value(null),
      ),
    );
    expect((await alice2.db.accountDao.current())!.profileKey, isNull);

    final id = await offer();
    final text = [
      for (final o in world.relay.objects.values) String.fromCharCodes(o),
    ].join();
    expect(text, isNot(contains('transfer text')));
    expect(text, isNot(contains(alice.account)));
    await alice2.backup.acceptOffer(id);
    expect(
      (await alice2.db.accountDao.current())!.profileKey,
      (await alice.db.accountDao.current())!.profileKey,
    );
    // Never the account identity key: its seed is not in anything stored.
    final seed = (await alice.db.cryptoDao.identityKeys())!.aikPrivate;
    expect(
      [
        for (final o in world.relay.objects.values) o,
      ].any((o) => _contains(o, seed)),
      isFalse,
    );
  });

  test(
    'a gap is detected and only the missing segments are fetched again',
    () async {
      await start();
      final id = await offer();
      final ids = uploaded();
      world.relay.dropOnce.add(ids[2]);

      final e = await failureOf(alice2.backup.acceptOffer(id));
      expect(e.failure, BackupFailure.offline);
      final waiting = (await alice2.backup.offers()).single;
      expect(waiting.phase, TransferPhase.waiting);
      expect(waiting.failure, BackupFailure.offline);
      final missing = await alice2.db.transfersDao.missingSequences(id);
      expect(missing!.first, 2);
      expect(await alice2.db.transfersDao.assemble(id), isNull);
      expect(
        await HistoryStore(alice2.db).messageCount(),
        0,
        reason: 'a partial transfer is never applied',
      );

      final result = await alice2.backup.acceptOffer(id);
      expect(result.added, 60);
      expect(
        world.relay.downloads[ids[0]],
        1,
        reason: 'kept, not fetched again',
      );
      expect(world.relay.downloads[ids[1]], 1);
      expect(world.relay.downloads[ids[2]], 2);
      expect(await historyDigest(alice2), await historyDigest(alice));
    },
  );

  test('pausing mid-import keeps the chunks; the next run applies only what '
      'is left', () async {
    await start();
    final id = await offer();
    final segments = uploaded().length - 1;
    final sub = alice2.backup.transferProgress.listen((p) {
      if (p.phase == TransferPhase.importing && p.done == 2) {
        alice2.backup.pauseTransfer(id);
      }
    });
    final e = await failureOf(alice2.backup.acceptOffer(id));
    await sub.cancel();
    expect(e.failure, BackupFailure.cancelled);
    final paused = (await alice2.backup.offers()).single;
    expect(paused.phase, TransferPhase.waiting);
    final partial = await HistoryStore(alice2.db).messageCount();
    expect(partial, greaterThan(0));
    expect(partial, lessThan(60));
    final fetched = Map.of(world.relay.downloads);

    final result = await alice2.backup.acceptOffer(id);
    expect(result.added, 60 - partial);
    expect(world.relay.downloads, fetched, reason: 'nothing fetched again');
    expect(segments, greaterThan(2));
    expect(await historyDigest(alice2), await historyDigest(alice));
  });

  test('a tampered segment fails the whole offer, applies nothing and '
      'tells the sender', () async {
    await start();
    final id = await offer();
    final ids = uploaded();
    world.relay.tamper = (object, bytes) {
      if (object == ids[1]) bytes[bytes.length ~/ 2] ^= 1;
      return bytes;
    };
    final e = await failureOf(alice2.backup.acceptOffer(id));
    expect(e.failure, BackupFailure.corrupt);
    final failed = (await alice2.backup.offers()).single;
    expect(failed.phase, TransferPhase.failed);
    expect(failed.failure, BackupFailure.corrupt);
    expect(await alice2.db.transfersDao.chunks(id), isEmpty);
    expect(await HistoryStore(alice2.db).messageCount(), 0);

    await alice2.engine.drainOutbox();
    await alice.engine.syncOnce();
    await alice.engine.runMaintenance();
    expect(world.relay.objects, isEmpty, reason: 'the sender cleaned up');
  });

  test('a swapped segment (valid, but not the one the manifest names) is '
      'refused', () async {
    await start();
    final id = await offer();
    final ids = uploaded();
    final other = world.relay.objects[ids[0]]!;
    world.relay.tamper = (object, bytes) =>
        object == ids[1] ? Uint8List.fromList(other) : bytes;
    final e = await failureOf(alice2.backup.acceptOffer(id));
    expect(e.failure, BackupFailure.corrupt);
    expect(await HistoryStore(alice2.db).messageCount(), 0);
  });

  test('a segment the relay no longer has ends the offer as expired', () async {
    await start();
    final id = await offer();
    final ids = uploaded();
    world.relay.objects.remove(ids[1]);
    final e = await failureOf(alice2.backup.acceptOffer(id));
    expect(e.failure, BackupFailure.expired);
    expect((await alice2.backup.offers()).single.phase, TransferPhase.failed);
  });

  test('the sender withdraws an offer: the relay is emptied and the '
      'receiver drops it', () async {
    await start();
    final id = await offer();
    await alice.backup.cancelSend(id);
    expect(world.relay.objects, isEmpty);
    await alice.engine.drainOutbox();
    await alice2.engine.syncOnce();
    expect(
      (await alice2.backup.offers()).single.phase,
      TransferPhase.cancelled,
    );
    final e = await failureOf(alice2.backup.acceptOffer(id));
    expect(e.failure, BackupFailure.cancelled);
    expect(await HistoryStore(alice2.db).messageCount(), 0);
  });

  test('declining tells the sender, which cleans up', () async {
    await start(messages: 6);
    final id = await offer();
    await alice2.backup.declineOffer(id);
    expect((await alice2.backup.offers()).single.phase, TransferPhase.declined);
    await alice2.engine.drainOutbox();
    await alice.engine.syncOnce();
    await alice.engine.runMaintenance();
    expect(world.relay.objects, isEmpty);
    expect(await HistoryStore(alice2.db).messageCount(), 0);
  });

  test('accepting again after it was applied does nothing', () async {
    await start(messages: 6);
    final id = await offer();
    await alice2.backup.acceptOffer(id);
    final downloads = Map.of(world.relay.downloads);
    final again = await alice2.backup.acceptOffer(id);
    expect(again.added, 0);
    expect(world.relay.downloads, downloads);
  });

  test('history the device already has is merged, not duplicated', () async {
    await start(messages: 10);
    // Alice2 already received half of it directly.
    await alice2.db.conversationsDao.ensureDirect(
      bobId,
      now: DateTime.utc(2026, 1, 1),
    );
    final mine = await alice.db.messagesDao.pageOlder(
      directConversationId(bobId),
      limit: 100,
    );
    for (final m in mine.messages.take(5)) {
      await alice2.db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: m.messageId,
          conversationId: m.conversationId,
          sender: m.sender,
          outgoing: m.outgoing,
          sortKey: m.sortKey,
          sentAt: m.sentAt,
          receivedAt: m.receivedAt,
          kind: 'text',
          status: m.status,
          body: Value(m.body),
        ),
      );
    }
    final id = await offer();
    final result = await alice2.backup.acceptOffer(id);
    expect(result.added, 5);
    expect(result.existing, 5);
    expect(await historyDigest(alice2), await historyDigest(alice));
  });

  group('who may offer', () {
    test('only a device of the same account', () async {
      await start(messages: 3);
      final bob = await world.register('bob', phone: '+8801711000002');
      // Bob sends Alice2 something shaped like an offer.
      final manifest = MediaPointer(
        id: '44444444-4444-4444-8444-444444444444',
        key: Uint8List(32),
        digest: Uint8List(32),
        size: 100,
        mime: 'application/octet-stream',
      );
      await bob.engine.debugSend(
        ContentMessage(
          id: '0192a4f0-0000-7000-8000-00000000f001',
          sentAt: DateTime.utc(2026, 10, 2),
          conversation: DirectConversation(to: alice2.account),
          body: DeviceTransferOfferBody(
            transferId: 'forged',
            relayMedia: manifest,
          ),
        ),
        audience: [alice2.account],
      );
      await bob.engine.drainOutbox();
      await alice2.engine.syncOnce();
      expect(await alice2.backup.offers(), isEmpty);
    });

    test('an offer without a relay pointer, or an oversized one, is '
        'ignored', () async {
      await start(messages: 3);
      Future<void> send(String id, DeviceTransferOfferBody body) async {
        await alice.engine.debugSend(
          ContentMessage(
            id: id,
            sentAt: DateTime.utc(2026, 10, 2),
            conversation: DirectConversation(to: alice.account),
            body: body,
          ),
          audience: [alice.account],
          urgent: false,
        );
      }

      await send(
        '0192a4f0-0000-7000-8000-00000000f002',
        const DeviceTransferOfferBody(transferId: 'no-pointer'),
      );
      await send(
        '0192a4f0-0000-7000-8000-00000000f003',
        DeviceTransferOfferBody(
          transferId: 'huge',
          relayMedia: MediaPointer(
            id: '44444444-4444-4444-8444-444444444444',
            key: Uint8List(32),
            digest: Uint8List(32),
            size: 50 * 1024 * 1024,
            mime: 'application/octet-stream',
          ),
        ),
      );
      await alice.engine.drainOutbox();
      await alice2.engine.syncOnce();
      expect(await alice2.backup.offers(), isEmpty);
    });

    test('an offer aimed at other devices is not recorded', () async {
      await start(messages: 3);
      final alice3 = await world.link(alice, 'alice3');
      final id = await alice.backup.sendHistory(devices: [alice3.device]);
      await alice.engine.drainOutbox();
      await alice2.engine.syncOnce();
      await alice3.engine.syncOnce();
      expect(await alice2.backup.offers(), isEmpty);
      expect((await alice3.backup.offers()).single.transferId, id);
    });

    test(
      'a withdrawal counts only from the device that made the offer',
      () async {
        await start(messages: 3);
        final alice3 = await world.link(alice, 'alice3');
        final id = await alice.backup.sendHistory();
        await alice.engine.drainOutbox();
        await alice3.engine.syncOnce();
        await alice2.engine.syncOnce();
        // Alice3 (not the offerer) "cancels" the offer it also received.
        await alice3.engine.debugSend(
          ContentMessage(
            id: '0192a4f0-0000-7000-8000-00000000f004',
            sentAt: DateTime.utc(2026, 10, 2),
            conversation: DirectConversation(to: alice3.account),
            body: DeviceTransferOfferBody(
              transferId: id,
              state: DeviceTransferState.cancelled,
            ),
          ),
          audience: [alice3.account],
          urgent: false,
        );
        await alice3.engine.drainOutbox();
        await alice2.engine.syncOnce();
        expect(
          (await alice2.backup.offers()).single.phase,
          TransferPhase.waiting,
        );
      },
    );
  });

  test('with no other device there is nobody to send to', () async {
    world = BackupWorld();
    alice = await world.register('solo', phone: '+8801711000005');
    await addHistory(alice, bobId, 3);
    final e = await failureOf(alice.backup.sendHistory());
    expect(e.failure, BackupFailure.noOtherDevices);
    expect(world.relay.objects, isEmpty);
  });

  test('a failed upload removes what was already on the relay and sends no '
      'offer', () async {
    await start();
    world.relay.failUploadsAfter = 1;
    final e = await failureOf(alice.backup.sendHistory());
    expect(e.failure, BackupFailure.offline);
    expect(world.relay.objects, isEmpty);
    expect(world.relay.deleted, hasLength(1));
    await alice.engine.drainOutbox();
    await alice2.engine.syncOnce();
    expect(await alice2.backup.offers(), isEmpty);
  });
}

bool _contains(Uint8List haystack, Uint8List needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length && match; j++) {
      match = haystack[i + j] == needle[j];
    }
    if (match) return true;
  }
  return false;
}
