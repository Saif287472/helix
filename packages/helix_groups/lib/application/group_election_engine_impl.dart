import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_domain/domain/models.dart';

class GroupElectionEngineImpl {
  GroupElectionEngineImpl({required this._repository, required this._onNotify});

  final GroupRepository _repository;
  final void Function() _onNotify;

  GroupSnapshot electHostAfterCrash(
    String groupId, {
    Iterable<String>? activeFingerprints,
  }) {
    final group = _repository.loadGroup(groupId);
    if (group == null) throw ArgumentError('Unknown groupId');

    final allowed =
        (activeFingerprints ?? group.members.map((m) => m.fingerprint))
            .where((fp) => group.members.any((m) => m.fingerprint == fp))
            .where((fp) => !group.banned.contains(fp))
            .toList()
          ..sort();

    if (allowed.isEmpty) throw StateError('No eligible group hosts');

    final newHostFp = allowed.first;
    final newHostMember = group.members.firstWhere(
      (m) => m.fingerprint == newHostFp,
    );

    final updated = GroupSnapshot(
      groupId: group.groupId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: newHostFp,
      hostEndpoint: newHostMember.endpoint,
      epoch: group.epoch + 1,
      membershipVersion: group.membershipVersion + 1,
      members: group.members,
      pending: group.pending,
      banned: group.banned,
    );

    _repository.saveGroup(updated);
    _onNotify();
    return updated;
  }

  void electHostIfNeeded(GroupSnapshot group, {required bool bumpEpoch}) {
    final hasHost =
        group.members.any((m) => m.fingerprint == group.hostFingerprint) &&
        !group.banned.contains(group.hostFingerprint);
    if (hasHost) return;

    final eligible =
        group.members
            .where((m) => !group.banned.contains(m.fingerprint))
            .map((m) => m.fingerprint)
            .toList()
          ..sort();

    if (eligible.isEmpty) return;

    final newHostFp = eligible.first;
    final newHostMember = group.members.firstWhere(
      (m) => m.fingerprint == newHostFp,
    );

    final updated = GroupSnapshot(
      groupId: group.groupId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: newHostFp,
      hostEndpoint: newHostMember.endpoint,
      epoch: bumpEpoch ? group.epoch + 1 : group.epoch,
      membershipVersion: group.membershipVersion,
      members: group.members,
      pending: group.pending,
      banned: group.banned,
    );

    _repository.saveGroup(updated);
    _onNotify();
  }
}
