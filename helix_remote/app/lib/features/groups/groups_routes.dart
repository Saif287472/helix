import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/groups/presentation/add_members_screen.dart';
import 'package:helix_remote/features/groups/presentation/banned_members_screen.dart';
import 'package:helix_remote/features/groups/presentation/create_group_screen.dart';
import 'package:helix_remote/features/groups/presentation/group_info_screen.dart';
import 'package:helix_remote/features/groups/presentation/group_invite_screen.dart';
import 'package:helix_remote/features/groups/presentation/group_settings_screen.dart';
import 'package:helix_remote/features/groups/presentation/join_group_screen.dart';
import 'package:helix_remote/features/groups/presentation/join_requests_screen.dart';
import 'package:helix_remote/shared/navigation/group_paths.dart';

/// The groups feature's routes: the management screens. (The group
/// *conversation* is the conversation feature's.) The paths are shared
/// (`GroupPaths`) so other features can link here without importing this one.
abstract final class GroupRoutes {
  /// New group: members, name, picture.
  static const create = GroupPaths.create;

  /// Join with a link. Opened with the link as the route's `extra` (a string)
  /// from a shared `HLX-GRP-…` link, or without one to paste a link.
  static const join = GroupPaths.join;

  static String info(String groupId) => GroupPaths.info(groupId);
  static String settings(String groupId) => GroupPaths.settings(groupId);
  static String invite(String groupId) => GroupPaths.invite(groupId);
  static String requests(String groupId) => GroupPaths.requests(groupId);
  static String banned(String groupId) => GroupPaths.banned(groupId);
  static String addMembers(String groupId) => GroupPaths.addMembers(groupId);
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
    path: '${GroupPaths.base}/:groupId',
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
