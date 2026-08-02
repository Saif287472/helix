import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/federation.dart';
import 'package:helix_remote_backend/src/invite_codes.dart';
import 'package:helix_remote_backend/src/modules/calls.dart';
import 'package:helix_remote_backend/src/outbox_worker.dart';
import 'package:helix_remote_backend/src/rate_limiter.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
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
    this.logFilePath,
    this.serverIdentity,
    this.federationClient,
    this.federationDomain,
    this.federationDirectoryUrl = '',
    this.publicBaseUrl = '',
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final BackendDatabase db;
  final RateLimiter rateLimiter;
  final WebSocketRelay wsRelay;
  final OutboxWorker outboxWorker;
  final CallsModule callsModule;
  final Set<String> adminAccountIds;
  final String turnSecret;
  final String turnUrl;
  final String? logFilePath;
  final ServerIdentity? serverIdentity;
  final FederationClient? federationClient;
  final String? federationDomain;
  final String federationDirectoryUrl;
  final String publicBaseUrl;
  final DateTime Function() _now;

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
    router.get('/config', _config);
    router.post('/backup', _backup);
    router.get('/users', _users);
    router.post('/users/<accountId>/suspend', _suspendUser);
    router.post('/users/<accountId>/unsuspend', _unsuspendUser);
    router.post('/users/<accountId>/delete', _deleteUser);
    router.get('/logs', _logs);
    router.post('/invites', _createInvite);
    router.get('/invites', _listInvites);
    router.post('/invites/<inviteId>/cancel', _cancelInvite);
    router.get('/federation', _federationStatus);
    router.post('/federation/worldwide', _setWorldwideMode);
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

  Response _config(Request request) {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    _auditAdminRead(request, 'ADMIN_CONFIG_READ');

    final serverId = db.getServerConfig('server_id') ?? 'unknown';
    final serverPubKey = db.getServerConfig('server_public_key') ?? 'unknown';

    return _json({
      'server_id': serverId,
      'server_public_key': serverPubKey,
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
      'federation': _federationConfig(),
    });
  }

  Response _federationStatus(Request request) {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    _auditAdminRead(request, 'ADMIN_FEDERATION_STATUS_READ');
    return _json(_federationConfig());
  }

  Future<Response> _setWorldwideMode(Request request) async {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final enabled = body['enabled'] as bool?;
    if (enabled == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing enabled flag'}),
        headers: {'Content-Type': 'application/json'},
      );
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
      return Response.badRequest(
        body: jsonEncode({
          'error': 'domain, address, and directory_url are required',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (serverIdentity == null || federationClient == null) {
      return _json({
        'error': 'Server identity is not initialized',
      }, status: 503);
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

  Response _backup(Request request) {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    _auditAdminRead(request, 'ADMIN_BACKUP_TRIGGER');

    try {
      final dbDir = Directory('backups');
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }
      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final backupPath = 'backups/backup_$timestamp.db';

      db.vacuumInto(backupPath);

      return _json({
        'status': 'success',
        'backup_file': backupPath,
        'timestamp': timestamp,
      });
    } catch (e) {
      return _json({'error': 'Failed to create backup: $e'}, status: 500);
    }
  }

  Response _users(Request request) {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    _auditAdminRead(request, 'ADMIN_USERS_LIST_READ');

    final params = request.url.queryParameters;
    final limit = int.tryParse(params['limit'] ?? '') ?? 50;
    final offset = int.tryParse(params['offset'] ?? '') ?? 0;

    if (limit <= 0 || offset < 0) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid limit or offset'}),
      );
    }

    final users = db.getAllUsersDetailedPaginated(limit: limit, offset: offset);
    return _json({'users': users, 'limit': limit, 'offset': offset});
  }

  Future<Response> _suspendUser(Request request, String accountId) async {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    if (!db.accountExists(accountId)) {
      return _json({'error': 'Account not found'}, status: 404);
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
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    if (!db.accountExists(accountId)) {
      return _json({'error': 'Account not found'}, status: 404);
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
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    if (!db.accountExists(accountId)) {
      return _json({'error': 'Account not found'}, status: 404);
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

  Future<Response> _cancelInvite(Request request, String inviteId) async {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    final cancelled = db.cancelInviteCredential(inviteId: inviteId);
    if (!cancelled) {
      return _json({
        'error': 'Invite not found, already redeemed, or already cancelled',
      }, status: 409);
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
      return _json({'error': 'Admin privileges required'}, status: 403);
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
      'shareable_url': '$publicBaseUrl/join?invite=$code',
      'expires_at': expiresAt,
    });
  }

  Response _listInvites(Request request) {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    _auditAdminRead(request, 'ADMIN_INVITES_LIST_READ');

    final params = request.url.queryParameters;
    final limit = int.tryParse(params['limit'] ?? '') ?? 50;
    final offset = int.tryParse(params['offset'] ?? '') ?? 0;
    if (limit <= 0 || offset < 0) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid limit or offset'}),
      );
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

  Response _logs(Request request) {
    if (!_isAdmin(request)) {
      return _json({'error': 'Admin privileges required'}, status: 403);
    }
    _auditAdminRead(request, 'ADMIN_LOGS_READ');

    if (logFilePath == null || logFilePath!.isEmpty) {
      return _json({
        'message':
            'Log file not configured. Please set HELIX_REMOTE_LOG_FILE to enable log tailing.',
        'logs': [],
      });
    }

    final file = File(logFilePath!);
    if (!file.existsSync()) {
      return _json({
        'message': 'Log file configured but does not exist at: $logFilePath',
        'logs': [],
      });
    }

    try {
      final lines = file.readAsLinesSync();
      final tail = lines.length > 100
          ? lines.sublist(lines.length - 100)
          : lines;
      return _json({'logs': tail});
    } catch (e) {
      return _json({'error': 'Failed to read logs: $e'}, status: 500);
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
