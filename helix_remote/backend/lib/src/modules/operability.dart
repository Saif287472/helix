import 'dart:convert';

import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/modules/calls.dart';
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
    required this.callsModule,
    required this.adminAccountIds,
    required this.turnSecret,
    required this.turnUrl,
  });

  final BackendDatabase db;
  final RateLimiter rateLimiter;
  final WebSocketRelay wsRelay;
  final OutboxWorker outboxWorker;
  final CallsModule callsModule;
  final Set<String> adminAccountIds;
  final String turnSecret;
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
    router.get('/support-diagnostic', _supportDiagnostic);
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
    final turnUrls = CallsModule.resolveTurnUrls(turnUrl);
    final turnConfigured = turnSecret.trim().isNotEmpty && turnUrls.isNotEmpty;
    final apiReady = dbOk;
    final websocketStats = wsRelay.stats();
    final websocketRejectLimit =
        alertThresholds['websocket_reconnect_rejections_5m'] as int;
    final websocketReady =
        (websocketStats['rejected_reconnects'] as int? ?? 0) <
        websocketRejectLimit;
    final pushConfigured = outboxWorker.pushProviderConfigured;
    final pushReady =
        pushConfigured &&
        outboxWorker.pushProviderAvailable &&
        failedOrDlq == 0;
    return _json({
      'status': apiReady ? 'ready' : 'not_ready',
      'api_ready': apiReady,
      'call_ready': turnConfigured,
      'websocket_ready': websocketReady,
      'push_ready': pushReady,
      'dependencies': {
        'database': dbOk ? 'ok' : 'failed',
        'websocket': websocketReady ? 'ok' : 'degraded_reconnect_rejections',
        'push_outbox': failedOrDlq == 0 ? 'ok' : 'degraded_failed_or_dlq_items',
        'push_provider': !pushConfigured
            ? 'not_configured'
            : outboxWorker.pushProviderAvailable
            ? 'available'
            : 'unavailable',
        'turn': turnConfigured ? 'configured' : 'not_configured',
      },
      'turn': {
        'configured': turnConfigured,
        'url_count': turnUrls.length,
        'live_reachability': 'not_checked',
      },
      'schema_version': db.schemaVersion,
      'capabilities': RemoteCapabilityRegistry.current().toJson(),
    }, status: apiReady ? 200 : 503);
  }

  Response _metrics(Request request) {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    _auditAdminRead(request, 'ADMIN_OPERABILITY_METRICS_READ');

    return _json({
      'service': 'helix_remote_backend',
      'schema_version': db.schemaVersion,
      'capabilities': RemoteCapabilityRegistry.current().toJson(),
      'database_quick_check_ok': db.quickCheckOk(),
      'table_counts': db.getOperationalTableCounts(),
      'mailbox': db.getOperationalMailboxStats(),
      'attachments': db.getOperationalAttachmentStats(),
      'outbox': db.getOutboxStatusCounts(),
      'websocket': wsRelay.stats(),
      'calls': callsModule.metrics(),
      'rate_limiter': rateLimiter.stats(),
      'push_provider': {
        'configured': outboxWorker.pushProviderConfigured,
        'available': outboxWorker.pushProviderAvailable,
      },
      'turn': _turnStatus(),
      'slo_targets': sloTargets,
      'alert_thresholds': alertThresholds,
    });
  }

  Response _supportDiagnostic(Request request) {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    _auditAdminRead(request, 'ADMIN_SUPPORT_DIAGNOSTIC_EXPORT');

    final outbox = db.getOutboxStatusCounts();
    final failedOrDlq = outbox['FAILED']! + outbox['DLQ']!;
    final dbOk = db.quickCheckOk();
    final turn = _turnStatus();
    return _json({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'redaction': {
        'tokens': 'excluded',
        'turn_secret': 'excluded',
        'raw_sdp': 'excluded',
        'raw_ice_candidates': 'excluded',
        'private_ips': 'redacted',
      },
      'readiness': {
        'api_ready': dbOk,
        'websocket_ready': true,
        'push_ready':
            outboxWorker.pushProviderConfigured &&
            outboxWorker.pushProviderAvailable &&
            failedOrDlq == 0,
        'turn_ready': turn['configured'],
      },
      'configuration': {
        'schema_version': db.schemaVersion,
        'capabilities': RemoteCapabilityRegistry.current().toJson(),
        'turn_url_count': turn['url_count'],
        'push_provider_configured': outboxWorker.pushProviderConfigured,
      },
      'metrics': {
        'calls': callsModule.metrics(),
        'websocket': wsRelay.stats(),
        'outbox': outbox,
        'rate_limiter': rateLimiter.stats(),
      },
      'alerts': alertThresholds,
    });
  }

  bool _isAdmin(Request request) {
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
      return false;
    }
    return true;
  }

  void _auditAdminRead(Request request, String action) {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    db.logAudit(
      auth?['account_id'] as String?,
      auth?['device_id'] as String?,
      action,
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
  }

  Map<String, dynamic> _turnStatus() {
    final urls = CallsModule.resolveTurnUrls(turnUrl);
    return {
      'configured': turnSecret.trim().isNotEmpty && urls.isNotEmpty,
      'url_count': urls.length,
      'live_reachability': 'not_checked',
    };
  }

  Response _json(Map<String, dynamic> body, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
