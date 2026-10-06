import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/devices/presentation/approve_device_page.dart';
import 'package:helix_remote/features/devices/presentation/devices_page.dart';
import 'package:helix_remote/features/devices/presentation/link_this_device_page.dart';
import 'package:helix_remote/features/devices/presentation/security_activity_page.dart';
import 'package:helix_remote/shared/route_paths.dart';

/// The device pages, added to the router with one line.
final List<RouteBase> devicesRoutes = [
  GoRoute(
    path: RoutePaths.devices,
    builder: (context, state) => const DevicesPage(),
  ),
  GoRoute(
    path: RoutePaths.devicesLink,
    builder: (context, state) => const ApproveDevicePage(),
  ),
  GoRoute(
    path: RoutePaths.devicesActivity,
    builder: (context, state) => const SecurityActivityPage(),
  ),
  // The new device's side of linking. Open while signed out; the router lets
  // it through and sends the device to the restore step when it signs in.
  GoRoute(
    path: RoutePaths.linkThisDevice,
    builder: (context, state) => const LinkThisDevicePage(),
  ),
];
