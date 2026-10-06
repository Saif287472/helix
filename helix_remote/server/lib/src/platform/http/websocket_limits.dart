import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:stream_channel/stream_channel.dart';

/// Caps the size of WebSocket messages a client may send (S7 #15).
/// `dart:io` buffers a whole message before handing it over and has no
/// limit of its own, so this reads the frame headers on the raw upgraded
/// socket and destroys the connection as soon as a frame (or a fragmented
/// message) announces more than [maxMessageBytes], before the payload is
/// buffered.
///
/// Wrap the upgrade request: `webSocketHandler(...)(limitWebSocketFrames(
/// request, maxMessageBytes: n))`.
Request limitWebSocketFrames(Request request, {required int maxMessageBytes}) {
  if (!request.canHijack) return request;
  return Request(
    request.method,
    request.requestedUri,
    protocolVersion: request.protocolVersion,
    headers: request.headers,
    handlerPath: request.handlerPath,
    url: request.url,
    context: request.context,
    onHijack: (callback) {
      try {
        request.hijack(
          // shelf_web_socket needs the sink to be the dart:io Socket
          // (`changeSink` would wrap it), so build the channel directly.
          (channel) {
            final sink = channel.sink;
            callback(
              sink is Socket
                  ? StreamChannel(
                      channel.stream,
                      _GuardedSocket(
                        sink,
                        WebSocketFrameGuard(maxMessageBytes),
                      ),
                    )
                  : channel,
            );
          },
        );
      } on HijackException {
        // Expected: the outer hijack reports it to the adapter.
      }
    },
  );
}

/// The client sent a WebSocket message over the limit.
final class WebSocketMessageTooLarge implements Exception {
  const WebSocketMessageTooLarge();

  @override
  String toString() => 'WebSocketMessageTooLarge';
}

/// A [Socket] whose incoming bytes pass a [WebSocketFrameGuard]; everything
/// else goes to the real socket.
final class _GuardedSocket extends Stream<Uint8List> implements Socket {
  _GuardedSocket(this._inner, this._guard);

  final Socket _inner;
  final WebSocketFrameGuard _guard;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _inner
      .transform(
        StreamTransformer<Uint8List, Uint8List>.fromHandlers(
          handleData: (chunk, out) {
            if (_guard.accept(chunk)) {
              out.add(chunk);
            } else {
              out.addError(const WebSocketMessageTooLarge());
              out.close();
              _inner.destroy();
            }
          },
        ),
      )
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  void add(List<int> data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> get done => _inner.done;

  @override
  Future<void> flush() => _inner.flush();

  @override
  void write(Object? object) => _inner.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);

  @override
  void writeln([Object? object = '']) => _inner.writeln(object);

  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);

  @override
  InternetAddress get address => _inner.address;

  @override
  int get port => _inner.port;

  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;

  @override
  int get remotePort => _inner.remotePort;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _inner.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);

  @override
  void destroy() => _inner.destroy();
}

/// Follows RFC 6455 frame boundaries in a client-to-server byte stream and
/// sums payload lengths per message (control frames, at most 125 bytes by
/// the RFC, are checked on their own).
final class WebSocketFrameGuard {
  WebSocketFrameGuard(this.maxMessageBytes);

  final int maxMessageBytes;

  final List<int> _header = [];
  int _payloadLeft = 0;
  int _messageBytes = 0;

  /// Feeds [bytes]; false once a limit is exceeded (stop reading then).
  bool accept(List<int> bytes) {
    var i = 0;
    while (i < bytes.length) {
      if (_payloadLeft > 0) {
        final take = bytes.length - i < _payloadLeft
            ? bytes.length - i
            : _payloadLeft;
        _payloadLeft -= take;
        i += take;
        continue;
      }
      _header.add(bytes[i++]);
      final needed = _headerLength();
      if (needed == null || _header.length < needed) continue;
      if (!_frame()) return false;
      _header.clear();
    }
    return true;
  }

  /// Header length once enough of it is known (2 + extended length + mask).
  int? _headerLength() {
    if (_header.length < 2) return null;
    final masked = _header[1] & 0x80 != 0;
    final len7 = _header[1] & 0x7f;
    final extended = len7 == 126 ? 2 : (len7 == 127 ? 8 : 0);
    return 2 + extended + (masked ? 4 : 0);
  }

  bool _frame() {
    final fin = _header[0] & 0x80 != 0;
    final opcode = _header[0] & 0x0f;
    final len7 = _header[1] & 0x7f;
    var length = len7;
    if (len7 == 126) {
      length = (_header[2] << 8) | _header[3];
    } else if (len7 == 127) {
      // A length past 2^53 cannot be represented and is over any limit.
      if (_header[2] != 0 || _header[3] & 0xe0 != 0) return false;
      length = 0;
      for (var k = 2; k < 10; k++) {
        length = length * 256 + _header[k];
      }
    }
    if (opcode >= 0x8) {
      if (length > 125) return false;
    } else {
      if (opcode != 0) _messageBytes = 0;
      _messageBytes += length;
      if (_messageBytes > maxMessageBytes) return false;
      if (fin) _messageBytes = 0;
    }
    _payloadLeft = length;
    return true;
  }
}
