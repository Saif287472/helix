import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_backend/src/admin_password.dart';
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/constant_time.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/federation.dart';
import 'package:helix_remote_backend/src/feature_flags.dart';
import 'package:helix_remote_backend/src/helix_code.dart';
import 'package:helix_remote_backend/src/invite_codes.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';
import 'package:helix_remote_backend/src/jwt.dart';
import 'package:helix_remote_backend/src/modules/attachments.dart';
import 'package:helix_remote_backend/src/modules/calls.dart';
import 'package:helix_remote_backend/src/outbox_worker.dart';
import 'package:helix_remote_backend/src/rate_limiter.dart';
import 'package:helix_remote_backend/src/reserved_identifiers.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:helix_remote_backend/src/server_log.dart';
import 'package:helix_remote_backend/src/server_name.dart';
import 'package:helix_remote_backend/src/websocket.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class OperabilityModule {
  OperabilityModule({
    required this.db,
    required this.rateLimiter,
    required this.wsRelay,
    required this.outboxWorker,
    required this.callsModule,
    this.attachmentsModule,
    this.smsProvider,
    required this.turnSecret,
    required this.turnUrl,
    this.logFilePath,
    this.logSink,
    this.serverIdentity,
    this.federationClient,
    this.federationDomain,
    this.federationDirectoryUrl = '',
    this.publicBaseUrl = '',
    this.getNeedsAdminSetup,
    this.jwt,
    this.adminPasswordOverride,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final BackendDatabase db;
  final bool Function()? getNeedsAdminSetup;
  final RateLimiter rateLimiter;
  final WebSocketRelay wsRelay;
  final OutboxWorker outboxWorker;
  final CallsModule callsModule;

  /// Optional so tests that only exercise health/ops routes need not build
  /// an attachments module; `/server/info` omits the limits when absent.
  final AttachmentsModule? attachmentsModule;

  /// Optional so tests need not construct an SMS provider. When absent,
  /// `/health` reports SMS as not configured.
  final SmsProvider? smsProvider;
  final String turnSecret;
  final String turnUrl;
  final String? logFilePath;

  /// In-process capture of the server's console output. Null when the
  /// server was constructed without one (most tests, and the CLI tools),
  /// in which case `/logs` falls back to the configured file alone.
  final ServerLogSink? logSink;
  final ServerIdentity? serverIdentity;
  final FederationClient? federationClient;
  final String? federationDomain;
  final String federationDirectoryUrl;
  final String publicBaseUrl;
  final JwtHelper? jwt;
  final String? adminPasswordOverride;
  final DateTime Function() _now;
  late final FeatureFlagService _featureFlags = FeatureFlagService(db);

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

  Handler get healthRouter {
    final router = Router();
    router.get('/live', _live);
    router.get('/ready', _ready);
    return withAppErrorHandling(router.call);
  }

  /// Server-level facts a logged-in client may show its user.
  ///
  /// Deliberately authenticated, unlike the health probes: it adds no new
  /// unauthenticated surface, and every caller that needs it already has a
  /// session. Someone still joining gets the same name from
  /// `/accounts/invite/lookup`, which is gated by holding a valid invite.
  Handler get serverRouter {
    final router = Router();
    router.get('/info', _serverInfo);
    router.get('/tos', _termsOfService);
    return withAppErrorHandling(router.call);
  }

  /// The current legal documents are public because a user must be able to
  /// read and accept them before creating an account. The text is versioned
  /// in the shared domain package so the client and registration audit record
  /// cannot silently disagree about which document was presented.
  Response _termsOfService(Request request) {
    return _json({
      'version': HelixLegalDocuments.termsVersion,
      'effective_date': HelixLegalDocuments.effectiveDate,
      'terms_title': HelixLegalDocuments.termsTitle,
      'terms': HelixLegalDocuments.termsOfService,
      'privacy_version': HelixLegalDocuments.privacyVersion,
      'privacy_title': HelixLegalDocuments.privacyTitle,
      'privacy_policy': HelixLegalDocuments.privacyPolicy,
    });
  }

  Response _serverInfo(Request request) {
    final configuredName = db.getServerConfig(serverNameConfigKey);
    final serverId =
        serverIdentity?.serverId ?? db.getServerConfig('server_id') ?? '';
    final effectiveName =
        (configuredName != null && configuredName.trim().isNotEmpty)
        ? configuredName.trim()
        : defaultServerName(serverId);

    return _json({
      'server_name': effectiveName,
      // Attachment limits live here so an operator can change them in .env
      // without an app release, and so the client's error message can never
      // disagree with what this server will actually accept. Both are
      // ciphertext byte counts - the same thing the upload endpoint
      // measures.
      'max_attachment_bytes': attachmentsModule?.maxFileSize,
      'account_quota_bytes': attachmentsModule?.maxQuota,
    });
  }

  /// Self-hosted crash sink (MED-4).
  ///
  /// Authenticated by the standard middleware — this route is not on the
  /// public skip list, so a report is always attributable to a device and
  /// cannot be used by an unauthenticated caller to flood the log.
  ///
  /// Deliberately *not* mounted under `/ops`: those routes are admin-gated,
  /// and the reporter here is an ordinary client posting about itself.
  Handler get telemetryRouter {
    final router = Router();
    router.post('/crash', _reportCrash);
    return withAppErrorHandling(router.call);
  }

  /// Counters behind `/ops/metrics`. In-process and reset by a restart, which
  /// is honest for a rate rather than a total: an operator reads this to see
  /// whether crashes are arriving now, and the redacted detail lands in the
  /// server log, which is durable.
  int _crashReportsAccepted = 0;
  int _crashReportsRejected = 0;
  DateTime? _lastCrashReportAt;

  Future<Response> _reportCrash(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    final accountId = auth?['account_id'] as String?;
    final deviceId = auth?['device_id'] as String?;
    if (accountId == null || deviceId == null) {
      throw AppError.unauthorized('Authentication required');
    }

    // The operator's opt-in. Every report below is counted as rejected when
    // the flag is off, so `/ops/metrics` shows a client that is still trying
    // to report to a server that has the sink disabled - which is a
    // misconfiguration worth seeing rather than a silent 200.
    if (!_featureFlags.isEnabled('crash_reporting_upload')) {
      _crashReportsRejected++;
      throw AppError.forbidden('Crash reporting is disabled on this server.');
    }

    // Per-device, so one device in a crash loop cannot drown out the rest.
    if (!rateLimiter.isAllowed('telemetry_crash:$deviceId')) {
      _crashReportsRejected++;
      throw AppError.tooManyRequests('Crash report rate exceeded');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      _crashReportsRejected++;
      throw AppError.badRequest('Invalid JSON body');
    }

    final name = body['name'];
    final fields = body['fields'];
    if (name is! String || name.isEmpty || fields is! Map) {
      _crashReportsRejected++;
      throw AppError.badRequest('name and fields are required');
    }

    // The client redacts before sending; this truncates before storing. Two
    // independent bounds because the server cannot verify the first one
    // happened, and an un-truncated stack from a hostile client would be an
    // unbounded write into the operator's log.
    final summary = fields.entries
        .take(_crashFieldLimit)
        .map((entry) => '${entry.key}=${_truncate('${entry.value}')}')
        .join(' | ');

    _crashReportsAccepted++;
    _lastCrashReportAt = _now().toUtc();
    logServerWarning(
      'telemetry_crash account=$accountId device=$deviceId '
      'event=${_truncate(name)} $summary',
    );

    return _json({'accepted': true});
  }

  static const _crashFieldLimit = 8;
  static const _crashValueLimit = 512;

  String _truncate(String value) {
    final flattened = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flattened.length <= _crashValueLimit
        ? flattened
        : '${flattened.substring(0, _crashValueLimit)}…';
  }

  Handler get opsRouter {
    final router = Router();
    router.get('/metrics', _metrics);
    router.get('/support-diagnostic', _supportDiagnostic);
    router.get('/config', _config);
    router.post('/config/server-name', _setServerName);
    router.post('/backup', _backup);
    router.get('/users', _users);
    router.post('/users/<accountId>/suspend', _suspendUser);
    router.post('/users/<accountId>/unsuspend', _unsuspendUser);
    router.post('/users/<accountId>/delete', _deleteUser);
    router.post('/users/<accountId>/block', _blockUser);
    router.post('/users/<accountId>/recovery-code', _generateUserRecoveryCode);
    router.post('/users/<accountId>/devices/<deviceId>/revoke', _revokeDevice);
    router.get('/logs', _logs);
    router.get('/logs/stream', _logsStream);
    router.post('/invites', _createInvite);
    router.get('/invites', _listInvites);
    router.post('/invites/<inviteId>/cancel', _cancelInvite);
    router.get('/reports', _adminReports);
    router.post('/reports/<reportId>/resolve', _resolveReport);
    router.post('/reports/<reportId>/dismiss', _dismissReport);
    router.get('/audit', _adminAuditLogs);
    router.get('/federation', _federationStatus);
    router.post('/federation/worldwide', _setWorldwideMode);
    router.get('/feature-flags', _featureFlagsSnapshot);
    router.post('/feature-flags/<name>', _setFeatureFlag);
    router.get('/setup-status', _setupStatus);
    router.post('/setup-admin-password', _setupAdminPassword);
    router.post('/maintenance', _setMaintenanceMode);
    router.post('/admin-pin', _changeAdminPin);
    router.post('/purge', _purge);
    return withAppErrorHandling(router.call);
  }

  Handler get adminRouter {
    final router = Router();
    router.post('/auth/login', _adminLogin);
    router.get('/metrics', _metrics);
    router.get('/support-diagnostic', _supportDiagnostic);
    router.get('/config', _config);
    router.post('/config/server-name', _setServerName);
    router.post('/backup', _backup);
    router.get('/users', _users);
    router.post('/users/<accountId>/suspend', _suspendUser);
    router.post('/users/<accountId>/unsuspend', _unsuspendUser);
    router.post('/users/<accountId>/delete', _deleteUser);
    router.post('/users/<accountId>/block', _blockUser);
    router.post('/users/<accountId>/recovery-code', _generateUserRecoveryCode);
    router.post('/users/<accountId>/devices/<deviceId>/revoke', _revokeDevice);
    router.get('/logs', _logs);
    router.get('/logs/stream', _logsStream);
    router.get('/invites', _listInvites);
    router.post('/invites', _createInvite);
    router.post('/invites/<inviteId>/cancel', _cancelInvite);
    router.get('/reports', _adminReports);
    router.post('/reports/<reportId>/resolve', _resolveReport);
    router.post('/reports/<reportId>/dismiss', _dismissReport);
    router.get('/audit', _adminAuditLogs);
    router.get('/federation', _federationStatus);
    router.post('/federation/worldwide', _setWorldwideMode);
    router.get('/feature-flags', _featureFlagsSnapshot);
    router.post('/feature-flags/<name>', _setFeatureFlag);
    router.get('/setup-status', _setupStatus);
    router.post('/setup-admin-password', _setupAdminPassword);
    router.post('/maintenance', _setMaintenanceMode);
    router.post('/admin-pin', _changeAdminPin);
    router.post('/purge', _purge);
    return withAppErrorHandling(router.call);
  }

  bool get _needsAdminSetup => getNeedsAdminSetup?.call() ?? false;

  Response _setupStatus(Request request) {
    return _json({
      'needs_setup': _needsAdminSetup,
      'server_id':
          serverIdentity?.serverId ?? db.getServerConfig('server_id') ?? '',
    });
  }

  Future<Response> _setupAdminPassword(Request request) async {
    if (!_needsAdminSetup) {
      throw AppError.conflict('Admin password has already been configured.');
    }
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      throw AppError.badRequest('Invalid JSON body');
    }
    final password = body['password'] as String?;
    if (password == null || password.trim().length < 6) {
      throw AppError.badRequest('Password must be at least 6 characters long');
    }
    final salt = generatePasswordSalt();
    final hash = hashAdminPassword(password.trim(), salt);
    db.setServerConfig('admin_password_salt', salt);
    db.setServerConfig('admin_password_hash', hash);
    logServerWarning('Admin password configured via first-time setup prompt.');
    return _json({'success': true});
  }

  /// Turns maintenance mode on or off.
  ///
  /// Enforced by a middleware above every module (see
  /// `BackendServer._maintenanceGuardMiddleware`), which exempts `/ops` and
  /// `/admin` so this route stays reachable while the mode is on.
  Future<Response> _setMaintenanceMode(Request request) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    final body = await _readJsonObject(request);
    final enabled = body['enabled'];
    if (enabled is! bool) {
      throw AppError.badRequest('Expected {"enabled": boolean}');
    }

    db.setServerConfig('maintenance_mode', enabled.toString());
    _auditAdminWrite(
      request,
      enabled ? 'ADMIN_MAINTENANCE_ENABLED' : 'ADMIN_MAINTENANCE_DISABLED',
    );
    return _json({'maintenance_mode': enabled});
  }

  /// Replaces the master admin password.
  ///
  /// Requires the current one, so a console left open on a shared machine
  /// cannot be used to take the server over. The salt is regenerated rather
  /// than reused, and neither value is echoed back.
  Future<Response> _changeAdminPin(Request request) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    final body = await _readJsonObject(request);
    final current = body['current_password'];
    final next = body['new_password'];
    if (current is! String || next is! String) {
      throw AppError.badRequest(
        'current_password and new_password are required',
      );
    }
    if (next.trim().length < 6) {
      throw AppError.badRequest(
        'New password must be at least 6 characters long',
      );
    }
    if (!_isValidAdminToken(current)) {
      // Counted, so a guessing attempt shows up in the audit trail instead of
      // looking like a success that silently did nothing.
      _auditAdminWrite(request, 'ADMIN_PIN_CHANGE_REJECTED');
      throw AppError.unauthorized('The current password is incorrect');
    }

    final salt = generatePasswordSalt();
    db.setServerConfig('admin_password_salt', salt);
    db.setServerConfig(
      'admin_password_hash',
      hashAdminPassword(next.trim(), salt),
    );
    _auditAdminWrite(request, 'ADMIN_PIN_CHANGED');
    return _json({'success': true});
  }

  /// Deletes data that is genuinely safe to discard.
  ///
  /// Deliberately conservative: never accounts, devices, messages, contacts,
  /// or audit history. Only tables that actually carry an age column are
  /// touched - `attachment_references` is keyed by (file_id, message_id) with
  /// no timestamp, so there is no honest way to age it out here, and guessing
  /// would be deleting rows an operator may still be able to resolve.
  ///
  /// Reports per-table counts so the console can show a real result rather
  /// than an unquantified "done".
  Future<Response> _purge(Request request) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    final now = _now().millisecondsSinceEpoch;
    const dayMs = 24 * 60 * 60 * 1000;

    final removed = <String, int>{
      'outbox_dead_letter': db.rawUpdate(
        "DELETE FROM outbox WHERE status = 'DLQ' AND created_at < ?;",
        [now - 7 * dayMs],
      ),
      'outbox_failed': db.rawUpdate(
        "DELETE FROM outbox WHERE status = 'FAILED' AND created_at < ?;",
        [now - 7 * dayMs],
      ),
      'refresh_tokens': db.rawUpdate(
        'DELETE FROM refresh_tokens WHERE expires_at < ?;',
        [now],
      ),
    };

    final total = removed.values.fold<int>(0, (a, b) => a + b);
    _auditAdminWrite(request, 'ADMIN_PURGE_RUN removed=$total');
    return _json({'removed': removed, 'total': total});
  }

  Future<Map<String, dynamic>> _readJsonObject(Request request) async {
    final decoded = jsonDecode(await request.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw AppError.badRequest('Expected a JSON object body');
    }
    return decoded;
  }

  Response _live(Request request) {
    return _json({
      'status': 'ok',
      'service': 'helix_remote_backend',
      'time': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Whether the WebSocket relay is healthy enough to keep serving clients.
  ///
  /// Shared by `/health/ready` and `/ops/support-diagnostic` so the support
  /// bundle an operator attaches to a ticket can never contradict (or
  /// over-report on) what the readiness probe actually said.
  bool _isWebsocketReady() {
    final websocketRejectLimit =
        alertThresholds['websocket_reconnect_rejections_5m'] as int;
    return (wsRelay.stats()['rejected_reconnects'] as int? ?? 0) <
        websocketRejectLimit;
  }

  Response _ready(Request request) {
    final dbOk = db.quickCheckOk();
    final outbox = db.getOutboxStatusCounts();
    final failedOrDlq = outbox['FAILED']! + outbox['DLQ']!;
    final turnUrls = CallsModule.resolveTurnUrls(turnUrl);
    final turnConfigured = turnSecret.trim().isNotEmpty && turnUrls.isNotEmpty;
    final apiReady = dbOk;
    final websocketReady = _isWebsocketReady();
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
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_OPERABILITY_METRICS_READ');

    return _json({
      'service': 'helix_remote_backend',
      'schema_version': db.schemaVersion,
      'capabilities': RemoteCapabilityRegistry.current().toJson(),
      'database_quick_check_ok': db.quickCheckOk(),
      'database_bytes': db.getDatabaseSizeBytes(),
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
      // Whether an SMS gateway is wired up at all, and which one. This says
      // nothing about whether the credential is *valid* - BulkSMSBD reports a
      // rejected key with HTTP 200, so configured == true can still mean
      // every signup fails. It is the difference between "SMS was never set
      // up" and "SMS is set up but broken", which is otherwise
      // indistinguishable until a user hits it.
      'sms_provider': {
        'configured': smsProvider?.isConfigured ?? false,
        'name': smsProvider?.displayName ?? 'None',
      },
      'turn': _turnStatus(),
      'telemetry': {
        'crash_reports_accepted': _crashReportsAccepted,
        'crash_reports_rejected': _crashReportsRejected,
        'last_crash_report_at': _lastCrashReportAt?.toIso8601String(),
      },
      'slo_targets': sloTargets,
      'alert_thresholds': alertThresholds,
    });
  }

  Response _supportDiagnostic(Request request) {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
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
        'websocket_ready': _isWebsocketReady(),
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
        // Whether an SMS provider is wired up at all. This says nothing
        // about whether the credential is *valid* - BulkSMSBD reports a
        // rejected key with HTTP 200, so a true here can still mean every
        // signup fails. It is the difference between "SMS was never set up"
        // and "SMS is set up but broken", which is otherwise indistinguishable
        // until a user hits it.
        'sms_provider_configured': smsProvider?.isConfigured ?? false,
        'sms_provider_name': smsProvider?.displayName ?? 'None',
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
    if (accountId != null && auth?['is_admin'] == true) {
      return true;
    }
    final authHeader = request.headers['authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      final token = authHeader.substring(7);
      if (_isValidAdminToken(token)) {
        return true;
      }
    }
    db.logAudit(
      accountId,
      deviceId,
      'ADMIN_ACCESS_DENIED',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return false;
  }

  bool _isValidAdminToken(String? token) {
    if (token == null || token.isEmpty) return false;

    if (adminPasswordOverride != null && adminPasswordOverride!.isNotEmpty) {
      if (constantTimeStringEqual(token, adminPasswordOverride!)) return true;
    }

    final dbHash = db.getServerConfig('admin_password_hash');
    final dbSalt = db.getServerConfig('admin_password_salt');
    if (dbHash != null && dbSalt != null && dbHash.isNotEmpty) {
      if (verifyAdminPassword(token, dbSalt, dbHash)) return true;
    }

    if (jwt != null) {
      final claims = jwt!.verifyToken(token, expect: ExpectedTokenType.admin);
      if (claims != null && claims['is_admin'] == true) return true;
    }

    return false;
  }

  Future<Response> _adminLogin(Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      throw AppError.badRequest('Invalid JSON body');
    }

    final password = body['password'] as String?;
    if (password == null || password.isEmpty) {
      throw AppError.badRequest('Password is required');
    }

    if (!_isValidAdminToken(password)) {
      throw AppError.unauthorized('Invalid master admin password');
    }

    final serverId =
        serverIdentity?.serverId ?? db.getServerConfig('server_id') ?? '';
    final configuredName = db.getServerConfig(serverNameConfigKey);
    final serverName =
        (configuredName != null && configuredName.trim().isNotEmpty)
        ? configuredName.trim()
        : defaultServerName(serverId);

    String token = password;
    if (jwt != null) {
      token = jwt!.generateToken({
        'account_id': kAdminTokenAccountId,
        'device_id': 'admin_session',
        'is_admin': true,
        'admin_scopes': const ['ops:*', 'admin:*'],
        'token_type': 'admin',
      }, const Duration(days: 7));
    }

    db.logAudit(
      kAdminTokenAccountId,
      'admin_session',
      'ADMIN_LOGIN_SUCCESS',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );

    return _json({
      'token': token,
      'expires_in': 604800,
      'server_name': serverName,
      'server_id': serverId,
      'status': 'authenticated',
    });
  }

  /// Paginated user list for the admin console's Users screen.
  ///
  /// Serves both `/api/v1/ops/users` and `/api/v1/admin/users` from one
  /// implementation. They used to be separate handlers, and only the
  /// `/admin/` one attached the `devices` list - which meant the console,
  /// which calls `/ops/users`, received a `device_count` and a null device
  /// list, so no device was ever shown or revocable. The count and the list
  /// must come from the same call, so there is now only one handler.
  Response _users(Request request) {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_USERS_LIST_READ');

    final params = request.url.queryParameters;
    final limit = int.tryParse(params['limit'] ?? '') ?? 50;
    final offset = int.tryParse(params['offset'] ?? '') ?? 0;

    if (limit <= 0 || offset < 0) {
      throw AppError.badRequest('Invalid limit or offset');
    }

    final users = db.getAllUsersDetailedPaginated(limit: limit, offset: offset);
    final usersWithDevices = users.map((user) {
      final accountId = user['account_id'] as String;
      final devices = db.getDevices(accountId);
      return {...user, 'devices': devices};
    }).toList();

    return _json({'users': usersWithDevices, 'limit': limit, 'offset': offset});
  }

  Future<Response> _revokeDevice(
    Request request,
    String accountId,
    String deviceId,
  ) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    if (!db.accountExists(accountId)) {
      throw AppError.notFound('Account not found');
    }
    db.revokeDevice(accountId, deviceId);
    db.logAudit(
      (request.context['auth'] as Map<String, dynamic>?)?['account_id']
          as String?,
      (request.context['auth'] as Map<String, dynamic>?)?['device_id']
          as String?,
      'ADMIN_DEVICE_REVOKED account=$accountId device=$deviceId',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return _json({
      'success': true,
      'account_id': accountId,
      'device_id': deviceId,
    });
  }

  Response _adminReports(Request request) {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_REPORTS_LIST_READ');

    final params = request.url.queryParameters;
    final limit = int.tryParse(params['limit'] ?? '') ?? 50;
    final offset = int.tryParse(params['offset'] ?? '') ?? 0;
    if (limit <= 0 || offset < 0) {
      throw AppError.badRequest('Invalid limit or offset');
    }

    final reports = db.getReports(limit: limit, offset: offset);
    return _json({
      'reports': reports,
      'limit': limit,
      'offset': offset,
    });
  }

  Future<Response> _resolveReport(Request request, String reportId) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    db.updateReportStatus(reportId, 'RESOLVED');
    db.logAudit(
      (request.context['auth'] as Map<String, dynamic>?)?['account_id']
          as String?,
      (request.context['auth'] as Map<String, dynamic>?)?['device_id']
          as String?,
      'ADMIN_REPORT_RESOLVED report=$reportId',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return _json({
      'success': true,
      'report_id': reportId,
      'status': 'RESOLVED',
    });
  }

  Future<Response> _dismissReport(Request request, String reportId) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    db.updateReportStatus(reportId, 'DISMISSED');
    db.logAudit(
      (request.context['auth'] as Map<String, dynamic>?)?['account_id']
          as String?,
      (request.context['auth'] as Map<String, dynamic>?)?['device_id']
          as String?,
      'ADMIN_REPORT_DISMISSED report=$reportId',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return _json({
      'success': true,
      'report_id': reportId,
      'status': 'DISMISSED',
    });
  }

  Response _adminAuditLogs(Request request) {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    final includeRead = request.url.queryParameters['include_read'] == 'true';
    final accountId = request.url.queryParameters['account_id'];
    var logs = db.getAuditLogs(accountId: accountId);
    if (!includeRead) {
      logs = logs.where((l) {
        final act = (l['action'] as String? ?? '').toUpperCase();
        return !act.endsWith('_READ') &&
            !act.endsWith('_POLL') &&
            !act.contains('METRICS_READ') &&
            !act.contains('AUDIT_LOGS_READ');
      }).toList();
    }
    return _json({'logs': logs});
  }

  FutureOr<Response> _logsStream(Request request) {
    final queryToken = request.url.queryParameters['token'];
    final authHeader = request.headers['authorization'];
    final headerToken = (authHeader != null && authHeader.startsWith('Bearer '))
        ? authHeader.substring(7)
        : null;
    final token = queryToken ?? headerToken;
    if (!_isValidAdminToken(token)) {
      throw AppError.forbidden('Admin authorization required');
    }

    final wsHandler = webSocketHandler((
      WebSocketChannel socket,
      String? protocol,
    ) {
      final initialLogs = logSink?.tail(50) ?? [];
      for (final line in initialLogs) {
        socket.sink.add(jsonEncode({'type': 'log', 'line': line}));
      }
      final sub = logSink?.onLine.listen((line) {
        try {
          socket.sink.add(jsonEncode({'type': 'log', 'line': line}));
        } catch (_) {}
      });
      socket.stream.listen(
        (msg) {},
        onDone: () => sub?.cancel(),
        onError: (_) => sub?.cancel(),
      );
    });
    return wsHandler(request);
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

  Response _config(Request request) {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_CONFIG_READ');

    final serverId = db.getServerConfig('server_id') ?? 'unknown';
    final serverPubKey = db.getServerConfig('server_public_key') ?? 'unknown';

    return _json({
      'server_id': serverId,
      'server_public_key': serverPubKey,
      // Empty when the admin has not named the server; the admin console
      // shows the placeholder and clients fall back to the hostname.
      'server_name': db.getServerConfig(serverNameConfigKey) ?? '',
      'default_server_name': defaultServerName(serverId),
      'max_server_name_length': maxServerNameLength,
      'public_base_url': publicBaseUrl,
      'port': Platform.environment['HELIX_REMOTE_PORT'] ?? '8080',
      'host': Platform.environment['HELIX_REMOTE_HOST'] ?? '127.0.0.1',
      'dev_mode': Platform.environment['HELIX_REMOTE_DEV_MODE'] == '1',
      'db_path':
          Platform.environment['HELIX_REMOTE_DB_PATH'] ?? 'remote_backend.db',
      'attachments_dir':
          Platform.environment['HELIX_REMOTE_ATTACHMENTS_DIR'] ?? 'not_set',
      'push_configured': outboxWorker.pushProviderConfigured,
      'turn_configured':
          turnSecret.trim().isNotEmpty &&
          CallsModule.resolveTurnUrls(turnUrl).isNotEmpty,
      // Read from storage rather than held in memory, so the switch reflects
      // reality after a restart instead of resetting itself silently.
      'maintenance_mode': db.getServerConfig('maintenance_mode') == 'true',
      'federation': _federationConfig(),
    });
  }

  Response _featureFlagsSnapshot(Request request) {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_FEATURE_FLAGS_READ');
    return _json({'flags': _featureFlags.snapshot()});
  }

  Future<Response> _setFeatureFlag(Request request, String name) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    final body = jsonDecode(await request.readAsString());
    if (body is! Map || body['enabled'] is! bool) {
      throw AppError.badRequest('Expected {"enabled": boolean}');
    }
    try {
      _featureFlags.set(name, body['enabled'] as bool);
    } on ArgumentError {
      throw AppError.notFound('Unknown feature flag');
    }
    _auditAdminRead(request, 'ADMIN_FEATURE_FLAG_UPDATED:$name');
    return _json({'name': name, 'enabled': _featureFlags.isEnabled(name)});
  }

  /// Sets (or clears) the server's display name.
  ///
  /// Takes effect immediately for everyone: the name is read per-request
  /// by the join-time invite lookup and the public server-info endpoint,
  /// so there is nothing to restart and no cache to invalidate.
  Future<Response> _setServerName(Request request) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      throw AppError.badRequest('Invalid JSON body');
    }

    final raw = body['server_name'];
    if (raw != null && raw is! String) {
      throw AppError.badRequest('server_name must be a string');
    }

    final result = validateServerName(raw as String?);
    switch (result) {
      case ServerNameInvalid(:final error):
        throw AppError.badRequest(error);
      case ServerNameCleared():
        db.deleteServerConfig(serverNameConfigKey);
        _auditAdminWrite(request, 'ADMIN_SERVER_NAME_CLEARED');
        return _json({'server_name': ''});
      case ServerNameValid(:final value):
        db.setServerConfig(serverNameConfigKey, value);
        _auditAdminWrite(request, 'ADMIN_SERVER_NAME_SET');
        return _json({'server_name': value});
    }
  }

  void _auditAdminWrite(Request request, String action) {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    db.logAudit(
      auth?['account_id'] as String?,
      auth?['device_id'] as String?,
      action,
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
  }

  Response _federationStatus(Request request) {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_FEDERATION_STATUS_READ');
    return _json(_federationConfig());
  }

  Future<Response> _setWorldwideMode(Request request) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final enabled = body['enabled'] as bool?;
    if (enabled == null) {
      throw AppError.badRequest('Missing enabled flag');
    }

    if (!enabled) {
      db.setServerConfig('federation_worldwide_mode', 'false');
      db.logAudit(
        (request.context['auth'] as Map<String, dynamic>?)?['account_id']
            as String?,
        (request.context['auth'] as Map<String, dynamic>?)?['device_id']
            as String?,
        'ADMIN_FEDERATION_WORLDWIDE_DISABLED',
        request.context['client_ip'] as String?,
        request.headers['user-agent'],
      );
      return _json(_federationConfig());
    }

    final domain = (body['domain'] as String? ?? federationDomain ?? '').trim();
    final address = (body['address'] as String? ?? publicBaseUrl).trim();
    final directory =
        (body['directory_url'] as String? ?? federationDirectoryUrl).trim();
    if (domain.isEmpty || address.isEmpty || directory.isEmpty) {
      throw AppError.badRequest(
        'domain, address, and directory_url are required',
      );
    }
    if (serverIdentity == null || federationClient == null) {
      throw AppError.serviceUnavailable('Server identity is not initialized');
    }

    db.setServerConfig('federation_worldwide_mode', 'true');
    db.setServerConfig('federation_domain', domain);
    db.setServerConfig('federation_public_base_url', address);
    db.setServerConfig('federation_directory_url', directory);

    final users = db
        .getAllUsersPaginated(limit: 10000, offset: 0)
        .map((user) => '${user['account_id']}@$domain')
        .toList();
    final registrationClient = directory == federationDirectoryUrl
        ? federationClient!
        : FederationClient(
            db: db,
            identity: serverIdentity!,
            directoryUrl: directory,
          );
    final registration = await registrationClient.registerDirectory(
      domain: domain,
      address: address,
      users: users,
    );
    db.logAudit(
      (request.context['auth'] as Map<String, dynamic>?)?['account_id']
          as String?,
      (request.context['auth'] as Map<String, dynamic>?)?['device_id']
          as String?,
      'ADMIN_FEDERATION_WORLDWIDE_ENABLED',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return _json({
      ..._federationConfig(),
      'directory_registration': registration,
    });
  }

  Future<Response> _backup(Request request) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_BACKUP_TRIGGER');

    try {
      final dbDir = Directory('backups');
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }
      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final backupPath = 'backups/backup_$timestamp.db';

      await Future<void>.delayed(Duration.zero);
      db.vacuumInto(backupPath);

      return _json({
        'status': 'success',
        'backup_file': backupPath,
        'timestamp': timestamp,
      });
    } catch (e) {
      throw AppError(
        'Failed to create backup: $e',
        statusCode: 500,
        code: RemoteErrorCode.internalError,
      );
    }
  }

  Future<Response> _suspendUser(Request request, String accountId) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    if (!db.accountExists(accountId)) {
      throw AppError.notFound('Account not found');
    }
    db.setAccountStatus(accountId, 'SUSPENDED');
    db.logAudit(
      (request.context['auth'] as Map<String, dynamic>?)?['account_id']
          as String?,
      (request.context['auth'] as Map<String, dynamic>?)?['device_id']
          as String?,
      'ADMIN_USER_SUSPENDED',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return _json({'account_id': accountId, 'status': 'SUSPENDED'});
  }

  Future<Response> _unsuspendUser(Request request, String accountId) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    if (!db.accountExists(accountId)) {
      throw AppError.notFound('Account not found');
    }
    db.setAccountStatus(accountId, 'ACTIVE');
    db.logAudit(
      (request.context['auth'] as Map<String, dynamic>?)?['account_id']
          as String?,
      (request.context['auth'] as Map<String, dynamic>?)?['device_id']
          as String?,
      'ADMIN_USER_UNSUSPENDED',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return _json({'account_id': accountId, 'status': 'ACTIVE'});
  }

  /// Permanently and irreversibly deletes an account and all of its data
  /// (messages, devices, prekeys, contacts referencing it, etc. - see
  /// BackendDatabase.deleteAccountData). Unlike the self-service
  /// `/accounts/delete` endpoint, this is admin-triggered: no confirmation
  /// phrase from the account's own token, since the admin isn't the
  /// account owner and can't produce one.
  Future<Response> _deleteUser(Request request, String accountId) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    if (!db.accountExists(accountId)) {
      throw AppError.notFound('Account not found');
    }
    await db.deleteAccountData(accountId);
    db.logAudit(
      (request.context['auth'] as Map<String, dynamic>?)?['account_id']
          as String?,
      (request.context['auth'] as Map<String, dynamic>?)?['device_id']
          as String?,
      'ADMIN_USER_DELETED',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return _json({'account_id': accountId, 'deleted': true});
  }

  /// Permanently bans this account's phone number from ever registering
  /// again, then deletes the account the same way `_deleteUser` does -
  /// unlike a plain delete, re-registering that number afterward is
  /// refused (see AuthRegistrationHandlers._registerHandler). Distinct
  /// action from delete: a plain delete leaves the phone number free to
  /// register a fresh account.
  Future<Response> _blockUser(Request request, String accountId) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    final account = db.getAccount(accountId);
    if (account == null) {
      throw AppError.notFound('Account not found');
    }
    final adminAccountId =
        (request.context['auth'] as Map<String, dynamic>?)?['account_id']
            as String?;
    final phoneHash = account['phone_hash'] as String?;
    if (phoneHash != null && phoneHash.isNotEmpty) {
      db.blockPhoneHash(phoneHash, blockedByAccountId: adminAccountId);
    }
    await db.deleteAccountData(accountId);
    db.logAudit(
      adminAccountId,
      (request.context['auth'] as Map<String, dynamic>?)?['device_id']
          as String?,
      'ADMIN_USER_BLOCKED',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return _json({'account_id': accountId, 'blocked': true, 'deleted': true});
  }

  /// Generates a single-use, 48-hour recovery code for an existing user account.
  /// Conceals the server's raw domain and port inside an opaque HLX-REC-... token.
  Future<Response> _generateUserRecoveryCode(
    Request request,
    String accountId,
  ) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    final account = db.getAccount(accountId);
    if (account == null) {
      throw AppError.notFound('Account not found');
    }
    if (account['status'] == 'BLOCKED') {
      throw AppError.forbidden(
        'Cannot generate recovery code for a blocked user',
      );
    }

    final recoveryCode = 'rec_${generatePasswordSalt()}';
    final salt = generatePasswordSalt();
    final codeHash = hashAdminPassword(recoveryCode, salt);
    final now = _now().millisecondsSinceEpoch;
    final expiresAt = now + const Duration(hours: 48).inMilliseconds;
    final recoveryId = generateUuidV4();

    db.createRecoveryCode(
      recoveryId: recoveryId,
      accountId: accountId,
      codeHash: codeHash,
      salt: salt,
      createdAt: now,
      expiresAt: expiresAt,
    );

    _auditAdminWrite(request, 'ADMIN_USER_RECOVERY_ISSUED');

    final opaqueCode = encodeHelixRecoveryCode(
      serverUrl: publicBaseUrl,
      accountId: accountId,
      recoveryCode: recoveryCode,
    );

    return _json({
      'account_id': accountId,
      'recovery_code': recoveryCode,
      'opaque_code': opaqueCode,
      'code': opaqueCode,
      'expires_at': expiresAt,
    });
  }

  Future<Response> _cancelInvite(Request request, String inviteId) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    final cancelled = db.cancelInviteCredential(inviteId: inviteId);
    if (!cancelled) {
      throw AppError.conflict(
        'Invite not found, already redeemed, or already cancelled',
      );
    }
    db.logAudit(
      (request.context['auth'] as Map<String, dynamic>?)?['account_id']
          as String?,
      (request.context['auth'] as Map<String, dynamic>?)?['device_id']
          as String?,
      'ADMIN_INVITE_CANCELLED',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );
    return _json({'invite_id': inviteId, 'status': 'CANCELLED'});
  }

  static const _inviteValidity = Duration(days: 7);

  Future<Response> _createInvite(Request request) async {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_INVITE_CREATED');

    final now = _now().millisecondsSinceEpoch;
    final inviteId = generateInviteId();
    final code = generateInviteCode();
    final expiresAt = now + _inviteValidity.inMilliseconds;

    db.createInviteCredential(
      inviteId: inviteId,
      inviteCodeHash: hashInviteCode(code),
      serverAddress: publicBaseUrl,
      issuerType: 'ADMIN',
      issuerLabel: 'admin',
      createdAt: now,
      expiresAt: expiresAt,
    );

    return _json({
      'invite_id': inviteId,
      'invite_code': code,
      'shareable_code': encodeHelixInviteCode(
        serverUrl: publicBaseUrl,
        inviteCode: code,
      ),
      'shareable_url': '$publicBaseUrl/join?invite=$code',
      'expires_at': expiresAt,
    });
  }

  Response _listInvites(Request request) {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_INVITES_LIST_READ');

    final params = request.url.queryParameters;
    final limit = int.tryParse(params['limit'] ?? '') ?? 50;
    final offset = int.tryParse(params['offset'] ?? '') ?? 0;
    if (limit <= 0 || offset < 0) {
      throw AppError.badRequest('Invalid limit or offset');
    }

    final now = _now().millisecondsSinceEpoch;
    final invites = db
        .getInviteCredentialsPaginated(limit: limit, offset: offset)
        .map(
          (invite) => {
            'invite_id': invite['invite_id'],
            'issuer_type': invite['issuer_type'],
            'issuer_label': invite['issuer_label'],
            // Never expose invite_code_hash - it's internal-only.
            'status': _displayInviteStatus(invite, now),
            'created_at': invite['created_at'],
            'expires_at': invite['expires_at'],
            'redeemed_at': invite['redeemed_at'],
            'redeemed_by_account_id': invite['redeemed_by_account_id'],
          },
        )
        .toList();

    return _json({'invites': invites, 'limit': limit, 'offset': offset});
  }

  /// `invite_credentials.status` only ever stores 'PENDING'/'REDEEMED'/
  /// 'CANCELLED' - expiry is derived at read time rather than written back,
  /// so there's no sweep job needed to keep it accurate.
  String _displayInviteStatus(Map<String, dynamic> invite, int now) {
    if (invite['status'] == 'PENDING' && (invite['expires_at'] as int) < now) {
      return 'EXPIRED';
    }
    return invite['status'] as String;
  }

  /// Largest number of lines a single `/logs` call will return. The admin
  /// console asks for 100 by default; the ceiling just stops a hand-crafted
  /// `?limit=` from trying to serialize an entire log file into one JSON
  /// response.
  static const _maxLogLines = 1000;

  /// How much of the tail of the log file to read. Only the last chunk is
  /// pulled off disk rather than the whole file - a long-running server's
  /// log grows without bound, and reading all of it to keep 100 lines
  /// blocked the isolate for as long as the read took.
  static const _logTailBytes = 256 * 1024;

  /// Serves recent server console output for the admin console's Logs
  /// screen.
  ///
  /// Sources, in order of preference:
  ///  1. the on-disk log file, when [ServerLogSink] is actively writing it -
  ///     it holds history from before the current process started;
  ///  2. the sink's in-memory ring buffer, which always exists and needs no
  ///     configuration at all;
  ///  3. the configured file on its own, for deployments that point
  ///     HELIX_REMOTE_LOG_FILE at a log another process writes.
  ///
  /// Anything that leaves the list empty is explained in `message` rather
  /// than returned as a bare empty array - the admin console shows that
  /// text, so an operator can tell "nothing has been logged yet" apart from
  /// "this server can't write its log file".
  Response _logs(Request request) {
    if (!_isAdmin(request)) {
      throw AppError.forbidden('Admin privileges required');
    }
    _auditAdminRead(request, 'ADMIN_LOGS_READ');

    final requestedLimit =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    if (requestedLimit <= 0) {
      throw AppError.badRequest('Invalid limit');
    }
    final limit = requestedLimit.clamp(1, _maxLogLines);

    final sink = logSink;
    final path = logFilePath;
    final hasFile = path != null && path.isNotEmpty && File(path).existsSync();

    if (sink != null && sink.fileActive && hasFile) {
      try {
        return _json({
          'logs': _readFileTail(path, limit),
          'source': 'file',
          'file_path': path,
        });
      } catch (e) {
        // Fall through to the in-memory buffer: it holds this process's
        // output regardless of what went wrong on disk.
      }
    }

    if (sink != null && sink.bufferedLineCount > 0) {
      return _json({
        'logs': sink.tail(limit),
        'source': 'memory',
        if (sink.fileError != null) 'message': sink.fileError,
      });
    }

    if (hasFile) {
      try {
        return _json({
          'logs': _readFileTail(path, limit),
          'source': 'file',
          'file_path': path,
        });
      } catch (e) {
        throw AppError(
          'Failed to read logs: $e',
          statusCode: 500,
          code: RemoteErrorCode.internalError,
        );
      }
    }

    return _json({
      'logs': <String>[],
      'source': 'none',
      'message': _emptyLogExplanation(sink, path),
    });
  }

  String _emptyLogExplanation(ServerLogSink? sink, String? path) {
    if (sink == null) {
      return 'This server was started without a log sink, so console output '
          'is not being captured. Restart it using bin/server.dart to enable '
          'the Logs screen.';
    }
    if (sink.fileError != null) return sink.fileError!;
    if (path != null && path.isNotEmpty) {
      return 'No output has been logged yet. Lines will appear here as the '
          'server handles requests, and are also being written to $path.';
    }
    return 'No output has been logged yet. Lines will appear here as the '
        'server handles requests. Set HELIX_REMOTE_LOG_FILE to also keep '
        'them across restarts.';
  }

  /// Reads at most the last [_logTailBytes] of [path] and returns its final
  /// [limit] lines.
  List<String> _readFileTail(String path, int limit) {
    final file = File(path);
    final handle = file.openSync();
    try {
      final length = handle.lengthSync();
      final start = length > _logTailBytes ? length - _logTailBytes : 0;
      handle.setPositionSync(start);
      final bytes = handle.readSync(length - start);
      var text = utf8.decode(bytes, allowMalformed: true);
      // A non-zero start almost certainly lands mid-line; drop that
      // fragment so the first row isn't a truncated half-message.
      if (start > 0) {
        final newline = text.indexOf('\n');
        text = newline == -1 ? '' : text.substring(newline + 1);
      }
      final lines = const LineSplitter()
          .convert(text)
          .where((line) => line.trim().isNotEmpty)
          .toList();
      if (lines.length <= limit) return lines;
      return lines.sublist(lines.length - limit);
    } finally {
      handle.closeSync();
    }
  }

  Map<String, dynamic> _federationConfig() {
    final domain =
        db.getServerConfig('federation_domain') ?? federationDomain ?? '';
    final directory =
        db.getServerConfig('federation_directory_url') ??
        federationDirectoryUrl;
    final address =
        db.getServerConfig('federation_public_base_url') ?? publicBaseUrl;
    return {
      'worldwide_mode':
          db.getServerConfig('federation_worldwide_mode') == 'true',
      'domain': domain,
      'directory_url': directory,
      'public_base_url': address,
      'server_identity_ready': serverIdentity != null,
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
