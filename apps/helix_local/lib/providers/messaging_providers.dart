// Messaging providers: messaging service, threads, typing, one-way inbox.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/session_provider.dart' show activeChatCountProvider;
import 'package:helix/providers/infrastructure_providers.dart';
import 'package:helix/providers/controllers/messaging_service.dart';
import 'package:helix_local_messaging/helix_messaging.dart';

/// The threadId of the chat screen currently visible, or null when no chat is open.
final currentChatThreadIdProvider = StateProvider<String?>((ref) => null);

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

final threadChangesStreamProvider = StreamProvider<ChatThread>((ref) {
  return ref.watch(messagingServiceProvider).threadChanges;
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

final peerTypingProvider = StreamProvider.family<bool, String>((ref, threadId) {
  final messaging = ref.watch(messagingServiceProvider);
  return messaging.typingChanges
      .where((e) => e.key == threadId)
      .map((e) => e.value);
});

final oneWayInboxProvider = StreamProvider<List<OneWayMessage>>((ref) {
  final messaging = ref.watch(messagingServiceProvider);
  return messaging.oneWayInboxUpdates;
});

final totalUnreadProvider = Provider<int>((ref) {
  final threads = ref.watch(threadsProvider);
  return threads.values.fold(0, (sum, t) => sum + t.unreadCount);
});

final threadByIdProvider = Provider.family<ChatThread?, String>((
  ref,
  threadId,
) {
  return ref.watch(threadsProvider)[threadId];
});

