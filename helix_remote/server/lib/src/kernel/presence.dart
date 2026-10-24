import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';

/// Which node holds a device's WebSocket (ADR-025). The realtime module
/// writes these routes with a heartbeat TTL; any module may read them to
/// decide between live delivery and a push. Kept in the kernel so modules
/// that need "is it online?" do not depend on the realtime module.
///
/// A route is only half the fact: it says a socket was written down, not that
/// the node holding it is still running. So every node renews a liveness key
/// of its own, and these reads require both. A crashed node's routes then
/// stop meaning "reachable" after [nodeTtl] instead of after [routeTtl]
/// (AUD-3-3), and the conservative direction is a push, never a silent drop.
abstract final class Presence {
  static const routeTtl = Duration(seconds: 75);

  /// How long a node may go without renewing its liveness key before the
  /// devices behind its routes count as offline. Shorter than [routeTtl] on
  /// purpose.
  static const nodeTtl = Duration(seconds: 20);

  /// How often a node renews its own key; four renewals fit in [nodeTtl], so
  /// one stalled database round trip does not empty the node.
  static const nodeRefresh = Duration(seconds: 5);

  static String routeKey(String deviceId) => 'rt:route:$deviceId';

  static String nodeKey(String nodeId) => 'rt:node:$nodeId';

  static String lastSeenKey(String accountId) => 'rt:seen:$accountId';

  /// The node a route value names: `<node id>|<connection id>`.
  static String nodeOf(String route) {
    final bar = route.indexOf('|');
    return bar < 0 ? route : route.substring(0, bar);
  }

  static Future<bool> isOnline(EphemeralStore store, String deviceId) async {
    final route = await store.get(routeKey(deviceId));
    if (route == null) return false;
    return await store.get(nodeKey(nodeOf(route))) != null;
  }

  /// Which of [deviceIds] are online, in two store reads whatever the device
  /// count (a send to many devices must not cost one round trip each): one
  /// for their routes, one for the nodes they sit on.
  static Future<Set<String>> online(
    EphemeralStore store,
    Iterable<String> deviceIds,
  ) async {
    final ids = deviceIds.toList();
    if (ids.isEmpty) return {};
    final routes = await store.getAll(ids.map(routeKey));
    if (routes.isEmpty) return {};
    final alive = await store.getAll({
      for (final route in routes.values) nodeKey(nodeOf(route)),
    });
    bool reached(String id) {
      final route = routes[routeKey(id)];
      return route != null && alive.containsKey(nodeKey(nodeOf(route)));
    }

    return {
      for (final id in ids)
        if (reached(id)) id,
    };
  }
}
