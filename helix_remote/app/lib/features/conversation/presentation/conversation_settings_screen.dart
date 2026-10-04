import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/conversation_settings.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings of one conversation: mute, disappearing messages, clear chat,
/// block. A group's members, roles and invite links are the groups feature's.
class ConversationSettingsScreen extends ConsumerWidget {
  const ConversationSettingsScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(conversationSettingsViewProvider(conversationId));
    final actions = ref.read(
      conversationSettingsActionsProvider(conversationId),
    );
    if (view == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    Future<void> chooseMute() async {
      final choice = await showMuteSheet(context, offerUnmute: view.muted);
      switch (choice) {
        case MuteLengthChoice(:final length):
          await actions.mute(length);
        case UnmuteChoice():
          await actions.mute(null);
        case null:
          break;
      }
    }

    Future<void> chooseDisappearing() async {
      final choice = await showHelixBottomSheet<DisappearingChoice>(
        context,
        title: 'Disappearing messages',
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in disappearingChoices)
              ListTile(
                title: Text(option.label),
                trailing: option.seconds == view.disappearingSeconds
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option),
              ),
          ],
        ),
      );
      if (choice != null) await actions.setDisappearing(choice.seconds);
    }

    Future<void> clearChat() async {
      final confirmed = await showHelixDestructiveDialog(
        context,
        title: 'Clear this chat?',
        message:
            'All messages are removed from this device. The chat stays in '
            'your list.',
        action: 'Clear',
      );
      if (confirmed) await actions.clear();
    }

    Future<void> toggleBlock() async {
      final peer = view.peerAccount;
      if (peer == null) return;
      if (view.blocked) {
        await actions.unblock(peer);
        return;
      }
      final confirmed = await showHelixDestructiveDialog(
        context,
        title: 'Block ${view.title}?',
        message:
            'They will not be able to message or call you. You can unblock '
            'them here at any time.',
        action: 'Block',
      );
      if (confirmed) await actions.block(peer);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Chat settings')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(HelixSpace.lg),
            child: Column(
              children: [
                HelixAvatar(
                  model: view.avatar,
                  size: HelixAvatarSize.xl,
                  semanticLabel: view.title,
                ),
                const SizedBox(height: HelixSpace.sm),
                Text(
                  view.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (view.subtitle != null)
                  Text(
                    view.subtitle!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          HelixSettingsSection(
            children: [
              HelixSettingsTile(
                icon: view.muted ? Icons.volume_off : Icons.volume_up_outlined,
                title: 'Mute notifications',
                subtitle: view.muted ? 'Muted' : 'Off',
                showChevron: true,
                onTap: chooseMute,
              ),
              HelixSettingsTile(
                icon: Icons.timer_outlined,
                title: 'Disappearing messages',
                subtitle: view.disappearingLabel,
                showChevron: true,
                onTap: chooseDisappearing,
              ),
            ],
          ),
          HelixSettingsSection(
            children: [
              HelixSettingsTile(
                icon: Icons.delete_sweep_outlined,
                title: 'Clear chat',
                destructive: true,
                onTap: clearChat,
              ),
              if (!view.isGroup)
                HelixSettingsTile(
                  icon: Icons.block,
                  title: view.blocked
                      ? 'Unblock ${view.title}'
                      : 'Block ${view.title}',
                  destructive: !view.blocked,
                  onTap: toggleBlock,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
