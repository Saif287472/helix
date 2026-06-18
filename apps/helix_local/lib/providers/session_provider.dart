// lib/providers/session_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:helix_domain/domain/models.dart';
import 'package:helix/providers/controllers/profile_service.dart';
import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix_storage/infrastructure/storage/flutter_profile_repository.dart';
import 'package:helix_storage/infrastructure/storage/flutter_secure_identity_store.dart';
import 'package:helix/application/identity/identity_manager_impl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProfileService provider
// ─────────────────────────────────────────────────────────────────────────────

final secureIdentityStoreProvider = Provider<SecureIdentityStore>((ref) {
  return const FlutterSecureIdentityStore();
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return const FlutterProfileRepository();
});

final identityManagerProvider = Provider<IdentityManager>((ref) {
  final manager = IdentityManagerImpl(
    profileRepository: ref.watch(profileRepositoryProvider),
    secureIdentityStore: ref.watch(secureIdentityStoreProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

final profileServiceProvider = Provider<ProfileService>((ref) {
  final service = ProfileService(
    identityManager: ref.watch(identityManagerProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

// ─────────────────────────────────────────────────────────────────────────────
// App initialisation (async — loads profile + identity from secure storage)
// ─────────────────────────────────────────────────────────────────────────────

final appInitProvider = FutureProvider<void>((ref) async {
  final profileService = ref.watch(profileServiceProvider);
  try {
    await profileService.init();
  } catch (e) {
    // On Windows, CryptUnprotectData fails when stored data was encrypted under
    // a different user session or machine key. The registry entries can still be
    // deleted (deleteAll doesn't decrypt), so wipe and fall through to first-run.
    final msg = e.toString();
    if (msg.contains('CryptUnprotectData') ||
        msg.contains('PlatformException')) {
      await profileService.reset();
      await profileService.init();
    } else {
      rethrow;
    }
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Profile stream
// ─────────────────────────────────────────────────────────────────────────────

final profileProvider = StreamProvider<Profile>((ref) async* {
  final service = ref.watch(profileServiceProvider);
  final profile = service.profile;
  if (profile != null) yield profile;
  yield* service.profileChanges;
});

// ─────────────────────────────────────────────────────────────────────────────
// Session state
// ─────────────────────────────────────────────────────────────────────────────

class SessionStateNotifier extends StateNotifier<SessionState> {
  SessionStateNotifier() : super(SessionState.idle);

  void startSession(String sessionId) {
    state = SessionState(phase: SessionPhase.active, sessionId: sessionId);
  }

  void stopSession() {
    state = SessionState.idle;
  }

  void setError(String error) {
    state = state.copyWith(phase: SessionPhase.idle, error: error);
  }
}

final sessionStateProvider =
    StateNotifierProvider<SessionStateNotifier, SessionState>(
      (ref) => SessionStateNotifier(),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Active chats / pending requests counters  (stubs — real logic lives in chat
// providers that haven't been written yet; these are referenced by
// HelixWindowListener in main.dart for the close-guard check)
// ─────────────────────────────────────────────────────────────────────────────

/// Number of currently active (connected) chat threads.
final activeChatCountProvider = StateProvider<int>((ref) => 0);

/// Number of pending inbound connection requests awaiting user action.
final pendingRequestCountProvider = StateProvider<int>((ref) => 0);

/// True when the session is active AND there are active chats or pending
/// requests — used by the Windows close-button guard (FR-SESSION-009).
final hasActiveSessionProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionStateProvider);
  final chats = ref.watch(activeChatCountProvider);
  final requests = ref.watch(pendingRequestCountProvider);
  return session.phase == SessionPhase.active && (chats > 0 || requests > 0);
});
