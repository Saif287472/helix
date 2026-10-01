import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// Called when a device's one-time prekeys run low (at most hourly per
/// device). The messaging module turns it into a `prekeys_low` envelope.
typedef PrekeysLowHook = Future<void> Function(String deviceId, int remaining);

/// The keys module's facade (ADR-026).
abstract interface class KeysApi {
  /// Bundles for an account's active devices (optionally only [devices]),
  /// consuming one one-time prekey per device. Null if the account is
  /// unknown.
  Future<AccountKeys?> bundles(String accountId, {Set<String>? devices});

  void onPrekeysLow(PrekeysLowHook hook);

  Future<void> purgeAccount(Tx tx, List<String> deviceIds);
}
