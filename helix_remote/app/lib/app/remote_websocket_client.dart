import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';

class RemoteWebSocketClient {
  RemoteWebSocketClient({
    required Uri wsUri,
    required String token,
    required void Function(RemoteRealtimeEnvelope event) onEvent,
    void Function(String error)? onError,
    void Function()? onDone,
    void Function(Map<String, dynamic> payload)? onRawSignal,
    Duration? pingInterval,
    Duration? connectTimeout,
    Duration? callSignalAckTimeout,
    int sinceSequence = 0,
  }) : _wsUri = wsUri,
       _token = token,
       _onEvent = onEvent,
       _onError = onError,
       _onDone = onDone,
       _onRawSignal = onRawSignal,
       _pingInterval = pingInterval ?? const Duration(seconds: 30),
       _connectTimeout = connectTimeout ?? const Duration(seconds: 10),
       _callSignalAckTimeout =
           callSignalAckTimeout ?? const Duration(seconds: 5),
       _sinceSequence = sinceSequence;

  final Uri _wsUri;
  final String _token;
  final void Function(RemoteRealtimeEnvelope) _onEvent;
  final void Function(String)? _onError;
  final void Function()? _onDone;
  final void Function(Map<String, dynamic> payload)? _onRawSignal;
  final Duration _pingInterval;
  final Duration _connectTimeout;
  final Duration _callSignalAckTimeout;
  final int _sinceSequence;

  WebSocket? _ws;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  final Map<String, Completer<Map<String, dynamic>>> _pendingCallAcks = {};
  bool _disposed = false;
  int _generation = 0;

  bool get isConnected => _ws?.readyState == WebSocket.open;

  Future<void> connect() async {
    if (_disposed) return;
    await disconnect();
    final generation = ++_generation;

    try {
      final uri = _sinceSequence > 0
          ? _wsUri.replace(queryParameters: {'since': '$_sinceSequence'})
          : _wsUri;
      AppLogger.instance.info(
        'WSClient',
        'connecting generation=$generation host=${_wsUri.host} '
            'path=${_wsUri.path} since=$_sinceSequence',
      );
      final socket = await WebSocket.connect(
        uri.toString(),
        headers: {
          'Authorization': 'Bearer $_token',
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(_connectTimeout);
      if (_disposed || generation != _generation) {
        await socket.close();
        return;
      }
      _ws = socket;
      final protocol = socket.protocol;
      AppLogger.instance.info(
        'WSClient',
        'connected generation=$generation '
            'protocol=${protocol == null || protocol.isEmpty ? "none" : protocol}',
      );
      // Protocol-level PING frames keep the connection alive through proxies
      // (Caddy, nginx) that close idle WebSocket tunnels. This is separate
      // from the application-level JSON ping sent by _startPing().
      _ws!.pingInterval = const Duration(seconds: 20);
      _subscription = socket.listen(
        _onData,
        onError: (error) {
          if (generation != _generation) return;
          final code = _ws?.closeCode;
          final reason = _ws?.closeReason;
          _ws = null;
          _failPendingCallAcks('WebSocket stream error: $error');
          AppLogger.instance.warn(
            'WSClient',
            'stream error — close_code=$code reason=${reason ?? "none"} '
                'error=$error',
          );
          _onError?.call(error.toString());
        },
        onDone: () {
          if (generation != _generation) return;
          final code = _ws?.closeCode;
          final reason = _ws?.closeReason;
          _ws = null;
          _failPendingCallAcks(
            'WebSocket closed before call signal acknowledgement',
          );
          AppLogger.instance.info(
            'WSClient',
            'closed — close_code=$code reason=${reason ?? "none"}',
          );
          _onDone?.call();
        },
      );
      _startPing(generation);
    } catch (e) {
      if (generation != _generation || _disposed) return;
      AppLogger.instance.warn(
        'WSClient',
        'handshake failure — uri=${_wsUri.host}${_wsUri.path} error=$e',
      );
      _onError?.call(e.toString());
      rethrow;
    }
  }

  void _onData(dynamic data) {
    try {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      final type = map['type'] as String?;

      // Call signals must be dispatched before envelope parsing — the server
      // includes a real event_id on call_signal frames, which would cause
      // fromJson to succeed and route to _onEvent (which drops them silently).
      if (type == 'call_signal') {
        final payload = map['payload'] as Map<String, dynamic>?;
        AppLogger.instance.info(
          'WSClient',
          'recv call_signal ${_payloadSummary(payload)} '
              'event_id=${map['event_id'] != null} '
              'seq=${map['server_sequence'] ?? map['sequence'] ?? "none"}',
        );
        if (payload != null) _onRawSignal?.call(payload);
        return;
      }
      if (type == 'call_signal_ack') {
        final requestId = map['request_id'] as String?;
        AppLogger.instance.info(
          'WSClient',
          'recv call_signal_ack req=${_requestSuffix(requestId)} '
              'status=${map['status'] ?? "unknown"} '
              'pending=${_pendingCallAcks.length}',
        );
        if (requestId != null) {
          _pendingCallAcks.remove(requestId)?.complete(map);
        }
        return;
      }
      if (type == 'pong') return;

      final envelope = RemoteRealtimeEnvelope.fromJson(map);
      if (envelope.eventId.isNotEmpty) {
        _onEvent(envelope);
      }
    } catch (e) {
      _onError?.call('WebSocket data error: $e');
    }
  }

  void _startPing(int generation) {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_disposed || generation != _generation) return;
      try {
        _ws?.add(jsonEncode({'type': 'ping'}));
      } catch (e) {
        _onError?.call('Ping send error: $e');
      }
    });
  }

  void acknowledge(String conversationId, int sequence) {
    try {
      _ws?.add(
        jsonEncode({
          'type': 'ack',
          'conversation_id': conversationId,
          'sequence': sequence,
        }),
      );
    } catch (e) {
      _onError?.call('Ack send error: $e');
    }
  }

  Future<Map<String, dynamic>> sendCallSignal({
    required String requestId,
    required Map<String, dynamic> payload,
  }) async {
    final socket = _ws;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('WebSocket is not connected');
    }
    final completer = Completer<Map<String, dynamic>>();
    _pendingCallAcks[requestId] = completer;
    try {
      AppLogger.instance.info(
        'WSClient',
        'send call_signal req=${_requestSuffix(requestId)} '
            '${_payloadSummary(payload)} pending=${_pendingCallAcks.length}',
      );
      socket.add(
        jsonEncode({
          'type': 'call_signal',
          'request_id': requestId,
          'payload': payload,
        }),
      );
    } catch (e) {
      _pendingCallAcks.remove(requestId);
      AppLogger.instance.warn(
        'WSClient',
        'send call_signal failed req=${_requestSuffix(requestId)} error=$e',
      );
      _onError?.call('Call signal send error: $e');
      rethrow;
    }
    try {
      final ack = await completer.future.timeout(_callSignalAckTimeout);
      AppLogger.instance.info(
        'WSClient',
        'ack completed req=${_requestSuffix(requestId)} status=${ack['status'] ?? "unknown"}',
      );
      return ack;
    } on TimeoutException {
      _pendingCallAcks.remove(requestId);
      AppLogger.instance.warn(
        'WSClient',
        'ack timeout req=${_requestSuffix(requestId)} '
            'pending=${_pendingCallAcks.length}',
      );
      throw TimeoutException(
        'Timed out waiting for call signal acknowledgement',
        _callSignalAckTimeout,
      );
    }
  }

  Future<void> disconnect() async {
    _generation++;
    AppLogger.instance.info(
      'WSClient',
      'disconnect generation=$_generation pending_acks=${_pendingCallAcks.length}',
    );
    _pingTimer?.cancel();
    _pingTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _ws?.close();
    _ws = null;
    _failPendingCallAcks('WebSocket disconnected');
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
  }

  void _failPendingCallAcks(String message) {
    if (_pendingCallAcks.isEmpty) return;
    final pending = Map<String, Completer<Map<String, dynamic>>>.of(
      _pendingCallAcks,
    );
    _pendingCallAcks.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError(message));
      }
    }
  }

  String _payloadSummary(Map<String, dynamic>? payload) {
    if (payload == null) return 'payload=null';
    final callId = payload['call_id'] as String? ?? '';
    final cid = callId.length > 8 ? callId.substring(0, 8) : callId;
    final signalType = payload['signal_type'] as String? ?? 'unknown';
    final sdp = payload['sdp'] as String?;
    final candidate = payload['candidate'] as String?;
    return 'type=$signalType cid=$cid '
        'sdp_len=${sdp?.length ?? 0} '
        'candidate_type=${_candidateType(candidate)}';
  }

  String _candidateType(String? candidate) {
    if (candidate == null) return 'none';
    if (candidate.isEmpty) return 'end';
    final match = RegExp(r' typ ([A-Za-z0-9_-]+)').firstMatch(candidate);
    return match?.group(1) ?? 'unknown';
  }

  String _requestSuffix(String? requestId) {
    if (requestId == null || requestId.isEmpty) return 'none';
    return requestId.length <= 10
        ? requestId
        : requestId.substring(requestId.length - 10);
  }
}
