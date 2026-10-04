import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/chat/chat_people.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Somewhere a message can be forwarded to: an existing chat, or a person
/// there is no chat with yet (it is created when the message is sent).
@immutable
class ForwardTarget {
  const ForwardTarget({
    required this.id,
    required this.title,
    required this.avatar,
    this.newPeer,
  });

  /// The conversation id; for a person without a chat, the id it will get.
  final String id;
  final String title;
  final HelixAvatarModel avatar;

  /// The account to open a direct chat with before sending, or null for an
  /// existing chat.
  final String? newPeer;

  @override
  bool operator ==(Object other) =>
      other is ForwardTarget &&
      other.id == id &&
      other.title == title &&
      other.avatar == avatar &&
      other.newPeer == newPeer;

  @override
  int get hashCode => Object.hash(id, title, avatar, newPeer);
}

/// The chats (newest first), then the people without a chat, by name.
final forwardTargetsProvider = StreamProvider.autoDispose<List<ForwardTarget>>((
  ref,
) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(chatPeopleProvider.future);
  final self = gateway.selfAccountId;
  yield* gateway.watchChats().map((rows) {
    final out = <ForwardTarget>[];
    final haveChat = <String>{};
    for (final row in rows) {
      final chat = row.conversation;
      final peer = peerOfConversation(chat.id);
      if (peer != null) {
        if (people.isBlocked(peer)) continue;
        haveChat.add(peer);
      }
      out.add(
        ForwardTarget(
          id: chat.id,
          title: chatTitleOf(chat, people),
          avatar: chatAvatarOf(chat, people),
        ),
      );
    }
    final strangers = [
      for (final account in people.accounts)
        if (account != self &&
            !haveChat.contains(account) &&
            !people.isBlocked(account))
          account,
    ]..sort((a, b) => people.nameOf(a).compareTo(people.nameOf(b)));
    for (final account in strangers) {
      out.add(
        ForwardTarget(
          id: 'direct:$account',
          title: people.nameOf(account),
          avatar: people.avatarOf(account),
          newPeer: account,
        ),
      );
    }
    return out;
  });
});
