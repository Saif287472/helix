import 'dart:async';
import 'dart:math' as math;

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/presence.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/http/websocket_limits.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The WebSocket gateway (REALTIME_V2.md). Stateless across nodes: which
/// node holds a device's socket is a route in the ephemeral store, and
/// nodes reach each other's sockets through the event bus.
final class RealtimeModule extends ModuleBase {
  RealtimeModule(
    super.context, {
    required this.messaging,
    required this.authenticator,
    EventBus? bus,
    Uptime? uptime,
  }) {
    _bus = bus ?? context.bus;
    _uptime = uptime ?? StopwatchUptime();
    _connected = context.metrics.counter(
      'helix_ws_connections_total',
      'WebSocket connections opened',
    );
    _refreshSkipped = context.metrics.counter(
      'helix_ws_refresh_skipped_total',
      'Route refresh ticks skipped because one was still running',
    );
    context.metrics.gauge(
      'helix_ws_open',
      'WebSocket connections open on this node',
      () => _connections.length.toDouble(),
    );
  }

  final MessagingApi messaging;

  /// Re-checks each socket's access token (expiry, session cut-off,
  /// suspension) on every route refresh and when sessions end.
  final Authenticator authenticator;

  /// The platform bus, unless a test replaces it.
  late final EventBus _bus;

  /// Frame-bucket and idle timing; monotonic, so a wall-clock step cannot
  /// close a well-behaved socket (AUD-3-9).
  late final Uptime _uptime;
  final Map<String, _Connection> _connections = {};
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Set<Future<void>> _tasks = {};
  Timer? _routeTimer;
  Timer? _nodeTimer;
  bool _refreshing = false;
  late final Counter _connected;
  late final Counter _refreshSkipped;

  static const heartbeat = Duration(seconds: 25);
  static const window = 100;
  static const _supersededTopic = 'realtime.connected';

  /// Upgrades per device; over it the socket opens and closes with 4029.
  static final upgradeLimit = RateLimitPolicy.per(
    'realtime.upgrade',
    20,
    const Duration(minutes: 10),
  );

  /// Client frames per connection: a burst of [frameBurst], refilled at
  /// [framesPerSecond]. Over it the socket closes with 4029.
  static const frameBurst = 300;
  static const framesPerSecond = 30;

  String get nodeId => context.config.nodeId;

  @override
  String get name => 'realtime';

  @override
  void routes(RouteRegistry r) {
    r.add(name, Routes.websocket, _upgrade, allowSuspended: true);
  }

  @override
  Future<void> start() async {
    final bus = _bus;
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
          final ref = m['r']! as String;
          for (final device in (m['d']! as List).cast<String>()) {
            final connection = _connections[device];
            if (connection != null) {
              track(() => connection.deliverEphemeral(ref));
            }
          }
        }),
      )
      ..add(
        bus.subscribe(IdentityTopics.sessionsEnded).listen((m) {
          final connection = _connections[m['device']];
          if (connection != null) track(connection.checkSession);
        }),
      )
      ..add(
        bus.subscribe(IdentityTopics.accountSuspended).listen((m) {
          for (final c in _connections.values.toList()) {
            if (c.accountId == m['account'] && !c.suspended) {
              track(
                () => c.close(RealtimeCloseCode.suspended, 'account suspended'),
              );
            }
          }
        }),
      )
      ..add(
        bus.subscribe(IdentityTopics.deviceRevoked).listen((m) {
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
        // The bus connection came back: wake-ups may have been missed, so
        // every socket checks its mailbox again.
        bus.subscribe(EventBus.resyncTopic).listen((_) {
          for (final c in _connections.values.toList()) {
            c.pump();
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
      (_) => track(refreshConnections),
    );
    await keepAlive();
    _nodeTimer = Timer.periodic(Presence.nodeRefresh, (_) => track(keepAlive));
  }

  /// Renews this node's liveness key. Presence reads it: a route on a node
  /// that stopped beating is treated as offline (AUD-3-3).
  Future<void> keepAlive() =>
      context.ephemeral.put(Presence.nodeKey(nodeId), '1', Presence.nodeTtl);

  /// Test hook: stops both refreshers and leaves every key they wrote behind,
  /// as a node that died where it stood does.
  void stallRefreshers() {
    _routeTimer?.cancel();
    _nodeTimer?.cancel();
  }

  @override
  Future<void> stop() async {
    _routeTimer?.cancel();
    _nodeTimer?.cancel();
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
    // Only now: while the sockets were still open the node was still alive.
    await context.ephemeral.delete(Presence.nodeKey(nodeId));
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

  /// Every 25 s (public for tests): refreshes each socket's route and
  /// closes sockets that were superseded elsewhere (4008), whose token
  /// expired or predates a session cut-off (4001), whose account was
  /// suspended (4004) or that went quiet (4010). A full window re-checks
  /// for credit that REST acks released.
  ///
  /// A tick that arrives while a pass is still running is skipped and
  /// counted: the pass awaits a store CAS and a token check per socket, so
  /// one stalled pass would otherwise overlap the next and double that
  /// traffic at the worst moment (AUD-3-4).
  Future<void> refreshConnections() async {
    if (_refreshing) {
      _refreshSkipped.inc();
      return;
    }
    _refreshing = true;
    try {
      for (final c in _connections.values.toList()) {
        if (!await c.refreshRoute()) continue;
        if (!await c.checkSession()) continue;
        c.checkIdle();
        c.reconcileCredit();
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<Response> _upgrade(HelixRequest q) async {
    final principal = q.device;
    final after = int.tryParse(q.query('after') ?? '') ?? 0;
    // The route authenticated this bearer token; keep it to re-check.
    final token = q.raw.headers[HelixHeaders.authorization]!
        .substring(7)
        .trim();
    final handler = webSocketHandler(
      (WebSocketChannel ws, String? protocol) {
        if (protocol != realtimeSubprotocolJson) {
          ws.sink.close(
            RealtimeCloseCode.protocolError,
            'use subprotocol $realtimeSubprotocolJson',
          );
          return;
        }
        // Checked after the upgrade: an await before the hijack would let the
        // adapter answer the request first.
        track(() async {
          final allowed = (await context.rateLimiter.hit(
            upgradeLimit,
            principal.deviceId,
          )).allowed;
          if (!allowed) {
            await ws.sink.close(
              RealtimeCloseCode.rateLimited,
              'too many connections',
            );
            return;
          }
          await _accept(ws, principal, token, after);
        });
      },
      protocols: const [realtimeSubprotocolJson],
      pingInterval: const Duration(seconds: 30),
    );
    return handler(
      limitWebSocketFrames(q.raw, maxMessageBytes: maxClientMessageBytes),
    );
  }

  /// Largest message a client may send (S7 #15). Client frames are acks and
  /// pings of a few dozen bytes; anything over this closes the connection
  /// before it is buffered.
  static const maxClientMessageBytes = 64 * 1024;

  Future<void> _accept(
    WebSocketChannel ws,
    DevicePrincipal principal,
    String token,
    int requested,
  ) async {
    // A cursor from before a database restore replays from the start
    // (REALTIME_V2.md, "Restored server"); hello tells the client so.
    final (:after, :head) = await messaging.resume(
      principal.deviceId,
      requested,
    );
    final connection = _Connection(
      this,
      ws,
      principal,
      token,
      Uuid.v7(),
      after,
      head,
    );
    final previous = _connections[principal.deviceId];
    _connections[principal.deviceId] = connection;
    _connected.inc();
    try {
      // The route first: once it names this connection, a later failure
      // closes it and takes that route with it. Closing the previous socket
      // first would leave its route behind if the save then failed.
      await connection.saveRoute();
      await previous?.close(
        RealtimeCloseCode.superseded,
        'replaced by a newer connection',
      );
      await _bus.publish(_supersededTopic, {
        'd': principal.deviceId,
        'c': connection.id,
      });
      await connection.start();
    } on Object {
      // Registered but never started: presence would call this device
      // online while nothing reaches it and no hello ever arrives
      // (AUD-3-10). Closing drops the map entry and the route.
      await connection.close(
        RealtimeCloseCode.goingAway,
        'connection setup failed',
      );
      rethrow;
    }
  }

  Future<void> _closed(_Connection connection) async {
    if (_connections[connection.deviceId] == connection) {
      _connections.remove(connection.deviceId);
      // Only this connection's route: a newer socket elsewhere keeps its.
      await context.ephemeral.deleteIf(
        Presence.routeKey(connection.deviceId),
        connection.routeValue,
      );
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
    this._token,
    this.id,
    this._lastSent,
    this._head,
  ) : deviceId = principal.deviceId,
      accountId = principal.accountId,
      suspended = principal.suspended {
    _frameAt = _m._uptime.elapsed;
    _lastHeard = _frameAt;
  }

  final RealtimeModule _m;
  final WebSocketChannel _ws;

  /// The access token the socket opened with. Never logged.
  final String _token;
  final String id;
  final String deviceId;
  final String accountId;

  /// The account was already suspended when the socket opened.
  final bool suspended;
  int _lastSent;

  /// The device's sequence head at connect time, sent in `hello`.
  final int _head;
  double _frameTokens = RealtimeModule.frameBurst.toDouble();

  /// When the frame bucket was last refilled, and when a client frame was
  /// last heard. Both are monotonic marks, never wall-clock times.
  late Duration _frameAt;
  final List<int> _unacked = [];
  late Duration _lastHeard;
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

  /// Extends the route only while it is still this connection's
  /// (compare-and-set), so a late refresh never overwrites a newer
  /// connection's route on another node. An expired route is restored; one
  /// held by another connection means this one was superseded (4008).
  /// False if the socket is closed.
  Future<bool> refreshRoute() async {
    final store = _m.context.ephemeral;
    final key = Presence.routeKey(deviceId);
    if (await store.replace(key, routeValue, routeValue, Presence.routeTtl) ||
        await store.putIfAbsent(key, routeValue, Presence.routeTtl)) {
      return !_closed;
    }
    await close(RealtimeCloseCode.superseded, 'replaced by a newer connection');
    return false;
  }

  /// Closes the socket if its token no longer authenticates (expired, or
  /// issued before a session cut-off: 4001), or if the account was
  /// suspended since it opened (4004). False if the socket is closed.
  Future<bool> checkSession() async {
    if (_closed) return false;
    final principal = await _m.authenticator.device(_token);
    if (principal == null) {
      await close(RealtimeCloseCode.unauthorized, 'session ended');
      return false;
    }
    if (principal.suspended && !suspended) {
      await close(RealtimeCloseCode.suspended, 'account suspended');
      return false;
    }
    return !_closed;
  }

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
        seqHead: _head,
      ),
    );
    pump();
  }

  void _onFrame(Object? data) {
    final now = _m._uptime.elapsed;
    final since = now - _frameAt;
    _frameAt = now;
    _lastHeard = now;
    _frameTokens = math.min(
      RealtimeModule.frameBurst.toDouble(),
      _frameTokens +
          (since.isNegative ? 0 : since.inMicroseconds) /
              1e6 *
              RealtimeModule.framesPerSecond,
    );
    if (_frameTokens < 1) {
      _m.track(() => close(RealtimeCloseCode.rateLimited, 'too many frames'));
      return;
    }
    _frameTokens -= 1;
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
        var credit = RealtimeModule.window - _unacked.length;
        if (credit <= 0) {
          await _dropAckedElsewhere();
          credit = RealtimeModule.window - _unacked.length;
        }
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

  /// Envelopes acked over REST (on any node) are gone from the mailbox, so
  /// their credit returns: un-acked seqs below the oldest stored envelope
  /// were acked (or expired) elsewhere.
  Future<void> _dropAckedElsewhere() async {
    final oldest = await _m.messaging.fetch(deviceId, after: 0, limit: 1);
    if (oldest.isEmpty) {
      _unacked.clear();
    } else {
      _unacked.removeWhere((s) => s < oldest.single.seq!);
    }
  }

  /// A full window may have been freed by REST acks; pumping re-checks.
  void reconcileCredit() {
    if (_unacked.length >= RealtimeModule.window) pump();
  }

  Future<void> deliverEphemeral(String ref) async {
    final envelope = await _m.messaging.takeEphemeral(ref, deviceId);
    if (envelope != null) _send(EnvelopeFrame(envelope));
  }

  void checkIdle() {
    if (_m._uptime.elapsed - _lastHeard > RealtimeModule.heartbeat * 2) {
      _m.track(() => close(RealtimeCloseCode.idleTimeout, 'no heartbeat'));
    }
  }

  Future<void> close(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    try {
      await _ws.sink.close(code, reason);
    } finally {
      // Whatever the socket does, the route goes, so the device is not
      // reported online while nothing reaches it.
      await _finish();
    }
  }

  Future<void> _finish() async {
    _closed = true;
    if (_finished) return;
    _finished = true;
    await _m._closed(this);
  }
}
