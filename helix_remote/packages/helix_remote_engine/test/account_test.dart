import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// Registration, linking, session renewal and sign-out, with the keys and
/// rows each leaves behind.
void main() {
  late Peers peers;

  setUp(() => peers = Peers());
  tearDown(() => peers.dispose());

  group('registration', () {
    test('a new database is signed out until it registers', () async {
      final peer = await peers.create('fresh');
      expect(peer.engine.status, EngineStatus.signedOut);
      expect(peer.engine.accountId, isNull);
      await expectLater(
        peer.engine.syncOnce(),
        throwsA(isA<NotSignedInException>()),
      );
    });

    test('registering stores the identity, prekeys and account, and '
        'publishes the same prekeys', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final row = (await alice.db.accountDao.current())!;
      expect(row.accountId, alice.account);
      expect(row.serverDomain, 'fake.helix.test');
      expect(row.phoneNumber, '+8801711000001');
      expect(row.profileKey, hasLength(32));

      final identity = (await alice.db.cryptoDao.identityKeys())!;
      expect(identity.deviceId, alice.device);
      // The certificate on the server verifies under the account key.
      final registered = peers.server.device(alice.device).registration;
      expect(
        await DeviceCertificates.isValid(
          accountIdentityKey: identity.aikPublic,
          device: DeviceAddress(alice.account, alice.device),
          identityKey: registered.identityKey,
          signingKey: registered.signingKey,
          certificate: registered.certificate,
        ),
        isTrue,
      );
      final signed = await alice.db.cryptoDao.prekeysOf(PrekeyKind.signed);
      final oneTime = await alice.db.cryptoDao.prekeysOf(PrekeyKind.oneTime);
      expect(signed, hasLength(1));
      expect(oneTime, hasLength(PrekeyPolicy.initialOneTimePrekeys));
      final server = peers.server.device(alice.device);
      expect(server.signedPrekey.id, signed.single.keyId);
      expect(server.oneTimePrekeys.length, oneTime.length);
      expect(
        server.oneTimePrekeys.map((k) => k.id).toSet(),
        oneTime.map((k) => k.keyId).toSet(),
      );
      // The session tokens live in the encrypted database, not in memory.
      expect(
        (await DbSessionTokenStore(alice.db).read())!.deviceId,
        alice.device,
      );
    });

    test(
      'an account that exists on this database cannot be registered over',
      () async {
        final alice = await peers.register('alice');
        await expectLater(
          alice.engine.account.register(verificationToken: 'verification'),
          throwsA(isA<EngineStateException>()),
        );
      },
    );

    test('private keys appear in no message the engine produces', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final identity = (await alice.db.cryptoDao.identityKeys())!;
      final secrets = [
        identity.aikPrivate,
        identity.dikPrivate,
        identity.dskPrivate,
      ];
      final bob = await peers.register('bob', phone: '+8801711000002');
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'x');
      await alice.engine.drainOutbox();
      final wire = peers.server.sends
          .map((s) => s.request.toJson().toString())
          .join();
      for (final secret in secrets) {
        expect(wire, isNot(contains(encodeBytes(secret))));
      }
    });
  });

  group('linking', () {
    test('a linked device gets the account key and profile key from the '
        'approving device', () async {
      final bob1 = await peers.register('bob1', phone: '+8801711000002');
      final bob2 = await peers.link(bob1, 'bob2');
      final id1 = (await bob1.db.cryptoDao.identityKeys())!;
      final id2 = (await bob2.db.cryptoDao.identityKeys())!;
      expect(id2.aikPublic, id1.aikPublic);
      expect(id2.aikPrivate, id1.aikPrivate);
      expect(id2.deviceId, isNot(id1.deviceId));
      expect(id2.dikPublic, isNot(id1.dikPublic));
      expect(
        (await bob2.db.accountDao.current())!.profileKey,
        (await bob1.db.accountDao.current())!.profileKey,
      );
      expect(peers.server.accounts[bob1.account]!.devices.keys.toSet(), {
        bob1.device,
        bob2.device,
      });
      // Other devices learn of it.
      await bob1.sync();
      expect(
        (await bob1.engine.devices.list()).map((d) => d.deviceId).toSet(),
        {bob1.device, bob2.device},
      );
    });

    test('a link code for another server is refused, a cancelled link '
        'ends', () async {
      final bob1 = await peers.register('bob1', phone: '+8801711000002');
      await expectLater(
        bob1.engine.devices.approveLink(
          LinkCode(
            serverOrigin: 'https://other.example',
            linkId: Uuid.v7(),
            ephemeralKey: Uint8List(32),
          ).encode(),
        ),
        throwsA(
          isA<SignInException>().having(
            (e) => e.reason,
            'reason',
            SignInFailure.badLinkCode,
          ),
        ),
      );
      await expectLater(
        bob1.engine.devices.approveLink('not a code'),
        throwsA(isA<SignInException>()),
      );

      final fresh = await peers.create('fresh');
      final link = await fresh.engine.account.beginLink();
      final waiting = link.complete(confirm: (_) async => true);
      link.cancel();
      await expectLater(
        waiting,
        throwsA(
          isA<SignInException>().having(
            (e) => e.reason,
            'reason',
            SignInFailure.linkExpired,
          ),
        ),
      );
      expect(fresh.engine.status, EngineStatus.signedOut);
    });
  });

  group('linking asks before it keeps anything', () {
    test(
      'the proposal shows the account; accepting registers the device',
      () async {
        final bob1 = await peers.register('bob', phone: '+8801711000002');
        await bob1.engine.settings.setHelixName('bobby');
        final fresh = await peers.create('fresh');
        final link = await fresh.engine.account.beginLink();
        final proposal = link.awaitApproval();
        await bob1.engine.devices.approveLink(link.code);
        final offered = await proposal;
        expect(offered.accountId, bob1.account);
        expect(offered.phoneMask, '+880********02');
        expect(offered.helixName, 'bobby');
        expect(offered.approverDeviceId, bob1.device);
        expect(offered.fingerprint, hasLength(24));
        expect(
          fresh.engine.status,
          EngineStatus.signedOut,
          reason: 'nothing is kept before the user says yes',
        );
        expect(await fresh.db.cryptoDao.identityKeys(), isNull);
        await offered.accept();
        expect(fresh.account, bob1.account);
      },
    );

    test('declining leaves the device empty, whoever approved', () async {
      final mallory = await peers.register('mallory', phone: '+8801711000009');
      final fresh = await peers.create('fresh');
      final link = await fresh.engine.account.beginLink();
      // Someone who saw the QR code approves it with an account of their own.
      final done = link.complete(
        confirm: (p) async {
          expect(p.accountId, mallory.account);
          return false;
        },
      );
      await mallory.engine.devices.approveLink(link.code);
      await expectLater(
        done,
        throwsA(
          isA<SignInException>().having(
            (e) => e.reason,
            'reason',
            SignInFailure.linkDeclined,
          ),
        ),
      );
      expect(fresh.engine.status, EngineStatus.signedOut);
      expect(await fresh.db.accountDao.current(), isNull);
      expect(await fresh.db.cryptoDao.identityKeys(), isNull);
    });
  });

  group('sessions', () {
    test('an expired session is renewed with the device key', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      peers.server.invalidateSession(alice.device);
      final devices = await alice.engine.devices.refresh();
      expect(devices.single.deviceId, alice.device);
      expect(peers.server.callsTo(Routes.deviceChallenge), 1);
      expect(peers.server.callsTo(Routes.deviceSignIn), 1);
      expect(alice.engine.status, EngineStatus.running);
      // The new session was stored.
      expect(
        (await DbSessionTokenStore(alice.db).read())!.accessToken,
        peers.server.device(alice.device).accessToken,
      );
    });

    test('a revoked device whose session ended wipes itself', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      peers.server
        ..invalidateSession(alice.device)
        ..revoke(alice.device);
      await expectLater(
        alice.engine.devices.refresh(),
        throwsA(isA<HelixApiException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(alice.engine.status, EngineStatus.revoked);
      expect(await alice.db.accountDao.current(), isNull);
    });

    test('revocation keeps the data when wiping is switched off', () async {
      final alice = await peers.register(
        'alice',
        phone: '+8801711000001',
        config: fastConfig.copyWith(wipeOnRevocation: false),
      );
      peers.server.revoke(alice.device);
      await expectLater(alice.engine.syncOnce(), throwsA(isA<ApiException>()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(alice.engine.status, EngineStatus.revoked);
      expect(await alice.db.accountDao.current(), isNotNull);
    });

    test('the hard-wipe hook runs once, after the rows are gone, on sign-out '
        'and on a revocation that wipes', () async {
      final calls = <String>[];
      late Peer alice;
      alice = await peers.register(
        'alice',
        phone: '+8801711000001',
        hardWipe: () async {
          // The host destroys the file and the key here: nothing is left to
          // read by then.
          calls.add(
            await alice.db.accountDao.current() == null ? 'empty' : 'rows',
          );
        },
      );
      await alice.engine.signOut();
      expect(calls, ['empty']);
      expect(alice.engine.status, EngineStatus.signedOut);

      final bob = await peers.register(
        'bob',
        phone: '+8801711000002',
        hardWipe: () async => calls.add('revoked'),
      );
      peers.server.revoke(bob.device);
      await expectLater(bob.engine.syncOnce(), throwsA(isA<ApiException>()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bob.engine.status, EngineStatus.revoked);
      expect(calls, ['empty', 'revoked']);
    });

    test('a failing hard-wipe hook still ends in the signed-out state, and the '
        'error reaches the caller', () async {
      final alice = await peers.register(
        'alice',
        phone: '+8801711000001',
        hardWipe: () async => throw StateError('keystore unavailable'),
      );
      await expectLater(alice.engine.signOut(), throwsStateError);
      expect(alice.engine.status, EngineStatus.signedOut);
      expect(await alice.db.accountDao.current(), isNull);
    });

    test(
      'signing out wipes everything and the database can be reused',
      () async {
        final alice = await peers.register('alice', phone: '+8801711000001');
        final bob = await peers.register('bob', phone: '+8801711000002');
        final chat = await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(chat.id, 'secret words');
        final accountId = alice.account;
        await alice.engine.signOut();
        expect(alice.engine.status, EngineStatus.signedOut);
        expect(await alice.db.accountDao.current(), isNull);
        expect(await alice.db.cryptoDao.identityKeys(), isNull);
        expect(await alice.db.messagesDao.search('secret'), isEmpty);
        expect(await alice.db.conversationsDao.byId(chat.id), isNull);
        expect(await alice.db.outboxDao.byId(1), isNull);
        expect(await DbSessionTokenStore(alice.db).read(), isNull);
        expect(
          peers.server.accounts[accountId]!.devices,
          isEmpty,
          reason: 'the device was removed from the account, not left behind',
        );
        // A new account can be registered on the same database.
        final challenge = await alice.engine.account.requestPhoneCode(
          '+8801711000009',
        );
        final verified = await alice.engine.account.verifyPhone(
          challenge.challengeId,
          '1',
        );
        await alice.engine.account.register(
          verificationToken: verified.verificationToken,
        );
        expect(alice.engine.status, EngineStatus.running);
      },
    );
  });
}
