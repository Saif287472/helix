import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/sync.dart';
import 'package:helix_remote_db/src/values.dart';

part 'inbox_dao.g.dart';

/// Inbound bookkeeping: the mailbox cursor, envelope de-duplication, and
/// actions waiting for their target message.
@DriftAccessor(tables: [InboxCursor, ProcessedEnvelopes, DeferredActions])
class InboxDao extends DatabaseAccessor<HelixDb> with _$InboxDaoMixin {
  InboxDao(super.attachedDatabase);

  Future<InboxCursorRow?> cursor() => select(inboxCursor).getSingleOrNull();

  /// Records the highest processed (and optionally acked) `seq`. Never
  /// moves backwards.
  Future<void> advanceCursor({
    required int processedSeq,
    int? ackedSeq,
    required DateTime now,
  }) async {
    await customInsert(
      'INSERT INTO inbox_cursor (id, last_processed_seq, last_acked_seq, '
      'updated_at) VALUES (1, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET '
      'last_processed_seq = max(last_processed_seq, '
      'excluded.last_processed_seq), '
      'last_acked_seq = max(last_acked_seq, excluded.last_acked_seq), '
      'updated_at = excluded.updated_at',
      variables: [
        Variable.withInt(processedSeq),
        Variable.withInt(ackedSeq ?? 0),
        Variable.withInt(now.millisecondsSinceEpoch),
      ],
      updates: {inboxCursor},
    );
  }

  /// True if the envelope was processed before (replay after reconnect).
  Future<bool> isProcessed(String envelopeId, {String? senderDevice}) async =>
      await (select(processedEnvelopes)..where(
            (e) =>
                e.envelopeId.equals(envelopeId) &
                e.senderDevice.equals(senderDevice ?? ''),
          ))
          .getSingleOrNull() !=
      null;

  /// Records an envelope as processed. Call inside the transaction that
  /// applies its effects. Returns false if it was already recorded.
  Future<bool> markProcessed(
    String envelopeId, {
    String? senderDevice,
    int? seq,
    required EnvelopeOutcome outcome,
    required DateTime at,
  }) async {
    final inserted = await into(processedEnvelopes).insertReturningOrNull(
      ProcessedEnvelopesCompanion.insert(
        envelopeId: envelopeId,
        senderDevice: Value(senderDevice ?? ''),
        seq: Value(seq),
        outcome: outcome,
        processedAt: at,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return inserted != null;
  }

  /// Forgets envelopes processed before [cutoff] (past the replay window).
  Future<int> pruneProcessed(DateTime cutoff) =>
      (delete(processedEnvelopes)..where(
            (e) =>
                e.processedAt.isSmallerThanValue(cutoff.millisecondsSinceEpoch),
          ))
          .go();

  // -------------------------------------------------- deferred actions

  Future<void> deferAction(DeferredActionsCompanion action) =>
      into(deferredActions).insert(action);

  /// Removes and returns the actions waiting for `{messageId, author}`,
  /// oldest first.
  Future<List<DeferredActionRow>> takeDeferred(
    String messageId, {
    required String author,
  }) => transaction(() async {
    final query = select(deferredActions)
      ..where(
        (a) =>
            a.targetMessageId.equals(messageId) & a.targetAuthor.equals(author),
      )
      ..orderBy([(a) => OrderingTerm.asc(a.id)]);
    final rows = await query.get();
    if (rows.isNotEmpty) {
      await (delete(
        deferredActions,
      )..where((a) => a.id.isIn(rows.map((r) => r.id)))).go();
    }
    return rows;
  });

  Future<int> purgeExpiredDeferred(DateTime now) =>
      (delete(deferredActions)..where(
            (a) =>
                a.expiresAt.isSmallerOrEqualValue(now.millisecondsSinceEpoch),
          ))
          .go();
}
