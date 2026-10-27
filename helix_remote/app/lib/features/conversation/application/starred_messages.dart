import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/chat/message_semantics.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:orbit_ui/orbit_ui.dart' show StarredItem;

/// The messages the person starred, in every chat, the newest star first, each
/// with the chat it is in. A starred message in a chat that is gone is left
/// out.
final starredItemsProvider = StreamProvider.autoDispose<List<StarredItem>>((
  ref,
) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(peopleDirectoryProvider.future);
  final now = ref.read(clockProvider)();
  final chats = <String, ConversationRow?>{};
  await for (final rows in gateway.watchStarred()) {
    final items = <StarredItem>[];
    for (final row in rows) {
      final chat = chats[row.conversationId] ??= await gateway.chat(
        row.conversationId,
      );
      if (chat == null) continue;
      items.add(
        StarredItem(
          chatId: chat.id,
          messageId: row.localRowid.toString(),
          title: chatTitleOf(chat, people),
          avatar: chatAvatarOf(chat, people),
          who: row.outgoing ? 'You' : people.firstNameOf(row.sender),
          text: oneLineOf(row),
          timeLabel: formatChatTime(row.sentAt, now),
        ),
      );
    }
    yield items;
  }
});
