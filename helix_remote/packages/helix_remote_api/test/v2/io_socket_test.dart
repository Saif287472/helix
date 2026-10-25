import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:helix_remote_api/src/v2/realtime/io_socket.dart';
import 'package:helix_remote_api/src/v2/realtime/socket.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Future<void> Function(HttpRequest request) handle;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      unawaited(handle(request));
    });
    handle = (request) async => request.response.close();
  });

  tearDown(() => server.close(force: true));

  Uri uri() => Uri.parse('ws://127.0.0.1:${server.port}/v1/ws');

  Future<RealtimeSocket> connect({Duration? timeout}) => connectPlatformSocket(
    uri(),
    headers: const {},
    protocols: const [realtimeSubprotocolJson],
    timeout: timeout ?? const Duration(seconds: 5),
  );

  /// Answers the upgrade by hand: `dart:io` will not write a 101 itself.
  Future<Socket> acceptUpgrade(
    HttpRequest request, {
    String? protocol,
    String? accept,
  }) async {
    final key = request.headers.value('sec-websocket-key')!;
    final expected = base64.encode(
      sha1
          .convert(ascii.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))
          .bytes,
    );
    final socket = await request.response.detachSocket(writeHeaders: false);
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n'
      'Connection: Upgrade\r\n'
      'Upgrade: websocket\r\n'
      'Sec-WebSocket-Accept: ${accept ?? expected}\r\n'
      '${protocol == null ? '' : 'Sec-WebSocket-Protocol: $protocol\r\n'}'
      '\r\n',
    );
    await socket.flush();
    return socket;
  }

  test(
    'a refusal whose body stalls is abandoned within the deadline',
    () async {
      handle = (request) async {
        final response = request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentLength = 64;
        unawaited(response.done.catchError((Object _) {}));
        await response.flush();
        // Never writes the body.
      };
      final watch = Stopwatch()..start();
      await expectLater(
        connect(timeout: const Duration(milliseconds: 200)),
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    },
  );

  test(
    'a 101 that omits or rewrites the offered subprotocol is refused',
    () async {
      for (final protocol in <String?>[null, 'helix.v2+json']) {
        handle = (request) async {
          final socket = await acceptUpgrade(request, protocol: protocol);
          socket.destroy();
        };
        await expectLater(
          connect(),
          throwsA(
            isA<WebSocketException>().having(
              (e) => e.message,
              'message',
              contains('Sec-WebSocket-Protocol'),
            ),
          ),
          reason: 'server answered with $protocol',
        );
      }
    },
  );

  test(
    'an accepted upgrade keeps a live socket after the client is closed',
    () async {
      final firstFrame = Completer<List<int>>();
      handle = (request) async {
        final socket = await acceptUpgrade(
          request,
          protocol: realtimeSubprotocolJson,
        );
        socket.listen((bytes) {
          if (!firstFrame.isCompleted) firstFrame.complete(bytes);
        }, onError: (Object _) {});
      };
      final socket = await connect();
      expect(socket.protocol, realtimeSubprotocolJson);
      socket.send('{"type":"ping"}');
      final frame = await firstFrame.future.timeout(const Duration(seconds: 5));
      expect(frame.first & 0x0f, 1, reason: 'a masked text frame');
      await socket.close(1000);
    },
  );
}
