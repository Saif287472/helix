// lib/providers/app_providers.dart
//
// UI-layer providers. Core providers (profileServiceProvider, appInitProvider,
// profileProvider, sessionStateProvider) live in session_provider.dart and are
// re-exported here for convenience so screens only need one import.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:helix_local_storage/data/database.dart';
import 'package:helix_local_storage/data/database_provider.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix/providers/session_provider.dart';
import 'package:helix/providers/controllers/session_service.dart';
import 'package:helix/providers/controllers/tcp_server_service.dart';
import 'package:helix/providers/controllers/request_service.dart';
import 'package:helix/providers/controllers/messaging_service.dart';
import 'package:helix/providers/controllers/diagnostics_service.dart';
import 'package:helix/providers/controllers/reconnect_service.dart';
import 'package:helix/providers/controllers/file_transfer_service.dart';
import 'package:helix/providers/controllers/ephemeral_media_service.dart';
import 'package:helix/providers/controllers/group_service.dart';
import 'package:helix/providers/controllers/notification_service.dart';
import 'package:helix/providers/controllers/qr_code_service.dart';
import 'package:helix/providers/controllers/secret_code_service.dart';
import 'package:helix_local_platform/platform/android_foreground.dart';
import 'package:helix/providers/controllers/trust_service.dart';
import 'package:helix/app/composition_root.dart' show LocalCompositionRoot;
import 'package:helix/application/wipe/local_panic_wipe_orchestrator.dart';
import 'package:helix/services/app_logger.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix/application/connection/connection_request_use_case_impl.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:helix/application/trust/trust_use_case_impl.dart';

import 'package:helix/application/connection/reconnection_coordinator_impl.dart';
import 'package:helix/application/session/active_session_tracker_impl.dart';
import 'package:helix/application/diagnostics/diagnostics_use_case_impl.dart';
import 'package:helix/application/qr/qr_code_use_case_impl.dart';
import 'package:helix/application/secret_code/secret_code_use_case_impl.dart';
import 'package:helix/application/tcp_server/tcp_server_use_case_impl.dart';
import 'package:helix_local_domain/domain/call/call_state.dart';
import 'package:helix_local_calls/infrastructure/call/call_signaling_gateway_adapter.dart';
import 'package:helix_local_calls/services/call_service.dart';
import 'package:helix_local_discovery/helix_discovery.dart';
import 'package:helix_local_groups/helix_groups.dart';
import 'package:helix_local_groups/platform/multicast_lock_android.dart';
import 'package:helix_local_groups/platform/multicast_lock_stub.dart';
import 'package:helix_local_messaging/helix_messaging.dart';
import 'package:helix_local_transfer/helix_transfer.dart';

export 'package:flutter_riverpod/legacy.dart';

export 'package:helix/providers/session_provider.dart'
    show
        productDescriptorProvider,
        profileServiceProvider,
        appInitProvider,
        profileProvider,
        sessionStateProvider,
        activeChatCountProvider,
        pendingRequestCountProvider,
        hasActiveSessionProvider;

// ---------------------------------------------------------------------------
// Composition root — single wiring point for all concrete implementations
// ---------------------------------------------------------------------------

final compositionRootProvider = Provider<LocalCompositionRoot>((ref) {
  final descriptor = ref.watch(productDescriptorProvider);
  final root = LocalCompositionRoot.production(descriptor);
  ref.onDispose(root.dispose);
  return root;
});

// ---------------------------------------------------------------------------
// Repository / cache providers — expose domain interfaces, hide concrete types
// ---------------------------------------------------------------------------

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ref.watch(compositionRootProvider).conversationRepository;
});

final connectionRequestRepositoryProvider =
    Provider<ConnectionRequestRepository>((ref) {
      return ref.watch(compositionRootProvider).connectionRequestRepository;
    });

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return ref.watch(compositionRootProvider).groupRepository;
});

final transferRepositoryProvider = Provider<TransferRepository>((ref) {
  return ref.watch(compositionRootProvider).transferRepository;
});

final ephemeralMediaCacheProvider = Provider<EphemeralMediaCache>((ref) {
  return ref.watch(compositionRootProvider).ephemeralMediaCache;
});

// ---------------------------------------------------------------------------
// Service providers — each created once, lazily, kept alive for app lifetime
// ---------------------------------------------------------------------------

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return ref.watch(compositionRootProvider).sessionRepository;
});

final foregroundServiceGatewayProvider = Provider<ForegroundServiceGateway>((
  ref,
) {
  return ref.watch(compositionRootProvider).foregroundServiceGateway;
});

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

final disconnectWipeSchedulerProvider = Provider<DisconnectWipeScheduler>((
  ref,
) {
  return ref.watch(compositionRootProvider).wipeScheduler;
});

final messagingServiceProvider = Provider<MessagingService>((ref) {
  late final MessagingService service;

  final conversationRepository = ref.watch(conversationRepositoryProvider);
  final messageGateway = MessageGatewayAdapter(
    (threadId) => service.getChannel(threadId),
  );
  final messageCodec = MessageCodecAdapter();
  final wipeScheduler = ref.watch(disconnectWipeSchedulerProvider);

  final sendMessageUseCase = SendMessageUseCaseImpl(
    conversationRepository: conversationRepository,
    messageGateway: messageGateway,
    messageCodec: messageCodec,
    onNotify: (threadId) => service.notify(threadId),
    isAtCapacity: (threadId) => service.isAtCapacity(threadId),
    setAtCapacity: (threadId, atCapacity) =>
        service.setAtCapacity(threadId, atCapacity),
    onChannelFailed: (threadId) => service.detachChannel(threadId),
  );

  final receiveMessageCoordinator = ReceiveMessageCoordinatorImpl(
    conversationRepository: conversationRepository,
    onNotify: (threadId) => service.notify(threadId),
    isAtCapacity: (threadId) => service.isAtCapacity(threadId),
    isDuplicate: (threadId, messageId) =>
        service.isDuplicate(threadId, messageId),
    markSeen: (threadId, messageId) => service.markSeen(threadId, messageId),
    setAtCapacity: (threadId, atCapacity) =>
        service.setAtCapacity(threadId, atCapacity),
  );

  final deliveryReceiptTracker = DeliveryReceiptTrackerImpl(
    conversationRepository: conversationRepository,
    onNotify: (threadId) => service.notify(threadId),
  );

  service = MessagingService(
    conversationRepository: conversationRepository,
    sendMessageUseCase: sendMessageUseCase,
    receiveMessageCoordinator: receiveMessageCoordinator,
    deliveryReceiptTracker: deliveryReceiptTracker,
    wipeScheduler: wipeScheduler,
  );

  ref.onDispose(service.dispose);

  return service;
});

final diagnosticsGatewayProvider = Provider<DiagnosticsGateway>((ref) {
  return ref.watch(compositionRootProvider).diagnosticsGateway;
});

final diagnosticsUseCaseProvider = Provider<DiagnosticsUseCase>((ref) {
  return DiagnosticsUseCaseImpl(gateway: ref.watch(diagnosticsGatewayProvider));
});

final diagnosticsServiceProvider = Provider<DiagnosticsService>((ref) {
  return DiagnosticsService(useCase: ref.watch(diagnosticsUseCaseProvider));
});

final qrCodeUseCaseProvider = Provider<QrCodeUseCase>((ref) {
  final useCase = const QrCodeUseCaseImpl();
  QrCodeService.globalUseCase = useCase;
  return useCase;
});

final qrCodeServiceProvider = Provider<QrCodeService>((ref) {
  return QrCodeService(useCase: ref.watch(qrCodeUseCaseProvider));
});

final secretCodeUseCaseProvider = Provider<SecretCodeUseCase>((ref) {
  final useCase = SecretCodeUseCaseImpl();
  SecretCodeService.globalUseCase = useCase;
  return useCase;
});

final secretCodeServiceProvider = Provider<SecretCodeService>((ref) {
  return SecretCodeService(useCase: ref.watch(secretCodeUseCaseProvider));
});

final notificationGatewayProvider = Provider<NotificationGateway>((ref) {
  return ref.watch(compositionRootProvider).notificationGateway;
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final svc = NotificationService(
    notificationGateway: ref.watch(notificationGatewayProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

final trustRepositoryProvider = Provider<TrustRepository>((ref) {
  return ref.watch(compositionRootProvider).trustRepository;
});

final trustUseCaseProvider = Provider<TrustUseCase>((ref) {
  final useCase = TrustUseCaseImpl(
    repository: ref.watch(trustRepositoryProvider),
  );
  ref.onDispose(useCase.dispose);
  return useCase;
});

final trustServiceProvider = Provider<TrustService>((ref) {
  final svc = TrustService(trustUseCase: ref.watch(trustUseCaseProvider));
  ref.onDispose(svc.dispose);
  return svc;
});

final knownPeersProvider = StreamProvider<List<KnownPeer>>((ref) {
  return ref.watch(trustServiceProvider).changes;
});

final discoveryCoordinatorProvider = Provider<DiscoveryCoordinator>((ref) {
  final descriptor = ref.watch(productDescriptorProvider);
  final coordinator = DiscoveryCoordinator(
    secretCodeUseCase: ref.watch(secretCodeUseCaseProvider),
    mdns: MdnsDiscovery(
      methodChannelName: '${descriptor.methodChannelNamespace}/mdns',
      eventChannelName: '${descriptor.methodChannelNamespace}/mdns/events',
    ),
  );
  ref.onDispose(() => coordinator.dispose().ignore());
  return coordinator;
});

final tcpServerUseCaseProvider = Provider<TcpServerUseCase>((ref) {
  final useCase = TcpServerUseCaseImpl();
  TcpServerService.globalUseCase = useCase;
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

/// Async database provider — initializes the SQLite database on first access.
/// Port for the app's active request listener.
///
/// Home owns the plain TCP listener used by nearby, direct-IP, and QR request
/// flows. Screens that need to advertise the current session read this value
/// instead of creating a second listener.
final activeTcpPortProvider = StateProvider<int>((ref) => 0);

/// The threadId of the chat screen currently visible, or null when no chat is open.
/// Set by ChatScreen on mount/unmount; used to suppress in-app banners for the open thread.
final currentChatThreadIdProvider = StateProvider<String?>((ref) => null);

/// Stream of individual ChatThread updates — fires whenever a thread changes.
final threadChangesStreamProvider = StreamProvider<ChatThread>((ref) {
  return ref.watch(messagingServiceProvider).threadChanges;
});

final databaseProvider = FutureProvider<HelixDatabase>((ref) async {
  ref.onDispose(() {
    DatabaseProvider.close();
  });
  final descriptor = ref.watch(productDescriptorProvider);
  return DatabaseProvider.initialize(databaseFilename: descriptor.databaseFilename);
});

/// Application lifecycle state.
final appStateProvider = StateProvider<AppState>((ref) {
  final profileSvc = ref.watch(profileServiceProvider);
  if (profileSvc.isFirstRun) return AppState.firstRun;
  final session = ref.watch(sessionStateProvider);
  switch (session.phase) {
    case SessionPhase.active:
      return AppState.sessionActive;
    case SessionPhase.starting:
    case SessionPhase.stopping:
      return AppState.sessionActive;
    case SessionPhase.idle:
      return AppState.setupComplete;
  }
});

// ---------------------------------------------------------------------------
// Derived state providers
// ---------------------------------------------------------------------------

/// Convenience: just the first-run flag (does not stream; read once after init).
final isFirstRunProvider = Provider<bool>((ref) {
  return ref.watch(profileServiceProvider).isFirstRun;
});

/// Live list of nearby peers from the discovery coordinator.
final nearbyPeersProvider = StreamProvider<List<Peer>>((ref) {
  return ref.watch(discoveryCoordinatorProvider).peerListChanges;
});

/// Trusted peers cross-referenced with nearby peers for online status.
/// A trusted peer is "online" when a nearby peer shares the same deviceSuffix.
typedef TrustedPeerPresence = ({KnownPeer peer, Peer? nearbyMatch});

final trustedPeersWithPresenceProvider = Provider<List<TrustedPeerPresence>>((
  ref,
) {
  final trusted =
      ref
          .watch(knownPeersProvider)
          .value
          ?.where((p) => p.trusted)
          .toList() ??
      [];
  final nearby = ref.watch(nearbyPeersProvider).value ?? [];
  return trusted.map((p) {
    final match = nearby.cast<Peer?>().firstWhere(
      (n) => n!.deviceSuffix == p.deviceSuffix,
      orElse: () => null,
    );
    return (peer: p, nearbyMatch: match);
  }).toList();
});

/// All pending connection requests (incoming + outgoing), updated live.
final pendingRequestsProvider =
    StateNotifierProvider<
      PendingRequestsNotifier,
      Map<String, ConnectionRequest>
    >((ref) {
      final notifier = PendingRequestsNotifier(ref);
      final svc = ref.watch(requestServiceProvider);

      // Seed with whatever is already pending.
      notifier.seed(Map.from(svc.pendingRequests));

      // Listen for incoming request events.
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

final oneWayMessageBridgeProvider = Provider<void>((ref) {
  final requestService = ref.watch(requestServiceProvider);
  final messagingService = ref.watch(messagingServiceProvider);
  final sub = requestService.incomingOneWayMessages.listen(
    messagingService.receiveOneWayMessage,
  );
  ref.onDispose(sub.cancel);
});

final threadsProvider =
    StateNotifierProvider<ThreadsNotifier, Map<String, ChatThread>>((ref) {
      final service = ref.watch(messagingServiceProvider);
      return ThreadsNotifier(ref, service);
    });

class ThreadsNotifier extends StateNotifier<Map<String, ChatThread>> {
  ThreadsNotifier(this._ref, MessagingService service)
    : _service = service,
      super(_snapshotThreads(service.threads)) {
    _syncActiveCount();
    _sub = _service.threadUpdates.listen((threads) {
      if (!mounted) return;
      state = _snapshotThreads(threads);
      _syncActiveCount();
    });
  }

  final Ref _ref;
  final MessagingService _service;
  late final StreamSubscription<Map<String, ChatThread>> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void refresh() {
    state = _snapshotThreads(_service.threads);
    _syncActiveCount();
  }

  void _syncActiveCount() {
    _ref.read(activeChatCountProvider.notifier).state = state.values
        .where((thread) => thread.status == ThreadStatus.active)
        .length;
  }
}

// ---------------------------------------------------------------------------
// Favorites — sessionIds of pinned peers, backed by the SQLite peers_cache
// ---------------------------------------------------------------------------

final favoritePeersProvider =
    StateNotifierProvider<FavoritePeersNotifier, Set<String>>((ref) {
      return FavoritePeersNotifier(ref);
    });

class FavoritePeersNotifier extends StateNotifier<Set<String>> {
  FavoritePeersNotifier(this._ref) : super(const {}) {
    _init();
  }

  final Ref _ref;

  Future<void> _init() async {
    final db = await _ref.read(databaseProvider.future);
    if (!mounted) return;
    final ids = db.getFavoritePeers().map((p) => p.sessionId).toSet();
    state = ids;
  }

  Future<void> toggle(Peer peer) async {
    final db = await _ref.read(databaseProvider.future);
    final isFav = state.contains(peer.sessionId);
    db.upsertPeerCache(peer, isFavorite: !isFav);
    state = isFav
        ? (Set<String>.from(state)..remove(peer.sessionId))
        : {...state, peer.sessionId};
  }
}

// Provider that returns all favorite Peer objects from DB (for home screen).
final favoritePeerListProvider = FutureProvider<List<Peer>>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return db.getFavoritePeers();
});

// ---------------------------------------------------------------------------
// Reconnect service — auto-reconnects disconnected threads
// ---------------------------------------------------------------------------

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

// Provider that activates the reconnect service when watched.
final reconnectBridgeProvider = Provider<void>((ref) {
  final svc = ref.watch(reconnectServiceProvider);
  svc.start();
});

// Wires the auto-resume callback and forwards silently accepted channels to
// MessagingService without surfacing them in the Requests UI.
final resumeAutoAcceptBridgeProvider = Provider<void>((ref) {
  final requestService = ref.watch(requestServiceProvider);
  final messagingService = ref.watch(messagingServiceProvider);
  final profileService = ref.watch(profileServiceProvider);
  final sessionService = ref.watch(sessionServiceProvider);

  requestService.setResumeCheck((peerFingerprint) async {
    if (!messagingService.shouldAutoResume(peerFingerprint)) return null;
    final identity = profileService.identity;
    final sessionId = sessionService.sessionId;
    if (identity == null || sessionId.isEmpty) return null;
    return (identity: identity, sessionId: sessionId);
  });

  final sub = requestService.resumeChannels.listen((autoResume) {
    messagingService.attachChannel(
      autoResume.threadId,
      autoResume.peerDisplayName,
      autoResume.peerDeviceSuffix,
      autoResume.channel,
      autoResume.peerSessionId,
      autoResume.peerHost,
      autoResume.peerPort,
    );
    messagingService.injectSystemMessage(autoResume.threadId, 'Reconnected.');
  });
  ref.onDispose(sub.cancel);
});

// Injects TrustService into MessagingService and RequestService.
final trustBridgeProvider = Provider<void>((ref) {
  final trust = ref.watch(trustServiceProvider);
  final messaging = ref.watch(messagingServiceProvider);
  final requests = ref.watch(requestServiceProvider);
  messaging.setTrustService(trust);
  requests.setTrustService(trust);
});

// Fires showNewMessage when a remote message arrives on a non-open thread.
final newMessageNotificationBridgeProvider = Provider<void>((ref) {
  final notif = ref.watch(notificationServiceProvider);
  final messaging = ref.watch(messagingServiceProvider);

  final sub = messaging.threadChanges.listen((thread) {
    final last = thread.lastMessage;
    if (last == null || last.origin == MessageOrigin.local || last.isSystem) {
      return;
    }
    if (ref.read(currentChatThreadIdProvider) == thread.threadId) return;
    final profile = ref.read(profileServiceProvider).profile;
    notif.showNewMessage(
      thread.peerDisplayName,
      profile?.notifyShowSender ?? false,
      threadId: thread.threadId,
      soundEnabled: profile?.notifySound ?? true,
    );
  });
  ref.onDispose(sub.cancel);
});

// Wires notification actions (direct-reply, mark-as-read, call accept/decline)
// to MessagingService / CallService.
final notificationActionBridgeProvider = Provider<void>((ref) {
  final notif = ref.watch(notificationServiceProvider);
  final messaging = ref.watch(messagingServiceProvider);

  final sub = notif.actions.listen((intent) {
    switch (intent.actionId) {
      case 'accept_call':
        ref.read(callServiceProvider).acceptIncomingCall();
        return;
      case 'decline_call':
        ref.read(callServiceProvider).declineIncomingCall();
        return;
    }

    final threadId = intent.threadId;
    if (threadId == null || threadId.isEmpty) return;

    switch (intent.actionId) {
      case 'reply':
        final text = intent.input?.trim() ?? '';
        if (text.isNotEmpty) {
          unawaited(
            messaging.sendMessage(threadId, text).then((_) {
              return notif.cancelAll();
            }).catchError((_) {}),
          );
        }
      case 'mark_read':
        messaging.markThreadRead(threadId);
        unawaited(notif.cancelAll().catchError((_) {}));
    }
  });
  ref.onDispose(sub.cancel);
});

/// Live set of blocked peer fingerprints (session-only, resets on app restart).
final blockedPeersProvider = StreamProvider<Set<String>>((ref) async* {
  final svc = ref.watch(requestServiceProvider);
  yield svc.blockedPeers;
  yield* svc.blockedPeersStream;
});

/// Emits the payload string whenever the user taps a notification body.
final notificationTapsProvider = StreamProvider<String>((ref) {
  return ref.watch(notificationServiceProvider).taps;
});

/// True when the device has at least one usable network interface.
final hasConnectivityProvider = StreamProvider<bool>((ref) async* {
  final conn = Connectivity();
  final initial = await conn.checkConnectivity();
  yield initial.any((r) => r != ConnectivityResult.none);
  yield* conn.onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});

// ---------------------------------------------------------------------------
// File transfer service
// ---------------------------------------------------------------------------

final fileTransferServiceProvider = Provider<FileTransferService>((ref) {
  final messaging = ref.watch(messagingServiceProvider);
  final repo = ref.watch(transferRepositoryProvider);

  final sendFileUseCase = SendFileUseCaseImpl(
    onProgressUpdate: (threadId, messageId, progress, {localFilePath}) {
      messaging.updateTransferProgress(
        threadId,
        messageId,
        progress,
        localFilePath: localFilePath,
      );
    },
  );

  final receiveFileCoordinator = ReceiveFileCoordinatorImpl(
    repository: repo,
    onProgressUpdate: (threadId, messageId, progress, {localFilePath}) {
      messaging.updateTransferProgress(
        threadId,
        messageId,
        progress,
        localFilePath: localFilePath,
      );
    },
    getCacheDirectory: () => getApplicationCacheDirectory(),
    getFinalDirectory: _helixMediaDir,
  );
  ref.onDispose(() => receiveFileCoordinator.dispose().ignore());

  return FileTransferService(
    sendFileUseCase: sendFileUseCase,
    receiveFileCoordinator: receiveFileCoordinator,
  );
});

final ephemeralMediaServiceProvider = Provider<EphemeralMediaService>((ref) {
  final messaging = ref.watch(messagingServiceProvider);
  final cache = ref.watch(ephemeralMediaCacheProvider);

  final sendEphemeralMediaUseCase = SendEphemeralMediaUseCaseImpl(
    cache: cache,
    onProgressUpdate: (threadId, messageId, progress, {localFilePath}) {
      messaging.updateTransferProgress(
        threadId,
        messageId,
        progress,
        localFilePath: localFilePath,
      );
    },
  );

  final receiveEphemeralMediaCoordinator = ReceiveEphemeralMediaCoordinatorImpl(
    cache: cache,
  );
  ref.onDispose(receiveEphemeralMediaCoordinator.dispose);

  return EphemeralMediaService(
    cache: cache,
    sendEphemeralMediaUseCase: sendEphemeralMediaUseCase,
    receiveEphemeralMediaCoordinator: receiveEphemeralMediaCoordinator,
  );
});

final groupServiceProvider = Provider<GroupService>((ref) {
  late final GroupService service;

  final repository = ref.watch(groupRepositoryProvider);
  final gateway = GroupSignalingGatewayAdapter(
    (peerFingerprint) => service.getChannel(peerFingerprint),
  );

  final createGroupUseCase = CreateGroupUseCaseImpl(
    repository: repository,
    localFingerprint: () => service.localFingerprint,
    localDisplayName: () => service.localDisplayName,
    localDeviceSuffix: () => service.localDeviceSuffix,
    localEndpoint: () => service.localEndpoint,
    onNotify: () => service.notify(),
  );

  final electionEngine = GroupElectionEngineImpl(
    repository: repository,
    onNotify: () => service.notify(),
  );

  final messageRouter = GroupMessageRouterImpl(
    repository: repository,
    gateway: gateway,
    localFingerprint: () => service.localFingerprint,
    onReceipt: (receipt) => service.emitMessageReceipt(receipt),
  );

  service = GroupService(
    repository: repository,
    createGroupUseCase: createGroupUseCase,
    electionEngine: electionEngine,
    messageRouter: messageRouter,
  );

  ref.onDispose(service.dispose);
  return service;
});

/// Wires FileTransferService into MessagingService so all incoming file frames
/// (chunk, probe, complete, cancel) are routed to the transfer service.
final fileTransferBridgeProvider = Provider<void>((ref) {
  final messaging = ref.watch(messagingServiceProvider);
  final fileTransfer = ref.watch(fileTransferServiceProvider);
  final ephemeralMedia = ref.watch(ephemeralMediaServiceProvider);
  final repository = ref.watch(transferRepositoryProvider);

  messaging.setFileChunkHandler((threadId, messageId, frame) async {
    final file = await fileTransfer.receiveChunk(
      threadId: threadId,
      messageId: messageId,
      frame: frame,
    );
    if (file == null) {
      final active = repository.loadTransfer(frame.fileId);
      if (active == null) {
        messaging.removeFileMessage(threadId, frame.fileId);
      }
    }
  });

  messaging.setFileProbeHandler((threadId, messageId, frame, channel) async {
    await fileTransfer.receiveProbe(
      threadId: threadId,
      messageId: messageId,
      frame: frame,
      channel: channel,
    );
    final active = repository.loadTransfer(frame.fileId);
    if (active == null) {
      messaging.removeFileMessage(threadId, frame.fileId);
    }
  });

  messaging.setFileCompleteHandler((threadId, messageId, fileId, sha256) async {
    await fileTransfer.receiveComplete(
      threadId: threadId,
      messageId: messageId,
      fileId: fileId,
      expectedSha256: sha256,
    );
  });

  messaging.setFileCancelHandler((threadId, fileId) async {
    await fileTransfer.cancelTransfer(fileId);
  });

  messaging.setEphemeralMediaChunkHandler((threadId, messageId, frame) async {
    final completed = ephemeralMedia.receiveChunk(frame);
    if (completed == null && !ephemeralMedia.isAssembling(frame.mediaId)) {
      messaging.removeFileMessage(threadId, frame.mediaId);
      return;
    }
    final validProgressFrame =
        frame.chunkCount > 0 &&
        frame.chunkIndex >= 0 &&
        frame.chunkIndex < frame.chunkCount;
    final progress = completed == null && validProgressFrame
        ? (frame.chunkIndex + 1) / frame.chunkCount
        : null;
    messaging.updateTransferProgress(threadId, messageId, progress);
  });
});

/// Watches the active chat count AND the current call, keeping the Android
/// foreground service alive (with the `microphone` type so the OS does not
/// cut mic capture once the app is backgrounded) for as long as either chats
/// are kept in memory or a call is in progress. No-op on non-Android
/// platforms.
final foregroundServiceBridgeProvider = Provider<void>((ref) {
  var running = false;
  Future<void> operation = Future.value();

  String callText(CallState call) {
    switch (call.status) {
      case CallStatus.ringing:
        return call.direction == CallDirection.incoming
            ? 'Incoming call from ${call.peerDisplayName}'
            : 'Calling ${call.peerDisplayName}…';
      case CallStatus.offering:
        return 'Calling ${call.peerDisplayName}…';
      case CallStatus.connecting:
        return 'Connecting call with ${call.peerDisplayName}';
      default:
        return 'Call with ${call.peerDisplayName}';
    }
  }

  void sync() {
    operation = operation.then((_) async {
      final chatCount = ref.read(activeChatCountProvider);
      final call = ref.read(currentCallProvider).value;
      final inCall = call != null && call.isInProgress;
      final shouldRun = inCall || chatCount > 0;

      if (!shouldRun) {
        if (running) {
          await AndroidForegroundService.stopService().catchError((_) {});
          running = false;
        }
        return;
      }

      final text = inCall
          ? callText(call)
          : (chatCount == 1
                ? 'Keeping 1 chat active in memory'
                : 'Keeping $chatCount chats active in memory');

      if (!running) {
        try {
          await AndroidForegroundService.startService(inCall: inCall);
          running = true;
          await AndroidForegroundService.updateNotificationText(text, inCall: inCall);
        } catch (_) {
          running = false;
        }
      } else {
        await AndroidForegroundService.updateNotificationText(text, inCall: inCall).catchError((_) {});
      }
    }).catchError((_) {
      running = false;
    });
  }

  ref.listen<int>(activeChatCountProvider, (_, _) => sync());
  ref.listen<AsyncValue<CallState?>>(currentCallProvider, (_, _) => sync());
});

final groupBridgeProvider = Provider<void>((ref) {
  final groupService = ref.watch(groupServiceProvider);
  final messaging = ref.watch(messagingServiceProvider);
  final profileService = ref.watch(profileServiceProvider);
  final identity = profileService.identity;
  final profile = profileService.profile;
  final port = ref.watch(activeTcpPortProvider);

  if (identity != null && profile != null) {
    groupService.configureLocalIdentity(
      fingerprint: identity.staticPublicKeyFingerprint,
      displayName: profile.displayName,
      deviceSuffix: identity.deviceSuffix,
      endpoint: port > 0 ? '0.0.0.0:$port' : '',
    );
  }

  groupService.connectChannelCallback = (fingerprint, endpoint) async {
    final active = messaging.getChannel(fingerprint);
    if (active != null) return active;

    if (endpoint.isEmpty) return null;

    final parts = endpoint.split(':');
    if (parts.length != 2) return null;
    final host = parts[0];
    final portVal = int.tryParse(parts[1]) ?? 4040;

    final peers = ref.read(nearbyPeersProvider).value ?? [];
    final peer = peers.cast<Peer?>().firstWhere(
      (p) => p!.host == host && p.port == portVal,
      orElse: () => Peer(
        sessionId: '',
        displayName: 'Host',
        deviceSuffix: '',
        host: host,
        port: portVal,
        source: PeerSource.directIp,
        seenAt: DateTime.now(),
        protocolMajor: kProtocolMajor,
        protocolMinor: kProtocolMinor,
      ),
    )!;

    try {
      final result = await ref.read(requestServiceProvider).sendRequest(
        peer,
        RequestSourceMethod.nearby,
        identity!,
        ref.read(sessionServiceProvider).sessionId,
        profile?.displayName ?? '',
        localTcpPort: port > 0 ? port : portVal,
      );
      return result.channel;
    } catch (_) {
      return null;
    }
  };

  groupService.resolvePeerDetails = (fingerprint) {
    final known = ref.read(trustServiceProvider).getPeer(fingerprint);
    if (known != null) {
      return (
        displayName: known.nickname ?? known.displayName,
        deviceSuffix: known.deviceSuffix,
        endpoint: '',
      );
    }
    final thread = ref.read(conversationRepositoryProvider).getThread(fingerprint);
    if (thread != null) {
      return (
        displayName: thread.peerDisplayName,
        deviceSuffix: thread.peerDeviceSuffix,
        endpoint: '',
      );
    }
    return (
      displayName: fingerprint.substring(0, 8),
      deviceSuffix: '',
      endpoint: '',
    );
  };

  groupService.getActivePeerFingerprints = () {
    return messaging.activeChannelFingerprints;
  };

  messaging.setGroupControlHandler((threadId, frame, channel) async {
    groupService.registerPeerChannel(threadId, channel);
    await groupService.handleControlFrame(
      peerFingerprint: threadId,
      channel: channel,
      frame: frame,
    );
  });

  messaging.setGroupMessageHandler((threadId, frame, channel) async {
    groupService.registerPeerChannel(threadId, channel);
    await groupService.handleMessageFrame(
      peerFingerprint: threadId,
      channel: channel,
      frame: frame,
    );
  });

  final subThreadChanges = messaging.threadChanges.listen((thread) {
    final threadId = thread.threadId;
    final lobby = groupService.groups.cast<GroupSnapshot?>().firstWhere(
      (g) => g!.groupId == GroupService.publicLobbyId,
      orElse: () => null,
    );
    if (lobby != null && lobby.hostFingerprint == threadId && threadId != identity?.staticPublicKeyFingerprint) {
      final active = lobby.members
          .map((m) => m.fingerprint)
          .where((fp) => fp == identity?.staticPublicKeyFingerprint || messaging.getChannel(fp) != null)
          .toList();

      if (active.isNotEmpty) {
        final elected = groupService.electHostAfterCrash(
          GroupService.publicLobbyId,
          activeFingerprints: active,
        );
        if (elected.hostFingerprint != identity?.staticPublicKeyFingerprint) {
          unawaited(groupService.joinGroup(
            groupId: GroupService.publicLobbyId,
            hostFingerprint: elected.hostFingerprint,
            hostEndpoint: elected.hostEndpoint,
            epoch: elected.epoch,
          ).catchError((Object e, StackTrace s) {}));
        }
      } else {
        unawaited(groupService.leaveGroup(GroupService.publicLobbyId)
            .catchError((Object e, StackTrace s) {}));
      }
    }
  });

  final subMessageReceipts = groupService.messageReceipts.listen((receipt) {
    try {
      final payloadStr = utf8.decode(receipt.encryptedPayload);
      final json = jsonDecode(payloadStr);
      if (json is Map && json['type'] == 'sync') {
        final membersJson = (json['members'] as List).cast<Map<String, dynamic>>();
        final newMembers = membersJson.map((m) => GroupMember(
          fingerprint: m['fingerprint'] as String,
          displayName: m['displayName'] as String,
          deviceSuffix: m['deviceSuffix'] as String,
          endpoint: m['endpoint'] as String,
          joinedAt: DateTime.now(),
          isAdmin: m['isAdmin'] as bool? ?? false,
        )).toList();

        final repo = ref.read(groupRepositoryProvider);
        final group = repo.loadGroup(receipt.groupId);
        if (group != null) {
          final updated = GroupSnapshot(
            groupId: group.groupId,
            name: group.name,
            visibility: group.visibility,
            hostFingerprint: group.hostFingerprint,
            hostEndpoint: group.hostEndpoint,
            epoch: group.epoch,
            membershipVersion: group.membershipVersion,
            members: newMembers,
            pending: group.pending,
            banned: group.banned,
          );
          repo.saveGroup(updated);
          groupService.notify();
        }
      }
    } catch (_) {}
  });

  ref.onDispose(() {
    subThreadChanges.cancel();
    subMessageReceipts.cancel();
  });

});

final groupSnapshotsProvider = StreamProvider<List<GroupSnapshot>>((
  ref,
) async* {
  final service = ref.watch(groupServiceProvider);
  yield service.groups;
  yield* service.groupUpdates;
});

class GroupMessage {
  const GroupMessage({
    required this.messageId,
    required this.groupId,
    required this.senderFingerprint,
    required this.text,
    required this.sentAt,
  });

  final String messageId;
  final String groupId;
  final String senderFingerprint;
  final String text;
  final DateTime sentAt;
}

class GroupMessagesNotifier extends StateNotifier<List<GroupMessage>> {
  GroupMessagesNotifier(this._groupService, this._groupId) : super([]) {
    _sub = _groupService.messageReceipts.listen((receipt) {
      if (!mounted || receipt.groupId != _groupId) return;
      try {
        final payloadStr = utf8.decode(receipt.encryptedPayload);
        final json = jsonDecode(payloadStr);
        if (json is Map && json['type'] == 'text') {
          final msg = GroupMessage(
            messageId: receipt.messageId,
            groupId: receipt.groupId,
            senderFingerprint: receipt.senderFingerprint,
            text: json['text'] as String,
            sentAt: DateTime.now(),
          );
          final nextState = [...state, msg];
          if (nextState.length > kMaxRetainedGroupMessages) {
            state = nextState.sublist(nextState.length - kMaxRetainedGroupMessages);
          } else {
            state = nextState;
          }
        }
      } catch (_) {}
    });
  }

  final GroupService _groupService;
  final String _groupId;
  StreamSubscription<dynamic>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> sendMessage(String text) async {
    final payload = jsonEncode({
      'type': 'text',
      'text': text,
    });
    await _groupService.sendGroupPayload(
      groupId: _groupId,
      encryptedPayload: utf8.encode(payload),
    );
  }
}

final groupMessagesProvider = StateNotifierProvider.family<GroupMessagesNotifier, List<GroupMessage>, String>((ref, groupId) {
  final groupService = ref.watch(groupServiceProvider);
  return GroupMessagesNotifier(groupService, groupId);
});

// ---------------------------------------------------------------------------
// LAN Lobby providers
// ---------------------------------------------------------------------------

final lanLobbyServiceProvider = Provider<LanLobbyService>((ref) {
  final descriptor = ref.watch(productDescriptorProvider);
  final service = LanLobbyService(
    multicastLock: Platform.isAndroid
        ? MulticastLockAndroid('${descriptor.methodChannelNamespace}/multicast_lock')
        : MulticastLockStub(),
  );
  ref.onDispose(service.dispose);
  return service;
});

final lanLobbyStateProvider = StreamProvider<LobbyState?>((ref) {
  return ref.watch(lanLobbyServiceProvider).stateStream;
});

class _LanLobbyMessagesNotifier extends StateNotifier<List<LobbyMessage>> {
  _LanLobbyMessagesNotifier(LanLobbyService service) : super([]) {
    _sub = service.messageStream.listen((msg) {
      if (!mounted) return;
      final nextState = [...state, msg];
      if (nextState.length > kMaxRetainedLobbyMessages) {
        state = nextState.sublist(nextState.length - kMaxRetainedLobbyMessages);
      } else {
        state = nextState;
      }
    });
  }

  late final StreamSubscription<LobbyMessage> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final lanLobbyMessagesProvider =
    StateNotifierProvider<_LanLobbyMessagesNotifier, List<LobbyMessage>>((ref) {
  return _LanLobbyMessagesNotifier(ref.watch(lanLobbyServiceProvider));
});

// ---------------------------------------------------------------------------
// Typing state (Phase 3.2)
// ---------------------------------------------------------------------------

/// Emits true/false when the peer in [threadId] starts/stops typing.
final peerTypingProvider = StreamProvider.family<bool, String>((ref, threadId) {
  final messaging = ref.watch(messagingServiceProvider);
  return messaging.typingChanges
      .where((e) => e.key == threadId)
      .map((e) => e.value);
});

// ---------------------------------------------------------------------------
// One-way inbox (Phase 3.7)
// ---------------------------------------------------------------------------

final oneWayInboxProvider = StreamProvider<List<OneWayMessage>>((ref) {
  final messaging = ref.watch(messagingServiceProvider);
  return messaging.oneWayInboxUpdates;
});

/// Total unread message count across all threads.
final totalUnreadProvider = Provider<int>((ref) {
  final threads = ref.watch(threadsProvider);
  return threads.values.fold(0, (sum, t) => sum + t.unreadCount);
});

/// Count of pending incoming requests (for badge).
final incomingRequestCountProvider = Provider<int>((ref) {
  final Map<String, ConnectionRequest> requests =
      ref.watch(pendingRequestsProvider);
  return requests.values
      .where(
        (r) =>
            r.direction == RequestDirection.incoming &&
            r.status == RequestStatus.pending,
      )
      .length;
});

/// Single thread by ID.
final threadByIdProvider = Provider.family<ChatThread?, String>((
  ref,
  threadId,
) {
  return ref.watch(threadsProvider)[threadId];
});

Map<String, ChatThread> _snapshotThreads(Map<String, ChatThread> threads) {
  return Map.unmodifiable(
    threads.map((id, thread) => MapEntry(id, _snapshotThread(thread))),
  );
}

ChatThread _snapshotThread(ChatThread thread) {
  return ChatThread(
    threadId: thread.threadId,
    peerDisplayName: thread.peerDisplayName,
    peerDeviceSuffix: thread.peerDeviceSuffix,
    peerStaticKeyFingerprint: thread.peerStaticKeyFingerprint,
    peerSessionId: thread.peerSessionId,
    peerHost: thread.peerHost,
    peerPort: thread.peerPort,
    status: thread.status,
    messages: List<ChatMessage>.of(thread.messages),
    unreadCount: thread.unreadCount,
    hasNewSessionSeparator: thread.hasNewSessionSeparator,
    isArchived: thread.isArchived,
    draftText: thread.draftText,
    manuallyDisconnected: thread.manuallyDisconnected,
    disconnectedAt: thread.disconnectedAt,
  );
}

// ---------------------------------------------------------------------------
// Call service (Stage 6 — WebRTC voice calls)
// ---------------------------------------------------------------------------

/// Wires a [CallService] backed by the WebRTC engine from the composition root
/// and a signaling gateway that routes call frames through active [SecureChannel]s.
final callServiceProvider = Provider<CallService>((ref) {
  final messaging = ref.watch(messagingServiceProvider);
  final engine = ref.watch(compositionRootProvider).callEngine;

  final signalingGateway = CallSignalingGatewayAdapter(
    (peerId) => messaging.getChannel(peerId),
  );

  final service = CallService(
    engine: engine,
    signalingGateway: signalingGateway,
  );

  messaging.setCallSignalHandler(service.handleSignal);
  ref.onDispose(() => service.dispose());
  return service;
});

/// The state of the current call (null when idle), updated on every transition.
final currentCallProvider = StreamProvider<CallState?>((ref) {
  return ref.watch(callServiceProvider).callStateStream;
});

/// Whether the in-progress call screen is shrunk to a small floating bar.
/// Presentation-only state — not part of [CallState] since it's a UI concern.
final callMinimizedProvider = StateProvider<bool>((ref) => false);

/// Mirrors [WidgetsBindingObserver.didChangeAppLifecycleState] so non-widget
/// controllers (e.g. the incoming-call alert) can check foreground/background
/// without registering a second observer.
final appLifecycleStateProvider = StateProvider<AppLifecycleState>(
  (ref) => AppLifecycleState.resumed,
);

// ---------------------------------------------------------------------------
// Media directory helpers
// ---------------------------------------------------------------------------

String _mediaCategoryForMime(String mimeType) {
  if (mimeType.startsWith('image/')) return 'Images';
  if (mimeType.startsWith('audio/')) return 'Audio';
  if (mimeType.startsWith('video/')) return 'Video';
  return 'Others';
}

Future<Directory> _helixMediaDir(String mimeType) async {
  Directory? base;
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    base = await getDownloadsDirectory();
  }
  // Android: getDownloadsDirectory() returns null; use external storage.
  base ??= await getExternalStorageDirectory();
  // Ultimate fallback (should not be reached in practice).
  base ??= await getApplicationDocumentsDirectory();

  final dir = Directory(
    p.join(base.path, 'Helix', 'Media', _mediaCategoryForMime(mimeType)),
  );
  await dir.create(recursive: true);
  return dir;
}

// ---------------------------------------------------------------------------
// Panic wipe orchestrator (P6-024)
// ---------------------------------------------------------------------------

/// Resolves to a fully-wired [LocalPanicWipeOrchestrator] scoped to this
/// Riverpod container. Async because it needs the database handle.
final panicWipeOrchestratorProvider =
    FutureProvider<LocalPanicWipeOrchestrator>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final descriptor = ref.watch(productDescriptorProvider);
  return LocalPanicWipeOrchestrator(
    messaging: ref.watch(messagingServiceProvider),
    discovery: ref.watch(discoveryCoordinatorProvider),
    groupService: ref.watch(groupServiceProvider),
    wipeScheduler: ref.watch(disconnectWipeSchedulerProvider),
    database: db,
    reconnect: ref.watch(reconnectServiceProvider),
    tcpServer: ref.watch(tcpServerServiceProvider),
    storagePrefix: descriptor.secureStoragePrefix,
    notifications: ref.watch(notificationGatewayProvider),
    onClearLogs: AppLogger.instance.clearLogs,
  );
});
