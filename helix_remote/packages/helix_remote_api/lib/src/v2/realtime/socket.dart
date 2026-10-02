import 'dart:async';

import 'package:helix_remote_api/src/v2/realtime/socket_stub.dart'
    if (dart.library.io) 'package:helix_remote_api/src/v2/realtime/io_socket.dart'
    as platform;
import 'package:helix_remote_api/src/v2/transport/errors.dart';

/// One WebSocket connection, as the realtime client needs it. Tests inject
/// fakes through [RealtimeSocketFactory].
abstract interface class RealtimeSocket {
  /// The negotiated subprotocol.
  String? get protocol;

  /// Text frames from the server (binary frames are dropped). Done when
  /// the socket closes; [closeCode] is set by then.
  Stream<String> get messages;

  void send(String text);

  Future<void> close([int? code, String? reason]);

  int? get closeCode;

  String? get closeReason;
}

/// Opens a socket to [uri] (`ws`/`wss`) with [headers] (the bearer token)
/// and the offered [protocols]. Throws [RealtimeUpgradeException] when the
/// server answers the upgrade with an HTTP error; any other exception means
/// the server could not be reached.
typedef RealtimeSocketFactory =
    Future<RealtimeSocket> Function(
      Uri uri, {
      required Map<String, String> headers,
      required List<String> protocols,
    });

/// `dart:io` sockets where available (Android, Windows, the CLI); elsewhere
/// it throws [UnsupportedError] and the caller must inject a factory.
const RealtimeSocketFactory defaultSocketFactory =
    platform.connectPlatformSocket;

/// The server refused the WebSocket upgrade with an HTTP error, e.g. 401
/// for an expired token or 403 `device_revoked`.
final class RealtimeUpgradeException implements Exception {
  const RealtimeUpgradeException(this.error);

  final ApiException error;

  @override
  String toString() => 'RealtimeUpgradeException($error)';
}
