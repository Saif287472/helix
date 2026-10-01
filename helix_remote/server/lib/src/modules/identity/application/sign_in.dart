import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/application/context.dart';
import 'package:helix_remote_server/src/modules/identity/config.dart';
import 'package:helix_remote_server/src/modules/identity/domain/secrets.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';

/// Password sign-in, adding devices, QR linking, device-key sign-in.
final class SignIn {
  SignIn(this.c);

  final IdentityContext c;

  static const maxFailures = 5;
  static const firstLock = Duration(minutes: 15);
  static const maxLock = Duration(hours: 24);

  // ---------------------------------------------------------------- password

  /// Real parameters for accounts with a password; stable decoys for
  /// everyone else, so this route does not reveal who has an account.
  Future<PasswordParamsResponse> params(PasswordParamsRequest req) async {
    final phoneHash = c.phoneHash(requireE164(req.phoneNumber));
    final account = await c.store.accountByPhone(c.db, phoneHash);
    if (account != null && account.hasPassword) {
      final row = (await c.credentials.password(c.db, account.id))!;
      return PasswordParamsResponse(
        kdf: KdfParams.fromJson(JsonReader(row.json('kdf'))),
        salt: row.bytes('salt'),
      );
    }
    return PasswordParamsResponse(
      kdf: const KdfParams(),
      salt: hmacSha256(c.config.phonePepper, [
        ...utf8.encode('decoy-salt:'),
        ...phoneHash,
      ]).sublist(0, 16),
    );
  }

  /// Step one of password sign-in. Wrong password and unknown number give
  /// the same answer; repeated failures lock the account's password (not
  /// the account) for 15 minutes, doubling up to 24 hours.
  Future<PasswordSignInResponse> signIn(PasswordSignInRequest req) async {
    final phoneHash = c.phoneHash(requireE164(req.phoneNumber));
    final account = await c.store.accountByPhone(c.db, phoneHash);
    if (account == null || !account.hasPassword) {
      // Same work as a real check, so timing does not tell the two apart.
      c.passwordVerifier(randomBytes(16), req.authKey);
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    final result = await c.db.tx<(Row?, ApiError?)>((tx) async {
      final row = (await c.credentials.password(
        tx,
        account.id,
        forUpdate: true,
      ))!;
      final lockedUntil = row.optTime('locked_until');
      if (lockedUntil != null && lockedUntil.isAfter(c.clock.now())) {
        return (null, _locked(lockedUntil));
      }
      final ok = constantTimeEquals(
        row.bytes('verifier'),
        c.passwordVerifier(row.bytes('verifier_salt'), req.authKey),
      );
      if (!ok) {
        final failures = row.integer('failed_attempts') + 1;
        final lock = failures >= maxFailures ? _lockFor(failures) : null;
        await c.credentials.recordPasswordFailure(
          tx,
          account.id,
          failures,
          lock,
        );
        return (
          null,
          lock == null
              ? const ApiError(ErrorCode.invalidCredentials)
              : _locked(lock),
        );
      }
      await c.credentials.clearPasswordFailures(tx, account.id);
      return (row, null);
    });
    if (result.$2 != null) throw result.$2!;
    final row = result.$1!;
    final record = (await c.store.account(c.db, account.id))!;
    final token = newToken('st');
    await c.ephemeral.put(
      '${IdentityContext.signInPrefix}${tokenKey(token)}',
      account.id,
      IdentityConfig.signInTokenLifetime,
    );
    return PasswordSignInResponse(
      accountId: account.id,
      identityKey: record.identityKey,
      wrappedIdentityKey: WrappedKey.fromJson(
        JsonReader(row.json('wrapped_identity_key')),
      ),
      signInToken: token,
      expiresAt: c.clock.now().add(IdentityConfig.signInTokenLifetime),
    );
  }

  DateTime _lockFor(int failures) {
    final factor = math.pow(2, failures - maxFailures).toInt();
    final lock = firstLock * factor;
    return c.clock.now().add(lock > maxLock ? maxLock : lock);
  }

  ApiError _locked(DateTime until) => ApiError(
    ErrorCode.passwordLocked,
    details: {'locked_until': toWireTime(until)},
    retryAfter: until.difference(c.clock.now()),
  );

  // ------------------------------------------------------------- add device

  Future<Session> addDevice(AddDeviceRequest req) async {
    if ((req.signInToken == null) == (req.linkToken == null)) {
      throw const ApiError(
        ErrorCode.badRequest,
        message: 'give exactly one of sign_in_token, link_token',
      );
    }
    final key = req.signInToken != null
        ? '${IdentityContext.signInPrefix}${tokenKey(req.signInToken!)}'
        : '${IdentityContext.linkTokenPrefix}${tokenKey(req.linkToken!)}';
    final accountId = await c.ephemeral.get(key);
    if (accountId == null) {
      throw const ApiError(
        ErrorCode.invalidCode,
        message: 'token expired or used',
      );
    }
    final account = await c.store.account(c.db, accountId);
    if (account == null) throw const ApiError(ErrorCode.invalidCode);
    await verifyDeviceRegistration(
      accountId: accountId,
      accountIdentityKey: account.identityKey,
      device: req.device,
    );
    if (await c.ephemeral.take(key) == null) {
      throw const ApiError(
        ErrorCode.invalidCode,
        message: 'token expired or used',
      );
    }
    return c.db.tx(
      (tx) => c.addDevice(
        tx,
        accountId: accountId,
        device: req.device,
        prekeys: req.prekeys,
        event: SecurityEventKind.deviceAdded,
      ),
    );
  }

  // ---------------------------------------------------------------- linking

  Future<LinkCreateResponse> createLink(LinkCreateRequest req) async {
    if (req.ephemeralKey.length != 32) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'ephemeral_key'},
      );
    }
    final linkId = Uuid.v7();
    final pollToken = newToken('lp');
    await c.ephemeral.put(
      '${IdentityContext.linkPrefix}$linkId',
      jsonEncode({'poll': tokenKey(pollToken), 'status': 'pending'}),
      IdentityConfig.linkLifetime,
    );
    return LinkCreateResponse(
      linkId: linkId,
      pollToken: pollToken,
      expiresAt: c.clock.now().add(IdentityConfig.linkLifetime),
    );
  }

  /// Long-polls until the link is approved or [wait] passes. An approved
  /// link is handed over once, then forgotten.
  Future<LinkPollResponse> pollLink(
    String linkId,
    String? bearer,
    Duration wait,
  ) async {
    final deadline = DateTime.now().add(wait);
    final key = '${IdentityContext.linkPrefix}$linkId';
    while (true) {
      final raw = await c.ephemeral.get(key);
      if (raw == null) {
        return const LinkPollResponse(status: LinkStatus.expired);
      }
      final state = jsonDecode(raw) as Map<String, Object?>;
      if (bearer == null ||
          !constantTimeEquals(
            utf8.encode(state['poll']! as String),
            utf8.encode(tokenKey(bearer)),
          )) {
        throw const ApiError(ErrorCode.unauthenticated);
      }
      if (state['status'] == 'approved') {
        await c.ephemeral.delete(key);
        return LinkPollResponse(
          status: LinkStatus.approved,
          provision: decodeBytes(state['provision']! as String),
          linkToken: state['link_token']! as String,
        );
      }
      if (!DateTime.now().isBefore(deadline)) {
        return const LinkPollResponse(status: LinkStatus.pending);
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> approveLink(
    DevicePrincipal approver,
    String linkId,
    LinkApproveRequest req,
  ) async {
    if (req.provision.isEmpty || req.provision.length > 4096) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'provision'},
      );
    }
    final key = '${IdentityContext.linkPrefix}$linkId';
    final raw = await c.ephemeral.get(key);
    if (raw == null) throw const ApiError(ErrorCode.expired);
    final state = jsonDecode(raw) as Map<String, Object?>;
    if (state['status'] != 'pending') throw const ApiError(ErrorCode.conflict);
    final linkToken = newToken('lt');
    await c.ephemeral.put(
      '${IdentityContext.linkTokenPrefix}${tokenKey(linkToken)}',
      approver.accountId,
      IdentityConfig.linkLifetime,
    );
    await c.ephemeral.put(
      key,
      jsonEncode({
        'poll': state['poll'],
        'status': 'approved',
        'provision': encodeBytes(req.provision),
        'link_token': linkToken,
      }),
      IdentityConfig.linkLifetime,
    );
  }

  // --------------------------------------------------- device-key sign-in

  Future<DeviceChallengeResponse> challenge(DeviceChallengeRequest req) async {
    if (!Uuid.isValid(req.deviceId) || !Uuid.isValid(req.accountId)) {
      throw const ApiError(ErrorCode.invalidField);
    }
    final challenge = randomBytes(32);
    // Issued for any id, so this route does not reveal which devices exist.
    await c.ephemeral.put(
      '${IdentityContext.challengePrefix}${req.deviceId}',
      encodeBytes(challenge),
      IdentityConfig.challengeLifetime,
    );
    return DeviceChallengeResponse(
      challenge: challenge,
      expiresAt: c.clock.now().add(IdentityConfig.challengeLifetime),
    );
  }

  Future<Session> deviceSignIn(DeviceSignInRequest req) async {
    if (!Uuid.isValid(req.deviceId)) {
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    final stored = await c.ephemeral.take(
      '${IdentityContext.challengePrefix}${req.deviceId}',
    );
    if (stored == null ||
        !constantTimeEquals(decodeBytes(stored), req.challenge)) {
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    final device = await c.store.deviceById(c.db, req.deviceId);
    if (device == null || !device.active || device.accountId != req.accountId) {
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    final ok = await verifyEd25519(
      publicKey: device.signingKey,
      message: signInSignatureBody(req.challenge),
      signature: req.signature,
    );
    if (!ok) throw const ApiError(ErrorCode.invalidCredentials);
    return c.db.tx(
      (tx) => c.sessions.issue(
        tx,
        accountId: device.accountId,
        deviceId: device.id,
      ),
    );
  }
}
