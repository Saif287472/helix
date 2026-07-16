// Connection providers: session tracker, TCP server, request service, reconnect.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix/providers/session_provider.dart';
import 'package:helix/providers/infrastructure_providers.dart';
import 'package:helix/providers/identity_providers.dart'
    show notificationServiceProvider;
import 'package:helix/providers/messaging_providers.dart'
    show messagingServiceProvider;
import 'package:helix/providers/discovery_providers.dart'
    show discoveryCoordinatorProvider;
import 'package:helix/providers/controllers/session_service.dart';
import 'package:helix/providers/controllers/tcp_server_service.dart';
import 'package:helix/providers/controllers/request_service.dart';
import 'package:helix/providers/controllers/reconnect_service.dart';
import 'package:helix/application/session/active_session_tracker_impl.dart';
import 'package:helix/application/tcp_server/tcp_server_use_case_impl.dart';
import 'package:helix/application/connection/connection_request_use_case_impl.dart';
import 'package:helix/application/connection/reconnection_coordinator_impl.dart';
import 'package:uuid/uuid.dart';

final activeSessionTrackerProvider = Provider<ActiveSessionTracker>((ref) {
  final tracker = ActiveSessionTrackerImpl(
    sessionRepository: ref.watch(sessionRepositoryProvider),
    foregroundServiceGateway: ref.watch(foregroundServiceGatewayProvider),
  );
  ref.onDispose(tracker.dispose);
  return tracker;
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(
    activeSessionTracker: ref.watch(activeSessionTrackerProvider),
  );
});

final tcpServerUseCaseProvider = Provider<TcpServerUseCase>((ref) {
  final useCase = TcpServerUseCaseImpl();
  ref.onDispose(useCase.dispose);
  return useCase;
});

final tcpServerServiceProvider = Provider<TcpServerService>((ref) {
  final service = TcpServerService(
    useCase: ref.watch(tcpServerUseCaseProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Port for the app's active request listener.
final activeTcpPortProvider = StateProvider<int>((ref) => 0);

final requestServiceProvider = Provider<RequestService>((ref) {
  late final RequestService service;

  final repository = ref.watch(connectionRequestRepositoryProvider);
  final uuid = const Uuid();

  final connectionRequestUseCase = ConnectionRequestUseCaseImpl(
    repository: repository,
    onIncoming: (req) => service.emitIncoming(req),
    onUpdate: (req) => service.emitUpdate(req),
    isPeerBlocked: (fingerprint) => service.isBlocked(fingerprint),
    detectImpersonation: (fingerprint, displayName) {
      return service.trustService?.detectImpersonation(
            fingerprint,
            displayName,
          ) !=
          null;
    },
    generateRequestId: () => uuid.v4(),
    tryConsumeGlobalRateLimit: (maxPerMinute) =>
        service.tryConsumeGlobalRateLimit(maxPerMinute),
    tryConsumeSourceRateLimit: (fingerprint, maxPerMinute) =>
        service.tryConsumeSourceRateLimit(fingerprint, maxPerMinute),
  );

  service = RequestService(
    connectionRequestRepository: repository,
    connectionRequestUseCase: connectionRequestUseCase,
  );

  ref.onDispose(service.close);
  return service;
});

final pendingRequestsProvider =
    StateNotifierProvider<
      PendingRequestsNotifier,
      Map<String, ConnectionRequest>
    >((ref) {
      final notifier = PendingRequestsNotifier(ref);
      final svc = ref.watch(requestServiceProvider);

      notifier.seed(Map.from(svc.pendingRequests));

      final sub = svc.incomingRequests.listen((request) {
        notifier.upsert(request);
        ref
            .read(notificationServiceProvider)
            .showIncomingRequest(request.peerDisplayName, request.requestId);
      });
      ref.onDispose(sub.cancel);

      final updatesSub = svc.requestUpdates.listen((request) {
        if (request.status == RequestStatus.pending) {
          notifier.upsert(request);
        } else {
          notifier.remove(request.requestId);
        }
      });
      ref.onDispose(updatesSub.cancel);

      return notifier;
    });

class PendingRequestsNotifier
    extends StateNotifier<Map<String, ConnectionRequest>> {
  PendingRequestsNotifier(this._ref) : super({});

  final Ref _ref;

  void seed(Map<String, ConnectionRequest> initial) {
    state = initial;
    _syncCount();
  }

  void upsert(ConnectionRequest request) {
    state = {...state, request.requestId: request};
    _syncCount();
  }

  void remove(String requestId) {
    final next = Map<String, ConnectionRequest>.from(state);
    next.remove(requestId);
    state = next;
    _syncCount();
  }

  void updateStatus(String requestId, RequestStatus status) {
    final existing = state[requestId];
    if (existing == null) return;
    existing.status = status;
    state = Map.from(state);
    _syncCount();
  }

  void _syncCount() {
    _ref.read(pendingRequestCountProvider.notifier).state = state.values
        .where(
          (r) =>
              r.direction == RequestDirection.incoming &&
              r.status == RequestStatus.pending,
        )
        .length;
  }
}

final blockedPeersProvider = StreamProvider<Set<String>>((ref) async* {
  final svc = ref.watch(requestServiceProvider);
  yield svc.blockedPeers;
  yield* svc.blockedPeersStream;
});

final incomingRequestCountProvider = Provider<int>((ref) {
  final Map<String, ConnectionRequest> requests = ref.watch(
    pendingRequestsProvider,
  );
  return requests.values
      .where(
        (r) =>
            r.direction == RequestDirection.incoming &&
            r.status == RequestStatus.pending,
      )
      .length;
});

final reconnectionCoordinatorProvider = Provider<ReconnectionCoordinator>((
  ref,
) {
  return ReconnectionCoordinatorImpl(
    messaging: ref.watch(messagingServiceProvider),
    requests: ref.watch(requestServiceProvider),
    discovery: ref.watch(discoveryCoordinatorProvider),
    profile: ref.watch(profileServiceProvider),
    session: ref.watch(sessionServiceProvider),
    localTcpPort: () => ref.read(activeTcpPortProvider),
  );
});

final reconnectServiceProvider = Provider<ReconnectService>((ref) {
  final svc = ReconnectService(
    messaging: ref.watch(messagingServiceProvider),
    requests: ref.watch(requestServiceProvider),
    discovery: ref.watch(discoveryCoordinatorProvider),
    profile: ref.watch(profileServiceProvider),
    session: ref.watch(sessionServiceProvider),
    localTcpPort: () => ref.read(activeTcpPortProvider),
    reconnectionCoordinator: ref.watch(reconnectionCoordinatorProvider),
  );
  ref.onDispose(svc.stop);
  return svc;
});
