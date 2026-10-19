import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_info.dart';
import 'package:helix_remote/features/groups/presentation/member_picker_wiring.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: add people to a group, drawn by `orbit_ui`'s Add members.
/// Each person is asked of the server; those whose privacy settings keep them
/// out are named with a way forward (an invite link), and the rest are in at
/// once and handed the group key.
class AddMembersScreen extends ConsumerStatefulWidget {
  const AddMembersScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends ConsumerState<AddMembersScreen> {
  List<String> _selected = const [];
  bool _adding = false;

  void _toggle(String account) {
    final next = [..._selected];
    if (!next.remove(account)) next.add(account);
    setState(() => _selected = next);
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(groupInfoProvider(widget.groupId)).value;
    final members = <String>{
      for (final m in info?.members ?? const <GroupMemberView>[]) m.account,
    };
    return orbit.AddMembersScreen(
      model: orbit.AddMembersModel(
        picker: memberPickerModel(ref, selected: _selected, exclude: members),
        adding: _adding,
      ),
      actions: orbit.AddMembersActions(
        picker: memberPickerActions(ref, onToggle: _toggle),
        onAdd: () async {
          setState(() => _adding = true);
          final result = await ref
              .read(groupActionsProvider)
              .addMembers(widget.groupId, _selected);
          if (mounted) setState(() => _adding = false);
          return (ok: result.ok, message: result.message);
        },
      ),
    );
  }
}
