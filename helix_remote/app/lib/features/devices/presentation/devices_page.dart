import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/devices/application/device_activity.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the devices signed in to this account, drawn by `orbit_ui`'s
/// [orbit.DeviceListScreen]: rename, remove, lost or stolen, link a new one,
/// the recent security activity, and sign out every other device. The
/// screen confirms the destructive ones; what each did is a toast.
class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(devicesActionsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final notifier = ref.read(devicesActionsProvider.notifier);
    ref.listen(devicesActionsProvider, (_, next) {
      final error = next.error;
      final notice = next.notice;
      if (error != null) {
        orbit.showOrbitToast(context, error, error: true);
      } else if (notice != null) {
        orbit.showOrbitToast(context, notice);
      }
    });
    final list = devices.value;
    if (list == null) {
      return orbit.OrbitYouPage(
        title: 'Devices',
        children: [
          if (devices.hasError)
            orbit.OrbitLoadFailed(
              title: 'The device list could not be loaded.',
              onRetry: () => ref.invalidate(devicesProvider),
            )
          else
            const orbit.OrbitPageLoading(),
        ],
      );
    }
    final recent = ref.watch(securityEventsProvider).value ?? const [];

    return orbit.DeviceListScreen(
      model: orbit.DeviceListModel(
        devices: [
          for (final d in list)
            orbit.DeviceItem(
              id: d.id,
              name: d.title,
              platform: d.platform,
              whenLabel: d.seen,
              isThis: d.isThisDevice,
              icon: d.kind == DevicePlatformKind.desktop
                  ? orbit.OrbitIcons.desktop
                  : orbit.OrbitIcons.deviceMobile,
            ),
        ],
        recent: [for (final e in recent.take(3)) activityItemOf(e)],
      ),
      actions: orbit.DeviceListActions(
        onLinkNew: () => context.push(RoutePaths.devicesLink),
        onRename: notifier.rename,
        onRemove: notifier.revoke,
        onLost: (id) => notifier.revoke(id, lost: true),
        onAllActivity: () => context.push(RoutePaths.devicesActivity),
        onSignOutOthers: notifier.revokeOthers,
      ),
    );
  }
}
