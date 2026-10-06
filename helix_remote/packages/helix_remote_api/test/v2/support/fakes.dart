import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One request the fake server saw.
final class Seen {
  Seen(this.request);

  final http.Request request;

  String get method => request.method;
  Uri get url => request.url;
  Map<String, String> get headers => request.headers;
  String get body => request.body;

  String? get bearer {
    final value = headers[HelixHeaders.authorization];
    return value?.substring('Bearer '.length);
  }

  @override
  String toString() => '$method ${url.path}';
}

typedef Handler = FutureOr<http.Response> Function(Seen request);

/// An HTTP client that answers from [handler] and records every request.
final class FakeHttp {
  FakeHttp([Handler? handler]) : handler = handler ?? ((_) => ok({}));

  Handler handler;
  final List<Seen> seen = [];

  late final http.Client client = MockClient((request) async {
    final s = Seen(request);
    seen.add(s);
    return handler(s);
  });
}

http.Response ok(
  Object? json, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(
  jsonEncode(json),
  status,
  headers: {'content-type': 'application/json', ...?headers},
);

http.Response noContent() => http.Response('', 204);

http.Response apiError(
  ErrorCode code, {
  JsonMap? details,
  Duration? retryAfter,
  bool header = true,
  int? status,
}) => http.Response(
  jsonEncode(
    ApiError(
      code,
      message: 'x',
      details: details,
      retryAfter: retryAfter,
    ).toJson(),
  ),
  status ?? code.status,
  headers: {
    'content-type': 'application/json',
    if (retryAfter != null && header)
      HelixHeaders.retryAfter: '${retryAfter.inSeconds}',
  },
);

Session session(String access, {Duration ttl = const Duration(minutes: 15)}) =>
    Session(
      accountId: 'a',
      deviceId: 'd',
      accessToken: access,
      accessExpiresAt: DateTime.now().add(ttl),
      refreshToken: 'refresh-$access',
      refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
    );

/// A WebSocket the test drives from the server side.
final class FakeSocket implements RealtimeSocket {
  FakeSocket({this.protocol = realtimeSubprotocolJson});

  @override
  final String? protocol;

  final StreamController<String> _incoming = StreamController();
  final List<String> sent = [];
  bool closedByClient = false;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  Stream<String> get messages => _incoming.stream;

  List<ClientFrame> get frames => [for (final s in sent) ClientFrame.decode(s)];

  List<int> get acks => [
    for (final f in frames)
      if (f is AckFrame) f.seq,
  ];

  int get pings => frames.whereType<PingFrame>().length;

  void push(ServerFrame frame) => _incoming.add(frame.encode());

  void pushRaw(String text) => _incoming.add(text);

  void hello({int window = 100, int lastSeq = 0, int heartbeat = 25}) => push(
    HelloFrame(
      serverTime: DateTime.utc(2026),
      heartbeatSeconds: heartbeat,
      window: window,
      lastSeq: lastSeq,
    ),
  );

  void envelope(int? seq, {EnvelopeKind kind = EnvelopeKind.message}) => push(
    EnvelopeFrame(
      Envelope(id: 'e$seq', kind: kind, sentAt: DateTime.utc(2026), seq: seq),
    ),
  );

  /// The server closes with [code].
  void serverClose(int? code, [String? reason]) {
    closeCode = code;
    closeReason = reason;
    unawaited(_incoming.close());
  }

  @override
  void send(String text) {
    if (!_incoming.isClosed) sent.add(text);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closedByClient = true;
    closeCode ??= code;
    if (!_incoming.isClosed) await _incoming.close();
  }
}

/// Hands out sockets in order (or throws what [failures] says) and records
/// each connection attempt.
final class FakeSockets {
  final List<Object> _queue = [];
  final List<Uri> uris = [];
  final List<Map<String, String>> headers = [];
  final List<List<String>> protocols = [];
  final List<FakeSocket> opened = [];

  /// The next connection gets [socket] (default a fresh one).
  FakeSocket next([FakeSocket? socket]) {
    final s = socket ?? FakeSocket();
    _queue.add(s);
    return s;
  }

  /// The next connection fails with [error].
  void fail(Object error) => _queue.add(error);

  Future<RealtimeSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
    required List<String> protocols,
  }) async {
    uris.add(uri);
    this.headers.add(headers);
    this.protocols.add(protocols);
    final item = _queue.isEmpty ? FakeSocket() : _queue.removeAt(0);
    if (item is FakeSocket) {
      opened.add(item);
      return item;
    }
    throw item;
  }
}

/// A fixed-token device auth that counts refreshes.
final class CountingAuth implements AuthProvider {
  CountingAuth({
    this.token = 't1',
    this.refreshTo = 't2',
    this.signOut = false,
  });

  String token;
  String refreshTo;
  bool signOut;
  int refreshes = 0;

  @override
  RouteAccess get audience => RouteAccess.device;

  @override
  Future<String> accessToken() async => token;

  @override
  Future<String> refresh(String rejected) async {
    refreshes++;
    if (signOut) {
      throw const SignedOutException(SignedOutReason.refreshRejected);
    }
    return token = refreshTo;
  }
}
