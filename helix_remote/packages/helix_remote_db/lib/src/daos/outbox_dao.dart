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

  Future<List<OutboxOpRow>> failed() => (select(
    outboxOps,
  )..where((o) => o.state.equalsValue(OutboxState.failed))).get();
}
