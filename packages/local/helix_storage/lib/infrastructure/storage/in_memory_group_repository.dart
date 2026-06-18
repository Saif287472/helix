import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_domain/domain/models.dart';

class InMemoryGroupRepository implements GroupRepository {
  final Map<String, GroupSnapshot> _groups = {};

  @override
  List<GroupSnapshot> listGroups() {
    final list = _groups.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(list);
  }

  @override
  GroupSnapshot? loadGroup(String groupId) {
    return _groups[groupId];
  }

  @override
  Future<void> saveGroup(GroupSnapshot group) async {
    _groups[group.groupId] = group;
  }

  @override
  Future<void> removeGroup(String groupId) async {
    _groups.remove(groupId);
  }
}
