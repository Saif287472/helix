import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/conversations.dart';
import 'package:helix_remote_db/src/tables/messages.dart';
import 'package:helix_remote_db/src/values.dart';
import 'package:meta/meta.dart';

part 'conversations_dao.g.dart';

/// A chat-list row: the conversation and its newest message (for kind,
/// status ticks, sender and "deleted").
@immutable
final class ConversationListItem {
  const ConversationListItem(this.conversation, this.lastMessage);

  final ConversationRow conversation;
  final MessageRow? lastMessage;
}

/// Badge numbers over all non-archived chats.
@immutable
final class UnreadTotals {
  const UnreadTotals({
    required this.messages,
    required this.conversations,
    required this.mentions,
  });

  static const zero = UnreadTotals(messages: 0, conversations: 0, mentions: 0);

  final int messages;
  final int conversations;
  final int mentions;

  @override
  bool operator ==(Object other) =>
      other is UnreadTotals &&
      other.messages == messages &&
      other.conversations == conversations &&
      other.mentions == mentions;

  @override
  int get hashCode => Object.hash(messages, conversations, mentions);

  @override
  String toString() =>
      'UnreadTotals(messages: $messages, conversations: $conversations, '
      'mentions: $mentions)';
}

/// Conversations, their members and the chat list. The summary columns are
/// written by `MessagesDao`, never here.
@DriftAccessor(tables: [Conversations, ConversationMembers, Messages])
class ConversationsDao extends DatabaseAccessor<HelixDb>
    with _$ConversationsDaoMixin {
  ConversationsDao(super.attachedDatabase);

  /// The direct chat with [peerAccountId], created if missing.
  Future<ConversationRow> ensureDirect(
    String peerAccountId, {
    required DateTime now,
  }) => transaction(() async {
    final id = directConversationId(peerAccountId);
    await into(conversations).insert(
      ConversationsCompanion.insert(
        id: id,
        kind: ConversationKind.direct,
        createdAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(conversationMembers).insert(
      ConversationMembersCompanion.insert(
        conversationId: id,
        accountId: peerAccountId,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return (await byId(id))!;
  });

  Future<ConversationRow?> byId(String id) =>
      (select(conversations)..where((c) => c.id.equals(id))).getSingleOrNull();

  Stream<ConversationRow?> watchById(String id) => (select(
    conversations,
  )..where((c) => c.id.equals(id))).watchSingleOrNull();

  /// The chat list: pinned chats first (most recently pinned on top), then
  /// by newest message, chats without messages by creation time.
  Stream<List<ConversationListItem>> watchList({bool archived = false}) {
    final activity = coalesce([
      conversations.lastMessageAt,
      conversations.createdAt,
    ]);
    final query =
        select(conversations).join([
            leftOuterJoin(
              messages,
              messages.localRowid.equalsExp(conversations.lastMessageRowid),
            ),
          ])
          ..where(conversations.archived.equals(archived))
          ..orderBy([
            OrderingTerm(
              expression: conversations.pinnedAt,
              mode: OrderingMode.desc,
              nulls: NullsOrder.last,
            ),
            OrderingTerm.desc(activity),
            OrderingTerm.asc(conversations.id),
          ]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ConversationListItem(
            row.readTable(conversations),
            row.readTableOrNull(messages),
          ),
      ],
    );
  }

  /// Unread messages, chats with unread messages, and mentions, over all
  /// non-archived chats.
  Stream<UnreadTotals> watchUnreadTotals() =>
      customSelect(
        'SELECT coalesce(sum(unread_count), 0) AS messages, '
        'coalesce(sum(unread_count > 0), 0) AS conversations, '
        'coalesce(sum(mention_count), 0) AS mentions '
        'FROM conversations WHERE archived = 0',
        readsFrom: {conversations},
      ).watchSingle().map(
        (row) => UnreadTotals(
          messages: row.read<int>('messages'),
          conversations: row.read<int>('conversations'),
          mentions: row.read<int>('mentions'),
        ),
      );

  Future<void> setPinned(String id, DateTime? pinnedAt) =>
      _write(id, ConversationsCompanion(pinnedAt: Value(pinnedAt)));

  Future<void> setMutedUntil(String id, DateTime? until) =>
      _write(id, ConversationsCompanion(mutedUntil: Value(until)));

  Future<void> setArchived(String id, bool archived) =>
      _write(id, ConversationsCompanion(archived: Value(archived)));

  Future<void> setDraft(String id, String? draft) => _write(
    id,
    ConversationsCompanion(
      draft: Value(draft == null || draft.isEmpty ? null : draft),
    ),
  );

  Future<void> setDisappearingSeconds(String id, int? seconds) =>
      _write(id, ConversationsCompanion(disappearingSeconds: Value(seconds)));

  Future<void> setTitleAndAvatar(
    String id, {
    required String? title,
    required Uint8List? avatar,
  }) => _write(
    id,
    ConversationsCompanion(title: Value(title), avatar: Value(avatar)),
  );

  /// Deletes the chat with all its messages (cascade).
  Future<void> deleteConversation(String id) =>
      (delete(conversations)..where((c) => c.id.equals(id))).go();

  Future<List<String>> membersOf(String id) => (select(
    conversationMembers,
  )..where((m) => m.conversationId.equals(id))).map((m) => m.accountId).get();

  /// Replaces the member list of [id].
  Future<void> setMembers(String id, Iterable<String> accountIds) =>
      transaction(() async {
        await (delete(
          conversationMembers,
        )..where((m) => m.conversationId.equals(id))).go();
        await batch(
          (b) => b.insertAll(conversationMembers, [
            for (final account in accountIds.toSet())
              ConversationMembersCompanion.insert(
                conversationId: id,
                accountId: account,
              ),
          ]),
        );
      });

  Future<void> _write(String id, ConversationsCompanion values) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(values);
}
