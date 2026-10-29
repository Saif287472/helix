// Regression tests for the identity security audit (docs/security/AUDIT_LOG.md):
// F-1 password change ends the other devices' sessions, F-4 a verification
// token is spent exactly once, F-5 a decoy sign-in failure is never dropped,
// F-6 a spent refresh token is still recognised after its expiry.
import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/application/context.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

const alice = '+8801711000001';

PasswordSetup _setup(int seed) => PasswordSetup(
  kdf: const KdfParams(),
  salt: bytes(16, seed),
  authKey: bytes(32, seed + 1),
  wrappedIdentityKey: WrappedKey(
    nonce: bytes(12, seed + 2),
    ciphertext: bytes(48, seed + 3),
  ),
);

void main() {
  group('identity audit', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(() async => h = await Harness.start());
    tearDown(() async => h.stop());

    Future<TestResponse> refresh(String token) => h.api.call(
      Routes.refreshSession,
      body: RefreshRequest(refreshToken: token).toJson(),
    );

    // ------------------------------------------------------------------ F-1

    test(
      'F-1 a password change ends the other devices, not the caller',
      () async {
        final a = await h.registerGlobal(alice);
        final b = await secondDevice(h, a, alice); // password: setup seed 9
        final current = bytes(32, 9);
        final change = await h.api.call(
          Routes.setPassword,
          bearer: a.bearer,
          body: SetPasswordRequest(
            password: _setup(40),
            currentAuthKey: current,
          ).toJson(),
        );
        expect(change.status, 204);

        expect(
          (await h.api.call(Routes.account, bearer: b.bearer)).status,
          401,
          reason: 'the other device\'s access token is cut off',
        );
        expect(
          (await refresh(b.session!.refreshToken)).status,
          401,
          reason: 'and its refresh token no longer renews it',
        );
        expect(
          (await h.api.call(Routes.account, bearer: a.bearer)).status,
          200,
          reason: 'the device that changed the password stays signed in',
        );
        expect((await refresh(a.session!.refreshToken)).status, 200);
        final bDevices = DeviceList.fromJson(
          (await h.api.call(Routes.devices, bearer: a.bearer)).json,
        );
        expect(
          bDevices.devices.map((d) => d.deviceId),
          containsAll([a.id, b.id]),
          reason: 'the other device is signed out, not revoked',
        );
      },
    );

    test(
      'F-1 a refresh racing a password change leaves no live session',
      () async {
        final a = await h.registerGlobal(alice);
        final b = await secondDevice(h, a, alice);
        final results = await Future.wait([
          h.api.call(
            Routes.setPassword,
            bearer: a.bearer,
            body: SetPasswordRequest(
              password: _setup(40),
              currentAuthKey: bytes(32, 9),
            ).toJson(),
          ),
          refresh(b.session!.refreshToken),
        ]);
        expect(results[0].status, 204);
        if (results[1].status == 200) {
          final minted = Session.fromJson(results[1].json);
          expect(
            (await refresh(minted.refreshToken)).status,
            401,
            reason: 'the refresh that won the race must not be renewable',
          );
        } else {
          expect(results[1].status, 401);
        }
      },
    );

    // ------------------------------------------------------------------ F-4

    test('F-4 one verification token replaces an identity once', () async {
      final first = await h.registerGlobal(alice);
      final verified = await h.verifyPhone(alice);
      final requests = <Map<String, Object?>>[];
      for (var i = 0; i < 2; i++) {
        final key = await first.account.rotated();
        final d = await key.newDevice(accountId: verified.accountId);
        requests.add(
          RegisterRequest(
            accountId: key.id,
            identityKey: key.publicKey,
            device: await d.registration(),
            prekeys: await d.prekeys(),
            verificationToken: verified.verificationToken,
            termsVersion: HelixLegalDocuments.termsVersion,
            replaceExisting: true,
          ).toJson(),
        );
      }
      final results = await Future.wait([
        for (final body in requests) h.api.call(Routes.register, body: body),
      ]);
      expect(
        results.where((r) => r.status == 201),
        hasLength(1),
        reason: 'exactly one of two concurrent uses of a token commits',
      );
      expect(
        results.where((r) => r.status != 201).single.errorCode,
        'invalid_code',
      );
    });

    test('F-4 a failed use leaves the token for a retry', () async {
      final first = await h.registerGlobal(alice);
      final verified = await h.verifyPhone(alice);
      final key = await first.account.rotated();
      final d = await key.newDevice(accountId: verified.accountId);
      // account_exists is answered before anything is spent.
      final reg = await d.registration();
      final keys = await d.prekeys();
      Map<String, Object?> body(bool replace) => RegisterRequest(
        accountId: key.id,
        identityKey: key.publicKey,
        device: reg,
        prekeys: keys,
        verificationToken: verified.verificationToken,
        termsVersion: HelixLegalDocuments.termsVersion,
        replaceExisting: replace,
      ).toJson();
      expect(
        (await h.api.call(Routes.register, body: body(false))).errorCode,
        'account_exists',
      );
      expect((await h.api.call(Routes.register, body: body(true))).status, 201);
    });

    test('F-4 one verification token changes a password once', () async {
      final device = await h.registerGlobal(alice);
      expect(
        (await h.api.call(
          Routes.setPassword,
          bearer: device.bearer,
          body: SetPasswordRequest(password: _setup(3)).toJson(),
        )).status,
        204,
      );
      final reset = await h.verifyPhone(
        alice,
        purpose: PhonePurpose.resetPassword,
      );
      Future<TestResponse> change(int seed) => h.api.call(
        Routes.setPassword,
        bearer: device.bearer,
        body: SetPasswordRequest(
          password: _setup(seed),
          verificationToken: reset.verificationToken,
        ).toJson(),
      );
      final results = await Future.wait([change(40), change(50)]);
      expect(results.where((r) => r.status == 204), hasLength(1));
      expect(
        results.where((r) => r.status != 204).single.errorCode,
        'invalid_code',
      );
    });

    // ------------------------------------------------------------------ F-5
    test(
      'F-5 every decoy sign-in failure is counted under contention',
      () async {
        // Five failures lock a password, so of any burst at most four can be
        // answered "wrong password"; a fifth means an attempt went uncounted.
        const attempts = 40;
        final results = await Future.wait([
          for (var i = 0; i < attempts; i++)
            h.api.call(
              Routes.passwordSignIn,
              body: PasswordSignInRequest(
                phoneNumber: '+8801711009999',
                authKey: bytes(32, 100 + i),
              ).toJson(),
            ),
        ]);
        final wrong = results.where(
          (r) => r.errorCode == 'invalid_credentials',
        );
        expect(
          wrong.length,
          lessThan(IdentityContext.passwordMaxFailures),
          reason: 'an attempt answered "wrong password" was never counted',
        );
        final entries = await h.env.platform.ephemeral.scan(
          'identity:pwdecoy:',
        );
        final failures =
            (jsonDecode(entries.values.single) as Map)['failed_attempts']
                as int;
        expect(failures, IdentityContext.passwordMaxFailures);
      },
    );

    // ------------------------------------------------------------------ F-6

    test('F-6 a spent refresh token is still caught after it expired', () async {
      final device = await h.registerGlobal(alice);
      final first = device.session!;
      final second = Session.fromJson((await refresh(first.refreshToken)).json);
      final identity =
          '${h.env.platform.schemas.of('identity')}.refresh_tokens';
      // The spent token expired 30 days ago (60-day life, issued 90 days ago).
      await h.env.platform.db.execute(
        "UPDATE $identity SET expires_at = now() - interval '30 days' "
        'WHERE used_at IS NOT NULL',
      );
      await h.identity.periodic
          .singleWhere((j) => j.name == 'identity.purge_expired')
          .run();
      expect((await refresh(first.refreshToken)).status, 401);
      expect(
        (await h.api.call(Routes.account, bearer: second.accessToken)).status,
        401,
        reason: 'replaying a spent token ends the device\'s newer sessions',
      );
      final event = await h.env.platform.db.queryOne(
        'SELECT kind FROM ${h.env.platform.schemas.of('identity')}.security_events '
        "WHERE account_id = @a:uuid AND kind = 'session_reuse'",
        {'a': device.accountId},
      );
      expect(event, isNotNull);
    });

    test(
      'F-6 spent tokens are still purged once the window has passed',
      () async {
        final device = await h.registerGlobal(alice);
        await refresh(device.session!.refreshToken);
        final identity =
            '${h.env.platform.schemas.of('identity')}.refresh_tokens';
        await h.env.platform.db.execute(
          "UPDATE $identity SET expires_at = now() - interval '2 years' "
          'WHERE used_at IS NOT NULL',
        );
        await h.identity.periodic
            .singleWhere((j) => j.name == 'identity.purge_expired')
            .run();
        final left = await h.env.platform.db.queryOne(
          'SELECT count(*) AS n FROM $identity WHERE used_at IS NOT NULL',
        );
        expect(left!.integer('n'), 0);
      },
    );
  });
}
