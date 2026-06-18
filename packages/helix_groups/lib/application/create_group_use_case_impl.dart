import 'package:uuid/uuid.dart';
import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix_domain/domain/models.dart';

class CreateGroupUseCaseImpl implements CreateGroupUseCase {
  CreateGroupUseCaseImpl({
    required this._repository,
    required this._localFingerprint,
    required this._localDisplayName,
    required this._localDeviceSuffix,
    required this._localEndpoint,
    required this._onNotify,
  });

  final GroupRepository _repository;
  final String Function() _localFingerprint;
  final String Function() _localDisplayName;
  final String Function() _localDeviceSuffix;
  final String Function() _localEndpoint;
  final void Function() _onNotify;

  static const _uuid = Uuid();
  static const publicLobbyId = 'public-lobby';

  @override
  Future<GroupSnapshot> createPublicLobby() async {
    final lf = _localFingerprint();
    if (lf.isEmpty) {
      throw StateError('GroupService local identity is not configured');
    }

    final existing = _repository.loadGroup(publicLobbyId);
    if (existing != null) return existing;

    final record = GroupSnapshot(
      groupId: publicLobbyId,
      name: 'LAN Lobby',
      visibility: GroupVisibility.publicLobby,
      hostFingerprint: lf,
      hostEndpoint: _localEndpoint(),
      epoch: 0,
      membershipVersion: 1,
      members: [
        GroupMember(
          fingerprint: lf,
          displayName: _localDisplayName(),
          deviceSuffix: _localDeviceSuffix(),
          endpoint: _localEndpoint(),
          joinedAt: DateTime.now(),
          isAdmin: true,
        ),
      ],
      pending: const [],
      banned: const {},
    );

    await _repository.saveGroup(record);
    _onNotify();
    return record;
  }

  @override
  Future<GroupSnapshot> createPrivateGroup(String displayName) async {
    final lf = _localFingerprint();
    if (lf.isEmpty) {
      throw StateError('GroupService local identity is not configured');
    }

    final id = _uuid.v4();
    final name = displayName.trim().isEmpty
        ? 'Private group'
        : displayName.trim();

    final record = GroupSnapshot(
      groupId: id,
      name: name,
      visibility: GroupVisibility.private,
      hostFingerprint: lf,
      hostEndpoint: _localEndpoint(),
      epoch: 0,
      membershipVersion: 1,
      members: [
        GroupMember(
          fingerprint: lf,
          displayName: _localDisplayName(),
          deviceSuffix: _localDeviceSuffix(),
          endpoint: _localEndpoint(),
          joinedAt: DateTime.now(),
          isAdmin: true,
        ),
      ],
      pending: const [],
      banned: const {},
    );

    await _repository.saveGroup(record);
    _onNotify();
    return record;
  }
}
