import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:helix_remote/features/groups/application/group_navigation.dart';
import 'package:helix_remote/features/groups/application/group_picture.dart';
import 'package:helix_remote/features/groups/groups_routes.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: join a group with a link, see who it is, then decide, drawn by
/// `orbit_ui`'s Join a group.
///
/// Opened from a shared `HLX-GRP-…` link (`https://…/open#HLX-GRP-…` or
/// `helix://open?code=…`) with the link ready, or empty to paste one.
/// Previewing changes nothing on the server; **joining is a separate,
/// explicit button**, so tapping a link never puts anybody in a group by
/// itself.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, this.initialLink});

  final String? initialLink;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  @override
  void initState() {
    super.initState();
    final initial = widget.initialLink;
    if (initial != null && initial.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(joinByLinkProvider.notifier).preview(initial);
      });
    }
  }

  void _openGroup(String groupId) {
    final chat = ref.read(groupChatLocationProvider)(
      groupConversationId(groupId),
    );
    context.pushReplacement(chat ?? GroupRoutes.info(groupId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(joinByLinkProvider);
    final controller = ref.read(joinByLinkProvider.notifier);
    final preview = state.preview;
    final pointer = preview?.avatarPointer;
    final bytes = pointer == null
        ? null
        : ref.watch(groupPictureProvider(jsonEncode(pointer))).value;
    final name = preview?.name ?? '';
    return orbit.JoinGroupScreen(
      model: orbit.JoinGroupModel(
        stage: orbit.JoinStage.values.byName(state.stage.name),
        initialLink: widget.initialLink ?? '',
        previewName: name,
        previewMemberCount: preview?.memberCount ?? 0,
        previewDescription: preview?.description?.trim(),
        previewAvatar: orbit.HelixAvatarModel(
          name: name.isEmpty ? 'Group' : name,
          colorIndex: orbit.HelixAvatarModel.colorIndexFor(
            preview?.groupId ?? 'group',
          ),
          isGroup: true,
          image: bytes == null ? null : MemoryImage(bytes),
        ),
        requiresApproval: preview?.requiresApproval ?? false,
        alreadyMember: state.alreadyMember,
        error: state.error,
      ),
      actions: orbit.JoinGroupActions(
        onContinue: controller.preview,
        linkLooksRight: looksLikeGroupLink,
        onJoin: controller.join,
        onOpenGroup: () {
          final id = state.groupId;
          if (id != null) _openGroup(id);
        },
        onRetry: controller.reset,
      ),
    );
  }
}
