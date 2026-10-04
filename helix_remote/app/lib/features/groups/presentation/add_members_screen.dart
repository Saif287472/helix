import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_info.dart';
import 'package:helix_remote/features/groups/presentation/widgets/member_picker.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Add people to a group. Each person is asked of the server; those whose
/// privacy settings keep them out are named with a way forward (an invite
/// link), and the rest are in at once and handed the group key.
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

  Future<void> _add() async {
    setState(() => _adding = true);
    final result = await ref
        .read(groupActionsProvider)
        .addMembers(widget.groupId, _selected);
    if (!mounted) return;
    setState(() => _adding = false);
    final message = result.message;
    if (result.ok) {
      if (message != null) showHelixSnackBar(context, message);
      Navigator.of(context).pop();
      return;
    }
    // Nobody was added: stay, say why, and let the person choose again.
    if (message != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No one was added'),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(groupInfoProvider(widget.groupId)).value;
    final members = <String>{
      for (final m in info?.members ?? const <GroupMemberView>[]) m.account,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Add members')),
      body: MemberPicker(
        selected: _selected,
        onToggle: _toggle,
        exclude: members,
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _adding ? null : _add,
              icon: _adding
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1),
              label: Text('Add ${_selected.length}'),
            ),
    );
  }
}
