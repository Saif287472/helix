import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/groups/presentation/add_members_screen.dart';
import 'package:helix_remote/features/groups/presentation/banned_members_screen.dart';
import 'package:helix_remote/features/groups/presentation/create_group_screen.dart';
import 'package:helix_remote/features/groups/presentation/group_info_screen.dart';
import 'package:helix_remote/features/groups/presentation/group_invite_screen.dart';
import 'package:helix_remote/features/groups/presentation/group_settings_screen.dart';
import 'package:helix_remote/features/groups/presentation/join_group_screen.dart';
import 'package:helix_remote/features/groups/presentation/join_requests_screen.dart';

/// The groups feature's routes: the management screens. (The group
/// *conversation* is the chats feature's.)
abstract final class GroupRoutes {
  static const _base = '/home/groups';

  /// New group: members, name, picture.
  static const create = '$_base/new';

  /// Join with a link. Opened with the link as the route's `extra` (a string)
  /// from a shared `HLX-GRP-…` link, or without one to paste a link.
  static const join = '$_base/join';

  static String info(String groupId) =>
      '$_base/${Uri.encodeComponent(groupId)}';
  static String settings(String groupId) => '${info(groupId)}/settings';
  static String invite(String groupId) => '${info(groupId)}/invite';
  static String requests(String groupId) => '${info(groupId)}/requests';
  static String banned(String groupId) => '${info(groupId)}/banned';
  static String addMembers(String groupId) => '${info(groupId)}/add';
}

/// Registered by the router with one line (`...groupsRoutes`). The fixed paths
/// come before the `:groupId` ones so `new` and `join` are never read as ids.
final List<RouteBase> groupsRoutes = [
  GoRoute(
    path: GroupRoutes.create,
    builder: (context, state) => const CreateGroupScreen(),
  ),
  GoRoute(
    path: GroupRoutes.join,
    builder: (context, state) => JoinGroupScreen(
      initialLink: state.extra is String ? state.extra as String : null,
    ),
  ),
  GoRoute(
    path: '${GroupRoutes._base}/:groupId',
    builder: (context, state) =>
        GroupInfoScreen(groupId: state.pathParameters['groupId'] ?? ''),
    routes: [
      GoRoute(
        path: 'settings',
        builder: (context, state) =>
            GroupSettingsScreen(groupId: state.pathParameters['groupId'] ?? ''),
      ),
      GoRoute(
        path: 'invite',
        builder: (context, state) =>
            GroupInviteScreen(groupId: state.pathParameters['groupId'] ?? ''),
      ),
      GoRoute(
        path: 'requests',
        builder: (context, state) =>
            JoinRequestsScreen(groupId: state.pathParameters['groupId'] ?? ''),
      ),
      GoRoute(
        path: 'banned',
        builder: (context, state) =>
            BannedMembersScreen(groupId: state.pathParameters['groupId'] ?? ''),
      ),
      GoRoute(
        path: 'add',
        builder: (context, state) =>
            AddMembersScreen(groupId: state.pathParameters['groupId'] ?? ''),
      ),
    ],
  ),
];
