import 'dart:async';
import 'dart:convert';
import 'dart:io' show stderr;
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
  // Pacing signal for offline-event replay: completed when the client sends
  // a `replay_ack` for the current page, or timed out so old clients that
  // never send one are not blocked forever. Keyed by deviceId.
  final Map<String, Completer<void>> _replayWaiters = {};
  Future<Map<String, dynamic>> Function({
    required String accountId,
    required String deviceId,
    required Map<String, dynamic> message,
  })?
  _callSignalHandler;
  int _rejectedReconnects = 0;

  WebSocketRelay(this.db, this.jwt, {this.maxReconnectsPerMinute = 30});

  @override
  void sendToDevice(String deviceId, Map<String, dynamic> payload) {
    final socket = _connections[deviceId];
    if (socket != null) {
      try {
        socket.sink.add(jsonEncode(payload));
      } catch (e) {
        stderr.writeln('WebSocket sendToDevice error for $deviceId: $e');
        _connections.remove(deviceId);
      }
    }
  }

  bool trySendToDevice(String deviceId, Map<String, dynamic> payload) {
    final socket = _connections[deviceId];
    if (socket == null) return false;
    try {
      socket.sink.add(jsonEncode(payload));
      return true;
    } catch (e) {
      stderr.writeln('WebSocket sendToDevice error for $deviceId: $e');
      _connections.remove(deviceId);
      return false;
    }
  }

  void setCallSignalHandler(
    Future<Map<String, dynamic>> Function({
      required String accountId,
      required String deviceId,
      required Map<String, dynamic> message,
    })
    handler,
  ) {
    _callSignalHandler = handler;
  }

  FutureOr<Response> handleUpgrade(Request request) {
    final authHeader = request.headers['authorization'];
    final token = authHeader != null && authHeader.startsWith('Bearer ')
        ? authHeader.substring('Bearer '.length)
        : null;
    if (token == null) {
      return Response.forbidden(
        jsonEncode({'error': 'Missing Authorization bearer token'}),
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

    // Client sends its current inbound cursor so we only replay new events.
    final sinceStr = request.url.queryParameters['since'];
    final sinceSequence = int.tryParse(sinceStr ?? '') ?? 0;

    // Return the upgraded WebSocket handler with captured authenticated claims
    return webSocketHandler((WebSocketChannel socket, String? protocol) {
      _registerConnection(socket, claims, sinceSequence);
    })(request);
  }

  void _registerConnection(
    WebSocketChannel socket,
    Map<String, dynamic> claims,
    int sinceSequence,
  ) {
    final accountId = claims['account_id'] as String;
    final deviceId = claims['device_id'] as String;

    _connections[deviceId] = socket;

    // Replay offline events asynchronously in small batches so we don't
    // flood the WS sink buffer when there are many queued events. Sending
    // everything synchronously in one tight loop overflows the send buffer
    // and causes the client to close the connection with code 1002.
    _replayOfflineEvents(socket, deviceId, sinceSequence);

    socket.stream.listen(
      (data) async {
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
          } else if (payload['type'] == 'replay_ack') {
            _replayWaiters.remove(deviceId)?.complete();
          } else if (payload['type'] == 'ping') {
            // Reply to client keepalive so the client can detect a dead server.
            try {
              socket.sink.add(jsonEncode({'type': 'pong'}));
            } catch (_) {}
          } else if (payload['type'] == 'call_signal') {
            final requestId = payload['request_id'] as String?;
            final handler = _callSignalHandler;
            Map<String, dynamic> ack;
            if (handler == null) {
              ack = {
                'status': 'rejected',
                'reason': 'call signaling unavailable',
              };
            } else {
              ack = await handler(
                accountId: accountId,
                deviceId: deviceId,
                message: payload,
              );
            }
            try {
              final response = {'type': 'call_signal_ack', ...ack};
              if (requestId != null) response['request_id'] = requestId;
              socket.sink.add(jsonEncode(response));
            } catch (_) {}
          }
        } catch (e) {
          stderr.writeln('Malformed WebSocket client message: $e');
        }
      },
      onDone: () {
        // Guard against a reconnecting device: if the map entry was already
        // replaced by a newer connection, do not remove the new socket.
        if (identical(_connections[deviceId], socket)) {
          _connections.remove(deviceId);
        }
        _replayWaiters.remove(deviceId)?.complete();
      },
      onError: (_) {
        if (identical(_connections[deviceId], socket)) {
          _connections.remove(deviceId);
        }
        _replayWaiters.remove(deviceId)?.complete();
      },
    );
  }

  // Send batches of 20 events then yield to the event loop so the TCP layer
  // can drain between batches. This prevents sink buffer overflow (close 1002)
  // when a device has a large offline queue (e.g. fresh connect with since=0).
  static const _replayBatchSize = 20;

  // Offline events are paged through in bounded `_replayPageSize` queries
  // instead of loading a device's entire backlog (which can be tens of
  // thousands of rows) into one Dart List. Between pages we wait for the
  // client to send a `replay_ack` for the page it just received — real
  // backpressure paced to the client's actual throughput, unlike a bare
  // `Future.delayed(Duration.zero)` yield, which does not wait for a slow
  // client (or a full TCP send buffer) to drain. Clients that never send
  // the ack (older app versions) are not blocked forever: `_replayAckTimeout`
  // falls back to sending the next page unconditionally.
  static const _replayPageSize = 50;
  static const _replayAckTimeout = Duration(seconds: 5);

  Future<void> _replayOfflineEvents(
    WebSocketChannel socket,
    String deviceId,
    int sinceSequence,
  ) async {
    try {
      var cursor = sinceSequence;
      while (true) {
        if (socket.closeCode != null) return;
        final page = db.getDeviceEventsPage(
          deviceId,
          cursor,
          limit: _replayPageSize,
        );
        if (page.isEmpty) return;

        for (var i = 0; i < page.length; i++) {
          if (socket.closeCode != null) return;
          final row = page[i];
          final payload =
              jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          socket.sink.add(
            jsonEncode({
              'event_id': row['event_id'],
              'schema_version': row['schema_version'],
              'timestamp': row['timestamp'],
              'type': row['event_type'],
              'payload': payload,
              'server_sequence': row['device_sequence'],
            }),
          );
          if ((i + 1) % _replayBatchSize == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        cursor = page.last['device_sequence'] as int;
        if (page.length < _replayPageSize) return; // last page

        if (socket.closeCode != null) return;
        final waiter = Completer<void>();
        _replayWaiters[deviceId] = waiter;
        await waiter.future.timeout(_replayAckTimeout, onTimeout: () {});
        if (identical(_replayWaiters[deviceId], waiter)) {
          _replayWaiters.remove(deviceId);
        }
      }
    } catch (e) {
      stderr.writeln('Offline event replay error for $deviceId: $e');
    } finally {
      _replayWaiters.remove(deviceId);
    }
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
