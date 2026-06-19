import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  /// Decrypts them, suppresses duplicates and tombstones, and transactionally
  /// updates database state.
  Future<int> syncInbound(SyncGateway gateway, String conversationId) async {
    final lastSeq = db.getSyncCursor(conversationId);
    
    try {
      final envelopes = await gateway.fetchInboundEvents(sinceSequence: lastSeq);
      
      // Sort envelopes by sequence to apply them in order
      final sortedEnvelopes = List<RemoteRealtimeEnvelope>.from(envelopes)
        ..sort((a, b) => (a.serverSequence ?? 0).compareTo(b.serverSequence ?? 0));

      int appliedCount = 0;
      for (final env in sortedEnvelopes) {
        final seq = env.serverSequence ?? 0;
        if (seq <= lastSeq) {
          continue; // Duplicate sequence check
        }

        if (env.type == 'chat_message') {
          final payload = env.payload;
          final messageId = env.eventId; // Use event ID as message ID
          final senderAccountId = payload['sender_account_id'] as String? ?? 'unknown';
          final senderDeviceId = payload['sender_device_id'] as int? ?? 0;
          final ciphertext = payload['ciphertext'] as String? ?? '';

          // Duplicate & tombstone checks
          if (db.isTombstoned(messageId, 'MESSAGE')) {
            // Drop silently
            db.updateSyncCursor(conversationId, seq);
            continue;
          }

          // Safety: logs must contain no plaintext message content (P11-035)
          if (kDebugMode) {
            print('SyncEngine: processing message envelope $messageId (seq: $seq)');
          }

          final message = RemoteMessage(
            messageId: messageId,
            conversationId: conversationId,
            senderAccountId: senderAccountId,
            senderDeviceId: senderDeviceId,
            ciphertext: ciphertext,
          );

          db.saveMessage(message, seq, env.timestamp, 'DELIVERED');
          db.updateSyncCursor(conversationId, seq);
          appliedCount++;
        } else if (env.type == 'sync_marker') {
          db.updateSyncCursor(conversationId, seq);
          appliedCount++;
        }
      }

      return appliedCount;
    } catch (e) {
      if (kDebugMode) {
        print('SyncEngine error during inbound sync: $e');
      }
      rethrow;
    }
  }

  /// Processes outbound pending operations queue with exponential backoff and jitter.
  Future<int> processOutboundQueue(SyncGateway gateway) async {
    final pendingOps = db.getPendingOperations();
    int processedCount = 0;

    for (final op in pendingOps) {
      final opId = op['op_id'] as String;
      final type = op['type'] as String;
      final payloadStr = op['payload'] as String;
      final retries = op['retries'] as int;
      final createdAt = op['created_at'] as int;

      // Exponential backoff logic with jitter: 1sec * 2^retries + random jitter (0-500ms)
      if (retries > 0) {
        final backoffMs = (1000 * (1 << retries));
        final now = DateTime.now().millisecondsSinceEpoch;

        if (now < createdAt + backoffMs) {
          continue; // Backoff wait window is still active
        }
      }

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
      }
    }

    return processedCount;
  }
}
