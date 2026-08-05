import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/federation.dart';
import 'package:helix_remote_backend/src/invite_codes.dart';
import 'package:helix_remote_backend/src/modules/calls.dart';
import 'package:helix_remote_backend/src/outbox_worker.dart';
import 'package:helix_remote_backend/src/rate_limiter.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:helix_remote_backend/src/server_log.dart';
import 'package:helix_remote_backend/src/server_name.dart';
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
    this.logSink,
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

  /// In-process capture of the server's console output. Null when the
  /// server was constructed without one (most tests, and the CLI tools),
  /// in which case `/logs` falls back to the configured file alone.
  final ServerLogSink? logSink;
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
    return withAppErrorHandling(router.call);
  }

  Response _serverInfo(Request request) {
    return _json({
      // Empty means the admin never named this server; clients fall back
      // to showing the hostname they connected to.
      'server_name': db.getServerConfig(serverNameConfigKey) ?? '',
    });
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
    router.get('/logs', _logs);
    router.post('/invites', _createInvite);
    router.get('/invites', _listInvites);
    router.post('/invites/<inviteId>/cancel', _cancelInvite);
    router.get('/federation', _federationStatus);
    router.post('/federation/worldwide', _setWorldwideMode);
    return withAppErrorHandling(router.call);
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
      throw AppError.forbidden('Admin privileges required');
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
      'max_server_name_length': maxServerNameLength,
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

  Response _backup(Request request) {
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
    return _json({'users': users, 'limit': limit, 'offset': offset});
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
