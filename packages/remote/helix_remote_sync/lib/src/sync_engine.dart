import 'dart:convert';
import 'dart:math' as math;
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';

abstract class SyncGateway {
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  });

  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  });
}

class RemoteSyncEngine {
  final HelixRemoteDatabase db;

  RemoteSyncEngine(this.db);

  /// Synchronises incoming events from the server since the last stored cursor.
  ///
  /// ATOMICITY (DEFECT-5 fix): the entire batch is wrapped in a single SQLite
  /// transaction. The cursor is updated only after ALL events are applied.
  /// A crash or error mid-batch rolls back everything; on the next sync the
  /// engine re-fetches from the unchanged cursor and replays the same batch.
  Future<int> syncInbound(SyncGateway gateway, String conversationId) async {
    final lastSeq = db.getSyncCursor(conversationId);

    final envelopes = await gateway.fetchInboundEvents(sinceSequence: lastSeq);

    final sortedEnvelopes = List<RemoteRealtimeEnvelope>.from(envelopes)
      ..sort((a, b) => (a.serverSequence ?? 0).compareTo(b.serverSequence ?? 0));

    int appliedCount = 0;
    int highestSeq = lastSeq;

    // Single transaction for the full batch — cursor advances only on COMMIT.
    db.rawExecute('BEGIN TRANSACTION;');
    try {
      for (final env in sortedEnvelopes) {
        final seq = env.serverSequence ?? 0;
        if (seq <= lastSeq) {
          continue; // Duplicate sequence — already applied before this batch
        }

        if (env.type == 'chat_message') {
          final payload = env.payload;
          final messageId = env.eventId;
          final senderAccountId = payload['sender_account_id'] as String? ?? 'unknown';
          final senderDeviceId = payload['sender_device_id'] as int? ?? 0;
          final ciphertext = payload['ciphertext'] as String? ?? '';

          if (db.isTombstoned(messageId, 'MESSAGE')) {
            // Tombstoned events still advance the cursor so they are not re-fetched.
            highestSeq = seq;
            continue;
          }

          final message = RemoteMessage(
            messageId: messageId,
            conversationId: conversationId,
            senderAccountId: senderAccountId,
            senderDeviceId: senderDeviceId,
            ciphertext: ciphertext,
          );

          db.saveMessage(message, seq, env.timestamp, 'DELIVERED');
          highestSeq = seq;
          appliedCount++;
        } else if (env.type == 'sync_marker') {
          highestSeq = seq;
          appliedCount++;
        }
      }

      // Update cursor once for the entire batch.
      if (highestSeq > lastSeq) {
        db.updateSyncCursor(conversationId, highestSeq);
      }

      db.rawExecute('COMMIT;');
    } catch (e) {
      db.rawExecute('ROLLBACK;');
      rethrow;
    }

    return appliedCount;
  }

  /// Processes the outbound pending-operations queue with exponential backoff.
  ///
  /// DEFECT-6 fix: backoff is computed from [next_attempt_at], which is
  /// persisted to the database after each failure. A process restart will not
  /// retry an operation before its scheduled deadline.
  Future<int> processOutboundQueue(SyncGateway gateway) async {
    final pendingOps = db.getPendingOperations();
    int processedCount = 0;

    for (final op in pendingOps) {
      final opId = op['op_id'] as String;
      final type = op['type'] as String;
      final payloadStr = op['payload'] as String;
      final retries = op['retries'] as int;

      // getPendingOperations() already filters by next_attempt_at <= now,
      // so no additional time check is needed here.

      try {
        final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

        await gateway.sendOutboundOperation(
          opId: opId,
          type: type,
          payload: payload,
        );

        db.updateOperationStatus(opId, 'COMPLETED', retries);
        processedCount++;
      } catch (e) {
        final nextRetries = retries + 1;
        final nextStatus = nextRetries >= 5 ? 'FAILED' : 'PENDING';
        db.updateOperationStatus(opId, nextStatus, nextRetries);

        if (nextRetries < 5) {
          // Exponential backoff: 2^retries seconds, plus 0–500 ms random jitter.
          final backoffMs = 1000 * (1 << nextRetries);
          final jitterMs = math.Random().nextInt(500);
          final nextAttempt =
              DateTime.now().millisecondsSinceEpoch + backoffMs + jitterMs;
          db.scheduleNextOperationAttempt(opId, nextAttempt);
        }
      }
    }

    return processedCount;
  }
}
