import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:helix_remote_api/src/v2/realtime/socket.dart';
import 'package:helix_remote_api/src/v2/transport/auth.dart';
import 'package:helix_remote_api/src/v2/transport/errors.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

enum RealtimePhase {
  /// Not started.
  idle,

  /// Opening the socket, or waiting for `hello`.
  connecting,

  /// `hello` received; envelopes flow.
  connected,

  /// Waiting [RealtimeState.retryIn] before reconnecting.
  waiting,

  /// 4004: the account was suspended. Tell the user; [RealtimeClient.reconnect]
  /// connects again (read-only) once they have been told.
  suspended,

  /// 4008: another connection for this device replaced this one. Not
  /// fought over: [RealtimeClient.reconnect] takes the socket back (e.g. on
  /// app resume).
  superseded,

  /// 4003 (or a 403 on upgrade): the device was revoked or the account
  /// deleted. Never reconnects; sign out locally.
  revoked,

  /// The token could not be refreshed. Never reconnects; show sign-in.
  signedOut,

  /// [RealtimeClient.stop] was called.
  stopped,
}

final class RealtimeState {
  const RealtimeState(
    this.phase, {
    this.closeCode,
    this.retryIn,
    this.attempt = 0,
    this.hello,
    this.error,
  });

  final RealtimePhase phase;

  /// Close code of the connection that just ended.
  final int? closeCode;

  /// Set while [RealtimePhase.waiting].
  final Duration? retryIn;

  /// Consecutive failed connections.
  final int attempt;

  /// The current connection's `hello` (while connected).
  final HelloFrame? hello;

  /// Why the last connection failed, when it was not a close code.
  final Object? error;

  @override
  String toString() =>
      'RealtimeState(${phase.name}'
      '${closeCode == null ? '' : ', close $closeCode'}'
      '${retryIn == null ? '' : ', retry in ${retryIn!.inMilliseconds} ms'})';
}

/// A protocol problem worth reporting: a 4400 close (the client sent
/// something the server could not parse), an `error` frame, or a frame this
/// client could not parse.
final class RealtimeProtocolError {
  const RealtimeProtocolError(this.source, {this.code, this.message});

  /// `close_4400`, `error_frame` or `bad_frame`.
  final String source;
  final String? code;
  final String? message;

  @override
  String toString() =>
      'RealtimeProtocolError($source${code == null ? '' : ', $code'})';
}

/// Reconnect timing (REALTIME_V2.md): 1 s doubling to 60 s with ±20%
/// jitter, reset once a connection has lasted 60 s; at least 30 s after a
/// 4029.
final class ReconnectPolicy {
  const ReconnectPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 60),
    this.jitter = 0.2,
    this.resetAfter = const Duration(seconds: 60),
    this.rateLimitedDelay = const Duration(seconds: 30),
  });

  final Duration initialDelay;
  final Duration maxDelay;
  final double jitter;
  final Duration resetAfter;
  final Duration rateLimitedDelay;

  Duration delay(int attempt, Random random) {
    final base = initialDelay * pow(2, max(0, attempt - 1)).toInt();
    final capped = base > maxDelay ? maxDelay : base;
    return capped * (1 + jitter * (2 * random.nextDouble() - 1));
  }
}

/// The device's realtime connection (`GET /v1/ws`, REALTIME_V2.md).
///
/// - **Delivery:** [envelopes] carries stored envelopes oldest first, plus
///   ephemeral ones (no `seq`: typing, call signals). Call [ack] with a
///   stored envelope's `seq` once it is durably processed; acks are
///   cumulative. Stored envelopes at or below the ack cursor are dropped as
///   replays; unknown frames and envelope kinds with a `seq` are acked in
///   order without being surfaced. [wakes] fires when the server's window
///   is full and more are waiting (keep acking, or page the REST mailbox).
/// - **Resume:** every connection asks to replay after the cursor
///   (`?after=`) and re-sends the cursor's ack after `hello`.
/// - **Heartbeat:** a `ping` whenever nothing was sent for 60% of
///   `heartbeat_s`; no frame from the server for two heartbeats (plus
///   grace) drops the socket and reconnects.
/// - **Close codes:** 4001 refreshes the token and reconnects at once; 4003
///   stops (revoked); 4004 parks in [RealtimePhase.suspended]; 4008 parks in
///   [RealtimePhase.superseded]; 4029 waits at least 30 s; 4400 is reported
///   on [protocolErrors] and reconnects with backoff; 4010, 4503 and drops
///   reconnect with backoff.
///
/// Listen to [envelopes] before [start]: the stream is broadcast, and an
/// envelope nobody hears is not acked, so it comes back on the next
/// connection.
final class RealtimeClient {
  RealtimeClient({
    required this.baseUrl,
    required AuthProvider auth,
    this._connect = defaultSocketFactory,
    this.policy = const ReconnectPolicy(),
    this.clientName,
    this.idleGrace = const Duration(seconds: 5),
    Random? random,
    DateTime Function()? now,
  }) : _auth = auth,
       _random = random ?? Random(),
       _now = now ?? DateTime.now {
    if (auth.audience != RouteAccess.device) {
      throw ArgumentError.value(auth.audience, 'auth', 'needs device tokens');
    }
  }

  final Uri baseUrl;
  final ReconnectPolicy policy;
  final String? clientName;

  /// Added to two heartbeats before a silent server counts as gone.
  final Duration idleGrace;

  final AuthProvider _auth;
  final RealtimeSocketFactory _connect;
  final Random _random;
  final DateTime Function() _now;

  final StreamController<RealtimeState> _states = StreamController.broadcast();
  final StreamController<Envelope> _envelopes = StreamController.broadcast();
  final StreamController<void> _wakes = StreamController.broadcast();
  final StreamController<RealtimeProtocolError> _errors =
      StreamController.broadcast();

  RealtimeState _state = const RealtimeState(RealtimePhase.idle);

  /// Bumped whenever a connection is abandoned, so late callbacks from it
  /// are ignored.
  int _generation = 0;
  bool _running = false;
  int _attempt = 0;
  bool _refreshedForThisAttempt = false;

  RealtimeSocket? _socket;
  StreamSubscription<String>? _subscription;
  String? _token;
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  DateTime _connectedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHeard = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _heartbeat = const Duration(seconds: 25);
  HelloFrame? _hello;

  int _cursor = 0;
  int _ackedOnSocket = 0;
  final SplayTreeSet<int> _outstanding = SplayTreeSet();
  final Set<int> _skippable = {};

  Stream<RealtimeState> get states => _states.stream;
  RealtimeState get state => _state;
  Stream<Envelope> get envelopes => _envelopes.stream;
  Stream<void> get wakes => _wakes.stream;
  Stream<RealtimeProtocolError> get protocolErrors => _errors.stream;

  /// Highest `seq` known processed (acked by the engine, or skipped).
  int get cursor => _cursor;

  /// Stored envelopes delivered on this connection and not yet acked.
  int get outstanding => _outstanding.length;

  /// The server's window (from `hello`; 0 before the first one).
  int get window => _hello?.window ?? 0;

  /// Starts connecting and keeps the connection up. [after] is the last
  /// `seq` the device processed in an earlier run.
  void start({int after = 0}) {
    if (_states.isClosed) throw StateError('RealtimeClient is disposed');
    if (after > _cursor) _cursor = after;
    if (_running) return;
    _running = true;
    _attempt = 0;
    unawaited(_open());
  }

  /// Connects now: after [RealtimePhase.suspended] or
  /// [RealtimePhase.superseded], or to skip a [RealtimePhase.waiting]
  /// delay (the app came to the foreground). Not after revoked or signed
  /// out unless the caller has a new session.
  void reconnect() {
    _abandon();
    _running = true;
    unawaited(_open());
  }

  /// Records that every stored envelope up to [seq] is durably processed
  /// and acks it.
  void ack(int seq) {
    if (seq <= _cursor) return;
    _cursor = seq;
    _advance();
  }

  /// Closes the connection and stops reconnecting.
  Future<void> stop() async {
    _running = false;
    _abandon();
    _emit(const RealtimeState(RealtimePhase.stopped));
  }

  Future<void> dispose() async {
    await stop();
    await Future.wait([
      _states.close(),
      _envelopes.close(),
      _wakes.close(),
      _errors.close(),
    ]);
  }

  // ------------------------------------------------------------ connection

  Future<void> _open() async {
    final generation = ++_generation;
    _retryTimer?.cancel();
    _emit(RealtimeState(RealtimePhase.connecting, attempt: _attempt));
    final String token;
    try {
      token = await _auth.accessToken();
    } on SignedOutException catch (e) {
      if (generation == _generation) _terminal(RealtimePhase.signedOut, e);
      return;
    } on Object catch (e) {
      // Offline while refreshing ahead of expiry.
      if (generation == _generation) _retry(error: e);
      return;
    }
    if (generation != _generation) return;

    final RealtimeSocket socket;
    try {
      socket = await _connect(
        _url(),
        headers: {
          HelixHeaders.authorization: 'Bearer $token',
          HelixHeaders.client: ?clientName,
        },
        protocols: const [realtimeSubprotocolJson],
      );
    } on RealtimeUpgradeException catch (e) {
      if (generation == _generation) await _upgradeRefused(e.error, token);
      return;
    } on Object catch (e) {
      if (generation == _generation) _retry(error: e);
      return;
    }
    if (generation != _generation) {
      unawaited(socket.close(1000));
      return;
    }

    final now = _now();
    _socket = socket;
    _token = token;
    _connectedAt = now;
    _lastHeard = now;
    _lastSent = now;
    _hello = null;
    _ackedOnSocket = 0;
    _outstanding.clear();
    _skippable.clear();
    _subscription = socket.messages.listen(
      _onText,
      onDone: () => _onClosed(generation, socket),
      onError: (Object _) {},
    );
    _armHeartbeat(_heartbeat);
  }

  Uri _url() {
    final prefix = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(
      scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws',
      path: '$prefix${Routes.websocket.path}',
      queryParameters: _cursor > 0 ? {'after': '$_cursor'} : null,
    );
  }

  Future<void> _upgradeRefused(ApiException error, String token) async {
    switch (error.status) {
      case 401:
        await _unauthorized(token, closeCode: null);
      case 403 when error.code == ErrorCode.accountSuspended:
        _park(RealtimePhase.suspended, error: error);
      case 403:
        _terminal(RealtimePhase.revoked, error);
      case 429:
        _retry(
          error: error,
          atLeast: _max(policy.rateLimitedDelay, error.retryAfter),
        );
      default:
        _retry(error: error, atLeast: error.retryAfter);
    }
  }

  void _onClosed(int generation, RealtimeSocket socket) {
    if (generation != _generation) return;
    final code = socket.closeCode;
    final lived = _now().difference(_connectedAt);
    final hadHello = _hello != null;
    _teardown();
    if (hadHello && lived >= policy.resetAfter) _attempt = 0;
    switch (code) {
      case RealtimeCloseCode.unauthorized:
        unawaited(_unauthorized(_token, closeCode: code));
      case RealtimeCloseCode.deviceRevoked:
        _terminal(RealtimePhase.revoked, null, closeCode: code);
      case RealtimeCloseCode.suspended:
        _park(RealtimePhase.suspended, closeCode: code);
      case RealtimeCloseCode.superseded:
        _park(RealtimePhase.superseded, closeCode: code);
      case RealtimeCloseCode.rateLimited:
        _retry(closeCode: code, atLeast: policy.rateLimitedDelay);
      case RealtimeCloseCode.protocolError:
        _errors.add(
          RealtimeProtocolError('close_4400', message: socket.closeReason),
        );
        _retry(closeCode: code);
      default:
        _retry(closeCode: code);
    }
  }

  /// 4001 or a 401 upgrade: refresh, then reconnect at once. A second one
  /// straight after a refresh backs off instead of looping.
  Future<void> _unauthorized(String? token, {required int? closeCode}) async {
    final generation = _generation;
    if (_refreshedForThisAttempt) {
      _retry(closeCode: closeCode);
      return;
    }
    try {
      if (token != null) await _auth.refresh(token);
    } on SignedOutException catch (e) {
      if (generation == _generation) {
        _terminal(RealtimePhase.signedOut, e, closeCode: closeCode);
      }
      return;
    } on Object catch (e) {
      if (generation == _generation) _retry(error: e, closeCode: closeCode);
      return;
    }
    if (generation != _generation || !_running) return;
    _refreshedForThisAttempt = true;
    unawaited(_open());
  }

  void _retry({Object? error, int? closeCode, Duration? atLeast}) {
    if (!_running) return;
    _attempt++;
    var delay = policy.delay(_attempt, _random);
    if (atLeast != null && atLeast > delay) delay = atLeast;
    _emit(
      RealtimeState(
        RealtimePhase.waiting,
        closeCode: closeCode,
        retryIn: delay,
        attempt: _attempt,
        error: error,
      ),
    );
    final generation = _generation;
    _retryTimer = Timer(delay, () {
      if (generation == _generation && _running) {
        _refreshedForThisAttempt = false;
        unawaited(_open());
      }
    });
  }

  /// Stops reconnecting until [reconnect].
  void _park(RealtimePhase phase, {int? closeCode, Object? error}) {
    _running = false;
    _emit(RealtimeState(phase, closeCode: closeCode, error: error));
  }

  void _terminal(RealtimePhase phase, Object? error, {int? closeCode}) {
    _running = false;
    _abandon();
    _emit(RealtimeState(phase, closeCode: closeCode, error: error));
  }

  /// Forgets the current connection without waiting for it to close.
  void _abandon() {
    _generation++;
    _retryTimer?.cancel();
    final socket = _socket;
    _teardown();
    if (socket != null) unawaited(socket.close(1000));
  }

  void _teardown() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _socket = null;
    _hello = null;
  }

  // ---------------------------------------------------------------- frames

  void _onText(String text) {
    _lastHeard = _now();
    final ServerFrame frame;
    try {
      frame = ServerFrame.decode(text);
    } on FormatException {
      _errors.add(const RealtimeProtocolError('bad_frame'));
      return;
    }
    switch (frame) {
      case final HelloFrame hello:
        _hello = hello;
        _refreshedForThisAttempt = false;
        _heartbeat = Duration(seconds: max(1, hello.heartbeatSeconds));
        _armHeartbeat(_heartbeat);
        _emit(RealtimeState(RealtimePhase.connected, hello: hello));
        if (_cursor > _ackedOnSocket) _sendAck(_cursor);
      case EnvelopeFrame(:final envelope):
        _onEnvelope(envelope);
      case WakeFrame():
        _wakes.add(null);
      case PongFrame():
        break;
      case ErrorFrame(:final code, :final message):
        _errors.add(
          RealtimeProtocolError('error_frame', code: code, message: message),
        );
      case UnknownServerFrame(:final seq):
        if (seq != null) _skip(seq);
    }
  }

  void _onEnvelope(Envelope envelope) {
    final seq = envelope.seq;
    if (seq == null) {
      _envelopes.add(envelope);
      return;
    }
    if (seq <= _cursor) return; // Replay of something already processed.
    if (envelope.kind == EnvelopeKind.unknown) {
      _skip(seq);
      return;
    }
    if (!_outstanding.add(seq)) return; // Sent twice on this connection.
    _envelopes.add(envelope);
  }

  void _skip(int seq) {
    if (seq <= _cursor) return;
    _outstanding.add(seq);
    _skippable.add(seq);
    _advance();
  }

  /// Moves the cursor over skippable seqs at the head and acks it.
  void _advance() {
    while (_outstanding.isNotEmpty && _outstanding.first <= _cursor) {
      _outstanding.remove(_outstanding.first);
    }
    while (_outstanding.isNotEmpty && _skippable.contains(_outstanding.first)) {
      _cursor = _outstanding.first;
      _outstanding.remove(_cursor);
    }
    _skippable.removeWhere((s) => s <= _cursor);
    if (_hello != null && _cursor > _ackedOnSocket) _sendAck(_cursor);
  }

  void _sendAck(int seq) {
    _send(AckFrame(seq: seq));
    _ackedOnSocket = seq;
  }

  void _send(ClientFrame frame) {
    final socket = _socket;
    if (socket == null) return;
    socket.send(frame.encode());
    _lastSent = _now();
  }

  // ------------------------------------------------------------- heartbeat

  void _armHeartbeat(Duration heartbeat) {
    _heartbeatTimer?.cancel();
    final tick = heartbeat ~/ 5;
    _heartbeatTimer = Timer.periodic(
      tick < const Duration(milliseconds: 200)
          ? const Duration(milliseconds: 200)
          : tick,
      (_) => _beat(),
    );
  }

  void _beat() {
    final socket = _socket;
    if (socket == null) return;
    final now = _now();
    if (now.difference(_lastHeard) > _heartbeat * 2 + idleGrace) {
      // The server went quiet (a dead network does not always close).
      _abandon();
      _retry(error: const NetworkException(timedOut: true));
      return;
    }
    if (now.difference(_lastSent) >= _heartbeat * 0.6) _send(const PingFrame());
  }

  void _emit(RealtimeState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  static Duration _max(Duration a, Duration? b) => b != null && b > a ? b : a;
}
