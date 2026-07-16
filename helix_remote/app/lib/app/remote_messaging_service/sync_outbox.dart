part of '../remote_messaging_service.dart';

mixin RemoteSyncOutbox on RemoteMessagingServiceBase {
  Future<int> syncInbound() => syncEngine.syncInbound(gateway);

  Future<int> processOutboundQueue() =>
      syncEngine.processOutboundQueue(gateway);

  RemoteOutboxSummary outboxSummary() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var queued = 0;
    var retryScheduled = 0;
    var failed = 0;
    int? nextRetryAt;
    for (final op in db.getOutboxOperations()) {
      final status = op['status'] as String;
      final retries = op['retries'] as int;
      final nextAttempt = op['next_attempt_at'] as int;
      if (status == 'FAILED') {
        failed++;
        continue;
      }
      if (status == 'PENDING' && nextAttempt > now && retries > 0) {
        retryScheduled++;
        nextRetryAt = nextRetryAt == null || nextAttempt < nextRetryAt
            ? nextAttempt
            : nextRetryAt;
      } else {
        queued++;
      }
    }
    return RemoteOutboxSummary(
      queuedCount: queued,
      retryScheduledCount: retryScheduled,
      failedCount: failed,
      nextRetryAt: nextRetryAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextRetryAt),
    );
  }

  Future<int> retryFailedOutbox() async {
    var retried = 0;
    for (final op in db.getOutboxOperations()) {
      if (op['status'] == 'FAILED') {
        db.retryOperationNow(op['op_id'] as String);
        retried++;
      }
    }
    if (retried > 0) {
      _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.outbox}));
      await processOutboundQueue();
    }
    return retried;
  }
}
