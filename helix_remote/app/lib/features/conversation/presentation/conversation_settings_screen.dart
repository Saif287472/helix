import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/conversation/application/conversation_links.dart';
import 'package:helix_remote/features/conversation/application/conversation_settings.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the settings of one conversation, mute, disappearing messages,
/// clear chat and block, drawn by `orbit_ui`'s chat settings page. A group's
/// members, roles and invite links are the groups feature's.
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
      return const orbit.ChatSettingsScreen(
        model: orbit.ChatSettingsModel(
          title: '',
          avatar: orbit.HelixAvatarModel(name: ''),
          loading: true,
        ),
      );
    }
    final info = ref.watch(conversationInfoRouteProvider(conversationId));
    final peer = view.peerAccount;
    return orbit.ChatSettingsScreen(
      model: orbit.ChatSettingsModel(
        title: view.title,
        subtitle: view.subtitle,
        avatar: view.avatar,
        isGroup: view.isGroup,
        hasInfoPage: info != null,
        muted: view.muted,
        muteChoices: [
          for (final length in MuteFor.values)
            (id: length.name, label: length.label),
        ],
        disappearingLabel: view.disappearingLabel,
        disappearingSeconds: view.disappearingSeconds,
        disappearingChoices: [
          for (final c in disappearingChoices)
            (seconds: c.seconds, label: c.label),
        ],
        blocked: view.blocked,
        wallpaper: view.wallpaper,
        bubbleTint: view.bubbleTint,
      ),
      actions: orbit.ChatSettingsActions(
        onOpenInfo: info == null ? null : () => context.push(info),
        onOpenSharedMedia: () =>
            context.push(sharedMediaLocation(conversationId)),
        onMute: (id) => unawaited(
          actions.mute(id == null ? null : MuteFor.values.byName(id)),
        ),
        onSetDisappearing: (seconds) =>
            unawaited(actions.setDisappearing(seconds)),
        onSetWallpaper: (w) => unawaited(actions.setWallpaper(w)),
        onSetBubbleTint: (t) => unawaited(actions.setBubbleTint(t)),
        onClear: () async {
          await actions.clear();
          if (context.mounted) orbit.showOrbitToast(context, 'Chat cleared');
        },
        onBlock: peer == null ? null : () => unawaited(actions.block(peer)),
        onUnblock: peer == null ? null : () => unawaited(actions.unblock(peer)),
      ),
    );
  }
}
