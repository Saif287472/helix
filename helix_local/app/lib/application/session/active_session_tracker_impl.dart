import 'dart:async';
import 'dart:math';

import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';

class ActiveSessionTrackerImpl implements ActiveSessionTracker {
  ActiveSessionTrackerImpl({
    required this._sessionRepository,
    required this._foregroundServiceGateway,
  });

  final SessionRepository _sessionRepository;
  final ForegroundServiceGateway _foregroundServiceGateway;

  SessionState _state = SessionState.idle;
  String? _sessionId;
  Timer? _watchdogTimer;

  final StreamController<SessionState> _stateController =
      StreamController<SessionState>.broadcast();

  @override
  SessionState get state => _state;

  @override
  String get sessionId => _sessionId ?? '';

  @override
  Stream<SessionState> get stateChanges => _stateController.stream;

  @override
  Future<void> startSession(Profile profile, DeviceIdentity identity) async {
    if (_state.phase == SessionPhase.active ||
        _state.phase == SessionPhase.starting) {
      return;
    }

    _emit(_state.copyWith(phase: SessionPhase.starting));

    // Start a watchdog timer — if we're still in 'starting' after 10 s,
    // something went wrong (e.g. foreground-service hung).
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(const Duration(seconds: 10), () {
      if (_state.phase == SessionPhase.starting) {
        _emit(
          SessionState(
            phase: SessionPhase.idle,
            error: 'Session start timed out',
          ),
        );
        _sessionId = null;
      }
    });

    try {
      // Generate a fresh session ID (random 16 bytes → 32 hex chars)
      _sessionId = _generateSessionId();

      _watchdogTimer?.cancel();
      _watchdogTimer = null;

      // Persist the session ID so it can be resumed after a cold restart.
      await _sessionRepository.saveSessionId(_sessionId!);

      _emit(SessionState(phase: SessionPhase.active, sessionId: _sessionId));
    } catch (e) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
      _emit(SessionState(phase: SessionPhase.idle, error: e.toString()));
      _sessionId = null;
      rethrow;
    }
  }

  @override
  Future<void> stopSession() async {
    if (_state.phase == SessionPhase.idle ||
        _state.phase == SessionPhase.stopping) {
      return;
    }

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    _emit(_state.copyWith(phase: SessionPhase.stopping));

    try {
      if (isAndroid) {
        await _foregroundServiceGateway.stopService();
      }
      await _sessionRepository.clearSessionId();
    } catch (_) {
      // Best-effort: log and continue to idle regardless
    } finally {
      _sessionId = null;
      _emit(SessionState.idle);
    }
  }

  @override
  Future<bool> resumeSession() async {
    if (_state.phase == SessionPhase.active) return true;

    final storedId = await _sessionRepository.loadSessionId();
    if (storedId == null || storedId.isEmpty) return false;

    _sessionId = storedId;
    _emit(SessionState(phase: SessionPhase.active, sessionId: _sessionId));
    return true;
  }

  void _emit(SessionState next) {
    _state = next;
    _stateController.add(next);
  }

  String _generateSessionId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(kSessionIdBytes, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _stateController.close();
  }
}
