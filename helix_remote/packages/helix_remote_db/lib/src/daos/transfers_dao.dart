import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/transfers.dart';
import 'package:helix_remote_db/src/values.dart';

part 'transfers_dao.g.dart';

/// The durable attachment transfer queue (plan §6.3).
///
/// A transfer is not an outbox op: it is long-running, resumable and
/// cancellable, where an outbox op is one request with a retry. Leases work the
/// same way as the outbox's, so a worker that dies does not strand a job.
///
/// The bytes live outside the database under a random name; this table holds
/// the path, the progress and the key.
@DriftAccessor(tables: [TransferJobs, TransferChunks])
class TransfersDao extends DatabaseAccessor<HelixDb> with _$TransfersDaoMixin {
  TransfersDao(super.attachedDatabase);

  // ------------------------------------------------------------- the queue

  /// Queues an upload for [attachmentRowid], or returns the existing job.
  ///
  /// Re-requesting an upload that is already queued must not start a second
  /// one, so the unique key on the attachment is what makes this idempotent.
  Future<int> enqueueUpload({
    required int attachmentRowid,
    required String localPath,
    required int size,
    required Uint8List mediaKey,
    required DateTime now,
  }) => _enqueue(
    kind: 'upload',
    attachmentRowid: attachmentRowid,
    localPath: localPath,
    size: size,
    mediaKey: mediaKey,
    now: now,
  );

  /// Queues a download, or returns the existing job.
  Future<int> enqueueDownload({
    required int attachmentRowid,
    required String mediaId,
    required Uint8List mediaKey,
    required int size,
    required DateTime now,
  }) => _enqueue(
    kind: 'download',
    attachmentRowid: attachmentRowid,
    mediaId: mediaId,
    mediaKey: mediaKey,
    size: size,
    now: now,
  );

  /// Queues a transfer that is not an attachment (a group avatar, a backup
  /// blob), or returns the existing job for the same [purpose].
  Future<int> enqueueStandalone({
    required String kind,
    required String purpose,
    required String localPath,
    required DateTime now,
  }) async {
    final existing = await byPurpose(purpose);
    if (existing != null) return existing.id;
    return into(transferJobs).insert(
      TransferJobsCompanion.insert(
        kind: kind,
        purpose: Value(purpose),
        localPath: Value(localPath),
        state: TransferState.pending,
        nextAttemptAt: now,
        createdAt: now,
      ),
    );
  }

  Future<int> _enqueue({
    required String kind,
    required int attachmentRowid,
    String? localPath,
    String? mediaId,
    required Uint8List mediaKey,
    required int size,
    required DateTime now,
  }) async {
    final existing = await byAttachment(attachmentRowid);
    if (existing != null) {
      await (update(
        transferJobs,
      )..where((t) => t.id.equals(existing.id))).write(
        TransferJobsCompanion(
          kind: Value(kind),
          localPath: Value(localPath),
          mediaId: Value(mediaId),
          mediaKey: Value(mediaKey),
          size: Value(size),
          // Re-queuing a failed or finished job makes it retryable again;
          // one a worker holds a lease on stays where it is.
          state: existing.state == TransferState.inFlight
              ? const Value.absent()
              : const Value(TransferState.pending),
          attempts: const Value(0),
          nextAttemptAt: Value(now),
          lastError: const Value(null),
        ),
      );
      return existing.id;
    }
    return into(transferJobs).insert(
      TransferJobsCompanion.insert(
        kind: kind,
        attachmentRowid: Value(attachmentRowid),
        localPath: Value(localPath),
        mediaId: Value(mediaId),
        mediaKey: Value(mediaKey),
        size: Value(size),
        state: TransferState.pending,
        nextAttemptAt: now,
        createdAt: now,
      ),
    );
  }

  Future<TransferRow?> byId(int id) =>
      (select(transferJobs)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<TransferRow?> byAttachment(int attachmentRowid) => (select(
    transferJobs,
  )..where((t) => t.attachmentRowid.equals(attachmentRowid))).getSingleOrNull();

  Future<TransferRow?> byPurpose(String purpose) => (select(
    transferJobs,
  )..where((t) => t.purpose.equals(purpose))).getSingleOrNull();

  /// Everything in flight or waiting, oldest first.
  Future<List<TransferRow>> pending() =>
      (select(transferJobs)
            ..where(
              (t) =>
                  t.state.equalsValue(TransferState.pending) |
                  t.state.equalsValue(TransferState.inFlight),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.nextAttemptAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  Stream<List<TransferRow>> watchPending() =>
      (select(transferJobs)
            ..where(
              (t) =>
                  t.state.equalsValue(TransferState.pending) |
                  t.state.equalsValue(TransferState.inFlight),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .watch();

  /// Jobs due at [now] whose lease has expired or was never taken, oldest
  /// first.
  Future<List<TransferRow>> due(DateTime now) {
    final nowMs = now.millisecondsSinceEpoch;
    return (select(transferJobs)
          ..where(
            (t) =>
                (t.state.equalsValue(TransferState.pending) |
                    t.state.equalsValue(TransferState.inFlight)) &
                t.nextAttemptAt.isSmallerOrEqualValue(nowMs) &
                (t.leaseUntil.isNull() |
                    t.leaseUntil.isSmallerOrEqualValue(nowMs)),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.nextAttemptAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// Claims the oldest due job under a lease, so a second worker cannot take
  /// it. Null when nothing is due (or somebody else holds what is). A job whose
  /// lease ran out (a worker that died) is due again and keeps its offset, so
  /// the next worker resumes it.
  ///
  /// With [kinds], only jobs of those kinds are considered (a worker with
  /// separate limits for uploads and downloads).
  Future<TransferRow?> claim(
    DateTime now, {
    required Duration lease,
    Set<String>? kinds,
  }) => transaction(() async {
    final nowMs = now.millisecondsSinceEpoch;
    for (final candidate in await due(now)) {
      if (kinds != null && !kinds.contains(candidate.kind)) continue;
      final taken =
          await (update(transferJobs)..where(
                (t) =>
                    t.id.equals(candidate.id) &
                    (t.leaseUntil.isNull() |
                        t.leaseUntil.isSmallerOrEqualValue(nowMs)),
              ))
              .write(
                TransferJobsCompanion(
                  state: const Value(TransferState.inFlight),
                  leaseUntil: Value(now.add(lease)),
                ),
              );
      if (taken > 0) return byId(candidate.id);
    }
    return null;
  });

  /// Extends the lease of a job a worker is still running. False when the
  /// job is gone or no longer leased (cancelled, or taken over).
  Future<bool> renewLease(int id, {required DateTime until}) async {
    final changed =
        await (update(transferJobs)..where(
              (t) =>
                  t.id.equals(id) & t.state.equalsValue(TransferState.inFlight),
            ))
            .write(TransferJobsCompanion(leaseUntil: Value(until)));
    return changed > 0;
  }

  /// Gives a leased job back without counting an attempt (the worker is
  /// stopping): pending again, due [at], with its progress kept.
  Future<void> release(int id, {required DateTime at}) =>
      (update(transferJobs)..where(
            (t) =>
                t.id.equals(id) & t.state.equalsValue(TransferState.inFlight),
          ))
          .write(
            TransferJobsCompanion(
              state: const Value(TransferState.pending),
              nextAttemptAt: Value(at),
              leaseUntil: const Value(null),
            ),
          );

  /// The attempt failed for a reason that may pass (no network, a busy
  /// server): pending again at [nextAttemptAt], progress kept, the attempt
  /// counted. Unlike [fail] this never gives up by itself.
  Future<void> reschedule(
    int id, {
    required DateTime nextAttemptAt,
    required String code,
  }) => customUpdate(
    'UPDATE transfer_jobs SET state = ?, attempts = attempts + 1, '
    'next_attempt_at = ?, lease_until = NULL, last_error = ? WHERE id = ?',
    variables: [
      Variable.withString(TransferState.pending.name),
      Variable.withInt(nextAttemptAt.millisecondsSinceEpoch),
      Variable.withString(code),
      Variable.withInt(id),
    ],
    updates: {transferJobs},
    updateKind: UpdateKind.update,
  );

  /// Forgets the progress and the server object of a job (the staged bytes
  /// were lost, so the transfer starts again from nothing).
  Future<void> resetProgress(int id) =>
      (update(transferJobs)..where((t) => t.id.equals(id))).write(
        const TransferJobsCompanion(offset: Value(0), mediaId: Value(null)),
      );

  /// Queues the download of an attachment's thumbnail, or returns the
  /// existing job. The thumbnail is its own small object, so this job
  /// carries the thumbnail's id and key.
  Future<int> enqueueThumbnail({
    required int attachmentRowid,
    required String mediaId,
    required Uint8List mediaKey,
    required int size,
    required DateTime now,
  }) async {
    final existing = await byAttachment(attachmentRowid);
    if (existing != null && existing.kind == 'download') return existing.id;
    return _enqueue(
      kind: 'thumbnail',
      attachmentRowid: attachmentRowid,
      mediaId: mediaId,
      mediaKey: mediaKey,
      size: size,
      now: now,
    );
  }

  /// Jobs that are queued, running or failed (everything that may still own
  /// staged bytes), oldest first.
  Future<List<TransferRow>> live() =>
      (select(transferJobs)
            ..where((t) => t.state.equalsValue(TransferState.done).not())
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  Stream<List<TransferRow>> watchLive() =>
      (select(transferJobs)
            ..where((t) => t.state.equalsValue(TransferState.done).not())
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .watch();

  /// Records progress after a chunk, so a resumed transfer continues. A null
  /// [mediaId] or [localPath] leaves the stored one as it is.
  Future<void> setProgress(
    int id, {
    required int offset,
    String? mediaId,
    String? localPath,
  }) => (update(transferJobs)..where((t) => t.id.equals(id))).write(
    TransferJobsCompanion(
      offset: Value(offset),
      mediaId: mediaId == null ? const Value.absent() : Value(mediaId),
      localPath: localPath == null ? const Value.absent() : Value(localPath),
    ),
  );

  Future<void> markDone(int id) =>
      (update(transferJobs)..where((t) => t.id.equals(id))).write(
        const TransferJobsCompanion(
          state: Value(TransferState.done),
          offset: Value(0),
          leaseUntil: Value(null),
          lastError: Value(null),
        ),
      );

  /// Schedules a retry, or gives up after [maxAttempts] and lets the UI offer
  /// one. The error is a code only.
  Future<bool> fail(
    int id, {
    required String code,
    required DateTime now,
    required Duration backoff,
    int maxAttempts = 5,
  }) async {
    final job = await byId(id);
    if (job == null) return true;
    final attempts = job.attempts + 1;
    final givenUp = attempts >= maxAttempts;
    await (update(transferJobs)..where((t) => t.id.equals(id))).write(
      TransferJobsCompanion(
        state: Value(givenUp ? TransferState.failed : TransferState.pending),
        attempts: Value(attempts),
        nextAttemptAt: Value(now.add(backoff * attempts)),
        leaseUntil: const Value(null),
        lastError: Value(code),
      ),
    );
    return givenUp;
  }

  /// Removes a finished job and its file.
  ///
  /// The file goes too: an attachment the user deleted must not be left on
  /// disk to be found later.
  Future<void> remove(int id) async {
    final job = await byId(id);
    if (job == null) return;
    await (delete(transferJobs)..where((t) => t.id.equals(id))).go();
    final path = job.localPath;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // The file is already gone, or is not ours to delete. Nothing to do.
    }
  }

  // ------------------------------------------------- device-to-device chunks

  /// Stores one chunk of an incoming transfer.
  ///
  /// Chunks may arrive in any order, so this is keyed by sequence and the
  /// caller checks for gaps once it has them all.
  Future<void> addChunk({
    required String transferId,
    required int sequence,
    required Uint8List payload,
    required int total,
    required bool isFinal,
    required DateTime now,
  }) => into(transferChunks).insertOnConflictUpdate(
    TransferChunksCompanion.insert(
      transferId: transferId,
      sequence: sequence,
      payload: payload,
      total: total,
      isFinal: Value(isFinal),
      receivedAt: now,
    ),
  );

  Future<List<TransferChunkRow>> chunks(String transferId) =>
      (select(transferChunks)
            ..where((c) => c.transferId.equals(transferId))
            ..orderBy([(c) => OrderingTerm.asc(c.sequence)]))
          .get();

  /// The sequence numbers still missing from [transferId], ascending.
  ///
  /// Null when no chunk has arrived (the total is not known yet). Chunks that
  /// disagree about the total are never trusted: the whole range is reported
  /// missing.
  Future<List<int>?> missingSequences(String transferId) async {
    final rows = await chunks(transferId);
    if (rows.isEmpty) return null;
    final total = rows.first.total;
    if (total <= 0) return const [];
    if (rows.any((row) => row.total != total)) {
      return [for (var i = 0; i < total; i++) i];
    }
    final seen = {for (final row in rows) row.sequence};
    return [
      for (var i = 0; i < total; i++)
        if (!seen.contains(i)) i,
    ];
  }

  /// Whether every chunk of [transferId] has arrived.
  Future<bool> isComplete(String transferId) async {
    final rows = await chunks(transferId);
    if (rows.isEmpty || rows.first.total <= 0) return false;
    return (await missingSequences(transferId))!.isEmpty;
  }

  /// The chunks joined in order, or null when there is a gap.
  ///
  /// A partial transfer is never used: restoring half a history would leave
  /// messages missing without saying so, so a gap means the whole transfer is
  /// asked for again.
  Future<Uint8List?> assemble(String transferId) async {
    if (!await isComplete(transferId)) return null;
    final rows = await chunks(transferId);
    final total = rows.first.total;
    final builder = BytesBuilder(copy: false);
    for (final row in rows.where((row) => row.sequence < total)) {
      builder.add(row.payload);
    }
    return builder.takeBytes();
  }

  Future<void> dropTransfer(String transferId) => transaction(() async {
    await (delete(
      transferChunks,
    )..where((c) => c.transferId.equals(transferId))).go();
  });
}
