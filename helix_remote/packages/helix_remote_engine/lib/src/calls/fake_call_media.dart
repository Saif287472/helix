import 'dart:async';

import 'package:helix_remote_engine/src/calls/call_media.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show IceCandidatePayload;

/// A deterministic in-memory [CallMediaFactory] for tests and loopback
/// tools (`package:helix_remote_engine/testing.dart`).
///
/// A fake session behaves like a tiny ICE agent: it gathers
/// [FakeCallMediaFactory.localCandidateCount] candidates after the local
/// description is set, and it reports `connected` once it holds the remote
/// description and [FakeCallMediaFactory.remoteCandidatesToConnect] remote
/// candidates, so a test sees the signalling carry candidates to the right
/// device before a call goes live. Tests can also break the connection.
final class FakeCallMediaFactory implements CallMediaFactory {
  FakeCallMediaFactory({
    this.label = 'fake',
    this.localCandidateCount = 2,
    this.remoteCandidatesToConnect = 1,
    this.autoConnect = true,
  });

  /// Prefixes the SDP strings, to tell two devices' sessions apart.
  final String label;

  /// Candidates a session gathers once its local description is set.
  final int localCandidateCount;

  /// Remote candidates (after the remote description) that connect it.
  final int remoteCandidatesToConnect;

  /// When false a session stays `connecting` until [FakeCallMediaSession.connect].
  bool autoConnect;

  /// Make [create] throw (the platform refused the microphone, say).
  bool failCreate = false;

  /// Every session created, oldest first.
  final List<FakeCallMediaSession> sessions = [];

  FakeCallMediaSession get last => sessions.last;

  @override
  Future<CallMediaSession> create(CallMediaConfig config) async {
    if (failCreate) throw StateError('media unavailable');
    final session = FakeCallMediaSession._(this, config, sessions.length);
    sessions.add(session);
    return session;
  }
}

/// One fake peer connection; see [FakeCallMediaFactory].
final class FakeCallMediaSession implements CallMediaSession {
  FakeCallMediaSession._(this._factory, this.config, this.index);

  final FakeCallMediaFactory _factory;
  final CallMediaConfig config;
  final int index;

  final StreamController<IceCandidatePayload> _candidates =
      StreamController<IceCandidatePayload>();
  final StreamController<CallMediaState> _states =
      StreamController<CallMediaState>.broadcast();

  /// The SDP this session made.
  String? localSdp;

  /// The SDP of the other side, once set.
  String? remoteSdp;

  /// Candidates received from the other side, in order.
  final List<IceCandidatePayload> remoteCandidates = [];

  bool muted = false;
  late bool videoEnabled = config.video;
  bool closed = false;
  CallMediaState state = CallMediaState.connecting;

  @override
  Stream<IceCandidatePayload> get localCandidates => _candidates.stream;

  @override
  Stream<CallMediaState> get states => _states.stream;

  @override
  Future<String> createOffer() async {
    _check();
    localSdp = '${_factory.label}-offer-$index';
    _gather();
    return localSdp!;
  }

  @override
  Future<String> acceptOffer(String offerSdp) async {
    _check();
    remoteSdp = offerSdp;
    localSdp = '${_factory.label}-answer-$index';
    _gather();
    _maybeConnect();
    return localSdp!;
  }

  @override
  Future<void> acceptAnswer(String answerSdp) async {
    _check();
    if (localSdp == null) throw StateError('no offer was made');
    remoteSdp = answerSdp;
    _maybeConnect();
  }

  @override
  Future<void> addRemoteCandidate(IceCandidatePayload candidate) async {
    _check();
    if (remoteSdp == null) {
      throw StateError('a candidate before the remote description');
    }
    remoteCandidates.add(candidate);
    _maybeConnect();
  }

  @override
  Future<void> setMuted({required bool muted}) async {
    _check();
    this.muted = muted;
  }

  @override
  Future<void> setVideoEnabled({required bool enabled}) async {
    _check();
    videoEnabled = enabled;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    _set(CallMediaState.closed);
    // Not awaited: a stream nobody listened to never reports done.
    unawaited(_states.close());
    unawaited(_candidates.close());
  }

  /// Connects now (for [FakeCallMediaFactory.autoConnect] false).
  void connect() => _set(CallMediaState.connected);

  /// Breaks the connection for good.
  void fail() => _set(CallMediaState.failed);

  /// Drops the connection temporarily.
  void disconnect() => _set(CallMediaState.disconnected);

  void _gather() {
    for (var i = 0; i < _factory.localCandidateCount; i++) {
      scheduleMicrotask(() {
        if (closed) return;
        _candidates.add(
          IceCandidatePayload(
            candidate: 'candidate:${_factory.label}-$index-$i',
            sdpMid: '0',
            sdpMLineIndex: 0,
          ),
        );
      });
    }
  }

  void _maybeConnect() {
    if (!_factory.autoConnect || state == CallMediaState.connected) return;
    if (remoteSdp != null &&
        remoteCandidates.length >= _factory.remoteCandidatesToConnect) {
      scheduleMicrotask(() => _set(CallMediaState.connected));
    }
  }

  void _set(CallMediaState next) {
    if (closed && next != CallMediaState.closed) return;
    state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _check() {
    if (closed) throw StateError('the media session is closed');
  }
}
