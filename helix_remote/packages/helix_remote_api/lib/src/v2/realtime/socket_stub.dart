import 'package:helix_remote_api/src/v2/realtime/socket.dart';

/// Platforms without `dart:io` (the web build of the admin console) must
/// inject a [RealtimeSocketFactory].
Future<RealtimeSocket> connectPlatformSocket(
  Uri uri, {
  required Map<String, String> headers,
  required List<String> protocols,
}) => throw UnsupportedError(
  'no default WebSocket on this platform; pass a RealtimeSocketFactory',
);
