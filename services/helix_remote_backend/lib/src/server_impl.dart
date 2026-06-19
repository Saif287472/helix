import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/jwt.dart';
import 'package:helix_remote_backend/src/rate_limiter.dart';
import 'package:helix_remote_backend/src/websocket.dart';
import 'package:helix_remote_backend/src/modules/auth.dart';
import 'package:helix_remote_backend/src/modules/prekeys.dart';
import 'package:helix_remote_backend/src/modules/contacts.dart';
import 'package:helix_remote_backend/src/modules/messaging.dart';
import 'package:helix_remote_backend/src/modules/backups.dart';
import 'package:helix_remote_backend/src/modules/attachments.dart';
import 'package:helix_remote_backend/src/modules/calls.dart';
import 'package:helix_remote_backend/src/modules/groups.dart';

class OutboxWorker {
  final BackendDatabase db;
  Timer? _timer;

  OutboxWorker(this.db);

  void start() {
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _processOutbox(),
    );
  }

  void stop() {
    _timer?.cancel();
  }

  void _processOutbox() {
    try {
      final items = db.getPendingOutbox();
      for (final item in items) {
        final eventId = item['event_id'] as String;
        final type = item['type'] as String;
        final retries = item['retries'] as int;

        if (type == 'PUSH_NOTIFICATION') {
          // Process mock push notification delivery
          db.updateOutboxStatus(eventId, 'COMPLETED', retries);
        } else {
          db.updateOutboxStatus(eventId, 'FAILED', retries + 1);
        }
      }
    } catch (_) {
      // Ignore background errors
    }
  }
}

class BackendServer {
  final BackendDatabase db;
  final JwtHelper jwt;
  final RateLimiter rateLimiter;
  final WebSocketRelay wsRelay;
  final OutboxWorker outboxWorker;
  final Directory? attachmentsStorageDir;
  final String turnSecret;
  final String turnUrl;
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
  });

  factory BackendServer.create({
    required Database sqliteDb,
    required String jwtSecret,
    double rateLimitMaxTokens = 100.0,
    double rateLimitRefillRate = 10.0,
    Directory? attachmentsStorageDir,
    String turnSecret = '',
    String turnUrl = '',
  }) {
    final db = BackendDatabase(sqliteDb);
    final jwt = JwtHelper(jwtSecret);
    final rateLimiter = RateLimiter(
      maxTokens: rateLimitMaxTokens,
      refillRatePerSecond: rateLimitRefillRate,
    );
    final wsRelay = WebSocketRelay(db, jwt);
    final outboxWorker = OutboxWorker(db);

    return BackendServer._(
      db: db,
      jwt: jwt,
      rateLimiter: rateLimiter,
      wsRelay: wsRelay,
      outboxWorker: outboxWorker,
      attachmentsStorageDir: attachmentsStorageDir,
      turnSecret: turnSecret,
      turnUrl: turnUrl,
    );
  }

  Handler getHandler() {
    final router = Router();

    final authModule = AuthModule(db, jwt, notifyDevice: wsRelay.sendToDevice);
    final prekeysModule = PrekeysModule(db);
    final contactsModule = ContactsModule(db);
    final backupsModule = BackupsModule(db);
    final attachmentsModule = AttachmentsModule(
      db,
      storageDir: attachmentsStorageDir,
    );
    final messagingModule = MessagingModule(
      db,
      wsRelay,
      onMessageDeleted: attachmentsModule.cleanAttachmentReferences,
    );
    final callsModule = CallsModule(
      db,
      wsRelay,
      turnSecret: turnSecret,
      turnUrl: turnUrl,
    );
    final groupsModule = GroupsModule(db, wsRelay);

    // Map modules
    router.mount('/api/v1/accounts', authModule.router.call);
    router.mount('/api/v1/devices', authModule.router.call);
    router.mount('/api/v1/prekeys', prekeysModule.router.call);
    router.mount('/api/v1/contacts', contactsModule.router.call);
    router.mount('/api/v1/messages', messagingModule.router.call);
    router.mount('/api/v1/backups', backupsModule.router.call);
    router.mount('/api/v1/attachments', attachmentsModule.router.call);
    router.mount('/api/v1/calls', callsModule.router.call);
    router.mount('/api/v1/groups', groupsModule.router.call);

    // WebSocket route
    router.get('/api/v1/ws', wsRelay.handleUpgrade);

    final pipeline = const Pipeline()
        .addMiddleware(_rateLimitMiddleware())
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
    await _httpServer?.close(force: true);
    db.close();
  }

  Middleware _rateLimitMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final connInfo = request.context['shelf.io.connection_info'];
        String ip = '127.0.0.1';
        if (connInfo is HttpConnectionInfo) {
          ip = connInfo.remoteAddress.address;
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

  Middleware _authMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final path = request.url.path;

        // Skip auth check for public routes
        if (path.endsWith('/accounts/register') ||
            path.endsWith('/accounts/challenge') ||
            path.endsWith('/accounts/login') ||
            path.endsWith('/accounts/refresh') ||
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

        final updatedRequest = request.change(context: {'auth': claims});
        return innerHandler(updatedRequest);
      };
    };
  }
}
