import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/sync.dart';
import 'package:helix_remote_db/src/values.dart';

part 'outbox_dao.g.dart';

/// The outbound queue (plan §6.3). Enqueue in the same transaction as the
/// optimistic row; the outbox worker claims due ops with a lease, sends
/// them, and completes, reschedules or fails them.
@DriftAccessor(tables: [OutboxOps])
class OutboxDao extends DatabaseAccessor<HelixDb> with _$OutboxDaoMixin {
  OutboxDao(super.attachedDatabase);

  /// Adds an op, due now. An existing op with the same idempotency key is
  /// kept and returned instead (enqueue is idempotent).
  Future<OutboxOpRow> enqueue({
    required String kind,
    required String idempotencyKey,
    required String payload,
    String? conversationId,
    int? messageRowid,
    required DateTime now,
  }) => transaction(() async {
    await into(outboxOps).insert(
      OutboxOpsCompanion.insert(
        kind: kind,
        idempotencyKey: idempotencyKey,
        payload: payload,
        conversationId: Value(conversationId),
        messageRowid: Value(messageRowid),
        state: OutboxState.pending,
        nextAttemptAt: now,
        createdAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return (select(
      outboxOps,
    )..where((o) => o.idempotencyKey.equals(idempotencyKey))).getSingle();
  });

  /// Where a held op is parked (see [enqueueHeld]); far past any real time.
  static final heldAt = DateTime.utc(9999, 12, 31);

  /// Whether [op] is parked by [enqueueHeld] or [hold] and waits for
  /// [release].
  static bool isHeld(OutboxOpRow op) =>
      op.state == OutboxState.pending &&
      op.nextAttemptAt.millisecondsSinceEpoch >= heldAt.millisecondsSinceEpoch;

  /// Adds an op that keeps its place in the chat's order but is not sent
  /// until [release]: an attachment message whose upload is still running.
  /// The held [payload] is a placeholder; a later [release] replaces it.
  /// Like [enqueue], an existing op with the same key is kept.
  Future<OutboxOpRow> enqueueHeld({
    required String kind,
    required String idempotencyKey,
    required String payload,
    String? conversationId,
    int? messageRowid,
    required DateTime now,
  }) => transaction(() async {
    await into(outboxOps).insert(
      OutboxOpsCompanion.insert(
        kind: kind,
        idempotencyKey: idempotencyKey,
        payload: payload,
        conversationId: Value(conversationId),
        messageRowid: Value(messageRowid),
        state: OutboxState.pending,
        nextAttemptAt: heldAt,
        createdAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return (select(
      outboxOps,
    )..where((o) => o.idempotencyKey.equals(idempotencyKey))).getSingle();
  });

  /// Ops parked by [enqueueHeld] or [hold], oldest first.
  Future<List<OutboxOpRow>> heldOps() =>
      (select(outboxOps)
            ..where(
              (o) =>
                  o.state.equalsValue(OutboxState.pending) &
                  o.nextAttemptAt.isBiggerOrEqualValue(
                    heldAt.millisecondsSinceEpoch,
                  ),
            )
            ..orderBy([(o) => OrderingTerm.asc(o.id)]))
          .get();

  /// Parks a pending or failed op again (an upload is being retried), with
  /// its placeholder [payload].
  Future<void> hold(int id, {required String payload}) =>
      (update(outboxOps)..where((o) => o.id.equals(id))).write(
        OutboxOpsCompanion(
          state: const Value(OutboxState.pending),
          nextAttemptAt: Value(heldAt),
          leaseUntil: const Value(null),
          attempts: const Value(0),
          lastError: const Value(null),
          payload: Value(payload),
        ),
      );

  /// Releases a held op with its real [payload]: it is due now. Returns
  /// false when the op is not held (gone, failed or already released), so a
  /// duplicate release changes nothing.
  Future<bool> release(
    int id, {
    required String payload,
    required DateTime now,
  }) async {
    final changed =
        await (update(outboxOps)..where(
              (o) =>
                  o.id.equals(id) &
                  o.state.equalsValue(OutboxState.pending) &
                  o.nextAttemptAt.isBiggerOrEqualValue(
                    heldAt.millisecondsSinceEpoch,
                  ),
            ))
            .write(
              OutboxOpsCompanion(
                nextAttemptAt: Value(now),
                payload: Value(payload),
              ),
            );
    return changed > 0;
  }

  /// Claims up to [limit] due ops, oldest first, leasing them until
  /// [leaseUntil]. Ops whose lease ran out (a crashed worker) are due again.
  Future<List<OutboxOpRow>> claimDue(
    DateTime now, {
    required DateTime leaseUntil,
    int limit = 20,
  }) => transaction(() async {
    final nowMs = now.millisecondsSinceEpoch;
    final due =
        await (select(outboxOps)
              ..where(
                (o) =>
                    (o.state.equalsValue(OutboxState.pending) &
                        o.nextAttemptAt.isSmallerOrEqualValue(nowMs)) |
                    (o.state.equalsValue(OutboxState.inFlight) &
                        o.leaseUntil.isSmallerOrEqualValue(nowMs)),
              )
              ..orderBy([(o) => OrderingTerm.asc(o.id)])
              ..limit(limit))
            .get();
    if (due.isEmpty) return due;
    return (update(outboxOps)..where((o) => o.id.isIn(due.map((o) => o.id))))
        .writeReturning(
          OutboxOpsCompanion(
            state: const Value(OutboxState.inFlight),
            leaseUntil: Value(leaseUntil),
          ),
        )
        .then((rows) => rows..sort((a, b) => a.id.compareTo(b.id)));
  });

  /// Like [claimDue], but an op is claimed only when no earlier op of the
  /// same conversation is still queued (pending, in flight or backing off),
  /// so messages of one chat leave in the order they were written even when
  /// an earlier one is being retried. Ops without a conversation never
  /// wait. Failed ops do not hold up the chat.
  Future<List<OutboxOpRow>> claimDueOrdered(
    DateTime now, {
    required DateTime leaseUntil,
    int limit = 20,
  }) => transaction(() async {
    final nowMs = now.millisecondsSinceEpoch;
    final queued =
        await (select(outboxOps)
              ..where(
                (o) =>
                    o.state.equalsValue(OutboxState.pending) |
                    o.state.equalsValue(OutboxState.inFlight),
              )
              ..orderBy([(o) => OrderingTerm.asc(o.id)]))
            .get();
    final seen = <String>{};
    final claim = <int>[];
    for (final op in queued) {
      final chat = op.conversationId;
      final blocked = chat != null && !seen.add(chat);
      final due = op.state == OutboxState.pending
          ? op.nextAttemptAt.millisecondsSinceEpoch <= nowMs
          : (op.leaseUntil?.millisecondsSinceEpoch ?? 0) <= nowMs;
      if (!blocked && due && claim.length < limit) claim.add(op.id);
    }
    if (claim.isEmpty) return const [];
    final rows = await (update(outboxOps)..where((o) => o.id.isIn(claim)))
        .writeReturning(
          OutboxOpsCompanion(
            state: const Value(OutboxState.inFlight),
            leaseUntil: Value(leaseUntil),
          ),
        );
    return rows..sort((a, b) => a.id.compareTo(b.id));
  });

  Future<OutboxOpRow?> byId(int id) =>
      (select(outboxOps)..where((o) => o.id.equals(id))).getSingleOrNull();

  /// The queued or failed ops of a message (status, "retry" and cancel).
  Future<List<OutboxOpRow>> forMessage(int messageRowid) => (select(
    outboxOps,
  )..where((o) => o.messageRowid.equals(messageRowid))).get();

  /// The op was sent: it leaves the queue.
  Future<void> complete(int id) =>
      (delete(outboxOps)..where((o) => o.id.equals(id))).go();

  /// The attempt failed and will be retried at [nextAttemptAt]. [errorCode]
  /// is an error code, never content.
  Future<void> reschedule(
    int id, {
    required DateTime nextAttemptAt,
    required String errorCode,
  }) => customUpdate(
    'UPDATE outbox_ops SET state = ?, attempts = attempts + 1, '
    'next_attempt_at = ?, lease_until = NULL, last_error = ? WHERE id = ?',
    variables: [
      Variable.withString(OutboxState.pending.name),
      Variable.withInt(nextAttemptAt.millisecondsSinceEpoch),
      Variable.withString(errorCode),
      Variable.withInt(id),
    ],
    updates: {outboxOps},
    updateKind: UpdateKind.update,
  );

  /// Gives up on the op; it stays visible as failed until retried or
  /// removed.
  Future<void> fail(int id, {required String errorCode}) => customUpdate(
    'UPDATE outbox_ops SET state = ?, attempts = attempts + 1, '
    'lease_until = NULL, last_error = ? WHERE id = ?',
    variables: [
      Variable.withString(OutboxState.failed.name),
      Variable.withString(errorCode),
      Variable.withInt(id),
    ],
    updates: {outboxOps},
    updateKind: UpdateKind.update,
  );

  /// Puts a failed op back in the queue, due now (user tapped "retry").
  Future<void> retry(int id, {required DateTime now}) =>
      (update(outboxOps)..where((o) => o.id.equals(id))).write(
        OutboxOpsCompanion(
          state: const Value(OutboxState.pending),
          nextAttemptAt: Value(now),
          leaseUntil: const Value(null),
        ),
      );

  /// When the worker should next wake up: the earliest pending attempt or
  /// lease expiry. Null when nothing is queued.
  Future<DateTime?> nextWakeAt() async {
    final row = await customSelect(
      'SELECT min(CASE state WHEN ? THEN next_attempt_at '
      'ELSE lease_until END) AS at FROM outbox_ops WHERE state IN (?, ?)',
      variables: [
        Variable.withString(OutboxState.pending.name),
        Variable.withString(OutboxState.pending.name),
        Variable.withString(OutboxState.inFlight.name),
      ],
      readsFrom: {outboxOps},
    ).getSingle();
    final at = row.readNullable<int>('at');
    return at == null ? null : const EpochMs().fromSql(at);
  }

  /// Number of queued (pending or in-flight) ops; emits on every change.
  /// The worker's single wake-up path listens to this.
  Stream<int> watchQueuedCount() => customSelect(
    'SELECT count(*) AS n FROM outbox_ops WHERE state IN (?, ?)',
    variables: [
      Variable.withString(OutboxState.pending.name),
      Variable.withString(OutboxState.inFlight.name),
    ],
    readsFrom: {outboxOps},
  ).watchSingle().map((row) => row.read<int>('n'));

  /// Changes whenever a queued op is added, retried, rescheduled or leaves
  /// the queue, even when the count stays the same (an op completing as
  /// another is enqueued). The worker's wake-up path.
  Stream<String> watchQueueMark() =>
      customSelect(
        'SELECT coalesce(max(id), 0) AS newest, count(*) AS n, '
        'coalesce(sum(attempts), 0) AS attempts, '
        'coalesce(sum(next_attempt_at), 0) AS due FROM outbox_ops '
        'WHERE state IN (?, ?)',
        variables: [
          Variable.withString(OutboxState.pending.name),
          Variable.withString(OutboxState.inFlight.name),
        ],
        readsFrom: {outboxOps},
      ).watchSingle().map(
        (row) =>
            '${row.read<int>('newest')}:${row.read<int>('n')}:'
            '${row.read<int>('attempts')}:${row.read<int>('due')}',
      );

  Future<List<OutboxOpRow>> failed() => (select(
    outboxOps,
  )..where((o) => o.state.equalsValue(OutboxState.failed))).get();
}
