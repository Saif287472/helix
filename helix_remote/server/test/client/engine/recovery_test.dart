import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart';

/// Account recovery with a recovery code on a fresh device, through the real
/// in-process server: lookup, phone verification, redeem under a new
/// identity key, every old device signed out, contacts told.
void main() {
  group('engine account recovery', skip: databaseTestSkipReason, () {
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

    /// What an operator does in the admin console.
    Future<String> issueCode(String accountId) async =>
        (await h.env.platform.db.tx(
          (tx) => h.identity.registration.issueRecoveryCode(tx, accountId),
        )).code;

    test('a full recovery-code redeem on a fresh device', () async {
      final alice1 = await world.register('alice1', aliceNumber);
      final alice2 = await world.link(alice1, 'alice2');
      final bob = await world.register('bob', bobNumber);
      final oldKey = (await alice1.db.cryptoDao.identityKeys())!.aikPublic;
      // The old devices forget their ids when revoked.
      final aliceId = alice1.account;
      final oldDevices = {alice1.device, alice2.device};

      // Alice and Bob know each other: Bob pins Alice's identity key.
      final chat = await alice1.engine.chats.openDirect(bob.account);
      await alice1.engine.chats.sendText(chat.id, 'before recovery');
      await waitForText(bob, alice1, 'before recovery');
      final pinned = (await bob.db.peopleDao.byAccount(aliceId))!.identityKey;
      expect(pinned, oldKey);
      final changes = <KeyChangedEvent>[];
      bob.engine.events.listen((e) {
        if (e is KeyChangedEvent) changes.add(e);
      });

      // Alice lost every device. The operator gives her a code.
      final code = await issueCode(aliceId);
      final fresh = await world.create('alice3');
      final account = fresh.engine.account;

      // The lookup names the account to a holder of the code.
      final lookup = await account.lookupRecoveryCode(code);
      expect(lookup.valid, isTrue);
      expect(lookup.verificationRequired, isTrue);
      expect(lookup.accountId, aliceId);
      // A code that does not exist is no oracle.
      final wrong = await account.lookupRecoveryCode('rec_not-a-real-code');
      expect(wrong.valid, isFalse);
      expect(wrong.accountId, isNull);
      expect(wrong.verificationRequired, isFalse);

      // The server has SMS: the phone must be verified first.
      await expectLater(
        account.recoverWithCode(recoveryCode: code),
        throwsA(
          isA<SignInException>().having(
            (e) => e.reason,
            'reason',
            SignInFailure.verificationRequired,
          ),
        ),
      );
      final challenge = await account.requestPhoneCode(
        aliceNumber,
        purpose: PhonePurpose.recover,
      );
      final verified = await account.verifyPhone(
        challenge.challengeId,
        h.sms.lastCodeFor(aliceNumber),
      );
      await account.recoverWithCode(
        recoveryCode: code,
        verificationToken: verified.verificationToken,
        phoneNumber: aliceNumber,
      );

      // Same account, new identity key, new device.
      expect(fresh.engine.status, EngineStatus.running);
      expect(fresh.account, aliceId);
      expect(oldDevices, isNot(contains(fresh.device)));
      final newKey = (await fresh.db.cryptoDao.identityKeys())!.aikPublic;
      expect(newKey, isNot(oldKey));
      final info = await fresh.api.identity.account();
      expect(info.identityKey, newKey);
      expect(info.accountId, aliceId);
      expect((await fresh.engine.devices.list()).map((d) => d.deviceId), [
        fresh.device,
      ]);

      // Every old device was signed out, and wiped itself.
      for (final old in [alice1, alice2]) {
        await settle(() async {
          expect(old.engine.status, EngineStatus.revoked, reason: old.name);
        });
        expect(await old.db.accountDao.current(), isNull);
        expect(await old.db.cryptoDao.identityKeys(), isNull);
      }

      // The code was single-use.
      final other = await world.create('alice4');
      final reuse = await other.engine.account.lookupRecoveryCode(code);
      expect(reuse.valid, isFalse);
      await expectLater(
        other.engine.account.recoverWithCode(recoveryCode: code),
        throwsA(
          isA<SignInException>().having(
            (e) => e.reason,
            'reason',
            SignInFailure.invalidRecoveryCode,
          ),
        ),
      );
      expect(await other.db.accountDao.current(), isNull);

      // Messages work both ways over fresh sessions, and Bob is told that
      // Alice's key changed.
      await fresh.engine.chats.openDirect(bob.account);
      await fresh.engine.chats.sendText(
        directConversationId(bob.account),
        'after recovery',
      );
      await waitForText(bob, fresh, 'after recovery');
      final person = (await bob.db.peopleDao.byAccount(aliceId))!;
      expect(person.identityKey, newKey);
      expect(person.identityKey, isNot(oldKey));
      expect(changes, hasLength(1));
      final notices = [
        for (final m in await messagesWith(bob, fresh))
          if (m.kind == 'system') m.payload,
      ];
      expect(notices.single, contains(MessageKinds.safetyNumberChanged));

      await bob.engine.chats.sendText(
        directConversationId(aliceId),
        'welcome back',
      );
      await waitForText(fresh, bob, 'welcome back');
    });

    test('a recovery with a new password: the password signs in afterwards, '
        'the old one is gone', () async {
      final alice1 = await world.register(
        'alice1',
        aliceNumber,
        password: 'the old password 123',
      );
      final aliceId = alice1.account;
      final code = await issueCode(aliceId);
      final fresh = await world.create('alice2');
      final challenge = await fresh.engine.account.requestPhoneCode(
        aliceNumber,
        purpose: PhonePurpose.recover,
      );
      final verified = await fresh.engine.account.verifyPhone(
        challenge.challengeId,
        h.sms.lastCodeFor(aliceNumber),
      );
      await fresh.engine.account.recoverWithCode(
        recoveryCode: code,
        verificationToken: verified.verificationToken,
        password: 'a brand new password 456',
        phoneNumber: aliceNumber,
      );
      expect(fresh.engine.status, EngineStatus.running);

      // Another device signs in with the NEW password and gets the NEW key.
      final next = await world.create('alice3');
      await next.engine.account.signInWithPassword(
        phoneNumber: aliceNumber,
        password: 'a brand new password 456',
      );
      expect(next.account, aliceId);
      expect(
        (await next.db.cryptoDao.identityKeys())!.aikPublic,
        (await fresh.db.cryptoDao.identityKeys())!.aikPublic,
      );
      // The old password no longer opens anything.
      final stale = await world.create('alice4');
      await expectLater(
        stale.engine.account.signInWithPassword(
          phoneNumber: aliceNumber,
          password: 'the old password 123',
        ),
        throwsA(anything),
      );
    });
  });
}
