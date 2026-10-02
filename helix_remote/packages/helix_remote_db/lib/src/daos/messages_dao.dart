import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/conversations.dart';
import 'package:helix_remote_db/src/tables/messages.dart';
import 'package:helix_remote_db/src/values.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ReceiptKind;
import 'package:meta/meta.dart';

part 'messages_dao.g.dart';

/// One page of a conversation, oldest first.
@immutable
final class MessagePage {
  const MessagePage(this.messages, {required this.hasMore});

  final List<MessageRow> messages;

  /// More messages exist beyond this page in the direction it was read.
  final bool hasMore;

  /// Cursors for the next page in each direction.
  String? get oldestSortKey => messages.isEmpty ? null : messages.first.sortKey;
  String? get newestSortKey => messages.isEmpty ? null : messages.last.sortKey;
}

/// Messages and everything attached to them. Every write that can change
/// what the chat list shows updates the conversation summary in the same
/// transaction.
@DriftAccessor(
  tables: [
    Conversations,
    Messages,
    MessageReactions,
    MessageReceipts,
    Attachments,
  ],
)
class MessagesDao extends DatabaseAccessor<HelixDb> with _$MessagesDaoMixin {
  MessagesDao(super.attachedDatabase);

  /// Longest chat-list preview, in Unicode code points.
  static const previewLength = 100;

  // ------------------------------------------------------------- writes

  /// Inserts [message] with its [media] (album order) and updates the
  /// conversation summary: last message, unread and mention counts. The
  /// conversation must exist. Fails on a duplicate `(message_id, sender)`.
  Future<MessageRow> insertMessage(
    MessagesCompanion message, {
    List<AttachmentsCompanion> media = const [],
  }) => transaction(() async {
    final row = await into(messages).insertReturning(message);
    for (final (index, item) in media.indexed) {
      await into(attachments).insert(
        item.copyWith(
          messageRowid: Value(row.localRowid),
          position: Value(index),
        ),
      );
    }
    final conversation = await _conversation(row.conversationId);
    final newest =
        conversation.lastMessageSortKey == null ||
        row.sortKey.compareTo(conversation.lastMessageSortKey!) > 0;
    final unread = row.status == MessageStatus.received;
    await (update(
      conversations,
    )..where((c) => c.id.equals(row.conversationId))).write(
      ConversationsCompanion(
        lastMessageRowid: newest ? Value(row.localRowid) : const Value.absent(),
        lastMessageSortKey: newest ? Value(row.sortKey) : const Value.absent(),
        lastMessageAt: newest ? Value(row.sentAt) : const Value.absent(),
        lastMessagePreview: newest ? Value(preview(row)) : const Value.absent(),
        unreadCount: Value(conversation.unreadCount + (unread ? 1 : 0)),
        mentionCount: Value(
          conversation.mentionCount + (unread && row.mentionsMe ? 1 : 0),
        ),
      ),
    );
    return row;
  });

  /// An edit by the author (CONTENT_V2.md §3): new text or caption, and
  /// optionally a new [payload].
  Future<void> editMessage(
    int rowid, {
    required String? body,
    String? payload,
    required DateTime editedAt,
  }) => transaction(() async {
    final row = await _message(rowid);
    await (update(messages)..where((m) => m.localRowid.equals(rowid))).write(
      MessagesCompanion(
        body: Value(body),
        payload: payload == null ? const Value.absent() : Value(payload),
        editedAt: Value(editedAt),
      ),
    );
    await refreshSummary(row.conversationId);
  });

  /// Replaces the JSON [payload] (poll votes, RSVPs, placeholder state)
  /// without marking the message edited.
  Future<void> updatePayload(int rowid, String? payload) =>
      (update(messages)..where((m) => m.localRowid.equals(rowid))).write(
        MessagesCompanion(payload: Value(payload)),
      );

  /// Delete for everyone: the row stays as "This message was deleted", its
  /// text, payload, reactions and media rows go. Returns the removed media
  /// rows so the caller can delete their local files.
  Future<List<AttachmentRow>> deleteForEveryone(
    int rowid, {
    required DateTime deletedAt,
  }) => transaction(() async {
    final row = await _message(rowid);
    final media = await (select(
      attachments,
    )..where((a) => a.messageRowid.equals(rowid))).get();
    await (delete(
      attachments,
    )..where((a) => a.messageRowid.equals(rowid))).go();
    await (delete(
      messageReactions,
    )..where((r) => r.messageRowid.equals(rowid))).go();
    await (update(messages)..where((m) => m.localRowid.equals(rowid))).write(
      MessagesCompanion(
        body: const Value(null),
        payload: const Value(null),
        deletedAt: Value(deletedAt),
      ),
    );
    await refreshSummary(row.conversationId);
    return media;
  });

  /// Removes messages from this device (delete for me, disappearing
  /// messages) and refreshes the affected summaries.
  Future<int> removeMessages(Iterable<int> rowids) => transaction(() async {
    final ids = rowids.toList();
    if (ids.isEmpty) return 0;
    final conversationIds =
        await (selectOnly(messages, distinct: true)
              ..addColumns([messages.conversationId])
              ..where(messages.localRowid.isIn(ids)))
            .map((r) => r.read(messages.conversationId)!)
            .get();
    final removed = await (delete(
      messages,
    )..where((m) => m.localRowid.isIn(ids))).go();
    for (final id in conversationIds) {
      await refreshSummary(id);
    }
    return removed;
  });

  /// Removes every message whose disappearing timer ran out by [now].
  Future<int> removeExpired(DateTime now) async {
    final due =
        await (selectOnly(messages)
              ..addColumns([messages.localRowid])
              ..where(
                messages.expiresAt.isSmallerOrEqualValue(
                  now.millisecondsSinceEpoch,
                ),
              ))
            .map((r) => r.read(messages.localRowid)!)
            .get();
    return removeMessages(due);
  }

  /// Marks incoming messages up to and including [sortKey] as read and
  /// recounts the conversation's unread and mention counts. Returns the
  /// messages that became read, for read receipts.
  Future<List<MessageRow>> markReadUpTo(
    String conversationId,
    String sortKey,
  ) => transaction(() async {
    final read =
        await (update(messages)..where(
              (m) =>
                  m.conversationId.equals(conversationId) &
                  m.status.equalsValue(MessageStatus.received) &
                  m.sortKey.isSmallerOrEqualValue(sortKey),
            ))
            .writeReturning(
              const MessagesCompanion(status: Value(MessageStatus.read)),
            );
    final conversation = await _conversation(conversationId);
    final previous = conversation.lastReadSortKey;
    if (previous == null || sortKey.compareTo(previous) > 0) {
      await (update(conversations)..where((c) => c.id.equals(conversationId)))
          .write(ConversationsCompanion(lastReadSortKey: Value(sortKey)));
    }
    await refreshSummary(conversationId);
    read.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return read;
  });

  /// Moves an outgoing message's status forward ([MessageStatus.advance]).
  Future<MessageStatus> advanceStatus(int rowid, MessageStatus next) =>
      transaction(() async {
        final row = await _message(rowid);
        final status = row.status.advance(next);
        if (status != row.status) {
          await (update(messages)..where((m) => m.localRowid.equals(rowid)))
              .write(MessagesCompanion(status: Value(status)));
        }
        return status;
      });

  /// Starts the disappearing timer when the message is first displayed.
  Future<void> markDisplayed(int rowid, DateTime displayedAt) async {
    await customUpdate(
      'UPDATE messages SET expires_at = ? + expire_seconds * 1000 '
      'WHERE local_rowid = ? AND expire_seconds IS NOT NULL '
      'AND expires_at IS NULL',
      variables: [
        Variable.withInt(displayedAt.millisecondsSinceEpoch),
        Variable.withInt(rowid),
      ],
      updates: {messages},
      updateKind: UpdateKind.update,
    );
  }

  /// When the next disappearing message runs out; null if none is pending.
  Future<DateTime?> nextExpiryAt() async {
    final row = await customSelect(
      'SELECT min(expires_at) AS at FROM messages WHERE expires_at IS NOT NULL',
      readsFrom: {messages},
    ).getSingle();
    final at = row.readNullable<int>('at');
    return at == null ? null : const EpochMs().fromSql(at);
  }

  /// Sets the view-once state (opened media is then deleted by the caller).
  Future<void> setViewOnceState(int rowid, ViewOnceState state) =>
      (update(messages)..where((m) => m.localRowid.equals(rowid))).write(
        MessagesCompanion(viewOnceState: Value(state)),
      );

  /// Recomputes the conversation summary from the messages table.
  Future<void> refreshSummary(String conversationId) => transaction(() async {
    final last =
        await (select(messages)
              ..where((m) => m.conversationId.equals(conversationId))
              ..orderBy([(m) => OrderingTerm.desc(m.sortKey)])
              ..limit(1))
            .getSingleOrNull();
    final counts = await customSelect(
      'SELECT count(*) AS unread, coalesce(sum(mentions_me), 0) AS mentions '
      'FROM messages WHERE conversation_id = ? AND status = ?',
      variables: [
        Variable.withString(conversationId),
        Variable.withString(MessageStatus.received.name),
      ],
      readsFrom: {messages},
    ).getSingle();
    await (update(
      conversations,
    )..where((c) => c.id.equals(conversationId))).write(
      ConversationsCompanion(
        lastMessageRowid: Value(last?.localRowid),
        lastMessageSortKey: Value(last?.sortKey),
        lastMessageAt: Value(last?.sentAt),
        lastMessagePreview: Value(last == null ? null : preview(last)),
        unreadCount: Value(counts.read<int>('unread')),
        mentionCount: Value(counts.read<int>('mentions')),
      ),
    );
  });

  /// The chat-list preview for [message]: its text or caption on one line,
  /// at most [previewLength] code points. Empty for deleted messages and
  /// messages without text; the list shows those by kind.
  static String preview(MessageRow message) {
    if (message.deletedAt != null) return '';
    final text = (message.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final runes = text.runes;
    if (runes.length <= previewLength) return text;
    return String.fromCharCodes(runes.take(previewLength));
  }

  // ---------------------------------------------- reactions and receipts

  /// Sets [reactor]'s reaction, replacing any earlier one.
  Future<void> setReaction(
    int rowid, {
    required String reactor,
    required String emoji,
    required DateTime at,
  }) => into(messageReactions).insertOnConflictUpdate(
    MessageReactionsCompanion.insert(
      messageRowid: rowid,
      reactor: reactor,
      emoji: emoji,
      reactedAt: at,
    ),
  );

  Future<void> removeReaction(int rowid, {required String reactor}) =>
      (delete(messageReactions)..where(
            (r) => r.messageRowid.equals(rowid) & r.reactor.equals(reactor),
          ))
          .go();

  Future<List<ReactionRow>> reactionsFor(Iterable<int> rowids) =>
      _reactionsQuery(rowids).get();

  Stream<List<ReactionRow>> watchReactionsFor(Iterable<int> rowids) =>
      _reactionsQuery(rowids).watch();

  SimpleSelectStatement<$MessageReactionsTable, ReactionRow> _reactionsQuery(
    Iterable<int> rowids,
  ) => select(messageReactions)
    ..where((r) => r.messageRowid.isIn(rowids.toList()))
    ..orderBy([(r) => OrderingTerm.asc(r.reactedAt)]);

  /// Records that [account] reached [kind] for an outgoing message. Each
  /// time is kept from its first receipt.
  Future<void> recordReceipt(
    int rowid, {
    required String account,
    required ReceiptKind kind,
    required DateTime at,
  }) async {
    final column = switch (kind) {
      ReceiptKind.delivered => 'delivered_at',
      ReceiptKind.read => 'read_at',
      ReceiptKind.viewed => 'viewed_at',
    };
    await customInsert(
      'INSERT INTO message_receipts (message_rowid, account_id, $column) '
      'VALUES (?, ?, ?) ON CONFLICT (message_rowid, account_id) '
      'DO UPDATE SET $column = coalesce($column, excluded.$column)',
      variables: [
        Variable.withInt(rowid),
        Variable.withString(account),
        Variable.withInt(at.millisecondsSinceEpoch),
      ],
      updates: {messageReceipts},
    );
  }

  Future<List<ReceiptRow>> receiptsFor(int rowid) => (select(
    messageReceipts,
  )..where((r) => r.messageRowid.equals(rowid))).get();

  // ------------------------------------------------------------ media

  Future<List<AttachmentRow>> attachmentsFor(Iterable<int> rowids) =>
      _attachmentsQuery(rowids).get();

  Stream<List<AttachmentRow>> watchAttachmentsFor(Iterable<int> rowids) =>
      _attachmentsQuery(rowids).watch();

  SimpleSelectStatement<$AttachmentsTable, AttachmentRow> _attachmentsQuery(
    Iterable<int> rowids,
  ) => select(attachments)
    ..where((a) => a.messageRowid.isIn(rowids.toList()))
    ..orderBy([
      (a) => OrderingTerm.asc(a.messageRowid),
      (a) => OrderingTerm.asc(a.position),
    ]);

  /// Transfer progress: state and local file paths.
  Future<void> updateAttachment(
    int id, {
    AttachmentTransfer? transfer,
    String? localPath,
    String? thumbnailPath,
  }) => (update(attachments)..where((a) => a.id.equals(id))).write(
    AttachmentsCompanion(
      transfer: transfer == null ? const Value.absent() : Value(transfer),
      localPath: localPath == null ? const Value.absent() : Value(localPath),
      thumbnailPath: thumbnailPath == null
          ? const Value.absent()
          : Value(thumbnailPath),
    ),
  );

  // ------------------------------------------------------------- reads

  Future<MessageRow?> byRowid(int rowid) => (select(
    messages,
  )..where((m) => m.localRowid.equals(rowid))).getSingleOrNull();

  /// The message other content refers to as `{id, author}`.
  Future<MessageRow?> find(String messageId, {required String sender}) =>
      (select(messages)..where(
            (m) => m.messageId.equals(messageId) & m.sender.equals(sender),
          ))
          .getSingleOrNull();

  /// A message of [conversationId] by its id, whoever wrote it (group chats:
  /// own-device read sync names messages of several authors).
  Future<MessageRow?> findInConversation(
    String conversationId,
    String messageId,
  ) =>
      (select(messages)..where(
            (m) =>
                m.conversationId.equals(conversationId) &
                m.messageId.equals(messageId),
          ))
          .getSingleOrNull();

  /// Messages older than [before] (or the newest ones), oldest first.
  Future<MessagePage> pageOlder(
    String conversationId, {
    String? before,
    int limit = 50,
  }) async {
    final rows =
        await (select(messages)
              ..where(
                (m) =>
                    m.conversationId.equals(conversationId) &
                    (before == null
                        ? const Constant(true)
                        : m.sortKey.isSmallerThanValue(before)),
              )
              ..orderBy([(m) => OrderingTerm.desc(m.sortKey)])
              ..limit(limit + 1))
            .get();
    final hasMore = rows.length > limit;
    return MessagePage(
      rows.take(limit).toList().reversed.toList(),
      hasMore: hasMore,
    );
  }

  /// Messages newer than [after], oldest first.
  Future<MessagePage> pageNewer(
    String conversationId, {
    required String after,
    int limit = 50,
  }) async {
    final rows =
        await (select(messages)
              ..where(
                (m) =>
                    m.conversationId.equals(conversationId) &
                    m.sortKey.isBiggerThanValue(after),
              )
              ..orderBy([(m) => OrderingTerm.asc(m.sortKey)])
              ..limit(limit + 1))
            .get();
    return MessagePage(rows.take(limit).toList(), hasMore: rows.length > limit);
  }

  /// The newest [limit] messages, oldest first; emits on every change.
  Stream<List<MessageRow>> watchLatest(
    String conversationId, {
    int limit = 50,
  }) =>
      (select(messages)
            ..where((m) => m.conversationId.equals(conversationId))
            ..orderBy([(m) => OrderingTerm.desc(m.sortKey)])
            ..limit(limit))
          .watch()
          .map((rows) => rows.reversed.toList());

  /// Up to [limit] messages from [from] (inclusive) onwards, oldest first:
  /// a window the user scrolled back to, kept live.
  Stream<List<MessageRow>> watchFrom(
    String conversationId,
    String from, {
    int limit = 200,
  }) =>
      (select(messages)
            ..where(
              (m) =>
                  m.conversationId.equals(conversationId) &
                  m.sortKey.isBiggerOrEqualValue(from),
            )
            ..orderBy([(m) => OrderingTerm.asc(m.sortKey)])
            ..limit(limit))
          .watch();

  /// Full-text search over message text and captions, newest first.
  /// [query] is plain user input: every word must match, as a prefix
  /// (`hel wor` finds "hello world"). Deleted messages never match.
  Future<List<MessageRow>> search(
    String query, {
    String? conversationId,
    int limit = 50,
  }) async {
    final match = ftsMatchExpression(query);
    if (match == null) return const [];
    final rows = await customSelect(
      'SELECT m.* FROM messages_fts f '
      'JOIN messages m ON m.local_rowid = f.rowid '
      'WHERE messages_fts MATCH ? AND m.deleted_at IS NULL '
      '${conversationId == null ? '' : 'AND m.conversation_id = ? '}'
      'ORDER BY m.sort_key DESC LIMIT ?',
      variables: [
        Variable.withString(match),
        if (conversationId != null) Variable.withString(conversationId),
        Variable.withInt(limit),
      ],
      readsFrom: {messages, attachedDatabase.messagesFts},
    ).get();
    return [for (final row in rows) messages.map(row.data)];
  }

  /// FTS5 MATCH expression for user input: the words (runs of letters,
  /// digits and marks, as the tokenizer sees them), each quoted and used as
  /// a prefix, so FTS syntax in the input is never interpreted. Null when
  /// there is nothing to search for.
  static String? ftsMatchExpression(String input) {
    final words = _word
        .allMatches(input)
        .map((m) => '"${m[0]}"*')
        .toList(growable: false);
    return words.isEmpty ? null : words.join(' ');
  }

  static final _word = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true);

  Future<MessageRow> _message(int rowid) =>
      (select(messages)..where((m) => m.localRowid.equals(rowid))).getSingle();

  Future<ConversationRow> _conversation(String id) =>
      (select(conversations)..where((c) => c.id.equals(id))).getSingle();
}
