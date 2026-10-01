import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Group federation transport (installed by the federation module). Every
/// payload is already in the receiving server's frame.
abstract interface class GroupRelay {
  /// This server's domain.
  String get localDomain;

  /// A local member's action on a group homed on [home].
  Future<S2SGroupActionResult> action(
    String home,
    String groupId,
    S2SGroupAction action,
  );

  /// The group as [home] shows it to this server; null if it is unknown
  /// there or has no members here.
  Future<Group?> fetchGroup(String home, String groupId);

  /// Pushes a snapshot and roster change to a member's server.
  Future<S2SGroupSyncResponse> sync(
    String domain,
    String groupId,
    S2SGroupSync sync,
  );

  /// Fans a group message out to a member's server.
  Future<void> message(String domain, String groupId, S2SGroupMessage message);
}

/// The groups module's facade for federation (ADR-026).
abstract interface class GroupsApi {
  void setRelay(GroupRelay relay);

  /// An action from a member on [domain] on a group homed here.
  Future<S2SGroupActionResult> receiveAction(
    String domain,
    String groupId,
    S2SGroupAction action,
  );

  /// The group in [domain]'s frame, if it is homed here and has members
  /// there.
  Future<Group?> viewFor(String domain, String groupId);

  /// A snapshot pushed by the group's home server [domain].
  Future<S2SGroupSyncResponse> receiveSync(
    String domain,
    String groupId,
    S2SGroupSync sync,
  );

  /// A group message fanned out by the group's home server [domain].
  Future<void> receiveMessage(
    String domain,
    String groupId,
    S2SGroupMessage message,
  );
}
