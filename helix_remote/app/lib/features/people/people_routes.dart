import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/people/presentation/contact_info_screen.dart';
import 'package:helix_remote/features/people/presentation/people_search_screen.dart';
import 'package:helix_remote/features/people/presentation/safety_number_screen.dart';
import 'package:helix_remote/features/people/presentation/safety_scan_screen.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote/shared/widgets/people_search_panel.dart';

/// The people routes (see `PeoplePaths` for the paths). `search` is declared
/// before the `:id` routes so it is not read as an account id.
final List<RouteBase> peopleRoutes = [
  GoRoute(
    path: PeoplePaths.home,
    builder: (context, state) => const PeopleSearchScreen(),
  ),
  GoRoute(
    path: PeoplePaths.search,
    builder: (context, state) => PeopleSearchScreen(
      mode: state.uri.queryParameters['mode'] == 'calls'
          ? PeopleSearchMode.calls
          : PeopleSearchMode.chats,
    ),
  ),
  GoRoute(
    path: '${PeoplePaths.home}/:id',
    builder: (context, state) =>
        ContactInfoScreen(accountId: state.pathParameters['id']!),
    routes: [
      GoRoute(
        path: 'safety',
        builder: (context, state) =>
            SafetyNumberScreen(accountId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'scan',
        builder: (context, state) =>
            SafetyScanScreen(accountId: state.pathParameters['id']!),
      ),
    ],
  ),
];
