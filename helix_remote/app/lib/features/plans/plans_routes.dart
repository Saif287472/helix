import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/plans/presentation/premium_page.dart';
import 'package:helix_remote/shared/route_paths.dart';

/// The Orbit Premium page, added to the router with one line.
final List<RouteBase> plansRoutes = [
  GoRoute(
    path: RoutePaths.premium,
    builder: (context, state) => const PremiumPage(),
  ),
];
