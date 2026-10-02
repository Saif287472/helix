import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
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
  });
}
