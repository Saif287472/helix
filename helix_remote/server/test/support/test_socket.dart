import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// A realtime client for tests: buffers server frames and exposes them one
/// at a time.
final class TestSocket {
  TestSocket._(this._ws) {
    _ws.listen(
      (data) {
        final frame = ServerFrame.decode(data as String);
        if (_waiting != null) {
          final w = _waiting!;
          _waiting = null;
          w.complete(frame);
        } else {
          _buffer.add(frame);
        }
      },
      onDone: () {
        _done.complete(_ws.closeCode);
        _waiting?.completeError(StateError('socket closed (${_ws.closeCode})'));
        _waiting = null;
      },
    );
  }

  final WebSocket _ws;
  final Queue<ServerFrame> _buffer = Queue();
  Completer<ServerFrame>? _waiting;
  final Completer<int?> _done = Completer();

  static Future<TestSocket> connect(
    Uri base,
    String accessToken, {
    int? after,
    List<String> protocols = const [realtimeSubprotocolJson],
  }) async {
    final uri = base.replace(
      scheme: 'ws',
      path: Routes.websocket.path,
      queryParameters: after == null ? null : {'after': '$after'},
    );
    final ws = await WebSocket.connect(
      uri.toString(),
      protocols: protocols,
      headers: {'authorization': 'Bearer $accessToken'},
    );
    return TestSocket._(ws);
  }

  Future<ServerFrame> next({Duration timeout = const Duration(seconds: 5)}) {
    if (_buffer.isNotEmpty) return Future.value(_buffer.removeFirst());
    final c = _waiting = Completer<ServerFrame>();
    return c.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_waiting, c)) _waiting = null;
        throw TimeoutException('no frame within $timeout');
      },
    );
  }

  Future<HelloFrame> hello() async => (await next()) as HelloFrame;

  Future<Envelope> envelope({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    while (true) {
      final frame = await next(timeout: timeout);
      if (frame is EnvelopeFrame) return frame.envelope;
    }
  }

  /// No frame arrives within [wait].
  Future<bool> silent([
    Duration wait = const Duration(milliseconds: 600),
  ]) async {
    try {
      await next(timeout: wait);
      return false;
    } on TimeoutException {
      return true;
    }
  }

  void ack(int seq) => _ws.add(AckFrame(seq: seq).encode());

  void ping([String? nonce]) => _ws.add(PingFrame(nonce: nonce).encode());

  void sendRaw(String text) => _ws.add(text);

  Future<int?> get closed => _done.future.timeout(const Duration(seconds: 5));

  Future<void> close() => _ws.close();
}
