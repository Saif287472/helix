import 'dart:convert';

import 'package:helix_remote_protocol/src/envelope.dart';
import 'package:helix_remote_protocol/src/json.dart';

/// Realtime protocol v1 (REALTIME_V2.md), JSON frames over the WebSocket
/// subprotocol `helix.v1+json`. Every frame is an object with a `t` (type).
/// Unknown frame types are ignored (and, if they carry a `seq`, acked).
sealed class ServerFrame {
  const ServerFrame();

  String get type;

  JsonMap toJson();

  String encode() => jsonEncode(toJson());

  static ServerFrame decode(String text) {
    final json = JsonReader.decode(text);
    return switch (json.string('t')) {
      'hello' => HelloFrame.fromJson(json),
      'envelope' => EnvelopeFrame.fromJson(json),
      'wake' => const WakeFrame(),
      'pong' => PongFrame(nonce: json.optString('nonce')),
      'error' => ErrorFrame.fromJson(json),
      final type => UnknownServerFrame(type: type, seq: json.optInt('seq')),
    };
  }
}

/// First frame after the upgrade.
final class HelloFrame extends ServerFrame {
  const HelloFrame({
    required this.serverTime,
    required this.heartbeatSeconds,
    required this.window,
    required this.lastSeq,
  });

  final DateTime serverTime;

  /// The client must send something (a ping at least) this often.
  final int heartbeatSeconds;

  /// Maximum un-acked stored envelopes in flight to this connection.
  final int window;

  /// Highest stored `seq` in this device's mailbox at connect time (0 if
  /// empty). Replay of anything after the client's cursor follows.
  final int lastSeq;

  @override
  String get type => 'hello';

  @override
  JsonMap toJson() => {
    't': type,
    'server_time': toWireTime(serverTime),
    'heartbeat_s': heartbeatSeconds,
    'window': window,
    'last_seq': lastSeq,
  };

  factory HelloFrame.fromJson(JsonReader json) => HelloFrame(
    serverTime: json.time('server_time'),
    heartbeatSeconds: json.integer('heartbeat_s'),
    window: json.integer('window'),
    lastSeq: json.integer('last_seq'),
  );
}

/// Delivers one envelope (stored or ephemeral).
final class EnvelopeFrame extends ServerFrame {
  const EnvelopeFrame(this.envelope);

  final Envelope envelope;

  @override
  String get type => 'envelope';

  @override
  JsonMap toJson() => {'t': type, 'envelope': envelope.toJson()};

  factory EnvelopeFrame.fromJson(JsonReader json) =>
      EnvelopeFrame(Envelope.fromJson(json.object('envelope')));
}

/// The mailbox has new envelopes the server did not push on this connection
/// (window full). The client should keep acking or fetch over REST.
final class WakeFrame extends ServerFrame {
  const WakeFrame();

  @override
  String get type => 'wake';

  @override
  JsonMap toJson() => {'t': type};
}

final class PongFrame extends ServerFrame {
  const PongFrame({this.nonce});

  final String? nonce;

  @override
  String get type => 'pong';

  @override
  JsonMap toJson() => compact({'t': type, 'nonce': nonce});
}

/// A protocol problem on this connection. Fatal errors are followed by a
/// close with one of [RealtimeCloseCode].
final class ErrorFrame extends ServerFrame {
  const ErrorFrame({required this.code, this.message});

  /// An `ErrorCode` wire value.
  final String code;
  final String? message;

  @override
  String get type => 'error';

  @override
  JsonMap toJson() => compact({'t': type, 'code': code, 'message': message});

  factory ErrorFrame.fromJson(JsonReader json) =>
      ErrorFrame(code: json.string('code'), message: json.optString('message'));
}

final class UnknownServerFrame extends ServerFrame {
  const UnknownServerFrame({required this.type, this.seq});

  @override
  final String type;
  final int? seq;

  @override
  JsonMap toJson() => compact({'t': type, 'seq': seq});
}

sealed class ClientFrame {
  const ClientFrame();

  String get type;

  JsonMap toJson();

  String encode() => jsonEncode(toJson());

  static ClientFrame decode(String text) {
    final json = JsonReader.decode(text);
    return switch (json.string('t')) {
      'ack' => AckFrame(seq: json.integer('seq')),
      'ping' => PingFrame(nonce: json.optString('nonce')),
      final type => UnknownClientFrame(type: type),
    };
  }
}

/// Cumulative ack: every stored envelope with `seq <= seq` is processed and
/// may be deleted from the mailbox. Also returns window credit.
final class AckFrame extends ClientFrame {
  const AckFrame({required this.seq});

  final int seq;

  @override
  String get type => 'ack';

  @override
  JsonMap toJson() => {'t': type, 'seq': seq};
}

final class PingFrame extends ClientFrame {
  const PingFrame({this.nonce});

  final String? nonce;

  @override
  String get type => 'ping';

  @override
  JsonMap toJson() => compact({'t': type, 'nonce': nonce});
}

final class UnknownClientFrame extends ClientFrame {
  const UnknownClientFrame({required this.type});

  @override
  final String type;

  @override
  JsonMap toJson() => {'t': type};
}

/// WebSocket close codes used by the server.
abstract final class RealtimeCloseCode {
  /// Missing, invalid or expired access token. Refresh, then reconnect.
  static const unauthorized = 4001;

  /// This device was revoked or the account was deleted. Do not reconnect.
  static const deviceRevoked = 4003;

  /// The account is suspended. Reconnect only after the user is told.
  static const suspended = 4004;

  /// Another connection for the same device replaced this one.
  static const superseded = 4008;

  /// Too many connection attempts. Back off (at least 30 s).
  static const rateLimited = 4029;

  /// A frame broke the protocol (bad JSON, unknown required field).
  static const protocolError = 4400;

  /// Server node going away (deploy, restart). Reconnect with backoff.
  static const goingAway = 1001;
}
