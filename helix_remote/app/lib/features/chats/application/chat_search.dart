import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/chat/chat_people.dart';
import 'package:helix_remote/core/chat/search_snippet.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One message found by the full-text search, and where to open it.
@immutable
class MessageHit {
  const MessageHit({
    required this.result,
    required this.conversationId,
    required this.messageId,
  });

  final HelixMessageSearchResult result;
  final String conversationId;

  /// The message's content id, which the conversation opens at.
  final String messageId;
}

/// What the Chats tab's search shows: chats whose name matches, and messages
/// whose text does. People who are not in a chat yet are the people search's
/// results (a seam in the tab; see `ChatsTab.peopleResults`).
@immutable
class ChatSearchResults {
  const ChatSearchResults({
    this.query = '',
    this.chats = const [],
    this.messages = const [],
  });

  final String query;
  final List<HelixChatListItem> chats;
  final List<MessageHit> messages;

  bool get isEmpty => chats.isEmpty && messages.isEmpty;
}

/// The text in the search box.
final class ChatSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final chatSearchQueryProvider = NotifierProvider<ChatSearchQuery, String>(
  ChatSearchQuery.new,
);

/// The results for the current query, a quarter of a second after the person
/// stops typing. A newer query disposes this one, which is what cancels the
/// wait.
final chatSearchResultsProvider = FutureProvider.autoDispose<ChatSearchResults>(
  (ref) async {
    final query = ref.watch(chatSearchQueryProvider).trim();
    if (query.isEmpty) return const ChatSearchResults();
    var superseded = false;
    ref.onDispose(() => superseded = true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (superseded) return const ChatSearchResults();

    final gateway = await ref.read(chatGatewayProvider.future);
    final people = await ref.read(chatPeopleProvider.future);
    final now = ref.read(clockProvider)();
    final lowered = query.toLowerCase();

    final chats = [
      ...await ref.read(chatListProvider.future),
      ...await ref.read(archivedChatListProvider.future),
    ].where((c) => c.title.toLowerCase().contains(lowered)).toList();

    final rows = await gateway.search(query);
    final titles = <String, ConversationRow?>{};
    final hits = <MessageHit>[];
    for (final row in rows) {
      final chat = titles[row.conversationId] ??= await gateway.chat(
        row.conversationId,
      );
      if (chat == null) continue;
      final isGroup = peerOfConversation(chat.id) == null;
      hits.add(
        MessageHit(
          conversationId: chat.id,
          messageId: row.messageId,
          result: HelixMessageSearchResult(
            id: row.localRowid.toString(),
            chatTitle: chatTitleOf(chat, people),
            avatar: chatAvatarOf(chat, people),
            snippet: snippetFor(row.body ?? '', query),
            timeLabel: formatChatTime(row.sentAt, now),
            senderLabel: row.outgoing
                ? 'You'
                : isGroup
                ? people.firstNameOf(row.sender)
                : null,
          ),
        ),
      );
    }
    return ChatSearchResults(query: query, chats: chats, messages: hits);
  },
);
