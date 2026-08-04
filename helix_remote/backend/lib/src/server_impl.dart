import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/jwt.dart';
import 'package:helix_remote_backend/src/outbox_worker.dart';
import 'package:helix_remote_backend/src/push_provider.dart';
import 'package:helix_remote_backend/src/rate_limiter.dart';
import 'package:helix_remote_backend/src/server_log.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';
import 'package:helix_remote_backend/src/websocket.dart';
import 'package:helix_remote_backend/src/federation.dart';
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
import 'package:helix_remote_backend/src/modules/admin_pairing.dart';
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
  final Directory? attachmentsStorageDir;
  final String turnSecret;
  final String turnUrl;
  final SmsProvider smsProvider;
  final Set<String> adminAccountIds;
  final Set<String> trustedProxyAddresses;
  final DateTime Function() now;
  final String? logFilePath;
  final String? adminTokenOverride;
  ServerIdentity? serverIdentity;
  final String? federationDomain;
  final String federationDirectoryUrl;
  final String publicBaseUrl;
  final bool globalInstanceMode;
  final String serverAudience;
  HttpServer? _httpServer;
  HttpServer? get httpServer => _httpServer;

  BackendServer._({
    required this.db,
    required this.jwt,
    required this.rateLimiter,
    required this.wsRelay,
    required this.outboxWorker,
    this.attachmentsStorageDir,
    this.turnSecret = '',
    this.turnUrl = '',
    this.smsProvider = const NoopSmsProvider(),
    this.adminAccountIds = const {'admin'},
    this.trustedProxyAddresses = const {'127.0.0.1', '::1'},
    required this.now,
    this.logFilePath,
    this.adminTokenOverride,
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
    double rateLimitMaxTokens = 100.0,
    double rateLimitRefillRate = 10.0,
    Directory? attachmentsStorageDir,
    String turnSecret = '',
    String turnUrl = '',
    SmsProvider? smsProvider,
    Set<String> adminAccountIds = const {'admin'},
    Set<String> trustedProxyAddresses = const {'127.0.0.1', '::1'},
    PushProvider? pushProvider,
    bool pushProviderAvailable = true,
    int wsReconnectsPerMinute = 30,
    DateTime Function()? now,
    String? logFilePath,
    String? adminTokenOverride,
    ServerIdentity? serverIdentity,
    String? federationDomain,
    String? federationDirectoryUrl,
    String? publicBaseUrl,
    bool? globalInstanceMode,
    String? serverAudience,
  }) {
    final db = BackendDatabase(sqliteDb);
    final jwt = JwtHelper(jwtSecret);
    final rateLimiter = RateLimiter(
      maxTokens: rateLimitMaxTokens,
      refillRatePerSecond: rateLimitRefillRate,
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
      attachmentsStorageDir: attachmentsStorageDir,
      turnSecret: turnSecret,
      turnUrl: turnUrl,
      smsProvider: smsProvider ?? const NoopSmsProvider(),
      adminAccountIds: adminAccountIds,
      trustedProxyAddresses: trustedProxyAddresses,
      now: now ?? DateTime.now,
      logFilePath: logFilePath ?? Platform.environment['HELIX_REMOTE_LOG_FILE'],
      adminTokenOverride:
          adminTokenOverride ??
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
      adminAccountIds: adminAccountIds,
      notifyDevice: wsRelay.sendToDevice,
    );
    final backupsModule = BackupsModule(db);
    final attachmentsModule = AttachmentsModule(
      db,
      storageDir: attachmentsStorageDir,
    );
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
    final privacyComplianceModule = PrivacyComplianceModule(
      db,
      adminAccountIds: adminAccountIds,
    );
    final adminPairingModule = AdminPairingModule(db: db, now: now);
    final operabilityModule = OperabilityModule(
      db: db,
      rateLimiter: rateLimiter,
      wsRelay: wsRelay,
      outboxWorker: outboxWorker,
      callsModule: callsModule,
      adminAccountIds: adminAccountIds,
      turnSecret: turnSecret,
      turnUrl: turnUrl,
      logFilePath: logFilePath,
      logSink: activeServerLog,
      serverIdentity: serverIdentity,
      federationClient: federationClient,
      federationDomain: federationDomain,
      federationDirectoryUrl: federationDirectoryUrl,
      publicBaseUrl: publicBaseUrl,
      now: now,
    );

    // Map modules
    router.mount('/api/v1/health', operabilityModule.healthRouter.call);
    router.mount('/api/v1/ops', operabilityModule.opsRouter.call);
    router.mount('/api/v1/server', operabilityModule.serverRouter.call);
    router.mount('/api/v1/admin-pairing', adminPairingModule.router.call);
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
        .addMiddleware(_requestLogMiddleware())
        .addMiddleware(_rateLimitMiddleware())
        .addMiddleware(_s2sAuthMiddleware())
        .addMiddleware(_authMiddleware())
        .addHandler(router.call);

    return pipeline;
  }

  Future<void> start(String host, int port) async {
    final handler = getHandler();
    _httpServer = await shelf_io.serve(handler, host, port);
    outboxWorker.start();
  }

  Future<void> stop() async {
    outboxWorker.stop();
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
          final line =
              '${request.method} /${request.url.path} '
              '${response.statusCode} ${watch.elapsedMilliseconds}ms';
          if (response.statusCode >= 500) {
            sink.error(line);
          } else if (response.statusCode >= 400) {
            sink.warn(line);
          } else {
            sink.info(line);
          }
          return response;
        } catch (e) {
          watch.stop();
          sink.error(
            '${request.method} /${request.url.path} threw after '
            '${watch.elapsedMilliseconds}ms: $e',
          );
          rethrow;
        }
      };
    };
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
    final candidate =
        (forwardedFor?.split(',').first.trim().isNotEmpty ?? false)
        ? forwardedFor!.split(',').first.trim()
        : realIp?.trim();
    if (candidate == null || candidate.isEmpty) {
      return immediatePeerIp;
    }
    final parsed = InternetAddress.tryParse(candidate);
    if (parsed == null) return immediatePeerIp;
    return parsed.address;
  }

  bool _isValidAdminToken(String token) {
    if (adminTokenOverride != null && adminTokenOverride!.isNotEmpty) {
      return token == adminTokenOverride;
    }
    final dbHash = db.getServerConfig('admin_token_hash');
    if (dbHash == null) return false;
    final inputHash = crypto_pkg.sha256.convert(utf8.encode(token)).toString();
    return inputHash == dbHash;
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
            path.endsWith('/contacts/discovery-salt') ||
            path.endsWith('/devices/link/request-new') ||
            path.endsWith('/devices/link/complete-new') ||
            path.endsWith('/health/live') ||
            path.endsWith('/health/ready') ||
            path.contains('/s2s/') ||
            path.contains('/admin-pairing/') ||
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

        // Check for Admin API token first
        if (_isValidAdminToken(token)) {
          final adminClaims = {
            'account_id': 'admin',
            'device_id': 'admin_device',
            'is_admin': true,
          };
          final updatedRequest = request.change(context: {'auth': adminClaims});
          return innerHandler(updatedRequest);
        }

        final claims = jwt.verifyToken(token);
        if (claims == null) {
          return Response(
            403,
            body: jsonEncode({'error': 'Forbidden: Invalid or expired token'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final accountId = claims['account_id'] as String?;
        final deviceId = claims['device_id'] as String?;
        if (accountId == null ||
            deviceId == null ||
            !db.isDeviceActive(accountId, deviceId)) {
          return Response(
            403,
            body: jsonEncode({'error': 'Forbidden: Device inactive'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        if (db.isAccountSuspended(accountId)) {
          return Response(
            403,
            body: jsonEncode({'error': 'Forbidden: Account suspended'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final updatedRequest = request.change(context: {'auth': claims});
        return innerHandler(updatedRequest);
      };
    };
  }

  Middleware _s2sAuthMiddleware() {
    final ed25519 = crypto.Ed25519();
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
          db.upsertFederationServer(
            serverId: senderId,
            publicKey: pubKeyB64,
            trustSource: 's2s_handshake',
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
