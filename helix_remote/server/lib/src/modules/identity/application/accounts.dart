import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/application/context.dart';
import 'package:helix_remote_server/src/modules/identity/domain/secrets.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';

/// Signed-in account management: password, `~Helix name`, devices, push
/// tokens, security history, sign-out.
final class Accounts {
  Accounts(this.c);

  final IdentityContext c;

  /// Password changes per account. The current-password check also shares
  /// password sign-in's failure counter and lockout.
  static final passwordChangeLimit = RateLimitPolicy.per(
    'identity.password_change',
    10,
    const Duration(hours: 1),
  );

  static const _reservedNames = {
    'admin',
    'administrator',
    'helix',
    'helixglobal',
    'support',
    'help',
    'security',
    'official',
    'system',
    'root',
    'staff',
    'moderator',
    'team',
  };

  /// Names that could pass for Helix staff are never available.
  static bool _isReserved(String name) {
    final bare = name.replaceAll(RegExp('[._0-9]'), '');
    return _reservedNames.contains(bare) ||
        bare.startsWith('helix') ||
        const [
          'admin',
          'support',
          'official',
          'moderator',
          'security',
        ].any(bare.contains);
  }

  Future<AccountInfo> info(DevicePrincipal me) async {
    final account = (await c.store.account(c.db, me.accountId))!;
    final password = await c.credentials.password(c.db, me.accountId);
    return AccountInfo(
      accountId: account.id,
      identityKey: account.identityKey,
      createdAt: account.createdAt,
      hasPassword: password != null,
      helixName: account.helixName,
      phoneLast4: account.phoneLast4,
      passwordUpdatedAt: password?.time('updated_at'),
    );
  }

  Future<void> setPassword(DevicePrincipal me, SetPasswordRequest req) async {
    c.checkPasswordSetup(req.password);
    await c.limit(passwordChangeLimit, me.accountId);
    final existing = await c.credentials.password(c.db, me.accountId);
    if (existing != null) {
      if (req.currentAuthKey != null) {
        final (_, error) = await c.db.tx<(Row?, ApiError?)>(
          (tx) => c.checkPassword(tx, me.accountId, req.currentAuthKey!),
        );
        if (error != null) throw error;
      } else {
        final verified = await c.verification(req.verificationToken);
        final phoneHash = await c.store.phoneHashOf(c.db, me.accountId);
        if (verified == null ||
            phoneHash == null ||
            !constantTimeEquals(verified.phoneHash, phoneHash)) {
          throw const ApiError(
            ErrorCode.invalidCredentials,
            message:
                'give the current password or verify the account phone number',
          );
        }
      }
    }
    await c.db.tx((tx) async {
      await c.storePassword(tx, me.accountId, req.password);
      await c.store.addEvent(
        tx,
        me.accountId,
        SecurityEventKind.passwordChanged,
        deviceId: me.deviceId,
      );
      await c.hooks.accountSignal(
        tx,
        me.accountId,
        AccountSignalEvent(
          signal: AccountSignalKind.passwordChanged,
          at: c.clock.now(),
          device: me.deviceId,
        ),
        exceptDevice: me.deviceId,
      );
    });
    if (req.verificationToken != null) {
      await c.spendVerification(req.verificationToken!);
    }
  }

  /// Proof that the caller owns the account, not merely a session token
  /// (account deletion). A password is checked against its shared failure
  /// counter and lockout; a phone verification token must be for the
  /// account's own number and is spent; a device-key signature over a fresh
  /// challenge is accepted only when the account has neither a password nor
  /// a number the server can text, so it never replaces a stronger proof.
  Future<void> confirmOwnership(
    String accountId,
    String deviceId, {
    Uint8List? authKey,
    String? verificationToken,
    DeviceKeyProof? deviceProof,
  }) async {
    final hasPassword = await c.credentials.password(c.db, accountId) != null;
    final phoneHash = await c.store.phoneHashOf(c.db, accountId);
    final textable = phoneHash != null && c.config.sms.isConfigured;

    if (authKey != null && hasPassword) {
      final (_, error) = await c.db.tx<(Row?, ApiError?)>(
        (tx) => c.checkPassword(tx, accountId, authKey),
      );
      if (error != null) throw error;
      return;
    }
    if (verificationToken != null && textable) {
      final verified = await c.verification(verificationToken);
      if (verified != null &&
          constantTimeEquals(verified.phoneHash, phoneHash)) {
        await c.spendVerification(verificationToken);
        return;
      }
    }
    if (deviceProof != null &&
        !hasPassword &&
        !textable &&
        await _deviceProofHolds(accountId, deviceId, deviceProof)) {
      return;
    }
    throw ApiError(
      ErrorCode.invalidCredentials,
      message: 'confirm that this is your account',
      details: {
        'accepted': [
          if (hasPassword) 'current_auth_key',
          if (textable) 'verification_token',
          if (!hasPassword && !textable) 'device_proof',
        ],
      },
    );
  }

  Future<bool> _deviceProofHolds(
    String accountId,
    String deviceId,
    DeviceKeyProof proof,
  ) async {
    if (!Uuid.isValid(proof.challengeId)) return false;
    final raw = await c.ephemeral.take(
      '${IdentityContext.challengePrefix}${proof.challengeId}',
    );
    final stored = raw == null ? null : jsonDecode(raw) as Map<String, Object?>;
    if (stored == null ||
        stored['d'] != deviceId ||
        !constantTimeEquals(
          decodeBytes(stored['c']! as String),
          proof.challenge,
        )) {
      return false;
    }
    final device = await c.store.deviceById(c.db, deviceId);
    if (device == null || !device.active || device.accountId != accountId) {
      return false;
    }
    return verifyEd25519(
      publicKey: device.signingKey,
      message: deleteAccountSignatureBody(proof.challenge),
      signature: proof.signature,
    );
  }

  Future<void> setHelixName(DevicePrincipal me, SetHelixNameRequest req) async {
    final name = req.name.toLowerCase();
    if (!SetHelixNameRequest.pattern.hasMatch(name)) {
      throw const ApiError(ErrorCode.invalidField, details: {'field': 'name'});
    }
    if (_isReserved(name)) throw const ApiError(ErrorCode.nameTaken);
    try {
      await c.store.setHelixName(c.db, me.accountId, name);
    } on DbConstraintViolation catch (e) {
      if (e.kind == DbConstraintKind.unique) {
        throw const ApiError(ErrorCode.nameTaken);
      }
      rethrow;
    }
  }

  Future<void> clearHelixName(DevicePrincipal me) =>
      c.store.setHelixName(c.db, me.accountId, null);

  Future<Page<SecurityEvent>> events(
    DevicePrincipal me,
    PageRequest page,
  ) async {
    final rows = await c.store.events(
      c.db,
      me.accountId,
      before: page.cursor != null && Uuid.isValid(page.cursor!)
          ? page.cursor
          : null,
      limit: page.limit + 1,
    );
    final more = rows.length > page.limit;
    final items = rows.take(page.limit).toList();
    return Page(
      items: [for (final r in items) r.event],
      nextCursor: more ? items.last.id : null,
    );
  }

  Future<DeviceList> devices(DevicePrincipal me) async {
    final devices = await c.store.activeDevices(c.db, me.accountId);
    return DeviceList(
      devices: [
        for (final d in devices)
          DeviceInfo(
            deviceId: d.id,
            name: d.name,
            platform: d.platform,
            createdAt: d.createdAt,
            lastSeenOn: d.lastSeenOn,
            current: d.id == me.deviceId,
          ),
      ],
    );
  }

  Future<void> rename(
    DevicePrincipal me,
    String deviceId,
    RenameDeviceRequest req,
  ) async {
    final name = req.name.trim();
    if (name.isEmpty || name.length > DeviceRegistration.maxNameLength) {
      throw const ApiError(ErrorCode.invalidField, details: {'field': 'name'});
    }
    await c.store.renameDevice(c.db, me.accountId, deviceId, name);
  }

  /// Revokes one of the account's devices (or this device). Its tokens,
  /// push token and (through hooks) prekeys and mailbox go with it.
  Future<void> revoke(
    DevicePrincipal me,
    String deviceId, {
    required bool lost,
  }) async {
    final target = await c.store.deviceById(c.db, deviceId);
    if (target == null || target.accountId != me.accountId || !target.active) {
      throw const ApiError(ErrorCode.notFound);
    }
    await c.db.tx((tx) => _revoke(tx, me, deviceId, lost ? 'lost' : 'user'));
  }

  Future<int> revokeOthers(DevicePrincipal me) async {
    final others = (await c.store.activeDevices(
      c.db,
      me.accountId,
    )).where((d) => d.id != me.deviceId);
    return c.db.tx((tx) async {
      var n = 0;
      for (final d in others) {
        if (await _revoke(tx, me, d.id, 'user')) n++;
      }
      return n;
    });
  }

  Future<bool> _revoke(
    Tx tx,
    DevicePrincipal me,
    String deviceId,
    String reason,
  ) async {
    final revoked = await c.store.revokeDevice(tx, deviceId, reason);
    if (revoked == null) return false;
    await c.hooks.deviceRevoked(tx, revoked);
    await c.hooks.deviceListChanged(tx, me.accountId);
    await c.store.addEvent(
      tx,
      me.accountId,
      SecurityEventKind.deviceRevoked,
      deviceId: revoked.id,
      deviceName: revoked.name,
    );
    await c.hooks.accountSignal(
      tx,
      me.accountId,
      AccountSignalEvent(
        signal: AccountSignalKind.deviceRevoked,
        at: c.clock.now(),
        device: revoked.id,
        deviceName: revoked.name,
      ),
    );
    tx.afterCommit(
      () => c.bus.publish('device.revoked', {'device': revoked.id}),
    );
    return true;
  }

  Future<void> setPushToken(DevicePrincipal me, PushTokenRequest req) async {
    if (req.token.length > 4096) {
      throw const ApiError(ErrorCode.invalidField, details: {'field': 'token'});
    }
    await c.store.setPushToken(c.db, me.deviceId, req);
  }

  Future<void> clearPushToken(DevicePrincipal me) =>
      c.store.clearPushToken(c.db, me.deviceId);

  /// Ends this device's sessions; the device stays registered. Its socket
  /// closes (4001) and the account's other devices get `signed_out`.
  Future<void> signOut(DevicePrincipal me) => c.db.tx((tx) async {
    await c.sessions.endSessions(tx, c.store, me.deviceId);
    await c.hooks.accountSignal(
      tx,
      me.accountId,
      AccountSignalEvent(
        signal: AccountSignalKind.signedOut,
        at: c.clock.now(),
        device: me.deviceId,
      ),
      exceptDevice: me.deviceId,
    );
  });
}
