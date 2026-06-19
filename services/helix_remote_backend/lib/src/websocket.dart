import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/jwt.dart';
import 'package:helix_remote_backend/src/modules/messaging.dart';

class WebSocketRelay implements MessageRelay {
  final BackendDatabase db;
  final JwtHelper jwt;
  final int maxReconnectsPerMinute;
  final Map<String, WebSocketChannel> _connections = {}; // key: deviceId
  final Map<String, List<int>> _reconnectAttempts = {};
  int _rejectedReconnects = 0;

  WebSocketRelay(this.db, this.jwt, {this.maxReconnectsPerMinute = 30});

  @override
  void sendToDevice(String deviceId, Map<String, dynamic> payload) {
    final socket = _connections[deviceId];
    if (socket != null) {
      try {
        socket.sink.add(jsonEncode(payload));
      } catch (_) {
        _connections.remove(deviceId);
      }
    }
  }

  FutureOr<Response> handleUpgrade(Request request) {
    final token = request.url.queryParameters['token'];
    if (token == null) {
      return Response.forbidden(
        jsonEncode({'error': 'Missing token query parameter'}),
      );
    }

    final claims = jwt.verifyToken(token);
    if (claims == null) {
      return Response.forbidden(
        jsonEncode({'error': 'Invalid or expired auth token'}),
      );
    }

    final accountId = claims['account_id'] as String?;
    final deviceId = claims['device_id'] as String?;
    if (accountId == null ||
        deviceId == null ||
        !db.isDeviceActive(accountId, deviceId)) {
      return Response.forbidden(jsonEncode({'error': 'Device inactive'}));
    }

    if (!_recordReconnectAttempt(deviceId)) {
      return Response(
        429,
        body: jsonEncode({'error': 'WebSocket reconnect rate exceeded'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Return the upgraded WebSocket handler with captured authenticated claims
    return webSocketHandler((WebSocketChannel socket, String? protocol) {
      _registerConnection(socket, claims);
    })(request);
  }

  void _registerConnection(
    WebSocketChannel socket,
    Map<String, dynamic> claims,
  ) {
    final accountId = claims['account_id'] as String;
    final deviceId = claims['device_id'] as String;

    _connections[deviceId] = socket;

    // Send any offline/pending messages
    try {
      final offlineMessages = db.getOfflineMessagesForDevice(deviceId);
      for (final msg in offlineMessages) {
        socket.sink.add(jsonEncode(msg));
      }
    } catch (_) {
      // Catch db/serialisation errors to avoid crashing connection
    }

    socket.stream.listen(
      (data) {
        try {
          final payload = jsonDecode(data as String) as Map<String, dynamic>;
          if (payload['type'] == 'ack') {
            final conversationId = payload['conversation_id'] as String?;
            final sequence = payload['sequence'] as int?;
            if (conversationId != null && sequence != null) {
              db.updateSyncCursor(
                accountId,
                deviceId,
                conversationId,
                sequence,
              );
            }
          }
        } catch (_) {
          // Safe fail-silent for malformed client messages
        }
      },
      onDone: () {
        _connections.remove(deviceId);
      },
      onError: (_) {
        _connections.remove(deviceId);
      },
    );
  }

  bool isDeviceConnected(String deviceId) {
    return _connections.containsKey(deviceId);
  }

  Map<String, dynamic> stats() => {
    'connected_devices': _connections.length,
    'tracked_reconnect_devices': _reconnectAttempts.length,
    'rejected_reconnects': _rejectedReconnects,
    'max_reconnects_per_minute': maxReconnectsPerMinute,
  };

  bool _recordReconnectAttempt(String deviceId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowStart = now - const Duration(minutes: 1).inMilliseconds;
    final attempts = _reconnectAttempts.putIfAbsent(deviceId, () => []);
    attempts.removeWhere((timestamp) => timestamp < windowStart);
    if (attempts.length >= maxReconnectsPerMinute) {
      _rejectedReconnects++;
      return false;
    }
    attempts.add(now);
    return true;
  }
}
