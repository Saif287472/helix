import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/groups/application/create_group.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/group_navigation.dart';
import 'package:helix_remote/features/groups/groups_routes.dart';
import 'package:helix_remote/features/groups/presentation/widgets/member_picker.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// New group: a name, an optional picture, and the people to start with.
///
/// People who cannot be added (their privacy settings) are told so after the
/// group exists, and sent an invite link instead; the group is made either way.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await ref.read(createGroupProvider.notifier).create();
    if (created == null || !mounted) return;
    if (created.rejected.isNotEmpty) {
      await _explainRejected(created);
      if (!mounted) return;
    }
    final chat = ref.read(groupChatLocationProvider)(created.conversationId);
    // The create screen is replaced, so back from the new group goes home.
    context.pushReplacement(chat ?? GroupRoutes.info(created.groupId));
  }

  Future<void> _explainRejected(CreatedGroupInfo created) async {
    final names = [for (final account in created.rejected) _nameOf(account)];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Some people were not added'),
        content: Text(
          '${names.join(', ')} only ${names.length == 1 ? 'lets' : 'let'} '
          'people they know add them to groups. The group was created; send '
          'them an invite link from the group\'s page.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _nameOf(String account) {
    final all = ref.read(groupCandidatesProvider).value ?? const [];
    for (final c in all) {
      if (c.account == account) return c.names.display;
    }
    return 'Someone';
  }

  Future<void> _picture() async {
    final state = ref.read(createGroupProvider);
    if (state.picture == null) {
      await ref.read(createGroupProvider.notifier).pickPicture();
      return;
    }
    final choice = await showHelixBottomSheet<String>(
      context,
      title: 'Group picture',
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose another picture'),
            onTap: () => Navigator.pop(sheet, 'choose'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remove picture'),
            onTap: () => Navigator.pop(sheet, 'remove'),
          ),
        ],
      ),
    );
    if (choice == 'choose') {
      await ref.read(createGroupProvider.notifier).pickPicture();
    } else if (choice == 'remove') {
      ref.read(createGroupProvider.notifier).clearPicture();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createGroupProvider);
    final controller = ref.read(createGroupProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HelixSpace.md,
              HelixSpace.md,
              HelixSpace.md,
              0,
            ),
            child: Row(
              children: [
                _PictureButton(
                  picture: state.picture,
                  name: state.name,
                  onTap: _picture,
                ),
                const SizedBox(width: HelixSpace.md),
                Expanded(
                  child: TextField(
                    controller: _name,
                    maxLength: kGroupNameMaxLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      counterText: '',
                    ),
                    onChanged: controller.setName,
                  ),
                ),
              ],
            ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HelixSpace.md,
                HelixSpace.xs,
                HelixSpace.md,
                0,
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  state.error!,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          Expanded(
            child: MemberPicker(
              selected: state.selected,
              onToggle: controller.toggle,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.canCreate ? _create : null,
        icon: state.creating
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        label: Text(
          state.selected.isEmpty
              ? 'Create group'
              : 'Create with ${state.selected.length}',
        ),
      ),
    );
  }
}

class _PictureButton extends StatelessWidget {
  const _PictureButton({
    required this.picture,
    required this.name,
    required this.onTap,
  });

  final Uint8List? picture;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: picture == null ? 'Add a group picture' : 'Change group picture',
      child: ExcludeSemantics(
        child: InkResponse(
          onTap: onTap,
          radius: 40,
          child: SizedBox.square(
            dimension: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
                image: picture == null
                    ? null
                    : DecorationImage(
                        image: MemoryImage(picture!),
                        fit: BoxFit.cover,
                      ),
              ),
              child: picture == null
                  ? Icon(
                      Icons.add_a_photo_outlined,
                      color: scheme.onSecondaryContainer,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
