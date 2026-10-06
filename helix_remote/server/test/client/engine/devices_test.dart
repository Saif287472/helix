import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart';

/// Linked devices, offline delivery, revocation and stale device lists with
/// real engines on the in-process server.
void main() {
  group('engine devices', skip: databaseTestSkipReason, () {
    late Harness h;
    late EngineWorld world;

    setUp(() async {
      h = await Harness.start();
      world = EngineWorld(h);
    });
    tearDown(() async {
      await world.dispose();
      await h.stop();
    });

    test('a linked second device receives, decrypts and syncs state', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob1 = await world.register('bob1', bobNumber);
      final bob2 = await world.link(bob1, 'bob2');
      // Both learn the new device list (an envelope for the old device, a
      // refresh after sign-in for the new one).
      await settle(() async {
        expect((await bob1.engine.devices.list()).length, 2);
        expect((await bob2.engine.devices.list()).length, 2);
      });

      final chat = await alice.engine.chats.openDirect(bob1.account);
      await alice.engine.chats.sendText(chat.id, 'to both');
      final on1 = await waitForText(bob1, alice, 'to both');
      final on2 = await waitForText(bob2, alice, 'to both');

      // Bob's first device replies; the second sees its own sent message.
      await bob1.engine.chats.sendText(
        directConversationId(alice.account),
        'from bob1',
      );
      await waitForText(alice, bob1, 'from bob1');
      final copy = await waitForText(bob2, alice, 'from bob1');
      expect(copy.outgoing, isTrue);
      expect(copy.sender, bob1.account);
      // Alice's delivered receipt reaches every device of Bob.
      expect(copy.status, anyOf(MessageStatus.sent, MessageStatus.delivered));

      // Reading on one device clears "unread" on the other.
      expect((await chatWith(bob2, alice))!.unreadCount, 1);
      await bob1.engine.chats.markRead(directConversationId(alice.account));
      await settle(() async {
        expect((await chatWith(bob2, alice))!.unreadCount, 0);
        final row = await bob2.db.messagesDao.byRowid(on2.localRowid);
        expect(row!.status, MessageStatus.read);
      });

      // Reactions made on one device show on the other and at the peer.
      await bob2.engine.chats.react(on2.localRowid, 'A');
      await settle(() async {
        final onBob1 = await bob1.db.messagesDao.reactionsFor([on1.localRowid]);
        expect(onBob1.single.emoji, 'A');
        final atAlice = await alice.db.messagesDao.reactionsFor([
          (await messagesWith(alice, bob1)).first.localRowid,
        ]);
        expect(atAlice.single.reactor, bob1.account);
      });
    });

    test('offline delivery: the mailbox keeps messages, a headless run '
        'catches up and sends the receipts', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber, realtime: false);
      await bob.engine.stop();

      final chat = await alice.engine.chats.openDirect(bob.account);
      final sent = [
        for (var i = 0; i < 3; i++)
          await alice.engine.chats.sendText(chat.id, 'while away $i'),
      ];
      await settle(() async {
        for (final m in sent) {
          final row = await alice.db.messagesDao.byRowid(m.localRowid);
          expect(row!.status, MessageStatus.sent);
        }
      });
      expect((await bob.api.messaging.mailbox()).envelopes, hasLength(3));

      // The FCM-isolate path: no socket, no timers, just one run.
      await bob.engine.start(realtime: false, background: false);
      final summary = await bob.engine.syncOnce();
      expect(summary.complete, isTrue);
      expect(summary.processed, 3);
      expect(summary.notices.map((n) => n.preview), [
        'while away 0',
        'while away 1',
        'while away 2',
      ]);
      expect((await chatWith(bob, alice))!.unreadCount, 3);
      expect((await bob.api.messaging.mailbox()).envelopes, isEmpty);

      // Running it again changes nothing.
      expect((await bob.engine.syncOnce()).processed, 0);

      // The delivered receipts left during that run.
      await settle(() async {
        for (final m in sent) {
          final row = await alice.db.messagesDao.byRowid(m.localRowid);
          expect(row!.status, MessageStatus.delivered);
        }
      });
    });

    test('coming back online replays what the socket missed', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'one');
      await waitForText(bob, alice, 'one');

      await bob.engine.stop();
      await alice.engine.chats.sendText(chat.id, 'two');
      await alice.engine.chats.sendText(chat.id, 'three');
      await settle(
        () async =>
            expect((await bob.api.messaging.mailbox()).envelopes, hasLength(2)),
      );
      await bob.engine.start();
      await waitForText(bob, alice, 'two');
      await waitForText(bob, alice, 'three');
      final texts = [for (final m in await messagesWith(bob, alice)) m.body];
      expect(texts, ['one', 'two', 'three']);
    });

    test(
      'revoking a device wipes it and drops it from the peer\'s lists',
      () async {
        final alice = await world.register('alice', aliceNumber);
        final bob1 = await world.register('bob1', bobNumber);
        final bob2 = await world.link(bob1, 'bob2');
        final chat = await alice.engine.chats.openDirect(bob1.account);
        await alice.engine.chats.sendText(chat.id, 'both');
        await waitForText(bob2, alice, 'both');

        final revoked = bob2.engine.statuses.firstWhere(
          (s) => s == EngineStatus.revoked,
        );
        await bob1.engine.devices.revoke(bob2.device);
        await revoked.timeout(const Duration(seconds: 15));
        expect(await bob2.db.accountDao.current(), isNull);
        expect(await bob2.db.cryptoDao.identityKeys(), isNull);
        expect(bob2.engine.accountId, isNull);
        expect((await bob1.engine.devices.list()).length, 1);

        // Alice still lists two devices for Bob; the server says one is
        // gone, she rebuilds the list and the message reaches Bob's device.
        await alice.engine.chats.sendText(chat.id, 'after revoke');
        await waitForText(bob1, alice, 'after revoke');
        final devices = await alice.db.peopleDao.devicesOf(bob1.account);
        expect(devices.map((d) => d.deviceId), [bob1.device]);
      },
    );

    test(
      'a device linked mid-conversation is added after device_list_stale',
      () async {
        final alice = await world.register('alice', aliceNumber);
        final bob1 = await world.register('bob1', bobNumber);
        final chat = await alice.engine.chats.openDirect(bob1.account);
        await alice.engine.chats.sendText(chat.id, 'before link');
        await waitForText(bob1, alice, 'before link');
        expect(
          (await alice.db.peopleDao.devicesOf(bob1.account)).length,
          1,
          reason: 'Alice has cached exactly one device for Bob',
        );

        final bob2 = await world.link(bob1, 'bob2');
        await alice.engine.chats.sendText(chat.id, 'after link');
        await waitForText(bob1, alice, 'after link');
        await waitForText(bob2, alice, 'after link');
        expect((await alice.db.peopleDao.devicesOf(bob1.account)).length, 2);
        // Bob's new device started a session of its own with Alice.
        await bob2.engine.chats.sendText(
          directConversationId(alice.account),
          'hello from bob2',
        );
        await waitForText(alice, bob2, 'hello from bob2');
      },
    );

    test('this account\'s own sends reach a device linked later', () async {
      final alice1 = await world.register('alice1', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final chat = await alice1.engine.chats.openDirect(bob.account);
      await alice1.engine.chats.sendText(chat.id, 'solo');
      await waitForText(bob, alice1, 'solo');

      final alice2 = await world.link(alice1, 'alice2');
      await settle(() async {
        expect((await alice1.engine.devices.list()).length, 2);
      });
      await alice1.engine.chats.sendText(chat.id, 'synced');
      final copy = await waitForText(alice2, bob, 'synced');
      expect(copy.outgoing, isTrue);
    });

    test('password sign-in adds a device without another device', () async {
      final alice = await world.register(
        'alice',
        aliceNumber,
        password: 'correct horse battery staple',
      );
      final second = await world.create('alice2');
      await expectLater(
        second.engine.account.signInWithPassword(
          phoneNumber: aliceNumber,
          password: 'wrong password',
        ),
        throwsA(isA<Object>()),
      );
      await second.engine.account.signInWithPassword(
        phoneNumber: aliceNumber,
        password: 'correct horse battery staple',
        deviceName: 'Laptop',
      );
      expect(second.account, alice.account);
      expect(second.device, isNot(alice.device));
      await settle(() async {
        final names = [
          for (final d in await second.engine.devices.refresh()) d.name,
        ];
        expect(names, containsAll(['Test device', 'Laptop']));
      });
      // The new device has the account's identity key, so it can certify
      // devices and talk to people.
      final bob = await world.register('bob', bobNumber);
      final chat = await second.engine.chats.openDirect(bob.account);
      await second.engine.chats.sendText(chat.id, 'from the laptop');
      await waitForText(bob, second, 'from the laptop');
    });

    test('changing the password needs the current one, and the new one '
        'signs in on another device', () async {
      final alice = await world.register(
        'alice',
        aliceNumber,
        password: 'correct horse battery staple',
      );
      // A wrong current password is refused and nothing changes.
      await expectLater(
        alice.engine.account.changePassword(
          newPassword: 'a brand new passphrase here',
          currentPassword: 'not the password',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ErrorCode.invalidCredentials,
          ),
        ),
      );
      await alice.engine.account.changePassword(
        newPassword: 'a brand new passphrase here',
        currentPassword: 'correct horse battery staple',
      );

      final second = await world.create('alice2');
      await expectLater(
        second.engine.account.signInWithPassword(
          phoneNumber: aliceNumber,
          password: 'correct horse battery staple',
        ),
        throwsA(isA<Object>()),
      );
      final third = await world.create('alice3');
      await third.engine.account.signInWithPassword(
        phoneNumber: aliceNumber,
        password: 'a brand new passphrase here',
      );
      expect(third.account, alice.account);
    });

    test('device management: rename, security events, push token, revoke '
        'all others', () async {
      final bob1 = await world.register('bob1', bobNumber);
      final bob2 = await world.link(bob1, 'bob2');
      await settle(() async {
        expect((await bob1.engine.devices.refresh()).length, 2);
      });
      await bob1.engine.devices.rename(bob2.device, 'Bob laptop');
      final names = {
        for (final d in await bob1.engine.devices.list()) d.deviceId: d.name,
      };
      expect(names[bob2.device], 'Bob laptop');
      await bob1.engine.push.register('fcm-test-token');
      await bob1.engine.push.unregister();
      final events = await bob1.engine.devices.securityEvents();
      expect(events, isNotEmpty);

      expect(
        () => bob1.engine.devices.revoke(bob1.device),
        throwsA(isA<EngineStateException>()),
        reason: 'revoking this device is signing out',
      );
      final revoked = bob2.engine.statuses.firstWhere(
        (s) => s == EngineStatus.revoked,
      );
      expect(await bob1.engine.devices.revokeOthers(), 1);
      await revoked.timeout(const Duration(seconds: 15));
      expect(await bob2.db.accountDao.current(), isNull);
      expect((await bob1.engine.devices.list()).length, 1);
    });

    test('signing out ends the session and wipes the database', () async {
      final alice = await world.register('alice', aliceNumber);
      await alice.engine.signOut();
      expect(alice.engine.status, EngineStatus.signedOut);
      expect(await alice.db.accountDao.current(), isNull);
      expect(await alice.api.auth.current(), isNull);
      final other = await world.register('alice-again', bobNumber);
      expect(other.engine.status, EngineStatus.running);
    });
  });
}
