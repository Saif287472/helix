import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/chunks.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/tombstones.dart';
import 'package:helix_remote_db/src/values.dart';

part 'tombstones_dao.g.dart';

/// What this device deleted, so a backup merge cannot put it back
/// (AUD-12q-1; the table and its rules are `tables/tombstones.dart`).
///
/// Only the engine's three local delete paths write here - "delete for me",
/// clear chat and delete chat. The disappearing-message sweep and replacing a
/// placeholder also remove rows, but nobody chose to delete those, and a
/// message that ran out is refused by the importer on its own expiry. The
/// backup importer reads it; nothing exports it.
@DriftAccessor(tables: [DeleteTombstones])
class TombstonesDao extends DatabaseAccessor<HelixDb>
    with _$TombstonesDaoMixin {
  TombstonesDao(super.attachedDatabase);

  /// Records the messages at [rowids] as deleted here, each by its wire id
  /// and author. Call it before the rows go, in the same transaction. A
  /// message recorded before is not recorded twice.
  Future<void> recordMessages(Iterable<int> rowids) async {
    // Read from the rows themselves, in runs of [statementIdLimit] (AUD-10-1).
    for (final chunk in rowids.toList().chunks()) {
      await customInsert(
        'INSERT OR IGNORE INTO delete_tombstones (kind, target_id, author_id) '
        'SELECT ?, message_id, sender FROM messages '
        'WHERE local_rowid IN (${List.filled(chunk.length, '?').join(', ')})',
        variables: [
          Variable.withString(TombstoneKind.message.name),
          for (final rowid in chunk) Variable.withInt(rowid),
        ],
        updates: {deleteTombstones},
      );
    }
  }

  /// Records that this device cleared or deleted the chat [conversationId]:
  /// no message a backup holds for it comes back, and a deleted chat is not
  /// created again from one.
  Future<void> recordConversation(String conversationId) =>
      into(deleteTombstones).insert(
        DeleteTombstonesCompanion.insert(
          kind: TombstoneKind.conversation,
          targetId: conversationId,
        ),
        mode: InsertMode.insertOrIgnore,
      );

  /// Whether this device deleted the message [messageId] by [author].
  Future<bool> messageDeleted(String messageId, {required String author}) =>
      _exists(TombstoneKind.message, messageId, author);

  /// Whether this device cleared or deleted the chat [conversationId].
  Future<bool> conversationDeleted(String conversationId) =>
      _exists(TombstoneKind.conversation, conversationId, '');

  Future<bool> _exists(
    TombstoneKind kind,
    String target,
    String author,
  ) async =>
      await (select(deleteTombstones)..where(
            (t) =>
                t.kind.equalsValue(kind) &
                t.targetId.equals(target) &
                t.authorId.equals(author),
          ))
          .getSingleOrNull() !=
      null;
}
