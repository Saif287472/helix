import 'dart:convert';

import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Writes the local, never-sent `system` rows of a group chat: "Alice added
/// Bob", "You were removed". They come from the server's `roster_change`
/// envelopes, which every member gets, so each device renders them itself;
/// a member cannot make others show a notice by sending one (the inbound
/// pipeline drops every group `system` message but `timer_changed`).
final class GroupNotices {
  GroupNotices(this._ctx);

  final EngineContext _ctx;

  /// Adds a notice to the chat of [groupId] (nothing if the chat does not
  /// exist). [messageId] makes it idempotent (a roster envelope's id).
  Future<void> add({
    required String groupId,
    required String kind,
    String? actor,
    List<String> members = const [],
    Map<String, Object?> fields = const {},
    String? messageId,
    DateTime? at,
  }) async {
    final conversation = GroupIds.conversationId(groupId);
    if (await _ctx.db.conversationsDao.byId(conversation) == null) return;
    final self = _ctx.identity.accountId;
    final id = messageId ?? _ctx.ids.next();
    final sender = actor ?? self;
    if (await _ctx.db.messagesDao.find(id, sender: sender) != null) return;
    final now = _ctx.now();
    final shown = at != null && at.isBefore(now) ? at : now;
    await _ctx.db.messagesDao.insertMessage(
      MessagesCompanion.insert(
        messageId: id,
        conversationId: conversation,
        sender: sender,
        outgoing: false,
        sortKey: SortKey.of(shown, id),
        sentAt: shown,
        receivedAt: now,
        kind: SystemBody.typeName,
        payload: Value(
          jsonEncode(
            SystemBody(
              kind: kind,
              fields: {
                'actor': ?actor,
                if (members.isNotEmpty) 'members': members,
                ...fields,
              },
            ).toJson(),
          ),
        ),
        // A notice is not unread.
        status: MessageStatus.read,
      ),
    );
  }
}
