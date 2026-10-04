import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/group_navigation.dart';
import 'package:helix_remote/features/groups/groups_routes.dart';
import 'package:helix_remote/features/groups/presentation/widgets/group_avatar.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Join a group with a link: see who it is, then decide.
///
/// Opened from a shared `HLX-GRP-…` link (`https://…/open#HLX-GRP-…` or
/// `helix://open?code=…`) with the link ready, or empty to paste one.
/// Previewing changes nothing on the server; **joining is a separate, explicit
/// button**, so tapping a link never puts anybody in a group by itself.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, this.initialLink});

  final String? initialLink;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final TextEditingController _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialLink;
    if (initial != null && initial.trim().isNotEmpty) {
      _link.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(joinByLinkProvider.notifier).preview(initial);
      });
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) setState(() => _link.text = text);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Join a group')),
      body: switch (state.stage) {
        JoinStage.input => _InputView(
          controller: _link,
          onPaste: _paste,
          onPreview: () => controller.preview(_link.text),
        ),
        JoinStage.loading => const _Busy(message: 'Opening the link…'),
        JoinStage.joining => const _Busy(message: 'Joining…'),
        JoinStage.preview => _PreviewView(
          preview: state.preview!,
          alreadyMember: state.alreadyMember,
          onJoin: controller.join,
          onOpen: () => _openGroup(state.groupId!),
          onCancel: () => Navigator.of(context).maybePop(),
        ),
        JoinStage.joined => _DoneView(
          icon: Icons.check_circle_outline,
          title: 'You joined ${_nameOf(state.preview)}',
          message: 'You are in the group now.',
          primaryLabel: 'Open group',
          onPrimary: () => _openGroup(state.groupId!),
        ),
        JoinStage.pending => _DoneView(
          icon: Icons.hourglass_top,
          title: 'Request sent',
          message:
              'An admin of ${_nameOf(state.preview)} has to approve you. You '
              'will see the group when they do.',
          primaryLabel: 'Done',
          onPrimary: () => Navigator.of(context).maybePop(),
        ),
        JoinStage.failed => HelixErrorState(
          message: state.error ?? 'That link did not work.',
          onRetry: controller.reset,
        ),
      },
    );
  }

  static String _nameOf(InvitePreviewInfo? preview) {
    final name = preview?.name ?? '';
    return name.isEmpty ? 'the group' : '"$name"';
  }
}

class _InputView extends StatelessWidget {
  const _InputView({
    required this.controller,
    required this.onPaste,
    required this.onPreview,
  });

  final TextEditingController controller;
  final VoidCallback onPaste;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(HelixSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste the group link you were sent. It starts with '
            'https:// or helix:// and ends with HLX-GRP-…',
          ),
          const SizedBox(height: HelixSpace.md),
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Group link',
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste),
                tooltip: 'Paste',
                onPressed: onPaste,
              ),
            ),
            onSubmitted: (_) => onPreview(),
          ),
          const SizedBox(height: HelixSpace.md),
          FilledButton(onPressed: onPreview, child: const Text('Continue')),
        ],
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: HelixSpace.md),
        Semantics(liveRegion: true, child: Text(message)),
      ],
    ),
  );
}

class _PreviewView extends StatelessWidget {
  const _PreviewView({
    required this.preview,
    required this.alreadyMember,
    required this.onJoin,
    required this.onOpen,
    required this.onCancel,
  });

  final InvitePreviewInfo preview;
  final bool alreadyMember;
  final VoidCallback onJoin;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = preview.name.isEmpty ? 'Group' : preview.name;
    final pointer = preview.avatarPointer;
    final members = preview.memberCount;
    return ListView(
      padding: const EdgeInsets.all(HelixSpace.lg),
      children: [
        Center(
          child: GroupAvatar(
            model: HelixAvatarModel(
              name: name,
              colorIndex: HelixAvatarModel.colorIndexFor(preview.groupId),
              isGroup: true,
            ),
            pictureKey: pointer == null ? null : jsonEncode(pointer),
          ),
        ),
        const SizedBox(height: HelixSpace.sm),
        Semantics(
          header: true,
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
        ),
        Text(
          members == 1 ? '1 member' : '$members members',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (preview.name.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: HelixSpace.sm),
            child: Text(
              'This link did not open the group\'s name. It may be cut off; '
              'you can still ask to join.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        if ((preview.description ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: HelixSpace.md),
            child: Text(
              preview.description!.trim(),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: HelixSpace.lg),
        if (alreadyMember) ...[
          const Text(
            'You are already in this group.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HelixSpace.md),
          FilledButton(onPressed: onOpen, child: const Text('Open group')),
        ] else ...[
          if (preview.requiresApproval)
            const Padding(
              padding: EdgeInsets.only(bottom: HelixSpace.md),
              child: Text(
                'An admin has to approve you before you are in.',
                textAlign: TextAlign.center,
              ),
            ),
          FilledButton(
            onPressed: onJoin,
            child: Text(
              preview.requiresApproval ? 'Ask to join' : 'Join group',
            ),
          ),
          const SizedBox(height: HelixSpace.xs),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ],
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) => HelixEmptyState(
    icon: icon,
    title: title,
    message: message,
    action: FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
  );
}
