import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/message_semantics.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:orbit_ui/models.dart';

/// The messages pinned in a chat, the newest pin first, as the banner under
/// the conversation's header shows them: one line each, and in a group who
/// wrote it.
final pinnedMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatPinnedMessage>, String>((ref, conversationId) async* {
      final gateway = await ref.watch(chatGatewayProvider.future);
      final people = await ref.watch(peopleDirectoryProvider.future);
      final self = gateway.selfAccountId;
      final group = conversationId.startsWith('group:');
      await for (final rows in gateway.watchPinned(conversationId)) {
        yield [
          for (final row in rows)
            ChatPinnedMessage(
              id: row.localRowid.toString(),
              text: oneLineOf(row),
              author: group
                  ? (row.sender == self
                        ? 'You'
                        : people.firstNameOf(row.sender))
                  : null,
            ),
        ];
      }
    });
