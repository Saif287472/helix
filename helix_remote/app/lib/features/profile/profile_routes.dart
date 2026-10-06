import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/profile/presentation/profile_page.dart';
import 'package:helix_remote/shared/route_paths.dart';

/// The profile page, added to the router with one line.
final List<RouteBase> profileRoutes = [
  GoRoute(
    path: RoutePaths.profile,
    builder: (context, state) => const ProfilePage(),
  ),
];
