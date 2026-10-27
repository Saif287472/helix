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
@DriftAccessor(
  tables: [
    Conversations,
    ConversationMembers,
    Messages,
    ChatLists,
    ChatListMembers,
  ],
)
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

  /// The group chat [id] (`group:<group id>`), created if missing. The
  /// title and avatar are written when given; existing members stay.
  Future<ConversationRow> ensureGroup(
    String id, {
    String? title,
    Uint8List? avatar,
    required DateTime now,
  }) => transaction(() async {
    await into(conversations).insert(
      ConversationsCompanion.insert(
        id: id,
        kind: ConversationKind.group,
        createdAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    if (title != null || avatar != null) {
      await _write(
        id,
        ConversationsCompanion(
          title: title == null ? const Value.absent() : Value(title),
          avatar: avatar == null ? const Value.absent() : Value(avatar),
        ),
      );
    }
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
          ..where(
            conversations.archived.equals(archived) &
                conversations.lockedAt.isNull(),
          )
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
        'FROM conversations WHERE archived = 0 AND locked_at IS NULL',
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

  /// Makes the chat a favourite at [at], or not one with null.
  Future<void> setFavourite(String id, DateTime? at) =>
      _write(id, ConversationsCompanion(favouriteAt: Value(at)));

  // ------------------------------------------------------------- lists

  /// The person's lists, in the order of their chips.
  Stream<List<ChatListRow>> watchLists() =>
      (select(chatLists)..orderBy([
            (l) => OrderingTerm.asc(l.position),
            (l) => OrderingTerm.asc(l.createdAt),
          ]))
          .watch();

  Future<List<ChatListRow>> lists() =>
      (select(chatLists)..orderBy([
            (l) => OrderingTerm.asc(l.position),
            (l) => OrderingTerm.asc(l.createdAt),
          ]))
          .get();

  /// Which chats are on which list, all of them.
  Stream<List<ChatListMemberRow>> watchListMembers() =>
      select(chatListMembers).watch();

  Future<List<ChatListMemberRow>> listMembers() =>
      select(chatListMembers).get();

  /// Makes a list at the end of the others.
  Future<void> createList(String id, String name, DateTime now) =>
      transaction(() async {
        final last =
            await (select(chatLists)
                  ..orderBy([(l) => OrderingTerm.desc(l.position)])
                  ..limit(1))
                .getSingleOrNull();
        await into(chatLists).insert(
          ChatListsCompanion.insert(
            id: id,
            name: name,
            position: (last?.position ?? 0) + 1,
            createdAt: now,
          ),
        );
      });

  Future<void> renameList(String id, String name) =>
      (update(chatLists)..where((l) => l.id.equals(id))).write(
        ChatListsCompanion(name: Value(name)),
      );

  /// Deletes the list; its chats stay, they just leave it.
  Future<void> deleteList(String id) =>
      (delete(chatLists)..where((l) => l.id.equals(id))).go();

  /// Puts the chat on the list; nothing changes when it is already there or
  /// either does not exist.
  Future<void> addToList(String listId, String conversationId) async {
    final list = await (select(
      chatLists,
    )..where((l) => l.id.equals(listId))).getSingleOrNull();
    final chat = await byId(conversationId);
    if (list == null || chat == null) return;
    await into(chatListMembers).insert(
      ChatListMembersCompanion.insert(
        listId: listId,
        conversationId: conversationId,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> removeFromList(String listId, String conversationId) =>
      (delete(chatListMembers)..where(
            (m) =>
                m.listId.equals(listId) &
                m.conversationId.equals(conversationId),
          ))
          .go();

  /// Locks the chat at [at], or unlocks it with null.
  Future<void> setLocked(String id, DateTime? at) =>
      _write(id, ConversationsCompanion(lockedAt: Value(at)));

  /// The locked chats, newest activity first (the Locked chats screen).
  Stream<List<ConversationListItem>> watchLocked() {
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
          ..where(conversations.lockedAt.isNotNull())
          ..orderBy([
            OrderingTerm.desc(activity),
            OrderingTerm.asc(conversations.id),
          ]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          ConversationListItem(
            r.readTable(conversations),
            r.readTableOrNull(messages),
          ),
      ],
    );
  }

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
