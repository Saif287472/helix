import 'dart:async';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/presence.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The WebSocket gateway (REALTIME_V2.md). Stateless across nodes: which
/// node holds a device's socket is a route in the ephemeral store, and
/// nodes reach each other's sockets through the event bus.
final class RealtimeModule extends ModuleBase {
  RealtimeModule(super.context, {required this.messaging}) {
    _connected = context.metrics.counter(
      'helix_ws_connections_total',
      'WebSocket connections opened',
    );
    context.metrics.gauge(
      'helix_ws_open',
      'WebSocket connections open on this node',
      () => _connections.length.toDouble(),
    );
  }

  final MessagingApi messaging;
  final Map<String, _Connection> _connections = {};
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Set<Future<void>> _tasks = {};
  Timer? _routeTimer;
  late final Counter _connected;

  static const heartbeat = Duration(seconds: 25);
  static const window = 100;
  static const _supersededTopic = 'realtime.connected';
  static const _revokedTopic = 'device.revoked';

  String get nodeId => context.config.nodeId;

  @override
  String get name => 'realtime';

  @override
  void routes(RouteRegistry r) {
    r.add(name, Routes.websocket, _upgrade, allowSuspended: true);
  }

  @override
  Future<void> start() async {
    final bus = context.bus;
    _subscriptions
      ..add(
        bus.subscribe(MailboxTopics.wake).listen((m) {
          for (final device in (m['d']! as List).cast<String>()) {
            _connections[device]?.pump();
          }
        }),
      )
      ..add(
        bus.subscribe(MailboxTopics.ephemeral).listen((m) {
          final connection = _connections[m['d']];
          if (connection != null) {
            track(() => connection.deliverEphemeral(m['r']! as String));
          }
        }),
      )
      ..add(
        bus.subscribe(_revokedTopic).listen((m) {
          final revoked = _connections[m['device']];
          if (revoked != null) {
            track(
              () => revoked.close(
                RealtimeCloseCode.deviceRevoked,
                'device revoked',
              ),
            );
          }
        }),
      )
      ..add(
        bus.subscribe(_supersededTopic).listen((m) {
          final existing = _connections[m['d']];
          if (existing != null && existing.id != m['c']) {
            track(
              () => existing.close(
                RealtimeCloseCode.superseded,
                'replaced by a newer connection',
              ),
            );
          }
        }),
      );
    _routeTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => track(_refreshRoutes),
    );
  }

  @override
  Future<void> stop() async {
    _routeTimer?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    for (final c in _connections.values.toList()) {
      await c.close(RealtimeCloseCode.goingAway, 'server shutting down');
    }
    // Let per-connection work (acks, cleanups) finish before the platform
    // closes the database.
    while (_tasks.isNotEmpty) {
      await Future.wait(_tasks.toList());
    }
  }

  /// Runs [work] for a connection, tracked so [stop] can wait for it.
  /// Errors are logged, never thrown into the socket's zone.
  void track(Future<void> Function() work) {
    late final Future<void> tracked;
    tracked = Future<void>(work)
        .catchError(
          (Object e) => log.warn('realtime_task_failed', {
            'error': e.runtimeType.toString(),
          }),
        )
        .whenComplete(() => _tasks.remove(tracked));
    _tasks.add(tracked);
  }

  Future<void> _refreshRoutes() async {
    for (final c in _connections.values.toList()) {
      await c.saveRoute();
      c.checkIdle();
    }
  }

  Future<Response> _upgrade(HelixRequest q) async {
    final principal = q.device;
    final after = int.tryParse(q.query('after') ?? '') ?? 0;
    final handler = webSocketHandler(
      (WebSocketChannel ws, String? protocol) {
        if (protocol != realtimeSubprotocolJson) {
          ws.sink.close(
            RealtimeCloseCode.protocolError,
            'use subprotocol $realtimeSubprotocolJson',
          );
          return;
        }
        track(() => _accept(ws, principal, after));
      },
      protocols: const [realtimeSubprotocolJson],
      pingInterval: const Duration(seconds: 30),
    );
    return handler(q.raw);
  }

  Future<void> _accept(
    WebSocketChannel ws,
    DevicePrincipal principal,
    int after,
  ) async {
    final connection = _Connection(this, ws, principal, Uuid.v7(), after);
    final previous = _connections[principal.deviceId];
    _connections[principal.deviceId] = connection;
    _connected.inc();
    await previous?.close(
      RealtimeCloseCode.superseded,
      'replaced by a newer connection',
    );
    await connection.saveRoute();
    await context.bus.publish(_supersededTopic, {
      'd': principal.deviceId,
      'c': connection.id,
    });
    await connection.start();
  }

  Future<void> _closed(_Connection connection) async {
    if (_connections[connection.deviceId] == connection) {
      _connections.remove(connection.deviceId);
      final key = Presence.routeKey(connection.deviceId);
      if (await context.ephemeral.get(key) == connection.routeValue) {
        await context.ephemeral.delete(key);
      }
      await context.ephemeral.put(
        Presence.lastSeenKey(connection.accountId),
        '${context.clock.now().millisecondsSinceEpoch}',
        const Duration(days: 90),
      );
    }
  }
}

/// One device's socket. Stored envelopes flow oldest first, at most
/// [RealtimeModule.window] un-acked at a time; acks delete them.
final class _Connection {
  _Connection(
    this._m,
    this._ws,
    DevicePrincipal principal,
    this.id,
    this._lastSent,
  ) : deviceId = principal.deviceId,
      accountId = principal.accountId;

  final RealtimeModule _m;
  final WebSocketChannel _ws;
  final String id;
  final String deviceId;
  final String accountId;
  int _lastSent;
  final List<int> _unacked = [];
  DateTime _lastHeard = DateTime.now();
  bool _closed = false;
  bool _finished = false;
  bool _pumping = false;
  bool _again = false;

  String get routeValue => '${_m.nodeId}|$id';

  Future<void> saveRoute() => _m.context.ephemeral.put(
    Presence.routeKey(deviceId),
    routeValue,
    Presence.routeTtl,
  );

  void _send(ServerFrame frame) {
    if (!_closed) _ws.sink.add(frame.encode());
  }

  Future<void> start() async {
    _ws.stream.listen(
      _onFrame,
      onDone: () => _m.track(_finish),
      onError: (Object _) => _m.track(_finish),
      cancelOnError: true,
    );
    _send(
      HelloFrame(
        serverTime: _m.context.clock.now(),
        heartbeatSeconds: RealtimeModule.heartbeat.inSeconds,
        window: RealtimeModule.window,
        lastSeq: await _m.messaging.lastSeq(deviceId),
      ),
    );
    pump();
  }

  void _onFrame(Object? data) {
    _lastHeard = DateTime.now();
    if (data is! String) {
      _m.track(
        () => close(RealtimeCloseCode.protocolError, 'text frames only'),
      );
      return;
    }
    final ClientFrame frame;
    try {
      frame = ClientFrame.decode(data);
    } on FormatException {
      _m.track(() => close(RealtimeCloseCode.protocolError, 'malformed frame'));
      return;
    }
    switch (frame) {
      case AckFrame(:final seq):
        _m.track(() => _ack(seq));
      case PingFrame(:final nonce):
        _send(PongFrame(nonce: nonce));
      case UnknownClientFrame():
        break;
    }
  }

  Future<void> _ack(int seq) async {
    await _m.messaging.ack(deviceId, seq);
    _unacked.removeWhere((s) => s <= seq);
    pump();
  }

  /// Sends stored envelopes after the last one sent, within the window.
  void pump() {
    if (_closed) return;
    if (_pumping) {
      _again = true;
      return;
    }
    _pumping = true;
    _m.track(_drain);
  }

  Future<void> _drain() async {
    try {
      do {
        _again = false;
        final credit = RealtimeModule.window - _unacked.length;
        if (credit <= 0) {
          _send(const WakeFrame());
          break;
        }
        final envelopes = await _m.messaging.fetch(
          deviceId,
          after: _lastSent,
          limit: credit,
        );
        for (final envelope in envelopes) {
          _send(EnvelopeFrame(envelope));
          _lastSent = envelope.seq!;
          _unacked.add(envelope.seq!);
        }
        if (envelopes.length == credit) _again = true;
      } while (_again && !_closed);
    } on Object {
      await close(RealtimeCloseCode.goingAway, 'delivery failed');
    } finally {
      _pumping = false;
    }
  }

  Future<void> deliverEphemeral(String ref) async {
    final envelope = await _m.messaging.takeEphemeral(ref);
    if (envelope != null) _send(EnvelopeFrame(envelope));
  }

  void checkIdle() {
    if (DateTime.now().difference(_lastHeard) > RealtimeModule.heartbeat * 2) {
      _m.track(() => close(RealtimeCloseCode.idleTimeout, 'no heartbeat'));
    }
  }

  Future<void> close(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    await _ws.sink.close(code, reason);
    await _finish();
  }

  Future<void> _finish() async {
    _closed = true;
    if (_finished) return;
    _finished = true;
    await _m._closed(this);
  }
}
