import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// Account recovery with a recovery code: the new device certifies itself
/// under a NEW identity key for the account id the lookup names.
void main() {
  late Peers peers;

  setUp(() => peers = Peers());
  tearDown(() => peers.dispose());

  Future<void> expectSignIn(Future<void> action, SignInFailure reason) =>
      expectLater(
        action,
        throwsA(
          isA<SignInException>().having((e) => e.reason, 'reason', reason),
        ),
      );

  test('a recovered device keeps the account id under a new identity key, '
      'and the old device is gone', () async {
    final old = await peers.register('old', phone: '+8801711000001');
    final oldIdentity = (await old.db.cryptoDao.identityKeys())!;
    final oldOnServer = peers.server.device(old.device);
    peers.server.recoveryCodes['rec_code'] = (
      account: old.account,
      needsVerification: false,
    );
    final fresh = await peers.create('fresh');

    await fresh.engine.account.recoverWithCode(
      recoveryCode: 'rec_code',
      phoneNumber: '+8801711000001',
    );

    expect(fresh.engine.status, EngineStatus.running);
    expect(fresh.account, old.account);
    expect(fresh.device, isNot(old.device));
    final identity = (await fresh.db.cryptoDao.identityKeys())!;
    expect(
      identity.aikPublic,
      isNot(oldIdentity.aikPublic),
      reason: 'the account identity key is rotated',
    );
    expect(peers.server.accounts[old.account]!.identityKey, identity.aikPublic);
    // The registered certificate verifies under the NEW key and names the
    // account.
    final registered = peers.server.device(fresh.device).registration;
    expect(
      await DeviceCertificates.isValid(
        accountIdentityKey: identity.aikPublic,
        device: DeviceAddress(fresh.account, fresh.device),
        identityKey: registered.identityKey,
        signingKey: registered.signingKey,
        certificate: registered.certificate,
      ),
      isTrue,
    );
    expect(
      await DeviceCertificates.isValid(
        accountIdentityKey: oldIdentity.aikPublic,
        device: DeviceAddress(fresh.account, fresh.device),
        identityKey: registered.identityKey,
        signingKey: registered.signingKey,
        certificate: registered.certificate,
      ),
      isFalse,
    );
    // Prekeys and the account row are in place like after registering.
    expect(
      await fresh.db.cryptoDao.prekeysOf(PrekeyKind.oneTime),
      hasLength(PrekeyPolicy.initialOneTimePrekeys),
    );
    final row = (await fresh.db.accountDao.current())!;
    expect(row.accountId, old.account);
    expect(row.phoneNumber, '+8801711000001');
    expect(row.profileKey, hasLength(32));
    // The server signed every other device out and spent the code.
    expect(oldOnServer.revoked, isTrue);
    expect(peers.server.recoveryCodes, isEmpty);
    await expectSignIn(
      (await peers.create(
        'late',
      )).engine.account.recoverWithCode(recoveryCode: 'rec_code'),
      SignInFailure.invalidRecoveryCode,
    );
  });

  test('a code that needs the phone verified says so before anything is '
      'sent, then works with the token', () async {
    final old = await peers.register('old', phone: '+8801711000001');
    peers.server.recoveryCodes['rec_code'] = (
      account: old.account,
      needsVerification: true,
    );
    final fresh = await peers.create('fresh');
    final before = peers.server.callsTo(Routes.recoveryRedeem);

    await expectSignIn(
      fresh.engine.account.recoverWithCode(recoveryCode: 'rec_code'),
      SignInFailure.verificationRequired,
    );
    expect(peers.server.callsTo(Routes.recoveryRedeem), before);
    expect(fresh.engine.status, EngineStatus.signedOut);
    expect(await fresh.db.accountDao.current(), isNull);
    expect(await fresh.db.cryptoDao.identityKeys(), isNull);

    final challenge = await fresh.engine.account.requestPhoneCode(
      '+8801711000001',
      purpose: PhonePurpose.recover,
    );
    final verified = await fresh.engine.account.verifyPhone(
      challenge.challengeId,
      '123456',
    );
    await fresh.engine.account.recoverWithCode(
      recoveryCode: 'rec_code',
      verificationToken: verified.verificationToken,
    );
    expect(fresh.engine.status, EngineStatus.running);
    expect(fresh.account, old.account);
  });

  test(
    'an unknown code, and a refused redeem, leave the database empty',
    () async {
      final old = await peers.register('old', phone: '+8801711000001');
      final fresh = await peers.create('fresh');
      await expectSignIn(
        fresh.engine.account.recoverWithCode(recoveryCode: 'rec_wrong'),
        SignInFailure.invalidRecoveryCode,
      );
      expect(await fresh.db.accountDao.current(), isNull);

      // The server accepts the lookup but refuses the redeem.
      peers.server.recoveryCodes['rec_code'] = (
        account: old.account,
        needsVerification: false,
      );
      peers.server.failNext(Routes.recoveryRedeem, code: ErrorCode.invalidCode);
      await expectLater(
        fresh.engine.account.recoverWithCode(recoveryCode: 'rec_code'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ErrorCode.invalidCode,
          ),
        ),
      );
      expect(fresh.engine.status, EngineStatus.signedOut);
      expect(await fresh.db.accountDao.current(), isNull);
      expect(await fresh.db.cryptoDao.identityKeys(), isNull);
      // Nothing was consumed: the code still works.
      await fresh.engine.account.recoverWithCode(recoveryCode: 'rec_code');
      expect(fresh.engine.status, EngineStatus.running);
    },
  );

  test('a server that does not say the account id: the caller may, else '
      'it fails', () async {
    final old = await peers.register('old', phone: '+8801711000001');
    peers.server
      ..omitRecoveryAccountId = true
      ..recoveryCodes['rec_code'] = (
        account: old.account,
        needsVerification: false,
      );
    final fresh = await peers.create('fresh');
    await expectSignIn(
      fresh.engine.account.recoverWithCode(recoveryCode: 'rec_code'),
      SignInFailure.unknownAccount,
    );
    await fresh.engine.account.recoverWithCode(
      recoveryCode: 'rec_code',
      accountId: old.account,
    );
    expect(fresh.account, old.account);
  });

  test(
    'a database that already holds an account cannot be recovered onto',
    () async {
      final alice = await peers.register('alice');
      await expectLater(
        alice.engine.account.recoverWithCode(recoveryCode: 'rec_code'),
        throwsA(isA<EngineStateException>()),
      );
    },
  );

  test('a new password wraps the new identity key', () async {
    final old = await peers.register('old', phone: '+8801711000001');
    peers.server.recoveryCodes['rec_code'] = (
      account: old.account,
      needsVerification: false,
    );
    final fresh = await peers.create('fresh');
    await fresh.engine.account.recoverWithCode(
      recoveryCode: 'rec_code',
      password: 'correct horse battery staple',
    );
    final redeem = peers.server.lastRedeem!;
    final setup = redeem.password!;
    final identity = (await fresh.db.cryptoDao.identityKeys())!;
    final keys = await PasswordKeys.derive(
      password: 'correct horse battery staple',
      salt: setup.salt,
      params: setup.kdf,
    );
    final unwrapped = await keys.unwrapIdentityKey(
      wrapped: setup.wrappedIdentityKey,
      accountId: fresh.account,
      expectedPublicKey: identity.aikPublic,
    );
    expect(unwrapped.publicKey, identity.aikPublic);
    // The password itself never went anywhere.
    expect(redeem.toJson().toString(), isNot(contains('horse')));
  });
}
