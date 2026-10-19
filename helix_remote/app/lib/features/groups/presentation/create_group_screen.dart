import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/groups/application/create_group.dart';
import 'package:helix_remote/features/groups/application/group_navigation.dart';
import 'package:helix_remote/features/groups/groups_routes.dart';
import 'package:helix_remote/features/groups/presentation/member_picker_wiring.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: New group, a name, an optional picture and the people to start
/// with, drawn by `orbit_ui`'s page (`contracts/people_groups.md`).
///
/// People who cannot be added (their privacy settings) are told so after the
/// group exists, and sent an invite link instead; the group is made either
/// way.
class CreateGroupScreen extends ConsumerWidget {
  const CreateGroupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(createGroupProvider);
    final controller = ref.read(createGroupProvider.notifier);
    final picture = state.picture;
    return orbit.NewGroupScreen(
      model: orbit.NewGroupModel(
        name: state.name,
        nameError: state.nameErrorText,
        error: state.error,
        hasPicture: picture != null,
        picture: picture == null ? null : MemoryImage(picture),
        picker: memberPickerModel(ref, selected: state.selected),
        creating: state.creating,
      ),
      actions: orbit.NewGroupActions(
        onNameChanged: controller.setName,
        onChoosePicture: controller.pickPicture,
        onRemovePicture: controller.clearPicture,
        picker: memberPickerActions(ref, onToggle: controller.toggle),
        onCreate: () async {
          final created = await controller.create();
          if (created == null) return null;
          final people = ref.read(groupCandidatesProvider).value ?? const [];
          String nameOf(String account) =>
              people
                  .where((c) => c.account == account)
                  .firstOrNull
                  ?.names
                  .display ??
              'Someone';
          return (
            groupId: created.groupId,
            conversationId: created.conversationId,
            notAddedNames: [for (final a in created.rejected) nameOf(a)],
          );
        },
        // The create page is replaced, so back from the new group goes home.
        onOpenGroupChat: (groupId, conversationId) {
          final chat = ref.read(groupChatLocationProvider)(conversationId);
          context.pushReplacement(chat ?? GroupRoutes.info(groupId));
        },
      ),
    );
  }
}
