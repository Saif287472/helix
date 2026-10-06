import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:helix_remote_api/src/v2/realtime/socket.dart';
import 'package:helix_remote_api/src/v2/transport/errors.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `dart:io` socket. The upgrade is done by hand (as `WebSocket.connect`
/// does internally) so that a refused upgrade surfaces its HTTP status and
/// v2 error code: a 401 means "refresh the token", a 403 `device_revoked`
/// means "stop", and `WebSocket.connect` reports both as the same
/// `WebSocketException`.
Future<RealtimeSocket> connectPlatformSocket(
  Uri uri, {
  required Map<String, String> headers,
  required List<String> protocols,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = null;
  final random = Random.secure();
  final nonce = base64.encode([
    for (var i = 0; i < 16; i++) random.nextInt(256),
  ]);
  try {
    final request = await client.openUrl(
      'GET',
      uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http'),
    );
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('sec-websocket-key', nonce)
      ..set('sec-websocket-version', '13')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (protocols.isNotEmpty) {
      request.headers.set('sec-websocket-protocol', protocols.join(', '));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.switchingProtocols) {
      final body = await _readCapped(response, 64 * 1024);
      throw RealtimeUpgradeException(
        ApiException.fromResponse(
          status: response.statusCode,
          body: body,
          retryAfterHeader: response.headers.value(HelixHeaders.retryAfter),
          requestId: response.headers.value(HelixHeaders.requestId),
        ),
      );
    }
    final expected = base64.encode(
      sha1
          .convert(ascii.encode('${nonce}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))
          .bytes,
    );
    if (response.headers.value('sec-websocket-accept') != expected) {
      (await response.detachSocket()).destroy();
      throw const WebSocketException('bad Sec-WebSocket-Accept');
    }
    final protocol = response.headers.value('sec-websocket-protocol');
    final socket = await response.detachSocket();
    return _IoSocket(
      WebSocket.fromUpgradedSocket(
        socket,
        protocol: protocol,
        serverSide: false,
      ),
    );
  } finally {
    client.close();
  }
}

Future<List<int>> _readCapped(Stream<List<int>> stream, int max) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk.take(max - bytes.length));
    if (bytes.length >= max) break;
  }
  return bytes;
}

final class _IoSocket implements RealtimeSocket {
  _IoSocket(this._ws);

  final WebSocket _ws;

  @override
  late final Stream<String> messages = _ws
      .where((message) => message is String)
      .cast<String>()
      .handleError((Object _) {});

  @override
  String? get protocol => _ws.protocol;

  @override
  void send(String text) {
    if (_ws.readyState == WebSocket.open) _ws.add(text);
  }

  @override
  Future<void> close([int? code, String? reason]) => _ws.close(code, reason);

  @override
  int? get closeCode => _ws.closeCode;

  @override
  String? get closeReason => _ws.closeReason;
}
