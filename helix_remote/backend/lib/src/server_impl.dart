import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/jwt.dart';
import 'package:helix_remote_backend/src/outbox_worker.dart';
import 'package:helix_remote_backend/src/push_provider.dart';
import 'package:helix_remote_backend/src/constant_time.dart';
import 'package:helix_remote_backend/src/rate_limiter.dart';
import 'package:helix_remote_backend/src/reserved_identifiers.dart';
import 'package:helix_remote_backend/src/server_log.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';
import 'package:helix_remote_backend/src/websocket.dart';
import 'package:helix_remote_backend/src/federation.dart';
import 'package:helix_remote_backend/src/federation_verifier.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:helix_remote_backend/src/modules/auth.dart';
import 'package:helix_remote_backend/src/modules/prekeys.dart';
import 'package:helix_remote_backend/src/modules/contacts.dart';
import 'package:helix_remote_backend/src/modules/messaging.dart';
import 'package:helix_remote_backend/src/modules/backups.dart';
import 'package:helix_remote_backend/src/modules/attachments.dart';
import 'package:helix_remote_backend/src/modules/calls.dart';
import 'package:helix_remote_backend/src/modules/groups.dart';
import 'package:helix_remote_backend/src/modules/group_calls.dart';
import 'package:helix_remote_backend/src/admin_password.dart';
import 'package:helix_remote_backend/src/modules/operability.dart';
import 'package:helix_remote_backend/src/modules/privacy_compliance.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/src/modules/s2s_module.dart';

class BackendServer {
  final BackendDatabase db;
  final JwtHelper jwt;
  final RateLimiter rateLimiter;
  final WebSocketRelay wsRelay;
  final OutboxWorker outboxWorker;
  final PushProvider pushProvider;
  final Directory? attachmentsStorageDir;
  final int? maxAttachmentBytes;
  final int? accountQuotaBytes;

  /// How long a completed attachment with no message references is kept
  /// before the storage sweep removes it. Null uses the module default.
  final Duration? attachmentRetention;
  final String turnSecret;
  final String turnUrl;
  final SmsProvider smsProvider;
  final Set<String> trustedProxyAddresses;
  final DateTime Function() now;
  final String? logFilePath;
  final String? adminPasswordOverride;
  String? get adminTokenOverride => adminPasswordOverride;
  ServerIdentity? serverIdentity;

  bool get hasDatabaseAdminPassword {
    final dbHash = db.getServerConfig('admin_password_hash');
    return dbHash != null && dbHash.isNotEmpty;
  }

  bool get needsAdminSetup {
    final hasEnv = adminPasswordOverride != null && adminPasswordOverride!.isNotEmpty;
    if (hasEnv) return false;
    return !hasDatabaseAdminPassword;
  }
  final String? federationDomain;
  final String federationDirectoryUrl;
  final String publicBaseUrl;
  final bool globalInstanceMode;
  final String serverAudience;
  HttpServer? _httpServer;
  HttpServer? get httpServer => _httpServer;

  /// Held so [start]/[stop] can run its storage sweep. Built in
  /// [getHandler]; null until then.
  AttachmentsModule? _attachmentsModule;

  BackendServer._({
    required this.db,
    required this.jwt,
    required this.rateLimiter,
    required this.wsRelay,
    required this.outboxWorker,
    this.pushProvider = const NoopPushProvider(),
    this.attachmentsStorageDir,
    this.maxAttachmentBytes,
    this.accountQuotaBytes,
    this.attachmentRetention,
    this.turnSecret = '',
    this.turnUrl = '',
    this.smsProvider = const NoopSmsProvider(),
    this.trustedProxyAddresses = const {'127.0.0.1', '::1'},
    required this.now,
    this.logFilePath,
    this.adminPasswordOverride,
    this.serverIdentity,
    this.federationDomain,
    required this.federationDirectoryUrl,
    required this.publicBaseUrl,
    this.globalInstanceMode = false,
    this.serverAudience = '',
  });

  factory BackendServer.create({
    required Database sqliteDb,
    required String jwtSecret,
    Map<String, String>? jwtKeyRing,
    String? jwtSigningKeyId,
    double rateLimitMaxTokens = 100.0,
    double rateLimitRefillRate = 10.0,
    Directory? attachmentsStorageDir,
    int? maxAttachmentBytes,
    int? accountQuotaBytes,
    Duration? attachmentRetention,
    String turnSecret = '',
    String turnUrl = '',
    SmsProvider? smsProvider,
    Set<String> trustedProxyAddresses = const {'127.0.0.1', '::1'},
    PushProvider? pushProvider,
    bool pushProviderAvailable = true,
    int wsReconnectsPerMinute = 30,
    DateTime Function()? now,
    String? logFilePath,
    String? adminPasswordOverride,
    String? adminTokenOverride,
    ServerIdentity? serverIdentity,
    String? federationDomain,
    String? federationDirectoryUrl,
    String? publicBaseUrl,
    bool? globalInstanceMode,
    String? serverAudience,
  }) {
    final db = BackendDatabase(sqliteDb);
    final jwt = jwtKeyRing == null
        ? JwtHelper(jwtSecret)
        : JwtHelper.keyRing(
            jwtKeyRing,
            keyId: jwtSigningKeyId ?? jwtKeyRing.keys.first,
          );
    final rateLimiter = RateLimiter(
      maxTokens: rateLimitMaxTokens,
      refillRatePerSecond: rateLimitRefillRate,
      store: SqliteRateLimitStore(sqliteDb),
    );
    final wsRelay = WebSocketRelay(
      db,
      jwt,
      maxReconnectsPerMinute: wsReconnectsPerMinute,
    );
    final outboxWorker = OutboxWorker(
      db,
      pushProvider: pushProvider,
      pushProviderAvailable: pushProviderAvailable,
    );

    return BackendServer._(
      db: db,
      jwt: jwt,
      rateLimiter: rateLimiter,
      wsRelay: wsRelay,
      outboxWorker: outboxWorker,
      pushProvider: pushProvider ?? const NoopPushProvider(),
      attachmentsStorageDir: attachmentsStorageDir,
      maxAttachmentBytes: maxAttachmentBytes,
      accountQuotaBytes: accountQuotaBytes,
      attachmentRetention: attachmentRetention,
      turnSecret: turnSecret,
      turnUrl: turnUrl,
      smsProvider: smsProvider ?? const NoopSmsProvider(),
      trustedProxyAddresses: trustedProxyAddresses,
      now: now ?? DateTime.now,
      logFilePath: logFilePath ?? Platform.environment['HELIX_REMOTE_LOG_FILE'],
      adminPasswordOverride:
          adminPasswordOverride ??
          adminTokenOverride ??
          Platform.environment['HELIX_REMOTE_ADMIN_PASSWORD'] ??
          Platform.environment['HELIX_REMOTE_ADMIN_TOKEN'],
      serverIdentity: serverIdentity,
      federationDomain:
          federationDomain ??
          Platform.environment['HELIX_REMOTE_FEDERATION_DOMAIN'],
      federationDirectoryUrl:
          federationDirectoryUrl ??
          Platform.environment['HELIX_REMOTE_FEDERATION_DIRECTORY_URL'] ??
          '',
      publicBaseUrl:
          publicBaseUrl ??
          Platform.environment['HELIX_REMOTE_PUBLIC_BASE_URL'] ??
          '',
      globalInstanceMode:
          globalInstanceMode ??
          (Platform.environment['HELIX_REMOTE_GLOBAL_INSTANCE_MODE'] == 'true'),
      serverAudience:
          serverAudience ??
          Platform.environment['HELIX_REMOTE_SERVER_AUDIENCE'] ??
          _audienceFromBaseUrl(
            publicBaseUrl ??
                Platform.environment['HELIX_REMOTE_PUBLIC_BASE_URL'] ??
                '',
          ),
    );
  }

  /// Derive a stable audience (host[:port]) from the configured public base
  /// URL so signed challenges never depend on the client-sent Host header.
  static String _audienceFromBaseUrl(String baseUrl) {
    if (baseUrl.isEmpty) return '';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return '';
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  Handler getHandler() {
    final router = Router();

    final authModule = AuthModule(
      db,
      jwt,
      notifyDevice: wsRelay.sendToDevice,
      now: now,
      configuredAudience: serverAudience.isEmpty ? null : serverAudience,
      publicBaseUrl: publicBaseUrl,
      globalInstanceMode: globalInstanceMode,
      smsProvider: smsProvider,
    );
    final federationClient = serverIdentity == null
        ? null
        : FederationClient(
            db: db,
            identity: serverIdentity!,
            directoryUrl: federationDirectoryUrl,
          );
    final prekeysModule = PrekeysModule(
      db,
      federationClient: federationClient,
      localDomain: federationDomain,
    );
    final contactsModule = ContactsModule(
      db,
      notifyDevice: wsRelay.sendToDevice,
    );
    final backupsModule = BackupsModule(db);
    final attachmentsModule = AttachmentsModule(
      db,
      storageDir: attachmentsStorageDir,
      maxFileSize: maxAttachmentBytes,
      maxQuota: accountQuotaBytes,
      unreferencedRetention: attachmentRetention,
    );
    _attachmentsModule = attachmentsModule;
    final messagingModule = MessagingModule(
      db,
      wsRelay,
      onMessageDeleted: attachmentsModule.cleanAttachmentReferences,
      federationClient: federationClient,
      localDomain: federationDomain,
    );
    final callsModule = CallsModule(
      db,
      wsRelay,
      turnSecret: turnSecret,
      turnUrl: turnUrl,
      pushProvider: pushProvider,
      federationClient: federationClient,
      localDomain: federationDomain,
    );
    final groupsModule = GroupsModule(
      db,
      wsRelay,
      federationClient: federationClient,
      localDomain: federationDomain,
    );
    final groupCallsModule = GroupCallsModule(db, wsRelay);
    final privacyComplianceModule = PrivacyComplianceModule(db);
    final operabilityModule = OperabilityModule(
      db: db,
      rateLimiter: rateLimiter,
      wsRelay: wsRelay,
      outboxWorker: outboxWorker,
      callsModule: callsModule,
      attachmentsModule: attachmentsModule,
      turnSecret: turnSecret,
      turnUrl: turnUrl,
      logFilePath: logFilePath,
      logSink: activeServerLog,
      serverIdentity: serverIdentity,
      federationClient: federationClient,
      federationDomain: federationDomain,
      federationDirectoryUrl: federationDirectoryUrl,
      publicBaseUrl: publicBaseUrl,
      getNeedsAdminSetup: () => needsAdminSetup,
      jwt: jwt,
      adminPasswordOverride: adminPasswordOverride,
      now: now,
    );

    // Map modules
    router.mount('/api/v1/health', operabilityModule.healthRouter.call);
    router.mount('/api/v1/ops', operabilityModule.opsRouter.call);
    router.mount('/api/v1/admin', operabilityModule.adminRouter.call);
    router.mount('/api/v1/server', operabilityModule.serverRouter.call);
    router.mount('/api/v1/telemetry', operabilityModule.telemetryRouter.call);
    router.mount('/api/v1/accounts', authModule.router.call);
    router.mount('/api/v1/devices', authModule.router.call);
    router.mount('/api/v1/prekeys', prekeysModule.router.call);
    router.mount('/api/v1/contacts', contactsModule.router.call);
    router.mount('/api/v1/messages', messagingModule.router.call);
    router.mount('/api/v1/backups', backupsModule.router.call);
    router.mount('/api/v1/attachments', attachmentsModule.router.call);
    router.mount('/api/v1/calls', callsModule.router.call);
    router.mount('/api/v1/groups', groupsModule.router.call);
    router.mount('/api/v1/group-calls', groupCallsModule.router.call);
    router.mount('/api/v1/privacy', privacyComplianceModule.privacyRouter.call);
    router.mount('/api/v1/account', privacyComplianceModule.accountRouter.call);

    final s2sModule = S2SModule(
      db,
      wsRelay,
      localDomain: federationDomain,
      groupsModule: groupsModule,
      callsModule: callsModule,
    );
    outboxWorker.federationClient = federationClient;
    router.mount('/api/v1/s2s', s2sModule.router.call);

    // WebSocket route
    router.get('/api/v1/ws', wsRelay.handleUpgrade);

    final pipeline = const Pipeline()
        .addMiddleware(_correlationMiddleware())
        .addMiddleware(_requestLogMiddleware())
        .addMiddleware(_errorHandlingMiddleware())
        .addMiddleware(_rateLimitMiddleware())
        .addMiddleware(_s2sAuthMiddleware())
        .addMiddleware(_authMiddleware())
        .addHandler(router.call);

    return pipeline;
  }

  /// Carries a client correlation id through middleware and returns it to the
  /// caller. A malformed value is replaced, so log search keys stay bounded
  /// and never become a header-injection or sensitive-data channel.
  Middleware _correlationMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final supplied = request.headers['x-correlation-id'];
        final correlationId =
            supplied != null &&
                RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(supplied)
            ? supplied
            : _newCorrelationId();
        // Published as a zone value as well as in the request context, so
        // every log line emitted while handling this request carries the same
        // id the caller gets back in the response header — without threading
        // a parameter through every module. That is the propagation the audit
        // recorded as missing: the ids were generated and went nowhere.
        final response = await runWithCorrelationId(
          correlationId,
          () => innerHandler(
            request.change(context: {'correlation_id': correlationId}),
          ),
        );
        return response.change(headers: {'x-correlation-id': correlationId});
      };
    };
  }

  String _newCorrelationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> start(String host, int port) async {
    final handler = getHandler();
    _httpServer = await shelf_io.serve(handler, host, port);
    outboxWorker.start();
    // Reclaims abandoned uploads and attachments nothing references any
    // more. Started here rather than in getHandler() so tests that only
    // build a handler do not get a live timer.
    _attachmentsModule?.startMaintenance();
  }

  Future<void> stop() async {
    outboxWorker.stop();
    _attachmentsModule?.stopMaintenance();
    rateLimiter.dispose();
    await _httpServer?.close(force: true);
    db.close();
  }

  /// Records one line per request into the log sink, so the admin console's
  /// Logs screen shows live server activity rather than only the startup
  /// banner.
  ///
  /// Deliberately logs the path and not the query string: invite codes and
  /// pairing codes travel as query parameters, and those lines are both
  /// served over the admin API and written to disk.
  Middleware _requestLogMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final sink = activeServerLog;
        if (sink == null) return innerHandler(request);
        final watch = Stopwatch()..start();
        try {
          final response = await innerHandler(request);
          watch.stop();

          // Filter out routine successful (2xx/3xx) GET data fetches to keep the console log focused on real events and anomalies
          final isRoutineGetFetch = request.method == 'GET' && response.statusCode < 400;

          if (!isRoutineGetFetch) {
            final path = request.url.path;
            final line =
                '${request.method} /$path '
                '${response.statusCode} ${watch.elapsedMilliseconds}ms '
                'correlation=${request.context['correlation_id'] ?? 'none'}';
            if (response.statusCode >= 500) {
              sink.error(line);
            } else if (response.statusCode >= 400) {
              sink.warn(line);
            } else {
              sink.info(line);
            }
          }
          return response;
        } catch (e) {
          watch.stop();
          if (e.runtimeType.toString() == 'HijackedException' || e.toString().contains('hijacked')) {
            // Standard Shelf control flow for WebSockets and SSE streams; not an actual error.
            rethrow;
          }
          sink.error(
            '${request.method} /${request.url.path} threw after '
            '${watch.elapsedMilliseconds}ms: $e',
          );
          rethrow;
        }
      };
    };
  }

  /// Converts a thrown [AppError] (or any other uncaught exception) into a
  /// normalized JSON response, once, instead of every route handler
  /// building its own `Response(..., jsonEncode({'error': ...}))`.
  ///
  /// Placed *inside* [_requestLogMiddleware] deliberately: that middleware
  /// only logs a normal status-coded request line when it sees a returned
  /// [Response], and logs a noisier "threw after Xms" error line when it
  /// sees an exception. Converting here means a routine 403/404 AppError
  /// still shows up in logs as a plain request line instead of manufacturing
  /// an alarming "threw" entry for an expected client error.
  Middleware _errorHandlingMiddleware() {
    return (Handler innerHandler) => withAppErrorHandling(innerHandler);
  }

  Middleware _rateLimitMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final connInfo = request.context['shelf.io.connection_info'];
        String ip = '127.0.0.1';
        if (connInfo is HttpConnectionInfo) {
          ip = _resolveClientIp(
            immediatePeerIp: connInfo.remoteAddress.address,
            forwardedFor: request.headers['x-forwarded-for'],
            realIp: request.headers['x-real-ip'],
          );
        }

        final updatedRequest = request.change(context: {'client_ip': ip});

        if (!rateLimiter.isAllowed(ip)) {
          return Response(
            429,
            body: jsonEncode({
              'error': 'Too many requests. Please try again later.',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        return innerHandler(updatedRequest);
      };
    };
  }

  String _resolveClientIp({
    required String immediatePeerIp,
    String? forwardedFor,
    String? realIp,
  }) {
    if (!trustedProxyAddresses.contains(immediatePeerIp)) {
      return immediatePeerIp;
    }
    // When behind a trusted single proxy (e.g. Caddy), X-Real-IP is authoritative.
    // If using X-Forwarded-For, the rightmost entry appended by our trusted proxy
    // is the genuine client IP, not the attacker-controlled first element.
    final candidate = realIp?.trim().isNotEmpty == true
        ? realIp!.trim()
        : (forwardedFor != null && forwardedFor.trim().isNotEmpty
            ? forwardedFor.split(',').last.trim()
            : null);
    if (candidate == null || candidate.isEmpty) {
      return immediatePeerIp;
    }
    final parsed = InternetAddress.tryParse(candidate);
    if (parsed == null) return immediatePeerIp;
    return parsed.address;
  }

  Map<String, dynamic>? _adminClaimsForToken(String token) {
    // Priority 1: .env password override
    if (adminPasswordOverride != null && adminPasswordOverride!.isNotEmpty) {
      return constantTimeStringEqual(token, adminPasswordOverride!)
          ? {
              'account_id': kAdminTokenAccountId,
              'device_id': 'admin_break_glass',
              'is_admin': true,
              'admin_scopes': const ['ops:*'],
              'admin_credential': 'environment_password',
            }
          : null;
    }

    // Priority 2: Database password
    final dbHash = db.getServerConfig('admin_password_hash');
    final dbSalt = db.getServerConfig('admin_password_salt');
    if (dbHash != null && dbSalt != null && dbHash.isNotEmpty) {
      if (verifyAdminPassword(token, dbSalt, dbHash)) {
        return {
          'account_id': kAdminTokenAccountId,
          'device_id': 'admin_device',
          'is_admin': true,
          'admin_scopes': const ['ops:*'],
          'admin_credential': 'database_password',
        };
      }
    }

    // Priority 3: Signed admin JWT
    final adminJwt = jwt.verifyToken(token, expect: ExpectedTokenType.admin);
    if (adminJwt != null && adminJwt['is_admin'] == true) {
      return {
        'account_id': kAdminTokenAccountId,
        'device_id': adminJwt['device_id'] as String? ?? 'admin_jwt_session',
        'is_admin': true,
        'admin_scopes': const ['ops:*', 'admin:*'],
        'admin_credential': 'admin_jwt',
      };
    }

    return null;
  }

  Middleware _authMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final path = request.url.path;

        // Skip auth check for public and S2S routes
        if (path.endsWith('/accounts/register') ||
            path.endsWith('/accounts/challenge') ||
            path.endsWith('/accounts/login') ||
            path.endsWith('/accounts/refresh') ||
            path.endsWith('/accounts/phone/otp/request') ||
            path.endsWith('/accounts/invite/lookup') ||
            path.endsWith('/accounts/invite/auto-issue') ||
            path.endsWith('/accounts/recovery/redeem') ||
            path.endsWith('/contacts/discovery-salt') ||
            path.endsWith('/devices/link/request-new') ||
            path.endsWith('/devices/link/complete-new') ||
            path.endsWith('/health/live') ||
            path.endsWith('/health/ready') ||
            path.contains('/s2s/') ||
            path.endsWith('/ops/setup-status') ||
            path.endsWith('/ops/setup-admin-password') ||
            path.endsWith('/admin/auth/login') ||
            path.endsWith('/admin/logs/stream') ||
            path.endsWith('/ops/logs/stream') ||
            path.endsWith('/ws')) {
          return innerHandler(request);
        }

        final authHeader = request.headers['Authorization'];
        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return Response(
            401,
            body: jsonEncode({
              'error': 'Unauthorized: Missing or invalid token',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final token = authHeader.substring(7);

        // Check for Admin API token first. This is the operator's break-glass
        // credential, so it carries the admin capability directly rather than
        // resolving one from an account row - there is no account behind it.
        final adminClaims = _adminClaimsForToken(token);
        if (adminClaims != null) {
          final updatedRequest = request.change(context: {'auth': adminClaims});
          return innerHandler(updatedRequest);
        }

        // Access tokens only. Accepting a refresh token here made the 1-hour
        // access token meaningless and let a stolen 7-day refresh token skip
        // /accounts/refresh entirely - which is the only path that detects
        // reuse and revokes the device's sessions.
        // 401 for authentication failures, 403 for authorization ones.
        //
        // This used to answer 403 for an expired token, which forced the
        // client to treat 403 as "refresh and retry". But `AppError.forbidden`
        // is also how ~40 handlers report ordinary permission denials ("only
        // the host can kick participants"), so every legitimate denial spent a
        // refresh-token rotation and re-sent a request that could never
        // succeed. Splitting the codes is what lets the client stop.
        final claims = jwt.verifyToken(token, expect: ExpectedTokenType.access);
        if (claims == null) {
          return Response(
            401,
            body: jsonEncode({
              'error': 'Unauthorized: Invalid or expired token',
              'code': 'token_invalid',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final accountId = claims['account_id'] as String?;
        final deviceId = claims['device_id'] as String?;
        if (accountId == null ||
            deviceId == null ||
            !db.isDeviceActive(accountId, deviceId)) {
          // 401, not 403: a revoked device means the credential no longer
          // identifies anyone, so the right client response is to re-
          // authenticate rather than to treat it as a permission problem.
          return Response(
            401,
            body: jsonEncode({
              'error': 'Unauthorized: Device inactive',
              'code': 'device_inactive',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
        if (db.isAccountSuspended(accountId)) {
          // Stays 403: the credential is valid and the caller is who they say
          // they are - they are simply not allowed. Refreshing would not help.
          return Response(
            403,
            body: jsonEncode({
              'error': 'Forbidden: Account suspended',
              'code': 'account_suspended',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Admin is a stored capability on the account row, resolved here so
        // every downstream handler reads one authoritative flag. It is
        // deliberately *not* derived from the account id: treating the string
        // 'admin' as the credential meant whoever registered that id first
        // became the operator.
        final authorizedClaims = Map<String, dynamic>.from(claims)
          ..['is_admin'] = db.isAccountAdmin(accountId);

        final updatedRequest = request.change(
          context: {'auth': authorizedClaims},
        );
        return innerHandler(updatedRequest);
      };
    };
  }

  Middleware _s2sAuthMiddleware() {
    final ed25519 = crypto.Ed25519();
    final processedSignatures = <String, int>{};
    final domainVerifier = FederationDomainVerifier();
    return (Handler innerHandler) {
      return (Request request) async {
        final path = request.url.path;

        if (!path.contains('/s2s/')) {
          return innerHandler(request);
        }

        final senderId = request.headers['X-Helix-S2S-Server-Id'];
        final pubKeyB64 = request.headers['X-Helix-S2S-Public-Key'];
        final timestampStr = request.headers['X-Helix-S2S-Timestamp'];
        final signatureB64 = request.headers['X-Helix-S2S-Signature'];

        if (senderId == null ||
            pubKeyB64 == null ||
            timestampStr == null ||
            signatureB64 == null) {
          return Response(
            401,
            body: jsonEncode({
              'error': 'Unauthorized: Missing S2S auth headers',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final timestamp = int.tryParse(timestampStr);
        if (timestamp == null) {
          return Response(
            400,
            body: jsonEncode({'error': 'Bad Request: Invalid S2S timestamp'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        if ((now - timestamp).abs() > 300000) {
          return Response(
            401,
            body: jsonEncode({'error': 'Unauthorized: S2S signature expired'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Replay defense: check if this signature was already processed within the window
        processedSignatures.removeWhere((_, exp) => now > exp);
        if (processedSignatures.containsKey(signatureB64)) {
          return Response(
            401,
            body: jsonEncode({'error': 'Unauthorized: S2S request replayed'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        processedSignatures[signatureB64] = now + 300000;

        final bodyStr = await request.readAsString();
        final bodyHash = crypto_pkg.sha256
            .convert(utf8.encode(bodyStr))
            .toString();

        final signedPayload =
            '$senderId|$timestamp|${request.requestedUri.path}|$bodyHash';
        final payloadBytes = utf8.encode(signedPayload);

        try {
          final pubBytes = base64Decode(pubKeyB64);
          final sigBytes = base64Decode(signatureB64);

          final knownServer = db.getFederationServerById(senderId);
          if (knownServer != null && knownServer['public_key'] != pubKeyB64) {
            return Response(
              401,
              body: jsonEncode({'error': 'Unauthorized: S2S key mismatch'}),
              headers: {'Content-Type': 'application/json'},
            );
          }

          final publicKey = crypto.SimplePublicKey(
            pubBytes,
            type: crypto.KeyPairType.ed25519,
          );
          final signature = crypto.Signature(sigBytes, publicKey: publicKey);

          final isValid = await ed25519.verify(
            payloadBytes,
            signature: signature,
          );
          if (!isValid) {
            return Response(
              401,
              body: jsonEncode({
                'error': 'Unauthorized: Invalid S2S signature',
              }),
              headers: {'Content-Type': 'application/json'},
            );
          }
        } catch (e) {
          return Response(
            401,
            body: jsonEncode({
              'error': 'Unauthorized: S2S signature verification failed: $e',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        if (db.getFederationServerById(senderId) == null) {
          if (senderId.contains('.') && !domainVerifier.isLoopbackOrTest(senderId)) {
            final isDomainVerified = await domainVerifier.verifyDomainKey(
              domain: senderId,
              expectedPublicKeyB64: pubKeyB64,
              expectedServerId: senderId,
            );
            if (!isDomainVerified) {
              return Response(
                403,
                body: jsonEncode({
                  'error':
                      'Forbidden: Cryptographic domain ownership verification failed for $senderId',
                }),
                headers: {'Content-Type': 'application/json'},
              );
            }
          }
          db.upsertFederationServer(
            serverId: senderId,
            publicKey: pubKeyB64,
            trustSource: senderId.contains('.') ? 'verified_domain' : 's2s_handshake',
          );
        }

        final updatedRequest = request.change(
          body: bodyStr,
          context: {'s2s_sender_id': senderId, 's2s_public_key': pubKeyB64},
        );

        return innerHandler(updatedRequest);
      };
    };
  }
}
