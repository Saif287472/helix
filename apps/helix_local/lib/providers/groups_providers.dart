// Group providers: group service, LAN lobby, group messages.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix/providers/session_provider.dart'
    show productDescriptorProvider;
import 'package:helix/providers/infrastructure_providers.dart';
import 'package:helix/providers/controllers/group_service.dart';
import 'package:helix/services/app_logger.dart';
import 'package:helix_local_groups/helix_groups.dart';
import 'package:helix_local_groups/platform/multicast_lock_android.dart';
import 'package:helix_local_groups/platform/multicast_lock_stub.dart';

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
            state = nextState.sublist(
              nextState.length - kMaxRetainedGroupMessages,
            );
          } else {
            state = nextState;
          }
        }
      } catch (e) {
        unawaited(
          AppLogger.instance.warn(
            'group_messages',
            'group message receipt parse failed: ${e.runtimeType}',
          ),
        );
      }
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
    final payload = jsonEncode({'type': 'text', 'text': text});
    await _groupService.sendGroupPayload(
      groupId: _groupId,
      encryptedPayload: utf8.encode(payload),
    );
  }
}

final groupMessagesProvider =
    StateNotifierProvider.family<
      GroupMessagesNotifier,
      List<GroupMessage>,
      String
    >((ref, groupId) {
      final groupService = ref.watch(groupServiceProvider);
      return GroupMessagesNotifier(groupService, groupId);
    });

final lanLobbyServiceProvider = Provider<LanLobbyService>((ref) {
  final descriptor = ref.watch(productDescriptorProvider);
  final service = LanLobbyService(
    multicastLock: Platform.isAndroid
        ? MulticastLockAndroid(
            '${descriptor.methodChannelNamespace}/multicast_lock',
          )
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
