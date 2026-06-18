import 'dart:async';

import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix/application/session/active_session_tracker_impl.dart';
import 'package:helix_local_storage/infrastructure/storage/secure_session_repository.dart';
import 'package:helix_local_platform/infrastructure/platform/android_foreground_service_gateway.dart';

class SessionService {
  final ActiveSessionTracker _activeSessionTracker;

  SessionService({ActiveSessionTracker? activeSessionTracker})
    : _activeSessionTracker =
          activeSessionTracker ??
          ActiveSessionTrackerImpl(
            sessionRepository: const SecureSessionRepository(),
            foregroundServiceGateway: const AndroidForegroundServiceGateway(),
          );

  SessionState get state => _activeSessionTracker.state;
  String get sessionId => _activeSessionTracker.sessionId;
  Stream<SessionState> get stateChanges => _activeSessionTracker.stateChanges;

  Future<void> startSession(Profile profile, DeviceIdentity identity) async {
    await _activeSessionTracker.startSession(profile, identity);
  }

  Future<void> stopSession() async {
    await _activeSessionTracker.stopSession();
  }

  Future<bool> resumeSession() async {
    return _activeSessionTracker.resumeSession();
  }

  void dispose() {
    _activeSessionTracker.dispose();
  }
}
