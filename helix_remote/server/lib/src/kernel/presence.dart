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

  /// Which of [deviceIds] are online, in one store read (a send to many
  /// devices must not cost one round trip each).
  static Future<Set<String>> online(
    EphemeralStore store,
    Iterable<String> deviceIds,
  ) async {
    final ids = deviceIds.toList();
    if (ids.isEmpty) return {};
    final live = await store.getAll(ids.map(routeKey));
    return {
      for (final id in ids)
        if (live.containsKey(routeKey(id))) id,
    };
  }
}
