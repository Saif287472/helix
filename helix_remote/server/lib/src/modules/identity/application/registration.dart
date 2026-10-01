import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/application/context.dart';
import 'package:helix_remote_server/src/modules/identity/config.dart';
import 'package:helix_remote_server/src/modules/identity/domain/secrets.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// Account creation, SMS takeover (explicit `replace_existing`), recovery.
final class Registration {
  Registration(this.c);

  final IdentityContext c;

  static const _verificationPurposes = {
    PhonePurpose.register,
    PhonePurpose.signIn,
  };

  Future<RegisterResponse> register(RegisterRequest req) async {
    if (!Uuid.isValid(req.accountId)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'account_id'},
      );
    }
    if (req.identityKey.length != 32) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'identity_key'},
      );
    }
    if (c.config.globalMode && req.termsVersion != c.config.termsVersion) {
      throw const ApiError(ErrorCode.termsNotAccepted);
    }
    final verified = await c.verification(req.verificationToken);
    if (verified != null && !_verificationPurposes.contains(verified.purpose)) {
      throw const ApiError(
        ErrorCode.invalidCode,
        message: 'verification was for another purpose',
      );
    }
    if (c.config.globalMode && verified == null) {
      throw const ApiError(
        ErrorCode.badRequest,
        message: 'verification_token is required',
      );
    }
    if (!c.config.globalMode && req.inviteCode == null) {
      throw const ApiError(
        ErrorCode.badRequest,
        message: 'invite_code is required',
      );
    }
    if (verified != null &&
        await c.credentials.isBanned(c.db, verified.phoneHash)) {
      throw const ApiError(ErrorCode.phoneBanned);
    }
    if (req.password != null) c.checkPasswordSetup(req.password!);

    final existing = verified == null
        ? null
        : await c.store.accountByPhone(c.db, verified.phoneHash);
    if (existing != null && !req.replaceExisting) {
      throw const ApiError(ErrorCode.accountExists);
    }
    final accountId = existing?.id ?? req.accountId;
    await verifyDeviceRegistration(
      accountId: accountId,
      accountIdentityKey: req.identityKey,
      device: req.device,
    );

    final session = await c.db.tx((tx) async {
      if (existing != null) {
        await _replaceIdentity(tx, existing.id, req);
      } else {
        await c.store.insertAccount(
          tx,
          id: accountId,
          identityKey: req.identityKey,
          phoneHash: verified?.phoneHash,
          discoveryHash: verified?.discoveryHash,
          phoneLast4: verified?.last4,
        );
      }
      if (!c.config.globalMode &&
          !await c.credentials.redeemInvite(
            tx,
            hashToken(req.inviteCode!),
            accountId,
          )) {
        throw const ApiError(
          ErrorCode.invalidCode,
          message: 'invite is not valid',
        );
      }
      if (req.password != null) {
        await c.storePassword(tx, accountId, req.password!);
      }
      return c.addDevice(
        tx,
        accountId: accountId,
        device: req.device,
        prekeys: req.prekeys,
        event: existing == null
            ? SecurityEventKind.deviceAdded
            : SecurityEventKind.signedIn,
        notifyOthers: false,
      );
    });
    if (req.verificationToken != null) {
      await c.spendVerification(req.verificationToken!);
    }
    c.log.info('account_registered', {
      'account_id': accountId,
      'device_id': req.device.deviceId,
      'replaced': existing != null,
    });
    return RegisterResponse(
      session: session,
      replacedExisting: existing != null,
    );
  }

  /// The account moves to a new AIK on this device: everything bound to the
  /// old key (devices, wrapped key, recovery codes) goes.
  Future<void> _replaceIdentity(
    Tx tx,
    String accountId,
    RegisterRequest req,
  ) async {
    await c.revokeAll(tx, accountId, 'identity_replaced');
    await c.store.setIdentityKey(tx, accountId, req.identityKey);
    await c.credentials.deletePassword(tx, accountId);
    await c.credentials.deleteRecoveryCodes(tx, accountId);
    await c.hooks.identityKeyChanged(tx, accountId, req.identityKey);
    await c.hooks.deviceListChanged(tx, accountId);
    await c.store.addEvent(tx, accountId, SecurityEventKind.identityChanged);
  }

  // ---------------------------------------------------------------- recovery

  /// Issues a 48-hour, single-use recovery code (admin console).
  Future<({String code, DateTime expiresAt})> issueRecoveryCode(
    Tx tx,
    String accountId,
  ) async {
    final code = newToken('rec');
    final expires = c.clock.now().add(IdentityConfig.recoveryLifetime);
    await c.credentials.insertRecoveryCode(
      tx,
      id: Uuid.v7(),
      accountId: accountId,
      codeHash: hashToken(code),
      expiresAt: expires,
    );
    return (code: code, expiresAt: expires);
  }

  Future<RecoveryLookupResponse> lookup(RecoveryLookupRequest req) async {
    final accountId = await c.credentials.validRecoveryAccount(
      c.db,
      hashToken(req.recoveryCode),
    );
    if (accountId == null) return const RecoveryLookupResponse(valid: false);
    return RecoveryLookupResponse(
      valid: true,
      verificationRequired: await _needsVerification(accountId),
    );
  }

  Future<bool> _needsVerification(String accountId) async =>
      c.config.sms.isConfigured &&
      await c.store.phoneHashOf(c.db, accountId) != null;

  Future<Session> redeem(RecoveryRedeemRequest req) async {
    if (req.identityKey.length != 32) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'identity_key'},
      );
    }
    if (req.password != null) c.checkPasswordSetup(req.password!);
    final accountId = await c.credentials.validRecoveryAccount(
      c.db,
      hashToken(req.recoveryCode),
    );
    if (accountId == null) throw const ApiError(ErrorCode.invalidCode);
    if (await _needsVerification(accountId)) {
      final verified = await c.verification(req.verificationToken);
      final phoneHash = await c.store.phoneHashOf(c.db, accountId);
      if (verified == null ||
          !constantTimeEquals(verified.phoneHash, phoneHash!)) {
        throw const ApiError(
          ErrorCode.invalidCode,
          message: 'verify the account phone number',
        );
      }
    }
    await verifyDeviceRegistration(
      accountId: accountId,
      accountIdentityKey: req.identityKey,
      device: req.device,
    );
    final session = await c.db.tx((tx) async {
      if (await c.credentials.consumeRecoveryCode(
            tx,
            hashToken(req.recoveryCode),
          ) !=
          accountId) {
        throw const ApiError(ErrorCode.invalidCode);
      }
      await c.revokeAll(tx, accountId, 'recovered');
      await c.store.setIdentityKey(tx, accountId, req.identityKey);
      await c.credentials.deletePassword(tx, accountId);
      await c.credentials.deleteRecoveryCodes(tx, accountId);
      if (req.password != null) {
        await c.storePassword(tx, accountId, req.password!);
      }
      await c.hooks.identityKeyChanged(tx, accountId, req.identityKey);
      await c.store.addEvent(tx, accountId, SecurityEventKind.recoveryUsed);
      return c.addDevice(
        tx,
        accountId: accountId,
        device: req.device,
        prekeys: req.prekeys,
        event: SecurityEventKind.deviceAdded,
        notifyOthers: false,
      );
    });
    if (req.verificationToken != null) {
      await c.spendVerification(req.verificationToken!);
    }
    return session;
  }
}
