import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart';

const carolNumber = '+8801711000003';
const daveNumber = '+8801711000004';

/// Key changes, lost session state (CRYPTO_V2.md §13a) and prekey upkeep,
/// end to end.
void main() {
  group('engine security', skip: databaseTestSkipReason, () {
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

    test('a changed identity key is pinned, announced in the chat and '
        'resets "verified"', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'hello');
      await waitForText(bob, alice, 'hello');

      // The takeover revokes (and wipes) Bob's old device.
      final bobAccount = bob.account;
      await alice.engine.people.setVerified(bobAccount, verified: true);
      final before = await alice.engine.people.safetyNumber(bobAccount);
      final firstKey = (await alice.db.peopleDao.byAccount(
        bobAccount,
      ))!.identityKey!;
      final changes = <KeyChangedEvent>[];
      alice.engine.events.listen((e) {
        if (e is KeyChangedEvent) changes.add(e);
      });

      // Someone takes over Bob's number with a brand new identity key.
      final newBob = await world.create('bob-new');
      final challenge = await newBob.engine.account.requestPhoneCode(bobNumber);
      final verified = await newBob.engine.account.verifyPhone(
        challenge.challengeId,
        h.sms.lastCodeFor(bobNumber),
      );
      expect(verified.accountExists, isTrue);
      await newBob.engine.account.register(
        verificationToken: verified.verificationToken,
        accountId: verified.accountId,
        replaceExisting: true,
        phoneNumber: bobNumber,
      );
      expect(newBob.account, bobAccount);

      await alice.engine.chats.sendText(chat.id, 'after the change');
      await waitForText(newBob, alice, 'after the change');

      final person = (await alice.db.peopleDao.byAccount(bobAccount))!;
      final newKey = (await newBob.db.cryptoDao.identityKeys())!.aikPublic;
      expect(person.identityKey, newKey);
      expect(person.identityKey, isNot(firstKey));
      expect(person.identityVerified, isFalse);
      expect(person.identityChangedAt, isNotNull);
      expect(changes, hasLength(1));
      final after = await alice.engine.people.safetyNumber(bobAccount);
      expect(after!.digits, isNot(before!.digits));
      // The chat says so.
      final notices = [
        for (final m in await messagesWith(alice, newBob))
          if (m.kind == 'system') m.payload,
      ];
      expect(notices.single, contains(MessageKinds.safetyNumberChanged));
      // Only the new device is trusted; the old one is gone.
      final devices = await alice.engine.people.devicesOf(bobAccount);
      expect(
        devices.where((d) => d.trust == DeviceTrust.trusted),
        hasLength(1),
      );
      expect(
        devices.where((d) => d.trust == DeviceTrust.trusted).single.deviceId,
        newBob.device,
      );
    });

    test('a contact known only from a group is announced in the group '
        'chat when its key changes', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final created = await alice.engine.groups.create(
        name: 'Weekend',
        members: [bob.account],
      );
      final chatId = 'group:${created.groupId}';
      final bobAccount = bob.account;
      await alice.engine.chats.sendText(chatId, 'hello group');
      await settle(() async {
        final rows = (await bob.db.messagesDao.pageOlder(chatId)).messages;
        expect(rows.any((m) => m.body == 'hello group'), isTrue);
      });
      expect(
        await alice.db.conversationsDao.byId(directConversationId(bobAccount)),
        isNull,
        reason: 'there is no direct chat with Bob',
      );

      final newBob = await world.create('bob-new');
      final challenge = await newBob.engine.account.requestPhoneCode(bobNumber);
      final verified = await newBob.engine.account.verifyPhone(
        challenge.challengeId,
        h.sms.lastCodeFor(bobNumber),
      );
      await newBob.engine.account.register(
        verificationToken: verified.verificationToken,
        accountId: verified.accountId,
        replaceExisting: true,
        phoneNumber: bobNumber,
      );
      await alice.engine.chats.sendText(chatId, 'after the change');
      await settle(() async {
        final notices = [
          for (final m in (await alice.db.messagesDao.pageOlder(
            chatId,
          )).messages)
            if (m.kind == 'system' &&
                (m.payload ?? '').contains(MessageKinds.safetyNumberChanged))
              m,
        ];
        expect(notices, hasLength(1));
        expect(notices.single.sender, bobAccount);
      });
    });

    test('lost session state: the message is shown as waiting, then '
        're-sent over a fresh session (CRYPTO_V2.md §13a)', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'm1');
      await waitForText(bob, alice, 'm1');
      await bob.engine.chats.sendText(
        directConversationId(alice.account),
        'm2',
      );
      await waitForText(alice, bob, 'm2');

      // Bob restores from a backup: sessions are never backed up.
      await bob.db.cryptoDao.deleteSessions(alice.account);
      final quarantined = <EnvelopeQuarantined>[];
      bob.engine.events.listen((e) {
        if (e is EnvelopeQuarantined) quarantined.add(e);
      });

      await alice.engine.chats.sendText(chat.id, 'm3 after restore');
      // The message arrives as a ratchet message for a session Bob no longer
      // has ('no_session'), or after Bob already started a new one for an
      // earlier envelope ('auth_failed'): either way a re-send is requested.
      await settle(() async => expect(quarantined, isNotEmpty));
      expect(
        quarantined.map((e) => e.code).toSet(),
        everyElement(anyOf('no_session', 'auth_failed')),
      );

      // The re-send arrives over the new session and replaces the
      // placeholder.
      await waitForText(bob, alice, 'm3 after restore');
      await settle(() async {
        final rows = await messagesWith(bob, alice);
        expect(
          rows.where((m) => m.kind == MessageKinds.undecryptable),
          isEmpty,
        );
        expect(rows.where((m) => m.body == 'm3 after restore'), hasLength(1));
      });
      // Both directions work again.
      await alice.engine.chats.sendText(chat.id, 'm4');
      await waitForText(bob, alice, 'm4');
      await bob.engine.chats.sendText(
        directConversationId(alice.account),
        'm5',
      );
      await waitForText(alice, bob, 'm5');
      expect(
        (await messagesWith(
          alice,
          bob,
        )).where((m) => m.body == 'm3 after restore'),
        hasLength(1),
      );
    });

    test('running low on one-time prekeys triggers a top-up', () async {
      final bob = await world.register(
        'bob',
        bobNumber,
        config: testEngineConfig.copyWith(initialOneTimePrekeys: 21),
      );
      expect((await bob.api.keys.status()).oneTimeRemaining, 21);
      final senders = [
        await world.register('alice', aliceNumber),
        await world.register('carol', carolNumber),
        await world.register('dave', daveNumber),
      ];
      for (final sender in senders) {
        final chat = await sender.engine.chats.openDirect(bob.account);
        await sender.engine.chats.sendText(chat.id, 'hi from ${sender.name}');
        await waitForText(bob, sender, 'hi from ${sender.name}');
      }
      // Three bundles were handed out (21 - 3 = 18 < 20): the server told
      // Bob, who generated and uploaded a batch.
      await settle(() async {
        final status = await bob.api.keys.status();
        expect(status.oneTimeRemaining, greaterThan(100));
      });
      final local = await bob.db.cryptoDao.prekeysOf(PrekeyKind.oneTime);
      expect(local.length, greaterThan(100));
      // Ids are never reused: the counter moved past the first 21.
      expect(local.map((k) => k.keyId).toSet().length, local.length);
    });

    test('signed prekeys rotate when due', () async {
      var now = DateTime.now().toUtc();
      final bob = await world.create(
        'bob',
        config: testEngineConfig,
        clock: () => now,
      );
      final challenge = await bob.engine.account.requestPhoneCode(bobNumber);
      final verified = await bob.engine.account.verifyPhone(
        challenge.challengeId,
        h.sms.lastCodeFor(bobNumber),
      );
      await bob.engine.account.register(
        verificationToken: verified.verificationToken,
        phoneNumber: bobNumber,
      );
      final first = await bob.db.cryptoDao.prekeysOf(PrekeyKind.signed);
      expect(first, hasLength(1));
      expect((await bob.api.keys.status()).signedPrekeyId, first.single.keyId);

      now = now.add(const Duration(days: 8));
      await bob.engine.runMaintenance();
      final rows = await bob.db.cryptoDao.prekeysOf(PrekeyKind.signed);
      expect(rows, hasLength(2));
      final current = rows.where((r) => r.retiredAt == null).single;
      expect(current.keyId, isNot(first.single.keyId));
      expect((await bob.api.keys.status()).signedPrekeyId, current.keyId);
      // The old private key stays for 30 days, then goes.
      now = now.add(const Duration(days: 31));
      await bob.engine.runMaintenance();
      final left = await bob.db.cryptoDao.prekeysOf(PrekeyKind.signed);
      expect(left.map((r) => r.keyId), isNot(contains(first.single.keyId)));
    });
    test('a stranger cannot pull messages of others with a re-send request; '
        'the chat peer can', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final carol = await world.register('carol', carolNumber);
      final secret = await alice.engine.chats.sendText(
        (await alice.engine.chats.openDirect(bob.account)).id,
        'for Bob only',
      );
      await waitForText(bob, alice, 'for Bob only');
      // Carol and Alice have a session (anyone can message anyone).
      await carol.engine.chats.sendText(
        (await carol.engine.chats.openDirect(alice.account)).id,
        'hi Alice',
      );
      await waitForText(alice, carol, 'hi Alice');

      Future<int> seq(EngineUser u) async =>
          (await u.db.inboxDao.cursor())?.lastProcessedSeq ?? 0;
      Future<void> ask(EngineUser from) => from.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: DateTime.now().toUtc(),
          conversation: DirectConversation(to: alice.account),
          body: ResendRequestBody(ids: [secret.messageId]),
        ),
        audience: [alice.account],
      );

      // Positive control: the chat peer's request is answered (Bob's
      // processed counter moves when the duplicate arrives).
      final bobBefore = await seq(bob);
      await ask(bob);
      await settle(() async => expect(await seq(bob), greaterThan(bobBefore)));

      // The stranger's is not: nothing reaches Carol, however long we wait.
      final carolBefore = await seq(carol);
      await ask(carol);
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(await seq(carol), carolBefore);
      expect(await carol.db.outboxDao.failed(), isEmpty);
    });
  });
  group(
    'engine account deletion and privacy',
    skip: databaseTestSkipReason,
    () {
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

      test('an account with a password proves it with the password, and only '
          'the right one deletes it', () async {
        final alice = await world.register(
          'alice',
          aliceNumber,
          password: 'correct horse battery staple',
        );
        await expectLater(
          alice.engine.deleteAccount(password: 'wrong password entirely'),
          throwsA(isA<ApiException>()),
        );
        expect(alice.engine.status, EngineStatus.running);
        await alice.engine.deleteAccount(
          password: 'correct horse battery staple',
        );
        expect(alice.engine.status, EngineStatus.signedOut);
        expect(await alice.db.accountDao.current(), isNull);
        // The account is gone on the server: nobody can sign in to it.
        final again = await world.create('alice-again');
        final challenge = await again.engine.account.requestPhoneCode(
          aliceNumber,
        );
        final verified = await again.engine.account.verifyPhone(
          challenge.challengeId,
          h.sms.lastCodeFor(aliceNumber),
        );
        expect(verified.accountExists, isFalse);
      });

      test('a texted account needs a fresh phone verification; a bare request '
          'is refused and the account survives', () async {
        final alice = await world.register('alice', aliceNumber);
        await expectLater(
          alice.engine.deleteAccount(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              ErrorCode.invalidCredentials,
            ),
          ),
        );
        expect(alice.engine.status, EngineStatus.running);
        final challenge = await alice.engine.account.requestPhoneCode(
          aliceNumber,
        );
        final verified = await alice.engine.account.verifyPhone(
          challenge.challengeId,
          h.sms.lastCodeFor(aliceNumber),
        );
        await alice.engine.deleteAccount(
          verificationToken: verified.verificationToken,
        );
        expect(alice.engine.status, EngineStatus.signedOut);
      });

      test('turning phone discovery back on sends the account number; a '
          'missing number is refused before anything is sent', () async {
        final alice = await world.register('alice', aliceNumber);
        await alice.engine.settings.setPrivacy(
          const PrivacySettings(discoverableByPhone: false),
        );
        expect(
          (await alice.engine.settings.privacy()).discoverableByPhone,
          isFalse,
        );
        await alice.engine.settings.setPrivacy(const PrivacySettings());
        expect(
          (await alice.engine.settings.privacy()).discoverableByPhone,
          isTrue,
        );
        // Another setting while discoverable needs no number.
        await alice.engine.settings.setPrivacy(
          const PrivacySettings(discoverableByName: false),
        );

        // A device that does not know the number cannot switch it back on.
        await alice.engine.settings.setPrivacy(
          const PrivacySettings(discoverableByPhone: false),
        );
        final row = (await alice.db.accountDao.current())!;
        await alice.db.accountDao.save(
          SelfAccountCompanion.insert(
            accountId: row.accountId,
            deviceId: row.deviceId,
            serverDomain: row.serverDomain,
            registeredAt: row.registeredAt,
            phoneNumber: const Value(null),
          ),
        );
        await expectLater(
          alice.engine.settings.setPrivacy(const PrivacySettings()),
          throwsArgumentError,
        );
        await alice.engine.settings.setPrivacy(
          const PrivacySettings(),
          phoneNumber: aliceNumber,
        );
        expect(
          (await alice.engine.settings.privacy()).discoverableByPhone,
          isTrue,
        );
      });
    },
  );

  group('device-key account deletion', skip: databaseTestSkipReason, () {
    late Harness h;
    late EngineWorld world;

    setUp(() async {
      h = await Harness.start(global: false);
      world = EngineWorld(h);
    });
    tearDown(() async {
      await world.dispose();
      await h.stop();
    });

    test('an account with no password and no number signs the deletion '
        'with its device key', () async {
      final invite = await h.identity.signUp.issueInvite(h.env.platform.db);
      final alice = await world.create('alice');
      await alice.engine.account.register(inviteCode: invite.code);
      expect(alice.engine.status, EngineStatus.running);
      await alice.engine.deleteAccount();
      expect(alice.engine.status, EngineStatus.signedOut);
      expect(await alice.db.accountDao.current(), isNull);
    });
  });
}
