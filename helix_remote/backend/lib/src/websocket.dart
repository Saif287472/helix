import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/jwt.dart';
import 'package:helix_remote_backend/src/modules/messaging.dart';
import 'package:helix_remote_backend/src/server_log.dart';

/// One live WebSocket connection to one device, and the single path through
/// which every write for that device goes.
///
/// Before this existed, `sendToDevice`, `trySendToDevice`, the `pong` reply,
/// the call-signal ack and offline-event replay each called
/// `socket.sink.add` directly from unrelated async contexts, each with its
/// own error handling. Two of them removed the device from the connection
/// map on a failed write *without checking that the socket that failed was
/// still the registered one*, so a late failure on a socket the device had
/// already replaced tore down its current, healthy connection.
///
/// **On backpressure.** This stack offers no signal for it, and it is worth
/// being precise about why rather than writing an `await` that awaits
/// nothing. `shelf_web_socket` hands us an `IOWebSocketChannel`; its sink is
/// a `StreamChannelController(sync: true)` whose listener calls
/// `WebSocket.sendText`, which returns `void` and buffers without bound.
/// There is no `bufferedAmount`, and `sink.addStream` completes as fast as
/// the source produces. The only real drain signal available is the one the
/// client already sends: a `replay_ack` per received event. Replay is
/// therefore paced by those acks as credits - see [needsReplayCredit].
class _DeviceConnection {
  _DeviceConnection(this.socket, this.deviceId);

  final WebSocketChannel socket;
  final String deviceId;

  bool _failed = false;

  /// False once the peer closed, or once a write threw - either way there is
  /// no point queueing more work for this socket.
  bool get isOpen => socket.closeCode == null && !_failed;

  /// Encodes and writes [payload]. Returns false if the connection is gone,
  /// in which case the caller should stop sending; the caller is responsible
  /// for deregistering, so that only the owner of the map entry can remove
  /// it.
  bool send(Map<String, dynamic> payload) {
    if (!isOpen) return false;
    try {
      socket.sink.add(jsonEncode(payload));
      return true;
    } catch (e) {
      _failed = true;
      logServerError('WebSocket send error for $deviceId: $e');
      return false;
    }
  }

  // --- Replay flow control ------------------------------------------------
  //
  // Counted as credits rather than compared as sequence numbers: the client
  // acks every envelope it receives, including live events relayed while a
  // replay is in flight, and a live event's `server_sequence` is unrelated
  // to the replay cursor. Counting acks matches what the client actually
  // does; the extra credit a live event contributes only widens the window
  // slightly, whereas comparing sequences would drain the whole window at
  // once and defeat the pacing.

  int _replaySent = 0;
  int _replayAcked = 0;
  Completer<void>? _creditWaiter;

  void noteReplaySent() => _replaySent++;

  void noteReplayAck() {
    _replayAcked++;
    if (_replaySent - _replayAcked < WebSocketRelay.replayWindow) {
      _releaseCreditWaiter();
    }
  }

  /// True when [WebSocketRelay.replayWindow] events are outstanding, i.e. the
  /// client has not confirmed receipt of them and we should stop feeding the
  /// socket.
  bool get needsReplayCredit =>
      _replaySent - _replayAcked >= WebSocketRelay.replayWindow;

  /// Waits for the client to acknowledge enough of the outstanding events to
  /// reopen the window. Returns false if [timeout] elapsed first, which means
  /// the client does not send `replay_ack` at all (an older app build) and
  /// the caller should stop waiting on credits for the rest of this replay.
  Future<bool> awaitReplayCredit(Duration timeout) async {
    final waiter = Completer<void>();
    _creditWaiter = waiter;
    var acked = true;
    await waiter.future.timeout(
      timeout,
      onTimeout: () {
        acked = false;
      },
    );
    if (identical(_creditWaiter, waiter)) _creditWaiter = null;
    return acked;
  }

  void _releaseCreditWaiter() {
    final waiter = _creditWaiter;
    _creditWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  /// Unblocks an in-flight replay so it can observe [isOpen] and stop.
  void dispose() {
    _failed = true;
    _releaseCreditWaiter();
  }
}

class WebSocketRelay implements MessageRelay {
  final BackendDatabase db;
  final JwtHelper jwt;
  final int maxReconnectsPerMinute;
  final Map<String, _DeviceConnection> _connections = {}; // key: deviceId
  final Map<String, List<int>> _reconnectAttempts = {};
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
    trySendToDevice(deviceId, payload);
  }

  bool trySendToDevice(String deviceId, Map<String, dynamic> payload) {
    final connection = _connections[deviceId];
    if (connection == null) return false;
    if (connection.send(payload)) return true;
    _deregister(connection);
    return false;
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

    // Access tokens only. A refresh token used to be accepted here, which
    // handed a 7-day credential the full realtime stream.
    final claims = jwt.verifyToken(token, expect: ExpectedTokenType.access);
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

    final connection = _DeviceConnection(socket, deviceId);
    // A reconnecting device replaces its own entry; disposing the previous
    // connection object unblocks any replay still paced against it, which
    // would otherwise sit on a credit wait for a socket nobody reads.
    final superseded = _connections[deviceId];
    _connections[deviceId] = connection;
    superseded?.dispose();

    // Replay offline events asynchronously, paced by the client's acks, so
    // we don't flood the WS sink buffer when there are many queued events.
    // Sending everything synchronously in one tight loop overflows the send
    // buffer and causes the client to close the connection with code 1002.
    _replayOfflineEvents(connection, sinceSequence);

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
            connection.noteReplayAck();
          } else if (payload['type'] == 'ping') {
            // Reply to client keepalive so the client can detect a dead server.
            connection.send({'type': 'pong'});
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
            final response = {'type': 'call_signal_ack', ...ack};
            if (requestId != null) response['request_id'] = requestId;
            connection.send(response);
          }
        } catch (e) {
          logServerError('Malformed WebSocket client message: $e');
        }
      },
      onDone: () => _deregister(connection),
      onError: (_) => _deregister(connection),
    );
  }

  /// Removes [connection] only if it is still the registered one. Guards
  /// against a reconnecting device: a late failure or close on a superseded
  /// socket must not evict the connection that replaced it.
  void _deregister(_DeviceConnection connection) {
    if (identical(_connections[connection.deviceId], connection)) {
      _connections.remove(connection.deviceId);
    }
    connection.dispose();
  }

  // Offline events are paged through in bounded [_replayPageSize] queries
  // instead of loading a device's entire backlog (which can be tens of
  // thousands of rows) into one Dart List.
  static const _replayPageSize = 50;

  /// How many replayed events may be outstanding - sent but not yet
  /// acknowledged - at any moment.
  ///
  /// The pacing this enforces used to happen only *between* 50-event pages;
  /// within a page all 50 went out back-to-back with a bare
  /// `Future.delayed(Duration.zero)` every 20, which yields to the event loop
  /// but, as the old comment here conceded, "does not wait for a slow client
  /// (or a full TCP send buffer) to drain". A window applied per event is
  /// paced to the client's actual throughput and is bounded regardless of
  /// page size.
  static const int replayWindow = 20;

  /// Yield interval used only for clients that never ack (see
  /// [_replayAckTimeout]) - it at least stops the replay monopolising the
  /// isolate, which is all the old code ever achieved.
  static const _replayYieldInterval = 20;

  static const _replayAckTimeout = Duration(seconds: 5);

  Future<void> _replayOfflineEvents(
    _DeviceConnection connection,
    int sinceSequence,
  ) async {
    final deviceId = connection.deviceId;
    try {
      var cursor = sinceSequence;
      // Latched on the first ack timeout: an app build that does not send
      // `replay_ack` would otherwise pay the 5-second timeout once per
      // window, turning a backlog into a many-minute crawl. Once we know the
      // client never acks, fall back to the old yield-based pacing for the
      // rest of this replay.
      var clientAcksReplay = true;
      var sent = 0;

      while (true) {
        if (!connection.isOpen) return;
        final page = db.getDeviceEventsPage(
          deviceId,
          cursor,
          limit: _replayPageSize,
        );
        if (page.isEmpty) return;

        for (final row in page) {
          if (!connection.isOpen) return;
          final payload =
              jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          final delivered = connection.send({
            'event_id': row['event_id'],
            'schema_version': row['schema_version'],
            'timestamp': row['timestamp'],
            'type': row['event_type'],
            'payload': payload,
            'server_sequence': row['device_sequence'],
          });
          if (!delivered) return;
          connection.noteReplaySent();
          sent++;

          if (!clientAcksReplay) {
            if (sent % _replayYieldInterval == 0) {
              await Future<void>.delayed(Duration.zero);
            }
          } else if (connection.needsReplayCredit) {
            clientAcksReplay = await connection.awaitReplayCredit(
              _replayAckTimeout,
            );
          }
        }

        cursor = page.last['device_sequence'] as int;
        if (page.length < _replayPageSize) return; // last page
      }
    } catch (e) {
      logServerError('Offline event replay error for $deviceId: $e');
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
