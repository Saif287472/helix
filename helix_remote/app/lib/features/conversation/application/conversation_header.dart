import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/chat/chat_people.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show PresenceResponse;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Everything the conversation's app bar and composer need to know about the
/// chat they are in.
@immutable
class ConversationHeader {
  const ConversationHeader({
    required this.id,
    required this.title,
    required this.avatar,
    this.subtitle,
    this.isGroup = false,
    this.peerAccount,
    this.typing = false,
    this.verified = false,
    this.blocked = false,
    this.muted = false,
    this.disappearingSeconds,
    this.composerDisabledReason,
  });

  final String id;
  final String title;
  final HelixAvatarModel avatar;

  /// "online", "last seen today at 14:05", "Sam is typing...", the members.
  final String? subtitle;
  final bool isGroup;

  /// The other person of a direct chat.
  final String? peerAccount;

  /// Somebody is typing (the subtitle says who).
  final bool typing;
  final bool verified;
  final bool blocked;
  final bool muted;
  final int? disappearingSeconds;

  /// Why nobody can write here (blocked, no longer in the group); the
  /// composer shows it instead of the text field.
  final String? composerDisabledReason;

  @override
  bool operator ==(Object other) =>
      other is ConversationHeader &&
      other.id == id &&
      other.title == title &&
      other.avatar == avatar &&
      other.subtitle == subtitle &&
      other.isGroup == isGroup &&
      other.peerAccount == peerAccount &&
      other.typing == typing &&
      other.verified == verified &&
      other.blocked == blocked &&
      other.muted == muted &&
      other.disappearingSeconds == disappearingSeconds &&
      other.composerDisabledReason == composerDisabledReason;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    avatar,
    subtitle,
    isGroup,
    peerAccount,
    typing,
    verified,
    blocked,
    muted,
    disappearingSeconds,
    composerDisabledReason,
  );
}

/// The chat's own row, live.
final conversationRowProvider = StreamProvider.autoDispose
    .family<ConversationRow?, String>((ref, id) async* {
      final gateway = await ref.watch(chatGatewayProvider.future);
      yield* gateway.watchChat(id);
    });

/// Who is typing in the chat.
final conversationTypingProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, id) async* {
      final gateway = await ref.watch(chatGatewayProvider.future);
      yield* gateway.watchTyping(id);
    });

/// The roster of a group chat, live (empty for a direct chat).
final groupMembersProvider = StreamProvider.autoDispose
    .family<List<GroupMemberRow>, String>((ref, conversationId) async* {
      final gateway = await ref.watch(chatGatewayProvider.future);
      final group = groupIdOf(conversationId);
      if (group == null) {
        yield const [];
        return;
      }
      yield* gateway.watchMembers(group);
    });

/// The group id inside a `group:<id>` conversation id, or null.
String? groupIdOf(String conversationId) =>
    conversationId.startsWith('group:') ? conversationId.substring(6) : null;

/// Whether a person is online, and when they were last seen: asked of the
/// server when the conversation opens and every minute after. Null when it is
/// not known or hidden - the header then shows nothing rather than guessing.
final peerPresenceProvider = StreamProvider.autoDispose
    .family<PresenceResponse?, String>((ref, account) async* {
      final gateway = await ref.watch(chatGatewayProvider.future);
      final controller = StreamController<PresenceResponse?>();
      Timer? next;
      var closed = false;
      Future<void> poll() async {
        final value = await gateway.presence(account);
        if (closed) return;
        controller.add(value);
        next = Timer(const Duration(minutes: 1), poll);
      }

      ref.onDispose(() {
        closed = true;
        next?.cancel();
        unawaited(controller.close());
      });
      unawaited(poll());
      yield* controller.stream;
    });

/// The header, assembled from the chat row, the people table, who is typing,
/// presence and the roster. Null until the chat row has loaded.
final conversationHeaderProvider = Provider.autoDispose
    .family<ConversationHeader?, String>((ref, id) {
      final chat = ref.watch(conversationRowProvider(id)).value;
      final people = ref.watch(chatPeopleProvider).value ?? ChatPeople.empty;
      final typing =
          ref.watch(conversationTypingProvider(id)).value ?? const {};
      final now = ref.watch(clockProvider)();
      if (chat == null) return null;
      final peer = peerOfConversation(id);
      final title = chatTitleOf(chat, people);
      final muted = chat.mutedUntil?.isAfter(now) ?? false;

      if (peer != null) {
        final presence = ref.watch(peerPresenceProvider(peer)).value;
        final blocked = people.isBlocked(peer);
        final String? subtitle;
        if (typing.isNotEmpty) {
          subtitle = 'typing...';
        } else if (presence?.online ?? false) {
          subtitle = 'online';
        } else if (presence?.lastSeenAt != null) {
          subtitle = formatLastSeen(presence!.lastSeenAt!, now);
        } else {
          subtitle = people.secondaryOf(peer);
        }
        return ConversationHeader(
          id: id,
          title: title,
          avatar: people.avatarOf(peer),
          subtitle: subtitle,
          peerAccount: peer,
          typing: typing.isNotEmpty,
          verified: people.isVerified(peer),
          blocked: blocked,
          muted: muted,
          disappearingSeconds: chat.disappearingSeconds,
          composerDisabledReason: blocked
              ? 'You blocked this contact. Open chat settings to unblock.'
              : null,
        );
      }

      final members = ref.watch(groupMembersProvider(id)).value;
      final self = ref.watch(chatGatewayProvider).value?.selfAccountId;
      final stillIn = members == null
          ? true
          : members.any((m) => m.isSelf || m.accountId == self);
      final String? subtitle;
      if (typing.isNotEmpty) {
        subtitle = typingLabelFor(id, typing, people);
      } else if (members == null || members.isEmpty) {
        subtitle = null;
      } else if (members.length <= 4) {
        subtitle = [
          for (final m in members)
            m.isSelf || m.accountId == self
                ? 'You'
                : people.firstNameOf(m.accountId),
        ].join(', ');
      } else {
        subtitle = '${members.length} members';
      }
      return ConversationHeader(
        id: id,
        title: title,
        avatar: chatAvatarOf(chat, people),
        subtitle: stillIn ? subtitle : 'You are no longer a member',
        isGroup: true,
        typing: typing.isNotEmpty,
        muted: muted,
        disappearingSeconds: chat.disappearingSeconds,
        composerDisabledReason: stillIn
            ? null
            : 'You can no longer send messages to this group.',
      );
    });
