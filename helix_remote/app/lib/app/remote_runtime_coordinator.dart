import 'dart:async';
import 'dart:math' as math;

enum RemoteRuntimeState {
  offline,
  connecting,
  syncing,
  ready,
  degraded,
  authRequired,
  retryScheduled,
  failed,
  disposed,
}

class RemoteRuntimeSnapshot {
  const RemoteRuntimeSnapshot({
    required this.state,
    required this.failedOperationCount,
    this.nextRetryAt,
    this.lastError,
  });

  final RemoteRuntimeState state;
  final int failedOperationCount;
  final DateTime? nextRetryAt;
  final String? lastError;
}

class RemoteRuntimeCoordinator {
  RemoteRuntimeCoordinator({
    required Future<bool> Function() validateSession,
    required Future<int> Function() catchUpInbound,
    required Future<int> Function() drainOutbox,
    required Future<void> Function() connectRealtime,
    required Future<void> Function() disconnectRealtime,
    Future<void> Function()? refreshSession,
    Future<void> Function()? replenishPrekeys,
    Future<void> Function()? startCallSignaling,
    Future<void> Function()? purgeLocalSession,
    Duration reconnectBaseDelay = const Duration(milliseconds: 250),
    Duration reconnectMaxDelay = const Duration(seconds: 30),
  }) : _validateSession = validateSession,
       _catchUpInbound = catchUpInbound,
       _drainOutbox = drainOutbox,
       _connectRealtime = connectRealtime,
       _disconnectRealtime = disconnectRealtime,
       _refreshSession = refreshSession,
       _replenishPrekeys = replenishPrekeys,
       _startCallSignaling = startCallSignaling,
       _purgeLocalSession = purgeLocalSession,
       _reconnectBaseDelay = reconnectBaseDelay,
       _reconnectMaxDelay = reconnectMaxDelay;

  final Future<bool> Function() _validateSession;
  final Future<int> Function() _catchUpInbound;
  final Future<int> Function() _drainOutbox;
  final Future<void> Function() _connectRealtime;
  final Future<void> Function() _disconnectRealtime;
  final Future<void> Function()? _refreshSession;
  final Future<void> Function()? _replenishPrekeys;
  final Future<void> Function()? _startCallSignaling;
  final Future<void> Function()? _purgeLocalSession;
  final Duration _reconnectBaseDelay;
  final Duration _reconnectMaxDelay;

  final _stateController =
      StreamController<RemoteRuntimeSnapshot>.broadcast();

  RemoteRuntimeState _state = RemoteRuntimeState.offline;
  Future<void>? _startup;
  Future<int>? _outboxDrain;
  Timer? _reconnectTimer;
  Timer? _periodicSyncTimer;
  bool _disposed = false;
  bool _networkAvailable = true;
  int _failedOperationCount = 0;
  int _reconnectAttempts = 0;
  final _jitter = math.Random();
  DateTime? _nextRetryAt;
  String? _lastError;

  RemoteRuntimeSnapshot get snapshot => RemoteRuntimeSnapshot(
    state: _state,
    failedOperationCount: _failedOperationCount,
    nextRetryAt: _nextRetryAt,
    lastError: _lastError,
  );

  Stream<RemoteRuntimeSnapshot> get snapshots => _stateController.stream;

  Future<void> start() {
    if (_disposed) return Future.value();
    if (_startup != null) return _startup!;
    final startup = _startOnce();
    _startup = startup;
    return startup.whenComplete(() {
      if (identical(_startup, startup)) {
        _startup = null;
      }
    });
  }

  Future<void> _startOnce() async {
    if (!_networkAvailable) {
      _setState(RemoteRuntimeState.offline);
      return;
    }

    try {
      _setState(RemoteRuntimeState.connecting);
      final hasSession = await _validateSession();
      if (_disposed) return;
      if (!hasSession) {
        _setState(RemoteRuntimeState.authRequired);
        return;
      }

      _setState(RemoteRuntimeState.syncing);
      await _refreshSession?.call();
      if (_disposed) return;
      await _catchUpInbound();
      if (_disposed) return;
      await drainOutbox();
      if (_disposed) return;
      await _replenishPrekeys?.call();
      if (_disposed) return;
      await _connectRealtime();
      if (_disposed) return;
      await _startCallSignaling?.call();
      if (_disposed) return;
      _reconnectAttempts = 0;
      _nextRetryAt = null;
      _startPeriodicSync();
      _setState(RemoteRuntimeState.ready);
    } on RemoteRuntimeAuthRequired catch (e) {
      _lastError = e.message;
      _setState(RemoteRuntimeState.authRequired);
    } catch (e) {
      _lastError = e.toString();
      _failedOperationCount++;
      _scheduleReconnect();
    }
  }

  Future<int> drainOutbox() {
    final existing = _outboxDrain;
    if (existing != null) return existing;
    final drain = _drainOutbox();
    _outboxDrain = drain;
    return drain.whenComplete(() {
      if (identical(_outboxDrain, drain)) {
        _outboxDrain = null;
      }
    });
  }

  Future<void> handleRealtimeGap() async {
    if (_disposed) return;
    _setState(RemoteRuntimeState.syncing);
    try {
      await _catchUpInbound();
      await drainOutbox();
      if (!_disposed) {
        _setState(RemoteRuntimeState.ready);
      }
    } catch (e) {
      _lastError = e.toString();
      if (!_disposed) _scheduleReconnect();
    }
  }

  /// Silently catches up inbound events without changing coordinator state.
  /// Safe to call at any time from UI; errors are swallowed.
  Future<void> softSync() async {
    if (_disposed || _state != RemoteRuntimeState.ready) return;
    try {
      await _catchUpInbound();
      await drainOutbox();
    } catch (_) {}
  }

  Future<void> handleRealtimeClosed() async {
    if (_disposed) return;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    await _disconnectRealtime();
    _scheduleReconnect();
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed || _state != RemoteRuntimeState.ready) return;
      _catchUpInbound().ignore();
    });
  }

  void setNetworkAvailable(bool available) {
    if (_disposed || _networkAvailable == available) return;
    _networkAvailable = available;
    if (!available) {
      _reconnectTimer?.cancel();
      _nextRetryAt = null;
      _disconnectRealtime().ignore();
      _setState(RemoteRuntimeState.offline);
    } else {
      _scheduleReconnect(resetAttempts: true);
    }
  }

  Future<void> logoutAndPurge() async {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    await _disconnectRealtime();
    await _purgeLocalSession?.call();
    _setState(RemoteRuntimeState.authRequired);
  }

  void _scheduleReconnect({bool resetAttempts = false}) {
    if (_disposed || !_networkAvailable) return;
    if (resetAttempts) {
      _reconnectAttempts = 0;
    }
    _reconnectTimer?.cancel();
    final delay = _nextReconnectDelay();
    _nextRetryAt = DateTime.now().add(delay);
    _setState(RemoteRuntimeState.retryScheduled);
    _reconnectTimer = Timer(delay, () {
      if (_disposed) return;
      start();
    });
  }

  Duration _nextReconnectDelay() {
    final multiplier = 1 << _reconnectAttempts.clamp(0, 10);
    _reconnectAttempts++;
    final candidate = _reconnectBaseDelay * multiplier;
    final capped = candidate > _reconnectMaxDelay
        ? _reconnectMaxDelay
        : candidate;
    final jitterMs = capped.inMilliseconds == 0
        ? 0
        : _jitter.nextInt((capped.inMilliseconds * 0.2).round() + 1);
    return capped + Duration(milliseconds: jitterMs);
  }

  void _setState(RemoteRuntimeState state) {
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(snapshot);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    await _disconnectRealtime();
    _setState(RemoteRuntimeState.disposed);
    await _stateController.close();
  }
}

class RemoteRuntimeAuthRequired implements Exception {
  const RemoteRuntimeAuthRequired(this.message);

  final String message;
}
