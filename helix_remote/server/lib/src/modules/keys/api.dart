import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// Called when a device's one-time prekeys run low (at most hourly per
/// device). The messaging module turns it into a `prekeys_low` envelope.
typedef PrekeysLowHook = Future<void> Function(String deviceId, int remaining);

/// Bundles of accounts on other servers (installed by the federation
/// module).
abstract interface class RemoteKeySource {
  /// This server's domain: addresses qualified with it are local.
  String get localDomain;

  /// [accountId]'s bundles from [domain]'s server (consuming one-time
  /// prekeys there); null if that server does not know the account.
  Future<AccountKeys?> fetch(
    String domain,
    String accountId, {
    Set<String>? devices,
  });
}

/// The keys module's facade (ADR-026).
abstract interface class KeysApi {
  /// Bundles for an account's active devices (optionally only [devices]),
  /// consuming one one-time prekey per device. Null if the account is
  /// unknown.
  Future<AccountKeys?> bundles(String accountId, {Set<String>? devices});

  /// [bundles] for another server: also counts against the account's
  /// per-target limit (`keys.bundle_target`) that local fetches share, so
  /// many servers cannot together drain its one-time prekeys.
  Future<AccountKeys?> remoteBundles(String accountId, {Set<String>? devices});

  void onPrekeysLow(PrekeysLowHook hook);

  void setRemoteSource(RemoteKeySource source);

  Future<void> purgeAccount(Tx tx, List<String> deviceIds);
}
