import 'dart:async';
import 'dart:math' as math;

import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_discovery/helix_discovery.dart';
import 'package:helix/providers/controllers/messaging_service.dart';
import 'package:helix/providers/controllers/profile_service.dart';
import 'package:helix/providers/controllers/request_service.dart';
import 'package:helix/providers/controllers/session_service.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';

class ReconnectionCoordinatorImpl implements ReconnectionCoordinator {
  ReconnectionCoordinatorImpl({
    required this._messaging,
    required this._requests,
    required this._discovery,
    required this._profile,
    required this._session,
    required this._localTcpPort,
  });

  final MessagingService _messaging;
  final RequestService _requests;
  final DiscoveryCoordinator _discovery;
  final ProfileService _profile;
  final SessionService _session;
  final int Function() _localTcpPort;

  StreamSubscription<ChatThread>? _sub;
  final Map<String, _ThreadReconnect> _active = {};

  @override
  void start() {
    _sub = _messaging.threadChanges.listen(_onThreadChanged);
  }

  @override
  void stop() {
    _sub?.cancel();
    _sub = null;
    for (final r in _active.values) {
      r.cancel();
    }
    _active.clear();
  }

  void _onThreadChanged(ChatThread thread) {
    if (_messaging.isOneWayOnlyThread(thread.threadId)) return;
    if (thread.manuallyDisconnected) return;
    if (thread.status == ThreadStatus.disconnected) {
      if (!(_active[thread.threadId]?.running ?? false)) {
        final r = _ThreadReconnect(
          threadId: thread.threadId,
          messaging: _messaging,
          requests: _requests,
          discovery: _discovery,
          profile: _profile,
          session: _session,
          localTcpPort: _localTcpPort,
        );
        _active[thread.threadId] = r;
        r.start();
      }
    } else if (thread.status == ThreadStatus.active) {
      _active.remove(thread.threadId)?.cancel();
    }
  }
}

class _ThreadReconnect {
  _ThreadReconnect({
    required this.threadId,
    required this._messaging,
    required this._requests,
    required this._discovery,
    required this._profile,
    required this._session,
    required this._localTcpPort,
  });

  final String threadId;
  final MessagingService _messaging;
  final RequestService _requests;
  final DiscoveryCoordinator _discovery;
  final ProfileService _profile;
  final SessionService _session;
  final int Function() _localTcpPort;

  int _attempt = 0;
  bool _cancelled = false;
  Timer? _timer;

  bool get running => !_cancelled && _timer != null;

  void start() {
    _messaging.injectSystemMessage(threadId, 'Reconnecting…');
    _scheduleNext();
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleNext() {
    if (_cancelled || _attempt >= kMaxReconnectAttempts) {
      if (!_cancelled) {
        _messaging.injectSystemMessage(
          threadId,
          'Could not reconnect. Open the peer from Home to try again.',
        );
      }
      cancel();
      return;
    }

    final delaySec = math.min(
      kReconnectBaseDelay.inSeconds * math.pow(3, _attempt).round(),
      kReconnectMaxDelay.inSeconds,
    );
    final jitter = math.Random().nextInt(2001); // 0–2000 ms
    _timer = Timer(
      Duration(seconds: delaySec, milliseconds: jitter),
      _attemptConnect,
    );
  }

  Future<void> _attemptConnect() async {
    if (_cancelled) return;
    _attempt++;

    final thread = _messaging.threads[threadId];
    if (thread == null) {
      cancel();
      return;
    }

    // Prefer a live peer from the registry; fall back to stored host:port.
    final activePeers = _discovery.peers;
    Peer? target = activePeers
        .where(
          (p) =>
              p.sessionId == thread.peerSessionId ||
              (p.host == thread.peerHost && p.port == thread.peerPort),
        )
        .firstOrNull;

    if (target == null && thread.peerHost.isNotEmpty && thread.peerPort > 0) {
      target = Peer(
        sessionId: thread.peerSessionId,
        displayName: thread.peerDisplayName,
        deviceSuffix: thread.peerDeviceSuffix,
        host: thread.peerHost,
        port: thread.peerPort,
        source: PeerSource.directIp,
        seenAt: DateTime.now(),
        protocolMajor: kProtocolMajor,
        protocolMinor: kProtocolMinor,
      );
    }

    if (target == null) {
      _scheduleNext();
      return;
    }

    final identity = _profile.identity;
    final profile = _profile.profile;
    final sessionId = _session.sessionId;
    if (identity == null || profile == null) {
      cancel();
      return;
    }

    final isResume = _messaging.shouldAutoResume(threadId);

    try {
      final result = await _requests.sendRequest(
        target,
        RequestSourceMethod.directIp,
        identity,
        sessionId,
        profile.displayName,
        localTcpPort: _localTcpPort(),
        isResume: isResume,
        resumeThreadId: isResume ? threadId : '',
      );

      if (_cancelled) return;

      if (result.request.status == RequestStatus.accepted &&
          result.channel != null) {
        _messaging.attachChannel(
          result.channel!.threadId,
          result.request.peerDisplayName,
          result.request.peerDeviceSuffix,
          result.channel!,
          result.request.peerSessionId,
          result.request.peerHost,
          result.request.peerPort,
        );
        _messaging.injectSystemMessage(threadId, 'Reconnected.');
        cancel();
      } else {
        _scheduleNext();
      }
    } catch (_) {
      if (!_cancelled) _scheduleNext();
    }
  }
}
