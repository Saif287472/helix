import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  }) : _wsUri = wsUri,
       _token = token,
       _onEvent = onEvent,
       _onError = onError,
       _onDone = onDone,
       _onRawSignal = onRawSignal,
       _pingInterval = pingInterval ?? const Duration(seconds: 30);

  final Uri _wsUri;
  final String _token;
  final void Function(RemoteRealtimeEnvelope) _onEvent;
  final void Function(String)? _onError;
  final void Function()? _onDone;
  final void Function(Map<String, dynamic> payload)? _onRawSignal;
  final Duration _pingInterval;

  WebSocket? _ws;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  bool _disposed = false;

  bool get isConnected => _ws != null;

  Future<void> connect() async {
    if (_disposed) return;
    await disconnect();

    final uri = _wsUri.replace(queryParameters: {'token': _token});
    try {
      _ws = await WebSocket.connect(uri.toString());
      _subscription = _ws!.listen(
        _onData,
        onError: (error) {
          _ws = null;
          _onError?.call(error.toString());
        },
        onDone: () {
          _ws = null;
          _onDone?.call();
        },
      );
      _startPing();
    } catch (e) {
      _onError?.call(e.toString());
      rethrow;
    }
  }

  void _onData(dynamic data) {
    try {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      try {
        final envelope = RemoteRealtimeEnvelope.fromJson(map);
        if (envelope.eventId.isNotEmpty) {
          _onEvent(envelope);
        }
      } catch (_) {
        if (map['type'] == 'call_signal') {
          final payload = map['payload'] as Map<String, dynamic>?;
          if (payload != null) {
            _onRawSignal?.call(payload);
          }
        }
      }
    } catch (e) {
      _onError?.call('WebSocket data error: $e');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
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

  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _ws?.close();
    _ws = null;
  }

  void dispose() {
    _disposed = true;
    disconnect();
  }
}
