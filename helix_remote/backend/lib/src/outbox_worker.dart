import 'dart:async';
import 'dart:convert';
import 'dart:io' show stderr;

import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/push_provider.dart';

class OutboxWorker {
  OutboxWorker(
    this.db, {
    PushProvider? pushProvider,
    this.interval = const Duration(seconds: 2),
    this.pushProviderAvailable = true,
    this.maxRetries = 5,
  }) : _pushProvider = pushProvider ?? const NoopPushProvider();

  final BackendDatabase db;
  final PushProvider _pushProvider;
  final Duration interval;
  bool pushProviderAvailable;
  final int maxRetries;
  Timer? _timer;

  bool get pushProviderConfigured => _pushProvider.isConfigured;

  void start() {
    _timer = Timer.periodic(interval, (_) {
      processOnce().catchError((Object e) {
        stderr.writeln('[OutboxWorker] timer error: $e');
        return <String, int>{'completed': 0, 'failed': 0, 'dlq': 0};
      });
    });
  }

  void stop() {
    _timer?.cancel();
  }

  Future<Map<String, int>> processOnce() async {
    final processed = <String, int>{'completed': 0, 'failed': 0, 'dlq': 0};
    try {
      final items = db.getPendingOutbox();
      for (final item in items) {
        final eventId = item['event_id'] as String;
        final type = item['type'] as String;
        final retries = item['retries'] as int;

        if (type == 'PUSH_NOTIFICATION') {
          Map<String, dynamic> payload;
          try {
            payload =
                jsonDecode(item['payload'] as String) as Map<String, dynamic>;
          } catch (_) {
            db.updateOutboxStatus(eventId, 'DLQ', retries + 1);
            processed['dlq'] = processed['dlq']! + 1;
            continue;
          }
          await _processPush(
            eventId: eventId,
            payload: payload,
            retries: retries,
            processed: processed,
          );
        } else {
          _failOrDlq(eventId, retries, processed);
        }
      }

      // Purge terminal pending calls older than 10 minutes.
      final tenMinutesAgo =
          DateTime.now().millisecondsSinceEpoch - const Duration(minutes: 10).inMilliseconds;
      db.purgeTerminalPendingCalls(tenMinutesAgo);
    } catch (e) {
      stderr.writeln('[OutboxWorker] processOnce error: $e');
    }
    return processed;
  }

  Future<void> _processPush({
    required String eventId,
    required Map<String, dynamic> payload,
    required int retries,
    required Map<String, int> processed,
  }) async {
    // Key is 'recipient_device_id' as stored by the messaging module.
    final targetDeviceId = payload['recipient_device_id'] as String?;

    if (targetDeviceId == null || targetDeviceId.isEmpty) {
      // No device to deliver to — treat as silently completed.
      db.updateOutboxStatus(eventId, 'COMPLETED', retries);
      processed['completed'] = processed['completed']! + 1;
      return;
    }

    // Look up push token at delivery time — never stored in the outbox payload.
    final pushToken = db.getDevicePushToken(targetDeviceId);

    if (pushToken == null || pushToken.isEmpty) {
      // Device has no registered push token — complete silently.
      db.updateOutboxStatus(eventId, 'COMPLETED', retries);
      processed['completed'] = processed['completed']! + 1;
      return;
    }

    if (!_pushProvider.isConfigured) {
      // FCM not configured — complete silently rather than filling the DLQ
      // with entries that can never succeed.
      db.updateOutboxStatus(eventId, 'COMPLETED', retries);
      processed['completed'] = processed['completed']! + 1;
      return;
    }

    if (!pushProviderAvailable) {
      _failOrDlq(eventId, retries, processed);
      return;
    }

    try {
      await _pushProvider.deliver(token: pushToken, data: payload);
      db.updateOutboxStatus(eventId, 'COMPLETED', retries);
      processed['completed'] = processed['completed']! + 1;
    } on FcmTokenNotFoundException {
      // Token is stale — silently complete (device will re-register or not).
      db.updateOutboxStatus(eventId, 'COMPLETED', retries);
      processed['completed'] = processed['completed']! + 1;
    } catch (e) {
      stderr.writeln('[OutboxWorker] FCM delivery error event=$eventId: $e');
      _failOrDlq(eventId, retries, processed);
    }
  }

  void _failOrDlq(String eventId, int retries, Map<String, int> processed) {
    final nextRetries = retries + 1;
    if (nextRetries >= maxRetries) {
      db.updateOutboxStatus(eventId, 'DLQ', nextRetries);
      processed['dlq'] = processed['dlq']! + 1;
    } else {
      db.updateOutboxStatus(eventId, 'FAILED', nextRetries);
      processed['failed'] = processed['failed']! + 1;
    }
  }
}
