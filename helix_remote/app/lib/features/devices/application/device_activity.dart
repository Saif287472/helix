import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/features/devices/application/devices_models.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// One security event as an Orbit activity row: "Pixel 8 · 5 minutes ago".
orbit.ActivityItem activityItemOf(SecurityEventView e) => orbit.ActivityItem(
  icon: switch (e.type) {
    SecurityEventType.signedIn => orbit.OrbitIcons.deviceMobile,
    SecurityEventType.deviceAdded => orbit.OrbitIcons.phonePlus,
    SecurityEventType.deviceRevoked => orbit.OrbitIcons.prohibit,
    SecurityEventType.passwordChanged => orbit.OrbitIcons.password,
    SecurityEventType.recoveryUsed => orbit.OrbitIcons.key,
    SecurityEventType.identityChanged => orbit.OrbitIcons.key,
    SecurityEventType.other => orbit.OrbitIcons.shield,
  },
  title: e.title,
  detail: [?e.detail, e.when].join(' · '),
  check: e.needsAttention,
);

/// The security events split into the last seven days and earlier.
final securityActivityProvider =
    Provider.autoDispose<
      AsyncValue<
        ({List<SecurityEventView> week, List<SecurityEventView> earlier})
      >
    >((ref) {
      final weekAgo = ref
          .watch(clockProvider)()
          .subtract(const Duration(days: 7));
      return ref
          .watch(securityEventsProvider)
          .whenData(
            (list) => (
              week: [
                for (final e in list)
                  if (e.at.isAfter(weekAgo)) e,
              ],
              earlier: [
                for (final e in list)
                  if (!e.at.isAfter(weekAgo)) e,
              ],
            ),
          );
    });
