/// The group routes, by path, so any feature can link to them without
/// importing the groups feature (features never import each other). The routes
/// themselves are registered by `features/groups/groups_routes.dart`, which
/// builds its own `GroupRoutes` from these.
abstract final class GroupPaths {
  static const base = '/home/groups';

  /// New group: members, name, picture.
  static const create = '$base/new';

  /// Join with a link. Opened with the link as the route's `extra` (a string),
  /// or without one to paste a link.
  static const join = '$base/join';

  /// The info page of the group [groupId] (the bare id, not `group:<id>`).
  static String info(String groupId) => '$base/${Uri.encodeComponent(groupId)}';
  static String settings(String groupId) => '${info(groupId)}/settings';
  static String invite(String groupId) => '${info(groupId)}/invite';
  static String requests(String groupId) => '${info(groupId)}/requests';
  static String banned(String groupId) => '${info(groupId)}/banned';
  static String addMembers(String groupId) => '${info(groupId)}/add';
}
