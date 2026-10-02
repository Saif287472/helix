import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

const adminPassword = 'correct horse battery staple';

/// The v2 client package (`helix_remote_api`, Phase C3a) against a real
/// in-process server: the same flows the engine will drive.
void main() {
  group('helix_remote_api v2', skip: databaseTestSkipReason, () {
    late Harness h;
    final apis = <HelixApi>[];

    setUp(
      () async => h = await Harness.start(
        extra: {'HELIX_ADMIN_PASSWORD': adminPassword},
      ),
    );
    tearDown(() async {
      for (final api in apis) {
        await api.close();
      }
      apis.clear();
      await h.stop();
    });

    HelixApi client([MemorySessionStore? store]) {
      final api = HelixApi(
        baseUrl: h.server.baseUri,
        sessions: store ?? MemorySessionStore(),
        clientName: 'cli/test',
      );
      apis.add(api);
      return api;
    }

    /// Registers [number] through the clients and stores the session.
    Future<(HelixApi, TestDevice)> register(String number) async {
      final api = client();
      final challenge = await api.identity.phoneChallenge(
        PhoneChallengeRequest(
          phoneNumber: number,
          purpose: PhonePurpose.register,
        ),
      );
      final verified = await api.identity.phoneVerify(
        PhoneVerifyRequest(
          challengeId: challenge.challengeId,
          code: h.sms.lastCodeFor(number),
        ),
      );
      final account = await TestAccount.create();
      final keys = await account.newDevice();
      final registered = await api.identity.register(
        RegisterRequest(
          accountId: account.id,
          identityKey: account.publicKey,
          device: await keys.registration(),
          prekeys: await keys.prekeys(oneTime: 5),
          verificationToken: verified.verificationToken,
          termsVersion: HelixLegalDocuments.termsVersion,
        ),
      );
      await api.auth.signedIn(registered.session);
      keys.session = registered.session;
      return (api, keys);
    }

    /// A second device on [first]'s account through password sign-in.
    Future<(HelixApi, TestDevice)> secondDevice(
      HelixApi first,
      TestDevice firstKeys,
      String number,
    ) async {
      final pw = PasswordSetup(
        kdf: const KdfParams(),
        salt: bytes(16),
        authKey: bytes(32, 9),
        wrappedIdentityKey: WrappedKey(nonce: bytes(12), ciphertext: bytes(48)),
      );
      await first.identity.setPassword(SetPasswordRequest(password: pw));
      final api = client();
      final step1 = await api.identity.passwordSignIn(
        PasswordSignInRequest(phoneNumber: number, authKey: pw.authKey),
      );
      final keys = await firstKeys.account.newDevice(name: 'Second');
      final session = await api.identity.addDevice(
        AddDeviceRequest(
          device: await keys.registration(),
          prekeys: await keys.prekeys(),
          signInToken: step1.signInToken,
        ),
      );
      await api.auth.signedIn(session);
      keys.session = session;
      return (api, keys);
    }

    Future<RealtimeState> reach(RealtimeClient rt, RealtimePhase phase) =>
        rt.state.phase == phase
        ? Future.value(rt.state)
        : rt.states
              .firstWhere((s) => s.phase == phase)
              .timeout(const Duration(seconds: 10));

    test('registers a device and reads its account', () async {
      final (alice, keys) = await register(aliceNumber);
      final account = await alice.identity.account();
      expect(account.accountId, keys.accountId);
      final devices = await alice.identity.devices();
      expect(devices.devices.single.deviceId, keys.id);
      expect(devices.devices.single.current, isTrue);
      expect((await alice.ops.serverInfo()).name, isNotEmpty);
    });

    test('uploads prekeys and hands out a bundle', () async {
      final (alice, aliceKeys) = await register(aliceNumber);
      final (bob, _) = await register(bobNumber);
      expect((await alice.keys.status()).oneTimeRemaining, 5);
      await alice.keys.setSignedPrekey(await aliceKeys.signedPrekey());
      final status = await alice.keys.addOneTimePrekeys(
        await aliceKeys.oneTimePrekeys(10),
      );
      expect(status.oneTimeRemaining, 15);

      final bundle = await bob.keys.accountKeys(aliceKeys.accountId);
      expect(bundle.identityKey, aliceKeys.account.publicKey);
      final device = bundle.devices.single;
      expect(device.deviceId, aliceKeys.id);
      expect(device.oneTimePrekey, isNotNull);
      expect((await alice.keys.status()).oneTimeRemaining, 14);
    });

    test('sends over REST and receives over the socket with acks', () async {
      final (alice, aliceKeys) = await register(aliceNumber);
      final (bob, bobKeys) = await register(bobNumber);
      final rt = alice.realtime;
      final received = <Envelope>[];
      rt.envelopes.listen(received.add);
      final connected = reach(rt, RealtimePhase.connected);
      rt.start();
      await connected;

      // A wrong device list is refused with the lists to fix.
      try {
        await bob.messaging.send(
          SendMessageRequest(
            id: Uuid.v7(),
            recipients: [Recipient(account: aliceKeys.accountId, devices: [])],
          ),
        );
        fail('expected device_list_stale');
      } on ApiException catch (e) {
        expect(e.code, ErrorCode.deviceListStale);
        expect(e.staleDevices!.accounts.single.missing, [aliceKeys.id]);
      }

      final payload = Uint8List.fromList(List.generate(64, (i) => i));
      final id = Uuid.v7();
      final request = SendMessageRequest(
        id: id,
        recipients: [
          Recipient(
            account: aliceKeys.accountId,
            devices: [DevicePayload(device: aliceKeys.id, payload: payload)],
          ),
        ],
      );
      await bob.messaging.send(request);
      // A retried send (same id) is not delivered twice.
      await bob.messaging.send(request);

      await eventually(() async => expect(received, hasLength(1)));
      final envelope = received.single;
      expect(envelope.from!.account, bobKeys.accountId);
      expect(envelope.payload, payload);
      expect(rt.outstanding, 1);

      rt.ack(envelope.seq!);
      expect(rt.outstanding, 0);
      await eventually(() async {
        final page = await alice.messaging.mailbox();
        expect(page.envelopes, isEmpty);
      });
    });

    test('revoking a device closes its socket with 4003', () async {
      final (alice, aliceKeys) = await register(aliceNumber);
      final (second, secondKeys) = await secondDevice(
        alice,
        aliceKeys,
        aliceNumber,
      );
      final rt = second.realtime;
      final connected = reach(rt, RealtimePhase.connected);
      rt.start();
      await connected;

      final revoked = reach(rt, RealtimePhase.revoked);
      await alice.identity.revokeDevice(secondKeys.id);
      final state = await revoked;
      expect(state.closeCode, RealtimeCloseCode.deviceRevoked);
    });

    test('a rejected access token is refreshed once for concurrent '
        'requests', () async {
      final (alice, keys) = await register(aliceNumber);
      final good = (await alice.auth.current())!;
      final store = MemorySessionStore(
        Session(
          accountId: good.accountId,
          deviceId: good.deviceId,
          accessToken: 'not-a-valid-token',
          accessExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
          refreshToken: good.refreshToken,
          refreshExpiresAt: good.refreshExpiresAt,
        ),
      );
      final api = client(store);
      final accounts = await Future.wait([
        for (var i = 0; i < 4; i++) api.identity.account(),
      ]);
      expect(accounts.map((a) => a.accountId).toSet(), {keys.accountId});
      final refreshed = (await store.read())!;
      expect(refreshed.accessToken, isNot('not-a-valid-token'));
      expect(refreshed.refreshToken, isNot(good.refreshToken));
    });

    test('after sign-out the refresh is refused and the client is signed '
        'out', () async {
      final (alice, _) = await register(aliceNumber);
      await alice.identity.signOut();
      final signedOut = alice.auth.signedOut.first;
      await expectLater(
        alice.identity.account(),
        throwsA(
          isA<SignedOutException>().having(
            (e) => e.reason,
            'reason',
            SignedOutReason.refreshRejected,
          ),
        ),
      );
      await signedOut;
      expect(await alice.auth.current(), isNull);
    });

    test('resumable upload and ranged download', () async {
      final (alice, _) = await register(aliceNumber);
      final data = Uint8List.fromList(List.generate(1000, (i) => i % 251));
      final target = await alice.media.createUpload(
        CreateUploadRequest(size: data.length),
      );
      await alice.media.upload(target, data, chunkSize: 300);
      final whole = await alice.media.download(target.mediaId);
      expect(whole.bytes, data);
      final part = await alice.media.download(
        target.mediaId,
        start: 100,
        end: 199,
      );
      expect(part.partial, isTrue);
      expect(part.size, 1000);
      expect(part.bytes, data.sublist(100, 200));
    });

    test('admin signs in on its own audience and lists accounts', () async {
      final (_, keys) = await register(aliceNumber);
      final console = HelixAdminApi(baseUrl: h.server.baseUri);
      addTearDown(console.close);
      expect((await console.admin.setupStatus()).configured, isTrue);
      await console.admin.signIn(adminPassword);
      final page = await console.admin.accounts();
      expect(page.items.map((a) => a.accountId), contains(keys.accountId));
      final detail = await console.admin.account(keys.accountId);
      expect(detail.devices.single.deviceId, keys.id);
      expect((await console.admin.config()).serverName, isNotEmpty);

      // A device token is no admin token: the server refuses it and the
      // console counts as signed out.
      final impostor = HelixAdminApi(
        baseUrl: h.server.baseUri,
        session: AdminSession(
          token: keys.bearer,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      addTearDown(impostor.close);
      await expectLater(
        impostor.admin.accounts(),
        throwsA(isA<SignedOutException>()),
      );
    });
  });
}
