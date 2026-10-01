import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';

/// Which node holds a device's WebSocket (ADR-025). The realtime module
/// writes these routes with a heartbeat TTL; any module may read them to
/// decide between live delivery and a push. Kept in the kernel so modules
/// that need "is it online?" do not depend on the realtime module.
abstract final class Presence {
  static const routeTtl = Duration(seconds: 75);

  static String routeKey(String deviceId) => 'rt:route:$deviceId';

  static String lastSeenKey(String accountId) => 'rt:seen:$accountId';

  static Future<bool> isOnline(EphemeralStore store, String deviceId) async =>
      await store.get(routeKey(deviceId)) != null;

  static Future<Set<String>> online(
    EphemeralStore store,
    Iterable<String> deviceIds,
  ) async {
    final out = <String>{};
    for (final id in deviceIds) {
      if (await isOnline(store, id)) out.add(id);
    }
    return out;
  }
}
