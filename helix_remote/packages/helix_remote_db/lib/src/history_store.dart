import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/values.dart';

/// Whole-history reads and merges for backup, restore and device-to-device
/// transfer (the engine's `backup` feature).
///
/// The ordinary DAOs answer per-chat questions; a backup walks everything.
/// Reads are keyset pages on the local row id, so a history of any size is
/// read a page at a time. Writes are merges that never overwrite what this
/// device already has (local wins), and they leave the conversation summary to
/// `MessagesDao.refreshSummary`, which the caller runs once per chat after the
/// last page.
///
/// Not a DAO (no generated code): it is plain queries over [HelixDb], so it
/// adds nothing to the schema or the generated files.
final class HistoryStore {
  const HistoryStore(this._db);

  final HelixDb _db;

  // -------------------------------------------------------------- export

  Future<List<ConversationRow>> conversations() => (_db.select(
    _db.conversations,
  )..orderBy([(c) => OrderingTerm.asc(c.id)])).get();

  Future<int> messageCount() async {
    final row = await _db
        .customSelect(
          'SELECT count(*) AS n FROM messages',
          readsFrom: {_db.messages},
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// Up to [limit] messages with a local row id below [beforeRowid] (the
  /// newest rows when null), newest first. Page by passing the last row's id.
  Future<List<MessageRow>> messagesBefore({
    int? beforeRowid,
    required int limit,
  }) =>
      (_db.select(_db.messages)
            ..where(
              (m) => beforeRowid == null
                  ? const Constant(true)
                  : m.localRowid.isSmallerThanValue(beforeRowid),
            )
            ..orderBy([(m) => OrderingTerm.desc(m.localRowid)])
            ..limit(limit))
          .get();

  /// Receipts of the given messages, by message row id.
  Future<Map<int, List<ReceiptRow>>> receiptsFor(Iterable<int> rowids) async {
    final ids = rowids.toList();
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(
      _db.messageReceipts,
    )..where((r) => r.messageRowid.isIn(ids))).get();
    final byRow = <int, List<ReceiptRow>>{};
    for (final row in rows) {
      (byRow[row.messageRowid] ??= []).add(row);
    }
    return byRow;
  }

  // -------------------------------------------------------------- chunks

  /// One chunk of a device-to-device transfer, or null. Assembling reads
  /// them one at a time through this, so a large history never sits in
  /// memory twice.
  Future<TransferChunkRow?> chunk(String transferId, int sequence) =>
      (_db.select(_db.transferChunks)..where(
            (c) =>
                c.transferId.equals(transferId) & c.sequence.equals(sequence),
          ))
          .getSingleOrNull();

  // --------------------------------------------------------------- merge

  /// Adds the conversation, or fills what the local row lacks (title, pin,
  /// mute, timer, draft, read position) and moves the creation time back
  /// when the backup's is older. Members are added, never removed.
  Future<void> mergeConversation({
    required String id,
    required ConversationKind kind,
    required DateTime createdAt,
    String? title,
    DateTime? pinnedAt,
    DateTime? mutedUntil,
    bool archived = false,
    String? draft,
    int? disappearingSeconds,
    String? lastReadSortKey,
    Iterable<String> members = const [],
  }) => _db.transaction(() async {
    final existing = await (_db.select(
      _db.conversations,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.conversations)
          .insert(
            ConversationsCompanion.insert(
              id: id,
              kind: kind,
              title: Value(title),
              pinnedAt: Value(pinnedAt),
              mutedUntil: Value(mutedUntil),
              archived: Value(archived),
              draft: Value(draft),
              disappearingSeconds: Value(disappearingSeconds),
              lastReadSortKey: Value(lastReadSortKey),
              createdAt: createdAt,
            ),
          );
    } else {
      final read = existing.lastReadSortKey;
      await (_db.update(
        _db.conversations,
      )..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(
          title: existing.title == null && title != null
              ? Value(title)
              : const Value.absent(),
          pinnedAt: existing.pinnedAt == null && pinnedAt != null
              ? Value(pinnedAt)
              : const Value.absent(),
          mutedUntil: existing.mutedUntil == null && mutedUntil != null
              ? Value(mutedUntil)
              : const Value.absent(),
          draft: existing.draft == null && draft != null
              ? Value(draft)
              : const Value.absent(),
          disappearingSeconds:
              existing.disappearingSeconds == null &&
                  disappearingSeconds != null
              ? Value(disappearingSeconds)
              : const Value.absent(),
          lastReadSortKey:
              lastReadSortKey != null &&
                  (read == null || lastReadSortKey.compareTo(read) > 0)
              ? Value(lastReadSortKey)
              : const Value.absent(),
          createdAt: createdAt.isBefore(existing.createdAt)
              ? Value(createdAt)
              : const Value.absent(),
        ),
      );
    }
    for (final account in members.toSet()) {
      await _db
          .into(_db.conversationMembers)
          .insert(
            ConversationMembersCompanion.insert(
              conversationId: id,
              accountId: account,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  });

  /// Fills this account's profile fields that are still empty (a device that
  /// signed in with only a password has no profile key or names).
  Future<void> fillSelfProfile({
    String? helixName,
    String? profileName,
    List<int>? profileKey,
  }) async {
    final row = await _db.select(_db.selfAccount).getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.selfAccount)..where((a) => a.id.equals(1))).write(
      SelfAccountCompanion(
        helixName: row.helixName == null && helixName != null
            ? Value(helixName)
            : const Value.absent(),
        profileName: row.profileName == null && profileName != null
            ? Value(profileName)
            : const Value.absent(),
        profileKey: row.profileKey == null && profileKey != null
            ? Value(Uint8List.fromList(profileKey))
            : const Value.absent(),
      ),
    );
  }
}
