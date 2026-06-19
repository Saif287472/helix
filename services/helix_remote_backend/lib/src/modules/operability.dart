import 'dart:convert';

import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/outbox_worker.dart';
import 'package:helix_remote_backend/src/rate_limiter.dart';
import 'package:helix_remote_backend/src/websocket.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

class OperabilityModule {
  OperabilityModule({
    required this.db,
    required this.rateLimiter,
    required this.wsRelay,
    required this.outboxWorker,
    required this.adminAccountIds,
    required this.turnUrl,
  });

  final BackendDatabase db;
  final RateLimiter rateLimiter;
  final WebSocketRelay wsRelay;
  final OutboxWorker outboxWorker;
  final Set<String> adminAccountIds;
  final String turnUrl;

  static const sloTargets = {
    'availability_monthly': '99.5%',
    'api_success_rate_5m': '99.0%',
    'message_enqueue_p95_ms': 500,
    'websocket_reconnect_reject_rate_5m_max': '5%',
    'push_outbox_dlq_max': 0,
    'turn_credential_error_rate_5m_max': '2%',
    'backup_restore_drill_max_age_days': 30,
  };

  static const alertThresholds = {
    'readiness_failed_minutes': 2,
    'api_5xx_rate_5m_percent': 2,
    'api_429_rate_5m_percent': 20,
    'outbox_failed_or_dlq_count': 10,
    'websocket_reconnect_rejections_5m': 25,
    'attachment_incomplete_objects': 100,
    'turn_unconfigured_in_production': true,
    'backup_restore_drill_overdue_days': 30,
    'monthly_cost_budget_percent': 80,
  };

  Router get healthRouter {
    final router = Router();
    router.get('/live', _live);
    router.get('/ready', _ready);
    return router;
  }

  Router get opsRouter {
    final router = Router();
    router.get('/metrics', _metrics);
    return router;
  }

  Response _live(Request request) {
    return _json({
      'status': 'ok',
      'service': 'helix_remote_backend',
      'time': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Response _ready(Request request) {
    final dbOk = db.quickCheckOk();
    final outbox = db.getOutboxStatusCounts();
    final failedOrDlq = outbox['FAILED']! + outbox['DLQ']!;
    final ready = dbOk;
    return _json({
      'status': ready ? 'ready' : 'not_ready',
      'dependencies': {
        'database': dbOk ? 'ok' : 'failed',
        'push_outbox': failedOrDlq == 0 ? 'ok' : 'degraded_failed_or_dlq_items',
        'turn': turnUrl.isEmpty ? 'not_configured' : 'configured',
      },
      'schema_version': db.schemaVersion,
    }, status: ready ? 200 : 503);
  }

  Response _metrics(Request request) {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    final accountId = auth?['account_id'] as String?;
    final deviceId = auth?['device_id'] as String?;
    if (accountId == null || !adminAccountIds.contains(accountId)) {
      db.logAudit(
        accountId,
        deviceId,
        'ADMIN_ACCESS_DENIED',
        request.context['client_ip'] as String?,
        request.headers['user-agent'],
      );
      return _json({'error': 'Admin privileges required'}, status: 403);
    }

    db.logAudit(
      accountId,
      deviceId,
      'ADMIN_OPERABILITY_METRICS_READ',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );

    return _json({
      'service': 'helix_remote_backend',
      'schema_version': db.schemaVersion,
      'database_quick_check_ok': db.quickCheckOk(),
      'table_counts': db.getOperationalTableCounts(),
      'mailbox': db.getOperationalMailboxStats(),
      'attachments': db.getOperationalAttachmentStats(),
      'outbox': db.getOutboxStatusCounts(),
      'websocket': wsRelay.stats(),
      'rate_limiter': rateLimiter.stats(),
      'push_provider': {
        'configured': true,
        'available': outboxWorker.pushProviderAvailable,
      },
      'turn': {'configured': turnUrl.isNotEmpty},
      'slo_targets': sloTargets,
      'alert_thresholds': alertThresholds,
    });
  }

  Response _json(Map<String, dynamic> body, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
