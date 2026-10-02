import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

const alice = '+8801711000001';
const bob = '+8801711000002';

void main() {
  group('identity on Helix Global', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(() async => h = await Harness.start());
    tearDown(() async => h.stop());

    test(
      'phone sign-up: code by text, single-use verification, working session',
      () async {
        final device = await h.registerGlobal(alice);
        final account = await h.api.call(Routes.account, bearer: device.bearer);
        expect(account.status, 200);
        final info = AccountInfo.fromJson(account.json);
        expect(info.accountId, device.accountId);
        expect(info.phoneLast4, '0001');
        expect(info.hasPassword, isFalse);

        final devices = DeviceList.fromJson(
          (await h.api.call(Routes.devices, bearer: device.bearer)).json,
        );
        expect(devices.devices.single.current, isTrue);
        expect(devices.devices.single.deviceId, device.id);
        expect(
          h.sms.sent.single.message,
          isNot(contains(alice)),
          reason: 'texts carry only the code',
        );
      },
    );

    test('a verification token cannot be spent twice', () async {
      final verified = await h.verifyPhone(alice);
      final acct = await TestAccount.create();
      Future<TestResponse> register() async {
        final d = await acct.newDevice();
        return h.api.call(
          Routes.register,
          body: RegisterRequest(
            accountId: acct.id,
            identityKey: acct.publicKey,
            device: await d.registration(),
            prekeys: await d.prekeys(),
            verificationToken: verified.verificationToken,
            termsVersion: HelixLegalDocuments.termsVersion,
          ).toJson(),
        );
      }

      expect((await register()).status, 201);
      expect((await register()).errorCode, 'invalid_code');
    });

    test('codes: five wrong tries burn the challenge', () async {
      final challenge = PhoneChallengeResponse.fromJson(
        (await h.api.call(
          Routes.phoneChallenge,
          body: const PhoneChallengeRequest(
            phoneNumber: alice,
            purpose: PhonePurpose.register,
          ).toJson(),
        )).json,
      );
      final right = h.sms.lastCodeFor(alice);
      final wrong = right == '111111' ? '222222' : '111111';
      for (var i = 0; i < 5; i++) {
        final r = await h.api.call(
          Routes.phoneVerify,
          body: PhoneVerifyRequest(
            challengeId: challenge.challengeId,
            code: wrong,
          ).toJson(),
        );
        expect(r.errorCode, 'invalid_code');
      }
      final late = await h.api.call(
        Routes.phoneVerify,
        body: PhoneVerifyRequest(
          challengeId: challenge.challengeId,
          code: right,
        ).toJson(),
      );
      expect(late.errorCode, 'invalid_code', reason: 'attempts exhausted');
    });

    test(
      'registration checks terms, number format and the device certificate',
      () async {
        final verified = await h.verifyPhone(alice);
        final acct = await TestAccount.create();
        final d = await acct.newDevice();
        Future<TestResponse> attempt({
          String? terms = HelixLegalDocuments.termsVersion,
          bool badCert = false,
        }) async => h.api.call(
          Routes.register,
          body: RegisterRequest(
            accountId: acct.id,
            identityKey: acct.publicKey,
            device: await d.registration(badCertificate: badCert),
            prekeys: await d.prekeys(),
            verificationToken: verified.verificationToken,
            termsVersion: terms,
          ).toJson(),
        );
        expect(
          (await attempt(terms: '2020-01')).errorCode,
          'terms_not_accepted',
        );
        final bad = await attempt(badCert: true);
        expect(bad.errorCode, 'invalid_field');
        expect(
          bad.json.object('error').object('details').string('field'),
          'device.certificate',
        );

        final badNumber = await h.api.call(
          Routes.phoneChallenge,
          body: const PhoneChallengeRequest(
            phoneNumber: '01711',
            purpose: PhonePurpose.register,
          ).toJson(),
        );
        expect(badNumber.errorCode, 'invalid_field');
      },
    );

    test(
      'an existing number needs replace_existing, which rotates the identity',
      () async {
        final first = await h.registerGlobal(alice);
        final verified = await h.verifyPhone(
          alice,
          purpose: PhonePurpose.signIn,
        );
        expect(verified.accountExists, isTrue);
        expect(verified.accountId, first.accountId);

        final newKey = await first.account.rotated();
        final d = await newKey.newDevice(accountId: verified.accountId);
        final request = RegisterRequest(
          accountId: newKey.id,
          identityKey: newKey.publicKey,
          device: await d.registration(),
          prekeys: await d.prekeys(),
          verificationToken: verified.verificationToken,
          termsVersion: HelixLegalDocuments.termsVersion,
        );
        expect(
          (await h.api.call(Routes.register, body: request.toJson())).errorCode,
          'account_exists',
        );

        final replaced = await h.api.call(
          Routes.register,
          body: RegisterRequest(
            accountId: request.accountId,
            identityKey: request.identityKey,
            device: request.device,
            prekeys: request.prekeys,
            verificationToken: request.verificationToken,
            termsVersion: request.termsVersion,
            replaceExisting: true,
          ).toJson(),
        );
        expect(replaced.status, 201);
        final result = RegisterResponse.fromJson(replaced.json);
        expect(result.replacedExisting, isTrue);
        expect(result.session.accountId, first.accountId);

        expect(
          (await h.api.call(Routes.account, bearer: first.bearer)).status,
          401,
          reason: 'old device was signed out',
        );
        d.session = result.session;
        final info = AccountInfo.fromJson(
          (await h.api.call(Routes.account, bearer: d.bearer)).json,
        );
        expect(info.identityKey, newKey.publicKey);
      },
    );

    test(
      'refresh rotates; reusing an old refresh token ends the device sessions',
      () async {
        final device = await h.registerGlobal(alice);
        final first = device.session!;
        final rotated = await h.api.call(
          Routes.refreshSession,
          body: RefreshRequest(refreshToken: first.refreshToken).toJson(),
        );
        expect(rotated.status, 200);
        final second = Session.fromJson(rotated.json);
        expect(second.refreshToken, isNot(first.refreshToken));
        expect(
          (await h.api.call(Routes.account, bearer: second.accessToken)).status,
          200,
        );

        final reuse = await h.api.call(
          Routes.refreshSession,
          body: RefreshRequest(refreshToken: first.refreshToken).toJson(),
        );
        expect(reuse.status, 401);
        expect(
          (await h.api.call(Routes.account, bearer: second.accessToken)).status,
          401,
          reason: 'theft response: every session of the device ends',
        );
        final secondRefresh = await h.api.call(
          Routes.refreshSession,
          body: RefreshRequest(refreshToken: second.refreshToken).toJson(),
        );
        expect(secondRefresh.status, 401);
      },
    );

    test('sign-out ends the session but keeps the device', () async {
      final device = await h.registerGlobal(alice);
      expect(
        (await h.api.call(Routes.signOut, bearer: device.bearer)).status,
        204,
      );
      expect(
        (await h.api.call(Routes.account, bearer: device.bearer)).status,
        401,
      );

      final challenge = DeviceChallengeResponse.fromJson(
        (await h.api.call(
          Routes.deviceChallenge,
          body: DeviceChallengeRequest(
            accountId: device.accountId,
            deviceId: device.id,
          ).toJson(),
        )).json,
      );
      final signature = await sign(
        device.dsk,
        signInSignatureBody(challenge.challenge),
      );
      final signedIn = await h.api.call(
        Routes.deviceSignIn,
        body: DeviceSignInRequest(
          accountId: device.accountId,
          deviceId: device.id,
          challengeId: challenge.challengeId,
          challenge: challenge.challenge,
          signature: signature,
        ).toJson(),
      );
      expect(signedIn.status, 200, reason: 'device-key sign-in after sign-out');
      final session = Session.fromJson(signedIn.json);
      expect(
        (await h.api.call(Routes.account, bearer: session.accessToken)).status,
        200,
      );

      final replay = await h.api.call(
        Routes.deviceSignIn,
        body: DeviceSignInRequest(
          accountId: device.accountId,
          deviceId: device.id,
          challengeId: challenge.challengeId,
          challenge: challenge.challenge,
          signature: signature,
        ).toJson(),
      );
      expect(
        replay.errorCode,
        'invalid_credentials',
        reason: 'challenges are single-use',
      );
    });

    test(
      'password: set, decoys for strangers, sign in on a new device, lockout',
      () async {
        final first = await h.registerGlobal(alice);
        final pw = PasswordSetup(
          kdf: const KdfParams(),
          salt: bytes(16, 3),
          authKey: bytes(32, 4),
          wrappedIdentityKey: WrappedKey(
            nonce: bytes(12, 5),
            ciphertext: bytes(48, 6),
          ),
        );
        expect(
          (await h.api.call(
            Routes.setPassword,
            bearer: first.bearer,
            body: SetPasswordRequest(password: pw).toJson(),
          )).status,
          204,
        );

        final params = PasswordParamsResponse.fromJson(
          (await h.api.call(
            Routes.passwordParams,
            body: const PasswordParamsRequest(phoneNumber: alice).toJson(),
          )).json,
        );
        expect(params.salt, pw.salt);
        final decoy1 = PasswordParamsResponse.fromJson(
          (await h.api.call(
            Routes.passwordParams,
            body: const PasswordParamsRequest(phoneNumber: bob).toJson(),
          )).json,
        );
        final decoy2 = PasswordParamsResponse.fromJson(
          (await h.api.call(
            Routes.passwordParams,
            body: const PasswordParamsRequest(phoneNumber: bob).toJson(),
          )).json,
        );
        expect(decoy1.salt, decoy2.salt, reason: 'stable decoys');
        expect(decoy1.salt.length, 16);

        final signIn = await h.api.call(
          Routes.passwordSignIn,
          body: PasswordSignInRequest(
            phoneNumber: alice,
            authKey: pw.authKey,
          ).toJson(),
        );
        expect(signIn.status, 200);
        final step1 = PasswordSignInResponse.fromJson(signIn.json);
        expect(step1.accountId, first.accountId);
        expect(
          step1.wrappedIdentityKey.ciphertext,
          pw.wrappedIdentityKey.ciphertext,
        );

        final second = await first.account.newDevice(name: 'Laptop');
        final added = await h.api.call(
          Routes.addDevice,
          body: AddDeviceRequest(
            device: await second.registration(),
            prekeys: await second.prekeys(),
            signInToken: step1.signInToken,
          ).toJson(),
        );
        expect(added.status, 201);
        second.session = Session.fromJson(added.json);
        final list = DeviceList.fromJson(
          (await h.api.call(Routes.devices, bearer: second.bearer)).json,
        );
        expect(
          list.devices.map((d) => d.deviceId),
          unorderedEquals([first.id, second.id]),
        );

        final reused = await h.api.call(
          Routes.addDevice,
          body: AddDeviceRequest(
            device: await (await first.account.newDevice()).registration(),
            prekeys: await second.prekeys(),
            signInToken: step1.signInToken,
          ).toJson(),
        );
        expect(
          reused.errorCode,
          'invalid_code',
          reason: 'sign-in tokens are single-use',
        );

        final events = Page.fromJson(
          (await h.api.call(Routes.securityEvents, bearer: first.bearer)).json,
          SecurityEvent.fromJson,
        );
        expect(
          events.items.map((e) => e.kind),
          contains(SecurityEventKind.passwordChanged),
        );

        for (var i = 0; i < 4; i++) {
          final r = await h.api.call(
            Routes.passwordSignIn,
            body: PasswordSignInRequest(
              phoneNumber: alice,
              authKey: bytes(32, 99),
            ).toJson(),
          );
          expect(r.errorCode, 'invalid_credentials');
        }
        final fifth = await h.api.call(
          Routes.passwordSignIn,
          body: PasswordSignInRequest(
            phoneNumber: alice,
            authKey: bytes(32, 99),
          ).toJson(),
        );
        expect(fifth.errorCode, 'password_locked');
        final whileLocked = await h.api.call(
          Routes.passwordSignIn,
          body: PasswordSignInRequest(
            phoneNumber: alice,
            authKey: pw.authKey,
          ).toJson(),
        );
        expect(
          whileLocked.errorCode,
          'password_locked',
          reason: 'even the right password waits',
        );

        final stranger = await h.api.call(
          Routes.passwordSignIn,
          body: PasswordSignInRequest(
            phoneNumber: bob,
            authKey: pw.authKey,
          ).toJson(),
        );
        expect(stranger.errorCode, 'invalid_credentials');
      },
    );

    test(
      'QR linking: new device polls, old device approves, provision handed over once',
      () async {
        final old = await h.registerGlobal(alice);
        final created = LinkCreateResponse.fromJson(
          (await h.api.call(
            Routes.linkCreate,
            body: LinkCreateRequest(ephemeralKey: bytes(32, 7)).toJson(),
          )).json,
        );
        final pending = await h.api.call(
          Routes.linkPoll,
          params: {'link_id': created.linkId},
          bearer: created.pollToken,
        );
        expect(
          LinkPollResponse.fromJson(pending.json).status,
          LinkStatus.pending,
        );
        final wrongPoller = await h.api.call(
          Routes.linkPoll,
          params: {'link_id': created.linkId},
          bearer: 'lp_not-the-token',
        );
        expect(wrongPoller.status, 401);

        final poll = h.api.call(
          Routes.linkPoll,
          params: {'link_id': created.linkId},
          bearer: created.pollToken,
          query: {'wait_s': '10'},
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          (await h.api.call(
            Routes.approveLink,
            params: {'link_id': created.linkId},
            bearer: old.bearer,
            body: LinkApproveRequest(provision: bytes(120, 8)).toJson(),
          )).status,
          204,
        );
        final approved = LinkPollResponse.fromJson((await poll).json);
        expect(approved.status, LinkStatus.approved);
        expect(approved.provision, bytes(120, 8));

        final linked = await old.account.newDevice(name: 'Tablet');
        final added = await h.api.call(
          Routes.addDevice,
          body: AddDeviceRequest(
            device: await linked.registration(),
            prekeys: await linked.prekeys(),
            linkToken: approved.linkToken,
          ).toJson(),
        );
        expect(added.status, 201);
        final after = await h.api.call(
          Routes.linkPoll,
          params: {'link_id': created.linkId},
          bearer: created.pollToken,
        );
        expect(
          LinkPollResponse.fromJson(after.json).status,
          LinkStatus.expired,
          reason: 'handed over once',
        );
      },
    );

    test(
      'revoking a device ends its session and removes it from bundles',
      () async {
        final first = await h.registerGlobal(alice);
        final verified = await h.verifyPhone(bob);
        final bobAccount = await TestAccount.create();
        final bobDevice = await bobAccount.newDevice();
        bobDevice.session = RegisterResponse.fromJson(
          (await h.api.call(
            Routes.register,
            body: RegisterRequest(
              accountId: bobAccount.id,
              identityKey: bobAccount.publicKey,
              device: await bobDevice.registration(),
              prekeys: await bobDevice.prekeys(),
              verificationToken: verified.verificationToken,
              termsVersion: HelixLegalDocuments.termsVersion,
            ).toJson(),
          )).json,
        ).session;

        // Alice adds a second device via password.
        final pw = PasswordSetup(
          kdf: const KdfParams(),
          salt: bytes(16),
          authKey: bytes(32, 2),
          wrappedIdentityKey: WrappedKey(
            nonce: bytes(12),
            ciphertext: bytes(48),
          ),
        );
        await h.api.call(
          Routes.setPassword,
          bearer: first.bearer,
          body: SetPasswordRequest(password: pw).toJson(),
        );
        final step1 = PasswordSignInResponse.fromJson(
          (await h.api.call(
            Routes.passwordSignIn,
            body: PasswordSignInRequest(
              phoneNumber: alice,
              authKey: pw.authKey,
            ).toJson(),
          )).json,
        );
        final second = await first.account.newDevice(name: 'Old laptop');
        second.session = Session.fromJson(
          (await h.api.call(
            Routes.addDevice,
            body: AddDeviceRequest(
              device: await second.registration(),
              prekeys: await second.prekeys(),
              signInToken: step1.signInToken,
            ).toJson(),
          )).json,
        );

        var bundle = AccountKeys.fromJson(
          (await h.api.call(
            Routes.accountKeys,
            params: {'account': first.accountId},
            bearer: bobDevice.bearer,
          )).json,
        );
        expect(
          bundle.devices.map((d) => d.deviceId),
          unorderedEquals([first.id, second.id]),
        );

        expect(
          (await h.api.call(
            Routes.revokeDevice,
            params: {'device_id': second.id},
            query: {'reason': 'lost'},
            bearer: first.bearer,
          )).status,
          204,
        );
        expect(
          (await h.api.call(Routes.account, bearer: second.bearer)).status,
          401,
        );
        final refresh = await h.api.call(
          Routes.refreshSession,
          body: RefreshRequest(
            refreshToken: second.session!.refreshToken,
          ).toJson(),
        );
        expect(refresh.status, isNot(200));
        bundle = AccountKeys.fromJson(
          (await h.api.call(
            Routes.accountKeys,
            params: {'account': first.accountId},
            bearer: bobDevice.bearer,
          )).json,
        );
        expect(bundle.devices.map((d) => d.deviceId), [first.id]);

        final notMine = await h.api.call(
          Routes.revokeDevice,
          params: {'device_id': bobDevice.id},
          bearer: first.bearer,
        );
        expect(
          notMine.status,
          404,
          reason: 'cannot revoke another account\'s device',
        );
      },
    );

    test(
      'recovery code: new identity on a new device, everything else signed out',
      () async {
        final first = await h.registerGlobal(alice);
        final code = await h.env.platform.db.tx(
          (tx) =>
              h.identity.registration.issueRecoveryCode(tx, first.accountId),
        );
        final lookup = RecoveryLookupResponse.fromJson(
          (await h.api.call(
            Routes.recoveryLookup,
            body: RecoveryLookupRequest(recoveryCode: code.code).toJson(),
          )).json,
        );
        expect(lookup.valid, isTrue);
        expect(lookup.verificationRequired, isTrue);
        expect(
          lookup.accountId,
          first.accountId,
          reason: 'the new device must certify the account',
        );

        // A wrong code is no oracle: the bare `valid: false`, no account.
        final wrong = await h.api.call(
          Routes.recoveryLookup,
          body: const RecoveryLookupRequest(
            recoveryCode: 'rec_not-a-real-code',
          ).toJson(),
        );
        expect(wrong.status, 200);
        expect(wrong.json.json, {
          'valid': false,
          'verification_required': false,
        });

        final verified = await h.verifyPhone(
          alice,
          purpose: PhonePurpose.recover,
        );
        final rotated = await first.account.rotated();
        final device = await rotated.newDevice();
        final redeemed = await h.api.call(
          Routes.recoveryRedeem,
          body: RecoveryRedeemRequest(
            recoveryCode: code.code,
            identityKey: rotated.publicKey,
            device: await device.registration(),
            prekeys: await device.prekeys(),
            verificationToken: verified.verificationToken,
          ).toJson(),
        );
        expect(redeemed.status, 200);
        device.session = Session.fromJson(redeemed.json);
        expect(
          (await h.api.call(Routes.account, bearer: first.bearer)).status,
          401,
        );
        final info = AccountInfo.fromJson(
          (await h.api.call(Routes.account, bearer: device.bearer)).json,
        );
        expect(info.identityKey, rotated.publicKey);
        final again = RecoveryLookupResponse.fromJson(
          (await h.api.call(
            Routes.recoveryLookup,
            body: RecoveryLookupRequest(recoveryCode: code.code).toJson(),
          )).json,
        );
        expect(again.valid, isFalse, reason: 'single use');
        expect(again.accountId, isNull);
      },
    );

    test(
      'helix names: unique, lowercase pattern, reserved names refused',
      () async {
        final a = await h.registerGlobal(alice);
        final b = await h.registerGlobal(bob);
        Future<String?> setName(TestDevice d, String name) async {
          final r = await h.api.call(
            Routes.setHelixName,
            bearer: d.bearer,
            body: SetHelixNameRequest(name: name).toJson(),
          );
          return r.status == 204 ? null : r.errorCode;
        }

        expect(await setName(a, 'alice_01'), isNull);
        expect(await setName(b, 'alice_01'), 'name_taken');
        expect(
          await setName(b, 'Helix_Support'),
          'name_taken',
          reason: 'case-insensitive and staff-like',
        );
        expect(await setName(b, 'bad name'), 'invalid_field');
        expect(await setName(b, 'support'), 'name_taken');
        expect(await setName(b, 'admin99'), 'name_taken');
        expect(
          AccountInfo.fromJson(
            (await h.api.call(Routes.account, bearer: a.bearer)).json,
          ).helixName,
          'alice_01',
        );
      },
    );

    test('suspended accounts can read and sign out but not act', () async {
      final a = await h.registerGlobal(alice);
      await h.env.platform.db.execute(
        "UPDATE ${h.env.platform.schemas.of('identity')}.accounts SET status = 'suspended' WHERE id = @id:uuid",
        {'id': a.accountId},
      );
      expect((await h.api.call(Routes.account, bearer: a.bearer)).status, 200);
      expect(
        (await h.api.call(Routes.keyStatus, bearer: a.bearer)).errorCode,
        'account_suspended',
      );
      expect((await h.api.call(Routes.signOut, bearer: a.bearer)).status, 204);
    });

    test('push tokens are stored but never listed', () async {
      final a = await h.registerGlobal(alice);
      expect(
        (await h.api.call(
          Routes.setPushToken,
          bearer: a.bearer,
          body: const PushTokenRequest(token: 'fcm-token-value').toJson(),
        )).status,
        204,
      );
      final listed = await h.api.call(Routes.devices, bearer: a.bearer);
      expect(listed.body, isNot(contains('fcm-token-value')));
      final target = await h.identity.api.pushTarget(h.env.platform.db, a.id);
      expect(target!.token, 'fcm-token-value');
    });

    test(
      'device challenges are keyed by a random id, not the device',
      () async {
        final device = await h.registerGlobal(alice);
        Future<DeviceChallengeResponse> challenge() async =>
            DeviceChallengeResponse.fromJson(
              (await h.api.call(
                Routes.deviceChallenge,
                body: DeviceChallengeRequest(
                  accountId: device.accountId,
                  deviceId: device.id,
                ).toJson(),
              )).json,
            );
        Future<TestResponse> signIn(
          String id,
          DeviceChallengeResponse c,
        ) async => h.api.call(
          Routes.deviceSignIn,
          body: DeviceSignInRequest(
            accountId: device.accountId,
            deviceId: id,
            challengeId: c.challengeId,
            challenge: c.challenge,
            signature: await sign(device.dsk, signInSignatureBody(c.challenge)),
          ).toJson(),
        );

        final mine = await challenge();
        // Anyone may ask for a challenge for this (public) device id.
        final theirs = await challenge();
        expect(theirs.challengeId, isNot(mine.challengeId));
        expect(
          (await signIn(device.id, mine)).status,
          200,
          reason: 'a second request neither replaces nor spends the first',
        );
        final other = await h.registerGlobal(bob);
        expect(
          (await signIn(other.id, theirs)).errorCode,
          'invalid_credentials',
          reason: 'a challenge only signs in the device it was issued for',
        );
        expect(
          (await signIn(device.id, theirs)).errorCode,
          'invalid_credentials',
          reason: 'and a failed attempt spends it',
        );
      },
    );

    test(
      'password change shares the sign-in lockout and is rate-limited',
      () async {
        final device = await h.registerGlobal(alice);
        PasswordSetup setup(int seed) => PasswordSetup(
          kdf: const KdfParams(),
          salt: bytes(16, seed),
          authKey: bytes(32, seed + 1),
          wrappedIdentityKey: WrappedKey(
            nonce: bytes(12, seed + 2),
            ciphertext: bytes(48, seed + 3),
          ),
        );
        final pw = setup(3);
        Future<TestResponse> change(Uint8List current) => h.api.call(
          Routes.setPassword,
          bearer: device.bearer,
          body: SetPasswordRequest(
            password: setup(40),
            currentAuthKey: current,
          ).toJson(),
        );
        expect(
          (await h.api.call(
            Routes.setPassword,
            bearer: device.bearer,
            body: SetPasswordRequest(password: pw).toJson(),
          )).status,
          204,
        );
        final codes = [
          for (var i = 0; i < 9; i++) (await change(bytes(32, 99))).errorCode,
        ];
        expect(codes.take(4), everyElement('invalid_credentials'));
        expect(
          codes.skip(4),
          everyElement('password_locked'),
          reason: 'wrong current passwords count as sign-in failures',
        );
        final signIn = await h.api.call(
          Routes.passwordSignIn,
          body: PasswordSignInRequest(
            phoneNumber: alice,
            authKey: pw.authKey,
          ).toJson(),
        );
        expect(
          signIn.errorCode,
          'password_locked',
          reason: 'one lockout for both routes',
        );
        expect(
          (await change(pw.authKey)).errorCode,
          'rate_limited',
          reason: '10 password changes per account per hour',
        );
      },
    );

    test('signing out and suspension are signalled to the account', () async {
      final a1 = await h.registerGlobal(alice);
      final a2 = await secondDevice(h, a1, alice);
      expect((await h.api.call(Routes.signOut, bearer: a2.bearer)).status, 204);
      final db = h.env.platform.db;
      final admin = h.identity.api.admin;
      await db.tx(
        (tx) => admin.setSuspended(tx, a1.accountId, suspended: true),
      );
      await db.tx(
        (tx) => admin.setSuspended(tx, a1.accountId, suspended: false),
      );
      final signals = [
        for (final e in (await mailbox(h, a1)).envelopes)
          if (e.kind == EnvelopeKind.accountSignal)
            AccountSignalEvent.fromJson(JsonReader(e.data!)).signal,
      ];
      expect(
        signals,
        containsAllInOrder([
          AccountSignalKind.signedOut,
          AccountSignalKind.suspended,
          AccountSignalKind.unsuspended,
        ]),
      );
    });
  });

  group('code resend throttle', skip: databaseTestSkipReason, () {
    test('a second code to the same number waits', () async {
      final h = await Harness.start(extra: {'HELIX_OTP_RESEND_SECONDS': '30'});
      try {
        Future<TestResponse> request() => h.api.call(
          Routes.phoneChallenge,
          body: const PhoneChallengeRequest(
            phoneNumber: alice,
            purpose: PhonePurpose.register,
          ).toJson(),
        );
        expect((await request()).status, 200);
        final again = await request();
        expect(again.status, 429);
        expect(
          int.parse(again.headers['retry-after']!),
          inInclusiveRange(1, 30),
        );
      } finally {
        await h.stop();
      }
    });
  });

  group('identity on a personal server', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(() async => h = await Harness.start(global: false));
    tearDown(() async => h.stop());

    test('registration needs an invite, which works once', () async {
      final invite = await h.identity.signUp.issueInvite(h.env.platform.db);
      final lookup = InviteLookupResponse.fromJson(
        (await h.api.call(
          Routes.inviteLookup,
          body: InviteLookupRequest(inviteCode: invite.code).toJson(),
        )).json,
      );
      expect(lookup.valid, isTrue);

      Future<TestResponse> register(String? code) async {
        final acct = await TestAccount.create();
        final d = await acct.newDevice();
        return h.api.call(
          Routes.register,
          body: RegisterRequest(
            accountId: acct.id,
            identityKey: acct.publicKey,
            device: await d.registration(),
            prekeys: await d.prekeys(),
            inviteCode: code,
          ).toJson(),
        );
      }

      expect((await register(null)).errorCode, 'bad_request');
      expect((await register(invite.code)).status, 201);
      expect((await register(invite.code)).errorCode, 'invalid_code');
      final used = InviteLookupResponse.fromJson(
        (await h.api.call(
          Routes.inviteLookup,
          body: InviteLookupRequest(inviteCode: invite.code).toJson(),
        )).json,
      );
      expect(used.reason, InviteInvalidReason.used);
      expect(
        (await h.api.call(Routes.inviteSelfIssue)).errorCode,
        'forbidden',
        reason: 'only Helix Global self-issues invites',
      );
    });
  });
}
