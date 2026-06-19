import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/websocket.dart';

class CallsModule {
  CallsModule(
    this.db,
    this.wsRelay, {
    required this.turnSecret,
    required this.turnUrl,
  });

  final BackendDatabase db;
  final WebSocketRelay wsRelay;
  final String turnSecret;
  final String turnUrl;

  static const int _maxCredentialsPerHour = 10;
  static const int _credentialValiditySeconds = 3600;

  Router get router {
    final r = Router();
    r.get('/turn-credentials', _handleTurnCredentials);
    r.post('/signal', _handleSignal);
    return r;
  }

  // GET /api/v1/calls/turn-credentials
  // Issues short-lived HMAC-SHA1 TURN credentials (TURN REST API spec).
  // Rate-limited: max 10 per account per hour (P15-005, P15-018).
  Future<Response> _handleTurnCredentials(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(
        jsonEncode({'error': 'Unauthorized'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final accountId = auth['account_id'] as String;

    final count = db.getTurnCredentialCountLastHour(accountId);
    if (count >= _maxCredentialsPerHour) {
      return Response(
        429,
        body: jsonEncode({'error': 'TURN credential quota exceeded. Try again later.'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final now = DateTime.now();
    final issuedAt = now.millisecondsSinceEpoch;
    final expiresAtSeconds = now.millisecondsSinceEpoch ~/ 1000 + _credentialValiditySeconds;

    // TURN REST API credential format: "<expiry_unix>:<account_id>"
    final username = '$expiresAtSeconds:$accountId';
    final credential = _hmacSha1Base64(turnSecret, username);

    final logId = '${accountId}_$issuedAt';
    db.logTurnCredential(
      logId: logId,
      accountId: accountId,
      issuedAt: issuedAt,
      expiresAt: expiresAtSeconds * 1000,
    );

    return Response.ok(
      jsonEncode({
        'url': turnUrl,
        'username': username,
        'credential': credential,
        'expires_at': expiresAtSeconds,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // POST /api/v1/calls/signal
  // Relays a call signal to a target device via WebSocket (P15-002).
  // If the device is offline the signal is silently dropped (calls are
  // time-sensitive; offline-message storage for calls is not implemented).
  // A generic push notification is enqueued for offline devices (P15-007).
  Future<Response> _handleSignal(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(
        jsonEncode({'error': 'Unauthorized'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final targetDeviceId = body['target_device_id'] as String?;
    final payload = body['payload'];

    if (targetDeviceId == null || payload == null) {
      return Response(
        400,
        body: jsonEncode({'error': 'Missing target_device_id or payload'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (payload is! Map<String, dynamic>) {
      return Response(
        400,
        body: jsonEncode({'error': 'payload must be a JSON object'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final delivered = wsRelay.isDeviceConnected(targetDeviceId);
    if (delivered) {
      wsRelay.sendToDevice(targetDeviceId, {
        'type': 'call_signal',
        'payload': payload,
      });
    } else {
      // Device is offline — enqueue a generic push notification.
      // Payload contains no call content: only a type hint so the OS can
      // wake the app (P15-007). Call media and content must never appear here.
      final notifId =
          '${targetDeviceId}_call_${DateTime.now().millisecondsSinceEpoch}';
      db.enqueueOutbox(
        notifId,
        'PUSH_NOTIFICATION',
        jsonEncode({'notification_type': 'incoming_call'}),
      );
    }

    return Response.ok(
      jsonEncode({'delivered': delivered}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  static String _hmacSha1Base64(String secret, String message) {
    final hmac = Hmac(sha1, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(message));
    return base64Encode(digest.bytes);
  }
}
