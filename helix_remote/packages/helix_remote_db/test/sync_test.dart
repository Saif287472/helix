import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Outbox, envelope de-duplication, the mailbox cursor, deferred actions,
/// people and crypto persistence.
void main() {
  late HelixDb db;

  setUp(() => db = memoryDb());

  group('outbox', () {
    test('enqueue is idempotent and atomic with the optimistic row', () async {
      final chat = (await directChat(db, 'bob')).id;
      final op = await db.transaction(() async {
        final row = await db.messagesDao.insertMessage(
          textMessage(chat, 'm1', sentAt: at(1), sender: 'me', outgoing: true),
        );
        return db.outboxDao.enqueue(
          kind: 'send_message',
          idempotencyKey: 'm1',
          payload: '{}',
          conversationId: chat,
          messageRowid: row.localRowid,
          now: at(1),
        );
      });
      final again = await db.outboxDao.enqueue(
        kind: 'send_message',
        idempotencyKey: 'm1',
        payload: '{"other":true}',
        now: at(2),
      );
      expect(again.id, op.id);
      expect(again.payload, '{}');

      // Rolling back the transaction drops both.
      await expectLater(
        db.transaction(() async {
          final row = await db.messagesDao.insertMessage(
            textMessage(
              chat,
              'm2',
              sentAt: at(2),
              sender: 'me',
              outgoing: true,
            ),
          );
          await db.outboxDao.enqueue(
            kind: 'send_message',
            idempotencyKey: 'm2',
            payload: '{}',
            messageRowid: row.localRowid,
            now: at(2),
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await db.outboxDao.claimDue(at(10), leaseUntil: at(70)), [
        isA<OutboxOpRow>().having((o) => o.idempotencyKey, 'key', 'm1'),
      ]);
    });

    test(
      'claims due ops with a lease, reschedules, fails and recovers',
      () async {
        final outbox = db.outboxDao;
        final queued = collect(outbox.watchQueuedCount());
        for (final key in ['a', 'b', 'c']) {
          await outbox.enqueue(
            kind: 'send_receipt',
            idempotencyKey: key,
            payload: '{}',
            now: at(0),
          );
        }
        await eventually(() => queued.isNotEmpty && queued.last == 3);
        expect(await outbox.nextWakeAt(), at(0));

        final claimed = await outbox.claimDue(
          at(1),
          leaseUntil: at(31),
          limit: 2,
        );
        expect(claimed.map((o) => o.idempotencyKey), ['a', 'b']);
        expect(claimed.every((o) => o.state == OutboxState.inFlight), isTrue);
        expect(
          (await outbox.claimDue(
            at(2),
            leaseUntil: at(32),
          )).map((o) => o.idempotencyKey),
          ['c'],
        );
        expect(await outbox.claimDue(at(3), leaseUntil: at(33)), isEmpty);

        await outbox.complete(claimed[0].id);
        await outbox.reschedule(
          claimed[1].id,
          nextAttemptAt: at(60),
          errorCode: 'network',
        );
        await eventually(() => queued.last == 2);
        expect(await outbox.nextWakeAt(), at(32), reason: 'c lease expiry');

        // c's worker crashed: after its lease runs out it is due again.
        final recovered = await outbox.claimDue(at(40), leaseUntil: at(70));
        expect(recovered.single.idempotencyKey, 'c');
        await outbox.fail(recovered.single.id, errorCode: 'device_list_stale');
        await eventually(() => queued.last == 1);

        final retried = await outbox.claimDue(at(60), leaseUntil: at(90));
        expect(retried.single.idempotencyKey, 'b');
        expect(retried.single.attempts, 1);
        expect(retried.single.lastError, 'network');

        final failed = await outbox.failed();
        expect(failed.single.idempotencyKey, 'c');
        await outbox.retry(failed.single.id, now: at(100));
        await eventually(() => queued.last == 2);
      },
    );
  });

  group('inbox', () {
    test('processed envelopes de-duplicate by id and sender device', () async {
      final inbox = db.inboxDao;
      expect(
        await inbox.markProcessed(
          'env1',
          senderDevice: 'd1',
          seq: 7,
          outcome: EnvelopeOutcome.applied,
          at: at(1),
        ),
        isTrue,
      );
      expect(
        await inbox.markProcessed(
          'env1',
          senderDevice: 'd1',
          outcome: EnvelopeOutcome.applied,
          at: at(2),
        ),
        isFalse,
      );
      expect(await inbox.isProcessed('env1', senderDevice: 'd1'), isTrue);
      expect(await inbox.isProcessed('env1', senderDevice: 'd2'), isFalse);
      expect(
        await inbox.markProcessed(
          'env2',
          outcome: EnvelopeOutcome.quarantined,
          at: at(3),
        ),
        isTrue,
      );
      expect(await inbox.isProcessed('env2'), isTrue);

      expect(await inbox.pruneProcessed(at(3)), 1);
      expect(await inbox.isProcessed('env1', senderDevice: 'd1'), isFalse);
    });

    test('the cursor never moves backwards', () async {
      final inbox = db.inboxDao;
      expect(await inbox.cursor(), isNull);
      await inbox.advanceCursor(processedSeq: 10, now: at(1));
      await inbox.advanceCursor(processedSeq: 12, ackedSeq: 10, now: at(2));
      await inbox.advanceCursor(processedSeq: 5, ackedSeq: 3, now: at(3));
      final cursor = (await inbox.cursor())!;
      expect(cursor.lastProcessedSeq, 12);
      expect(cursor.lastAckedSeq, 10);
    });

    test('deferred actions wait for their target, then expire', () async {
      final inbox = db.inboxDao;
      DeferredActionsCompanion action(String target, int expiresIn) =>
          DeferredActionsCompanion.insert(
            targetMessageId: target,
            targetAuthor: 'bob',
            sender: 'carol',
            kind: 'reaction',
            payload: '{}',
            receivedAt: at(0),
            expiresAt: at(expiresIn),
          );
      await inbox.deferAction(action('m1', 100));
      await inbox.deferAction(action('m1', 100));
      await inbox.deferAction(action('m2', 10));

      expect(await inbox.takeDeferred('m1', author: 'alice'), isEmpty);
      expect(await inbox.takeDeferred('m1', author: 'bob'), hasLength(2));
      expect(await inbox.takeDeferred('m1', author: 'bob'), isEmpty);
      expect(await inbox.purgeExpiredDeferred(at(10)), 1);
      expect(await inbox.takeDeferred('m2', author: 'bob'), isEmpty);
    });
  });

  test(
    'people: upsert keeps columns, search, blocks and device trust',
    () async {
      final people = db.peopleDao;
      await people.upsertPerson(
        PeopleCompanion.insert(
          accountId: 'bob',
          phonebookName: const Value('Bob Builder'),
          updatedAt: at(1),
        ),
      );
      await people.upsertPerson(
        PeopleCompanion.insert(
          accountId: 'bob',
          helixName: const Value('bob_100%'),
          updatedAt: at(2),
        ),
      );
      final bob = (await people.byAccount('bob'))!;
      expect(bob.phonebookName, 'Bob Builder');
      expect(bob.helixName, 'bob_100%');

      expect((await people.search('build')).single.accountId, 'bob');
      expect((await people.search('100%')).single.accountId, 'bob');
      expect(await people.search('_1'), isNotEmpty);
      expect(await people.search('x%'), isEmpty, reason: '% is literal');

      await people.setBlocked('bob', true, now: at(3));
      expect(await people.blockedAccounts(), ['bob']);
      expect(await people.search('build'), isEmpty);
      expect((await people.byAccount('bob'))!.phonebookName, 'Bob Builder');

      await people.upsertDevice(
        PersonDevicesCompanion.insert(
          accountId: 'bob',
          deviceId: 'd1',
          identityKey: Uint8List(32),
          signingKey: Uint8List(32),
          trust: DeviceTrust.trusted,
          firstSeenAt: at(1),
          updatedAt: at(1),
        ),
      );
      expect(await people.devicesOf('bob'), hasLength(1));
      await people.markDevicesStale('bob');
      expect(await people.devicesOf('bob'), isEmpty);
      expect(await people.devicesOf('bob', includeStale: true), hasLength(1));
    },
  );

  test(
    'crypto: identity, sessions per device pair, prekeys, sender keys',
    () async {
      final crypto = db.cryptoDao;
      final k = Uint8List.fromList(List.filled(32, 7));
      await crypto.saveIdentity(
        IdentityCompanion.insert(
          id: const Value(99),
          accountId: 'me',
          deviceId: 'd0',
          aikPublic: k,
          aikPrivate: k,
          dikPublic: k,
          dikPrivate: k,
          dskPublic: k,
          dskPrivate: k,
          deviceCertificate: k,
          createdAt: at(0),
        ),
      );
      expect((await crypto.identityKeys())!.id, 1);

      final s = [
        for (var i = 0; i < 3; i++) Uint8List.fromList([i]),
      ];
      await crypto.saveSessions('bob', 'd1', s, now: at(1));
      await crypto.saveSessions('bob', 'd2', [s[0]], now: at(1));
      await crypto.saveSessions('bob', 'd1', [s[2], s[0]], now: at(2));
      final d1 = await crypto.sessionsWith('bob', 'd1');
      expect(d1.map((r) => r.state.single), [2, 0]);
      expect(d1.first.createdAt, at(1));
      expect(d1.first.updatedAt, at(2));
      expect(
        () => crypto.saveSessions('bob', 'd1', List.filled(7, k), now: at(3)),
        throwsArgumentError,
      );
      await crypto.deleteSessions('bob', device: 'd1');
      expect(await crypto.sessionsWith('bob', 'd1'), isEmpty);
      expect(await crypto.sessionsWith('bob', 'd2'), hasLength(1));

      await crypto.savePrekeys([
        for (var id = 1; id <= 3; id++)
          PrekeysCompanion.insert(
            kind: PrekeyKind.oneTime,
            keyId: id,
            publicKey: k,
            privateKey: k,
            createdAt: at(0),
          ),
        PrekeysCompanion.insert(
          kind: PrekeyKind.signed,
          keyId: 1,
          publicKey: k,
          privateKey: k,
          signature: Value(k),
          createdAt: at(0),
        ),
      ]);
      expect(await crypto.prekeysOf(PrekeyKind.oneTime), hasLength(3));
      await crypto.deletePrekey(PrekeyKind.oneTime, 2);
      expect(await crypto.prekey(PrekeyKind.oneTime, 2), isNull);
      await crypto.retireSignedPrekey(1, at(10));
      expect(await crypto.deleteRetiredBefore(at(10)), 0);
      expect(await crypto.deleteRetiredBefore(at(11)), 1);
      expect(await crypto.prekeysOf(PrekeyKind.oneTime), hasLength(2));

      await crypto.saveSenderKey(
        SenderKeysCompanion.insert(
          groupId: 'g1',
          accountId: 'bob',
          deviceId: 'd1',
          distId: 'dist1',
          state: k,
          createdAt: at(0),
          updatedAt: at(0),
        ),
      );
      expect(
        await crypto.senderKey(
          groupId: 'g1',
          account: 'bob',
          device: 'd1',
          distId: 'dist1',
        ),
        isNotNull,
      );
      await crypto.deleteSenderKeys('g1', account: 'bob');
      expect(
        await crypto.senderKey(
          groupId: 'g1',
          account: 'bob',
          device: 'd1',
          distId: 'dist1',
        ),
        isNull,
      );
    },
  );

  test('account: one self row and the device list', () async {
    final account = db.accountDao;
    await account.save(
      SelfAccountCompanion.insert(
        id: const Value(5),
        accountId: 'me',
        deviceId: 'd0',
        serverDomain: 'helix.example.org',
        registeredAt: at(0),
      ),
    );
    await account.save(
      SelfAccountCompanion.insert(
        id: const Value(1),
        accountId: 'me',
        deviceId: 'd0',
        serverDomain: 'helix.example.org',
        helixName: const Value('me'),
        registeredAt: at(0),
      ),
    );
    expect((await account.current())!.helixName, 'me');
    await expectLater(
      db.customStatement(
        "INSERT INTO self_account (id, account_id, device_id, server_domain, "
        "registered_at) VALUES (2, 'x', 'y', 'z', 0)",
      ),
      throwsA(anything),
      reason: 'CHECK (id = 1)',
    );

    await account.replaceDevices([
      SelfDevicesCompanion.insert(
        deviceId: 'd0',
        isThisDevice: const Value(true),
      ),
      SelfDevicesCompanion.insert(deviceId: 'd1', lastActiveAt: Value(at(5))),
    ]);
    await account.replaceDevices([
      SelfDevicesCompanion.insert(
        deviceId: 'd0',
        isThisDevice: const Value(true),
      ),
    ]);
    expect((await account.devices()).single.deviceId, 'd0');
  });
}
