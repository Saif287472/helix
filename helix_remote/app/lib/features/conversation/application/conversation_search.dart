import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/chat/search_snippet.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A message found by searching inside one conversation.
@immutable
class InChatHit {
  const InChatHit({required this.result, required this.messageId});

  final HelixMessageSearchResult result;

  /// The message's content id, which the timeline jumps to.
  final String messageId;
}

/// The text in the in-conversation search box.
final class InChatSearchQuery extends Notifier<String> {
  InChatSearchQuery(this.conversationId);

  final String conversationId;

  @override
  String build() => '';

  void set(String value) => state = value;
}

final inChatSearchQueryProvider = NotifierProvider.autoDispose
    .family<InChatSearchQuery, String, String>(InChatSearchQuery.new);

/// Messages of the conversation matching the query (full-text search), a
/// quarter of a second after the person stops typing, newest first.
final inChatSearchResultsProvider = FutureProvider.autoDispose
    .family<List<InChatHit>, String>((ref, conversationId) async {
      final query = ref.watch(inChatSearchQueryProvider(conversationId)).trim();
      if (query.isEmpty) return const [];
      var superseded = false;
      ref.onDispose(() => superseded = true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (superseded) return const [];
      final gateway = await ref.read(chatGatewayProvider.future);
      final people = await ref.read(peopleDirectoryProvider.future);
      final now = ref.read(clockProvider)();
      final isGroup = peerOfConversation(conversationId) == null;
      final rows = await gateway.search(query, conversationId: conversationId);
      return [
        for (final row in rows)
          InChatHit(
            messageId: row.messageId,
            result: HelixMessageSearchResult(
              id: row.localRowid.toString(),
              chatTitle: row.outgoing ? 'You' : people.displayOf(row.sender),
              avatar: row.outgoing
                  ? const HelixAvatarModel(name: 'You')
                  : people.avatarOf(row.sender),
              snippet: snippetFor(row.body ?? '', query),
              timeLabel: formatChatTime(row.sentAt, now),
              senderLabel: isGroup && !row.outgoing
                  ? people.firstNameOf(row.sender)
                  : null,
            ),
          ),
      ];
    });
