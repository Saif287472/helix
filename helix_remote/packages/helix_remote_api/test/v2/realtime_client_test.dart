import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

const _steady = ReconnectPolicy(jitter: 0);

/// One realtime client on fake time with fake sockets.
final class Rig {
  Rig(
    this.async, {
    ReconnectPolicy policy = _steady,
    CountingAuth? auth,
    Random? random,
  }) : auth = auth ?? CountingAuth() {
    final start = DateTime.utc(2026, 10, 2);
    client = RealtimeClient(
      baseUrl: Uri.parse('https://helix.test'),
      auth: this.auth,
      connect: sockets.connect,
      policy: policy,
      random: random ?? Random(7),
      now: () => start.add(async.elapsed),
    );
    client.states.listen(states.add);
    client.envelopes.listen(envelopes.add);
    client.protocolErrors.listen(errors.add);
    client.wakes.listen((_) => wakes++);
  }

  final FakeAsync async;
  final CountingAuth auth;
  final FakeSockets sockets = FakeSockets();
  late final RealtimeClient client;
  final List<RealtimeState> states = [];
  final List<Envelope> envelopes = [];
  final List<RealtimeProtocolError> errors = [];
  int wakes = 0;

  RealtimePhase get phase => client.state.phase;

  /// Starts and completes the hello on the first socket.
  FakeSocket connect({int after = 0, int heartbeat = 25}) {
    final socket = sockets.next();
    client.start(after: after);
    async.flushMicrotasks();
    socket.hello(heartbeat: heartbeat);
    async.flushMicrotasks();
    return socket;
  }

  void settle([Duration by = Duration.zero]) {
    async.elapse(by);
    async.flushMicrotasks();
  }
}

void main() {
  group('connection', () {
    test('offers the subprotocol and the bearer, resumes after the cursor '
        'and re-acks it after hello', () {
      fakeAsync((async) {
        final r = Rig(async);
        final socket = r.connect(after: 41);
        expect(
          r.sockets.uris.single.toString(),
          'wss://helix.test/v1/ws?after=41',
        );
        expect(r.sockets.protocols.single, [realtimeSubprotocolJson]);
        expect(
          r.sockets.headers.single[HelixHeaders.authorization],
          'Bearer t1',
        );
        expect(r.phase, RealtimePhase.connected);
        expect(r.client.window, 100);
        expect(socket.acks, [41]);
        expect(r.states.map((s) => s.phase), [
          RealtimePhase.connecting,
          RealtimePhase.connected,
        ]);
      });
    });

    test('stop closes the socket and never reconnects', () {
      fakeAsync((async) {
        final r = Rig(async);
        final socket = r.connect();
        r.client.stop();
        r.settle(const Duration(minutes: 5));
        expect(socket.closedByClient, isTrue);
        expect(socket.closeCode, 1000);
        expect(r.phase, RealtimePhase.stopped);
        expect(r.sockets.opened, hasLength(1));
      });
    });
  });

  group('delivery', () {
    test('stored envelopes are acked cumulatively; ephemeral ones never', () {
      fakeAsync((async) {
        final r = Rig(async);
        final socket = r.connect();
        socket
          ..envelope(1)
          ..envelope(2)
          ..envelope(null)
          ..envelope(3);
        r.settle();
        expect(r.envelopes.map((e) => e.seq), [1, 2, null, 3]);
        expect(r.client.outstanding, 3);
        expect(socket.acks, isEmpty);

        r.client.ack(2);
        expect(socket.acks, [2]);
        expect(r.client.outstanding, 1);
        expect(r.client.cursor, 2);

        r.client.ack(1); // Behind the cursor: nothing to do.
        expect(socket.acks, [2]);
      });
    });

    test('replays at or below the cursor and repeats are dropped', () {
      fakeAsync((async) {
        final r = Rig(async);
        final socket = r.connect(after: 5);
        socket
          ..envelope(4)
          ..envelope(5)
          ..envelope(6)
          ..envelope(6);
        r.settle();
        expect(r.envelopes.map((e) => e.seq), [6]);
      });
    });

    test('unknown frames and kinds with a seq are acked in order without '
        'being surfaced', () {
      fakeAsync((async) {
        final r = Rig(async);
        final socket = r.connect();
        socket
          ..envelope(1)
          ..pushRaw('{"t":"future_thing","seq":2}')
          ..envelope(3, kind: EnvelopeKind.unknown);
        r.settle();
        expect(r.envelopes.map((e) => e.seq), [1]);
        expect(socket.acks, isEmpty, reason: '1 is not processed yet');
        r.client.ack(1);
        expect(socket.acks, [3]);
        expect(r.client.cursor, 3);
        socket.pushRaw('{"t":"future_thing","seq":4}');
        r.settle();
        expect(socket.acks, [3, 4]);
      });
    });

    test('wake frames are surfaced (window full)', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().push(const WakeFrame());
        r.settle();
        expect(r.wakes, 1);
      });
    });

    test('error frames and unparsable frames are reported', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect()
          ..push(const ErrorFrame(code: 'bad_request'))
          ..pushRaw('not json');
        r.settle();
        expect(r.errors.map((e) => e.source), ['error_frame', 'bad_frame']);
        expect(r.phase, RealtimePhase.connected);
      });
    });

    test('acks made while disconnected are sent after the next hello', () {
      fakeAsync((async) {
        final r = Rig(async);
        final first = r.connect();
        first.envelope(1);
        r.settle();
        first.serverClose(RealtimeCloseCode.goingAway);
        r.settle();
        r.client.ack(1);
        expect(first.acks, isEmpty);
        final second = r.sockets.next();
        r.settle(const Duration(seconds: 1));
        expect(r.sockets.uris.last.queryParameters['after'], '1');
        second.hello();
        r.settle();
        expect(second.acks, [1]);
      });
    });
  });

  group('heartbeat', () {
    test('pings when idle and drops a silent server', () {
      fakeAsync((async) {
        final r = Rig(async);
        final socket = r.connect(heartbeat: 10);
        r.settle(const Duration(seconds: 7));
        expect(socket.pings, 1);
        r.settle(const Duration(seconds: 19)); // 26 s without a frame.
        expect(r.phase, RealtimePhase.waiting);
        expect(socket.closedByClient, isTrue);
        r.settle(const Duration(seconds: 1));
        expect(r.sockets.opened, hasLength(2));
      });
    });

    test('frames from the server keep the connection alive', () {
      fakeAsync((async) {
        final r = Rig(async);
        final socket = r.connect(heartbeat: 10);
        for (var i = 0; i < 10; i++) {
          r.settle(const Duration(seconds: 8));
          socket.push(const PongFrame());
        }
        r.settle();
        expect(r.phase, RealtimePhase.connected);
        expect(r.sockets.opened, hasLength(1));
      });
    });
  });

  group('close codes', () {
    test('4001 refreshes the token and reconnects at once', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().serverClose(RealtimeCloseCode.unauthorized);
        r.settle();
        expect(r.auth.refreshes, 1);
        expect(r.sockets.opened, hasLength(2));
        expect(r.sockets.headers.last[HelixHeaders.authorization], 'Bearer t2');
      });
    });

    test('4001 with a refused refresh signs out and stops', () {
      fakeAsync((async) {
        final r = Rig(async, auth: CountingAuth(signOut: true));
        r.connect().serverClose(RealtimeCloseCode.unauthorized);
        r.settle(const Duration(minutes: 5));
        expect(r.phase, RealtimePhase.signedOut);
        expect(r.sockets.opened, hasLength(1));
      });
    });

    test('a 4001 straight after a refresh backs off instead of looping', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().serverClose(RealtimeCloseCode.unauthorized);
        r.settle();
        r.sockets.opened.last.serverClose(RealtimeCloseCode.unauthorized);
        r.settle();
        expect(r.auth.refreshes, 1);
        expect(r.phase, RealtimePhase.waiting);
      });
    });

    test('4003 stops for good: the device was revoked', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().serverClose(RealtimeCloseCode.deviceRevoked);
        r.settle(const Duration(minutes: 10));
        expect(r.phase, RealtimePhase.revoked);
        expect(r.client.state.closeCode, 4003);
        expect(r.sockets.opened, hasLength(1));
      });
    });

    test('4004 parks as suspended until reconnect is called', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().serverClose(RealtimeCloseCode.suspended);
        r.settle(const Duration(minutes: 10));
        expect(r.phase, RealtimePhase.suspended);
        expect(r.sockets.opened, hasLength(1));
        r.client.reconnect();
        r.settle();
        expect(r.sockets.opened, hasLength(2));
      });
    });

    test('4008 does not fight the newer connection', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().serverClose(RealtimeCloseCode.superseded);
        r.settle(const Duration(minutes: 10));
        expect(r.phase, RealtimePhase.superseded);
        expect(r.sockets.opened, hasLength(1));
      });
    });

    test('4029 waits at least 30 s', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().serverClose(RealtimeCloseCode.rateLimited);
        r.settle();
        expect(r.client.state.retryIn, const Duration(seconds: 30));
        r.settle(const Duration(seconds: 29));
        expect(r.sockets.opened, hasLength(1));
        r.settle(const Duration(seconds: 1));
        expect(r.sockets.opened, hasLength(2));
      });
    });

    test('4503 and drops back off 1 s doubling to 60 s', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().serverClose(RealtimeCloseCode.goingAway);
        final waits = <Duration>[];
        for (var i = 0; i < 8; i++) {
          r.settle();
          waits.add(r.client.state.retryIn!);
          r.settle(r.client.state.retryIn!);
          r.sockets.opened.last.serverClose(null);
        }
        expect(waits, [
          for (final s in [1, 2, 4, 8, 16, 32, 60, 60]) Duration(seconds: s),
        ]);
      });
    });

    test('backoff resets once a connection lasted 60 s', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().serverClose(RealtimeCloseCode.goingAway);
        r.settle();
        r.settle(const Duration(seconds: 1));
        final second = r.sockets.opened.last..serverClose(null);
        expect(second, isNot(r.sockets.opened.first));
        r.settle();
        expect(r.client.state.retryIn, const Duration(seconds: 2));
        r.settle(const Duration(seconds: 2));
        final third = r.sockets.opened.last..hello();
        r.settle(const Duration(seconds: 30));
        third.push(const PongFrame());
        r.settle(const Duration(seconds: 31));
        expect(r.phase, RealtimePhase.connected);
        third.serverClose(RealtimeCloseCode.idleTimeout);
        r.settle();
        expect(r.client.state.retryIn, const Duration(seconds: 1));
      });
    });

    test('4400 is reported and reconnects with backoff', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.connect().serverClose(RealtimeCloseCode.protocolError, 'bad frame');
        r.settle();
        expect(r.errors.single.source, 'close_4400');
        expect(r.phase, RealtimePhase.waiting);
      });
    });

    test('jitter stays within ±20%', () {
      fakeAsync((async) {
        final r = Rig(async, policy: const ReconnectPolicy());
        final socket = r.sockets.next();
        r.client.start();
        r.settle();
        socket.serverClose(null);
        r.settle();
        final wait = r.client.state.retryIn!;
        expect(wait.inMilliseconds, inInclusiveRange(800, 1200));
      });
    });
  });

  group('refused upgrades', () {
    RealtimeUpgradeException refused(ErrorCode code, {Duration? retryAfter}) =>
        RealtimeUpgradeException(
          ApiException(status: code.status, code: code, retryAfter: retryAfter),
        );

    test('401 refreshes and reconnects', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.sockets.fail(refused(ErrorCode.tokenExpired));
        r.sockets.next();
        r.client.start();
        r.settle();
        expect(r.auth.refreshes, 1);
        expect(r.sockets.opened, hasLength(1));
        expect(r.sockets.headers.last[HelixHeaders.authorization], 'Bearer t2');
      });
    });

    test('403 device_revoked stops', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.sockets.fail(refused(ErrorCode.deviceRevoked));
        r.client.start();
        r.settle(const Duration(minutes: 5));
        expect(r.phase, RealtimePhase.revoked);
        expect(r.sockets.uris, hasLength(1));
      });
    });

    test('429 honours a Retry-After above the 30 s floor', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.sockets.fail(
          refused(
            ErrorCode.rateLimited,
            retryAfter: const Duration(seconds: 45),
          ),
        );
        r.client.start();
        r.settle();
        expect(r.client.state.retryIn, const Duration(seconds: 45));
      });
    });

    test('an unreachable server is retried with backoff', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.sockets.fail(const NetworkException());
        r.client.start();
        r.settle();
        expect(r.phase, RealtimePhase.waiting);
        r.sockets.next();
        r.settle(const Duration(seconds: 1));
        expect(r.sockets.opened, hasLength(1));
      });
    });
  });
}
