import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

enum SessionPhase { idle, starting, active, stopping }

/// Application lifecycle state — drives routing and session decisions.
enum AppState { firstRun, setupComplete, sessionActive, sessionIdle }

@immutable
class SessionState {
  final SessionPhase phase;
  final String? sessionId;
  final String? error;

  const SessionState({required this.phase, this.sessionId, this.error});

  static const idle = SessionState(phase: SessionPhase.idle);

  static const _sentinel = Object();

  SessionState copyWith({
    SessionPhase? phase,
    Object? sessionId = _sentinel,
    Object? error = _sentinel,
  }) => SessionState(
    phase: phase ?? this.phase,
    sessionId: identical(sessionId, _sentinel)
        ? this.sessionId
        : sessionId as String?,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );
}
