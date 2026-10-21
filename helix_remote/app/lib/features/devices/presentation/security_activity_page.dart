import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/devices/application/device_activity.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: sign-ins, devices and key changes, newest first, drawn by
/// `orbit_ui`'s [orbit.SecurityActivityScreen]. A key change or a recovery
/// is marked for a second look.
class SecurityActivityPage extends ConsumerWidget {
  const SecurityActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(securityActivityProvider);
    final list = events.value;
    if (list == null) {
      return orbit.OrbitYouPage(
        title: 'Security activity',
        children: [
          if (events.hasError)
            orbit.OrbitLoadFailed(
              title: 'The activity could not be loaded.',
              onRetry: () => ref.invalidate(securityEventsProvider),
            )
          else
            const orbit.OrbitPageLoading(),
        ],
      );
    }
    return orbit.SecurityActivityScreen(
      model: orbit.SecurityActivityModel(
        thisWeek: [for (final e in list.week) activityItemOf(e)],
        earlier: [for (final e in list.earlier) activityItemOf(e)],
        deviceCount: ref.watch(devicesProvider).value?.length ?? 1,
      ),
      actions: orbit.SecurityActivityActions(
        onDevices: () => context.push(RoutePaths.devices),
        onPassword: () => context.push(RoutePaths.changePassword),
      ),
    );
  }
}
