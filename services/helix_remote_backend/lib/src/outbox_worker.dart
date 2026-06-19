import 'dart:async';
import 'dart:io' show stderr;

import 'package:helix_remote_backend/src/database.dart';

class OutboxWorker {
  OutboxWorker(
    this.db, {
    this.interval = const Duration(seconds: 2),
    this.pushProviderAvailable = true,
    this.maxRetries = 5,
  });

  final BackendDatabase db;
  final Duration interval;
  bool pushProviderAvailable;
  final int maxRetries;
  Timer? _timer;

  void start() {
    _timer = Timer.periodic(interval, (_) => processOnce());
  }

  void stop() {
    _timer?.cancel();
  }

  Map<String, int> processOnce() {
    final processed = <String, int>{'completed': 0, 'failed': 0, 'dlq': 0};
    try {
      final items = db.getPendingOutbox();
      for (final item in items) {
        final eventId = item['event_id'] as String;
        final type = item['type'] as String;
        final retries = item['retries'] as int;
        final nextRetries = retries + 1;

        if (type == 'PUSH_NOTIFICATION') {
          if (pushProviderAvailable) {
            // Process mock push notification delivery.
            db.updateOutboxStatus(eventId, 'COMPLETED', retries);
            processed['completed'] = processed['completed']! + 1;
          } else if (nextRetries >= maxRetries) {
            db.updateOutboxStatus(eventId, 'DLQ', nextRetries);
            processed['dlq'] = processed['dlq']! + 1;
          } else {
            db.updateOutboxStatus(eventId, 'FAILED', nextRetries);
            processed['failed'] = processed['failed']! + 1;
          }
        } else if (nextRetries >= maxRetries) {
          db.updateOutboxStatus(eventId, 'DLQ', nextRetries);
          processed['dlq'] = processed['dlq']! + 1;
        } else {
          db.updateOutboxStatus(eventId, 'FAILED', nextRetries);
          processed['failed'] = processed['failed']! + 1;
        }
      }
    } catch (e) {
      stderr.writeln('OutboxWorker error: $e');
    }
    return processed;
  }
}
