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
