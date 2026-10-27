import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/core/security/device_auth.dart';
import 'package:helix_remote/core/security/locked_chats.dart';
import 'package:helix_remote/shared/wallpaper.dart';
import 'package:helix_remote/shared/widgets/locked_chat_gate.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart';
import 'package:orbit_ui/models.dart';

/// One timer the disappearing-messages sheet offers.
@immutable
class DisappearingChoice {
  const DisappearingChoice(this.seconds, this.label);

  /// Null is "Off".
  final int? seconds;
  final String label;
}

/// The timers offered, from off to 90 days.
final disappearingChoices = [
  for (final seconds in const <int?>[
    null,
    5 * 60,
    60 * 60,
    24 * 60 * 60,
    7 * 24 * 60 * 60,
    90 * 24 * 60 * 60,
  ])
    DisappearingChoice(seconds, describeDisappearing(seconds)),
];

/// What the conversation settings page shows, as finished text.
@immutable
class ConversationSettingsView {
  const ConversationSettingsView({
    required this.title,
    required this.avatar,
    required this.muted,
    required this.disappearingLabel,
    required this.isGroup,
    this.subtitle,
    this.peerAccount,
    this.blocked = false,
    this.disappearingSeconds,
    this.wallpaper,
    this.bubbleTint = HelixBubbleTint.theme,
    this.locked = false,
  });

  /// The chat's own wallpaper; null follows the default.
  final HelixWallpaper? wallpaper;

  /// The colour of your own bubbles in the chat.
  final HelixBubbleTint bubbleTint;

  /// The chat is locked.
  final bool locked;
  final String title;
  final String? subtitle;
  final HelixAvatarModel avatar;
  final bool muted;
  final String disappearingLabel;
  final int? disappearingSeconds;
  final bool isGroup;
  final String? peerAccount;
  final bool blocked;
}

/// The settings page's content, or null until the chat has loaded.
final conversationSettingsViewProvider = Provider.autoDispose
    .family<ConversationSettingsView?, String>((ref, id) {
      final header = ref.watch(conversationHeaderProvider(id));
      if (header == null) return null;
      return ConversationSettingsView(
        title: header.title,
        subtitle: header.subtitle,
        avatar: header.avatar,
        muted: header.muted,
        disappearingLabel: describeDisappearing(header.disappearingSeconds),
        disappearingSeconds: header.disappearingSeconds,
        isGroup: header.isGroup,
        peerAccount: header.peerAccount,
        blocked: header.blocked,
        wallpaper: ref.watch(chatWallpaperChoiceProvider(id)).value,
        locked: ref.watch(chatLockedProvider(id)).value ?? false,
        bubbleTint:
            ref.watch(chatBubbleTintProvider(id)).value ??
            HelixBubbleTint.theme,
      );
    });

/// What a person can change about one conversation from its settings: mute,
/// disappearing messages, clear, block. The group's own management (members,
/// roles, invite links) is the groups feature's.
final class ConversationSettingsActions {
  ConversationSettingsActions(this._ref, this.conversationId);

  final Ref _ref;
  final String conversationId;

  Future<ChatGateway> get _gateway => _ref.read(chatGatewayProvider.future);

  /// Mutes for [length]; null unmutes.
  Future<void> mute(MuteFor? length) async {
    final now = _ref.read(clockProvider)();
    await (await _gateway).setMutedUntil(conversationId, length?.until(now));
  }

  /// Sets the timer (null turns it off) and tells the other side.
  Future<void> setDisappearing(int? seconds) async =>
      (await _gateway).setDisappearing(conversationId, seconds);

  /// Removes every message from this device; the chat stays.
  Future<void> clear() async => (await _gateway).clearChat(conversationId);

  /// Gives this chat its own wallpaper; null follows the default again.
  Future<void> setWallpaper(HelixWallpaper? wallpaper) => _ref
      .read(localSettingsProvider)
      .set(AppSettings.chatWallpaper(conversationId), wallpaper?.name ?? '');

  /// Gives your bubbles in this chat a colour.
  Future<void> setBubbleTint(HelixBubbleTint tint) => _ref
      .read(localSettingsProvider)
      .set(
        AppSettings.chatBubbleTint(conversationId),
        tint == HelixBubbleTint.theme ? '' : tint.name,
      );

  /// Locks the chat, or unlocks it. Locking needs a screen lock on the phone;
  /// null when it was done, else the sentence to show.
  Future<String?> setLocked({required bool locked}) async {
    if (locked) {
      final why = await whyNotLock(_ref.read(deviceAuthenticatorProvider));
      if (why != null) return why;
    }
    await (await _gateway).setLocked(conversationId, locked: locked);
    return null;
  }

  Future<void> block(String account) async => (await _gateway).block(account);

  Future<void> unblock(String account) async =>
      (await _gateway).unblock(account);
}

final conversationSettingsActionsProvider =
    Provider.family<ConversationSettingsActions, String>(
      ConversationSettingsActions.new,
    );
