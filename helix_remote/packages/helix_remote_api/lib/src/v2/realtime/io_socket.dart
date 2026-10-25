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
///
/// [timeout] bounds the response headers and the body of a refusal (a server
/// that answers and then stalls must not hold the caller in `connecting`).
Future<RealtimeSocket> connectPlatformSocket(
  Uri uri, {
  required Map<String, String> headers,
  required List<String> protocols,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = null;
  final random = Random.secure();
  final nonce = base64.encode([
    for (var i = 0; i < 16; i++) random.nextInt(256),
  ]);
  var detached = false;
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
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.switchingProtocols) {
      final body = await _readCapped(response, 64 * 1024, timeout: timeout);
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
    // The server's choice must be one that was offered (RFC 6455, 4.2.2):
    // an intermediary that drops or rewrites it must not get a connection.
    final protocol = response.headers.value('sec-websocket-protocol');
    final agreed = protocol == null
        ? protocols.isEmpty
        : protocols.contains(protocol);
    if (!agreed) {
      (await response.detachSocket()).destroy();
      throw WebSocketException('bad Sec-WebSocket-Protocol: $protocol');
    }
    final socket = await response.detachSocket();
    detached = true;
    return _IoSocket(
      WebSocket.fromUpgradedSocket(
        socket,
        protocol: protocol,
        serverSide: false,
      ),
    );
  } finally {
    // A graceful close leaves a timed-out or refused request running; an
    // upgraded connection is detached from the client already.
    client.close(force: !detached);
  }
}

/// Reads at most [max] bytes of a refusal body, giving up after [timeout]:
/// the subscription is cancelled whatever ends the read.
Future<List<int>> _readCapped(
  Stream<List<int>> stream,
  int max, {
  required Duration timeout,
}) async {
  final bytes = <int>[];
  final done = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
  final timer = Timer(timeout, () {
    unawaited(subscription.cancel());
    if (!done.isCompleted) {
      done.completeError(TimeoutException('refusal body', timeout));
    }
  });
  subscription = stream.listen(
    (chunk) {
      bytes.addAll(chunk.take(max - bytes.length));
      if (bytes.length >= max) {
        timer.cancel();
        unawaited(subscription.cancel());
        if (!done.isCompleted) done.complete();
      }
    },
    onError: (Object error, StackTrace stack) {
      timer.cancel();
      if (!done.isCompleted) done.completeError(error, stack);
    },
    onDone: () {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );
  try {
    await done.future;
  } finally {
    timer.cancel();
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
