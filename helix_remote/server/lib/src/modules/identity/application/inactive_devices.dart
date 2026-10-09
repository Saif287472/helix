import 'package:helix_remote_server/src/modules/identity/application/context.dart';

/// Revokes devices nobody has used for `HELIX_DEVICE_INACTIVE_DAYS` days
/// (off by default). A device that is never opened but never signed out
/// (an old PC) otherwise collects every message to its account until its
/// mailbox overflows. An account always keeps its most recently used device.
final class InactiveDevices {
  InactiveDevices(this.c);

  final IdentityContext c;

  /// Revokes up to [batch] devices per round, for at most [rounds] rounds;
  /// returns how many. Each device is re-checked under its row lock, so one
  /// that signed in meanwhile is kept.
  Future<int> revoke({int batch = 200, int rounds = 10}) async {
    final days = c.config.inactiveDeviceDays;
    if (days <= 0) return 0;
    var total = 0;
    for (var round = 0; round < rounds; round++) {
      final candidates = await c.store.inactiveDevices(
        c.db,
        days: days,
        limit: batch,
      );
      var revoked = 0;
      for (final d in candidates) {
        final done = await c.db.tx((tx) async {
          if (!await c.store.stillInactive(tx, d.deviceId, days)) return false;
          return c.revokeDevice(tx, d.accountId, d.deviceId, 'inactive');
        });
        if (done) revoked++;
      }
      total += revoked;
      if (candidates.length < batch || revoked == 0) break;
    }
    if (total > 0) {
      c.log.info('devices_revoked_inactive', {'count': total, 'days': days});
    }
    return total;
  }
}
