// Bridge providers: cross-service wiring that would create circular imports
// if placed in individual feature files.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/call/call_state.dart';
import 'package:helix_local_platform/platform/android_foreground.dart';
import 'package:helix/providers/session_provider.dart';
import 'package:helix/providers/infrastructure_providers.dart';
import 'package:helix/providers/identity_providers.dart';
import 'package:helix/providers/connection_providers.dart';
import 'package:helix/providers/messaging_providers.dart';
import 'package:helix/providers/discovery_providers.dart';
import 'package:helix/providers/groups_providers.dart';
import 'package:helix/providers/controllers/group_service.dart' show GroupService;
import 'package:helix/providers/calls_providers.dart';
import 'package:helix/providers/transfer_providers.dart';
import 'package:helix/services/app_logger.dart';

// Forwards incoming one-way messages from RequestService to MessagingService.
final oneWayMessageBridgeProvider = Provider<void>((ref) {
  final requestService = ref.watch(requestServiceProvider);
  final messagingService = ref.watch(messagingServiceProvider);
  final sub = requestService.incomingOneWayMessages.listen(
    messagingService.receiveOneWayMessage,
  );
  ref.onDispose(sub.cancel);
});

// Activates the reconnect service on startup.
final reconnectBridgeProvider = Provider<void>((ref) {
  final svc = ref.watch(reconnectServiceProvider);
  svc.start();
});

// Wires auto-resume callback and forwards silently accepted channels to MessagingService.
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

// Wires notification actions to MessagingService / CallService.
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
            messaging
                .sendMessage(threadId, text)
                .then((_) => notif.cancelAll())
                .catchError((_) {}),
          );
        }
      case 'mark_read':
        messaging.markThreadRead(threadId);
        unawaited(notif.cancelAll().catchError((_) {}));
    }
  });
  ref.onDispose(sub.cancel);
});

// Routes incoming file/ephemeral-media frames to the transfer service.
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
      if (active == null) messaging.removeFileMessage(threadId, frame.fileId);
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
    if (active == null) messaging.removeFileMessage(threadId, frame.fileId);
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

// Keeps the Android foreground service alive during active chats or calls.
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
    operation = operation
        .then((_) async {
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
              await AndroidForegroundService.updateNotificationText(
                text,
                inCall: inCall,
              );
            } catch (_) {
              running = false;
            }
          } else {
            await AndroidForegroundService.updateNotificationText(
              text,
              inCall: inCall,
            ).catchError((_) {});
          }
        })
        .catchError((_) {
          running = false;
        });
  }

  ref.listen<int>(activeChatCountProvider, (_, _) => sync());
  ref.listen<AsyncValue<CallState?>>(currentCallProvider, (_, _) => sync());
});

// Wires GroupService message/control handlers and lobby election logic.
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
      final result = await ref
          .read(requestServiceProvider)
          .sendRequest(
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
    final thread = ref
        .read(conversationRepositoryProvider)
        .getThread(fingerprint);
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
    if (lobby != null &&
        lobby.hostFingerprint == threadId &&
        threadId != identity?.staticPublicKeyFingerprint) {
      final active = lobby.members
          .map((m) => m.fingerprint)
          .where(
            (fp) =>
                fp == identity?.staticPublicKeyFingerprint ||
                messaging.getChannel(fp) != null,
          )
          .toList();

      if (active.isNotEmpty) {
        final elected = groupService.electHostAfterCrash(
          GroupService.publicLobbyId,
          activeFingerprints: active,
        );
        if (elected.hostFingerprint != identity?.staticPublicKeyFingerprint) {
          unawaited(
            groupService
                .joinGroup(
                  groupId: GroupService.publicLobbyId,
                  hostFingerprint: elected.hostFingerprint,
                  hostEndpoint: elected.hostEndpoint,
                  epoch: elected.epoch,
                )
                .catchError((Object e, StackTrace s) {}),
          );
        }
      } else {
        unawaited(
          groupService
              .leaveGroup(GroupService.publicLobbyId)
              .catchError((Object e, StackTrace s) {}),
        );
      }
    }
  });

  final subMessageReceipts = groupService.messageReceipts.listen((receipt) {
    try {
      final payloadStr = utf8.decode(receipt.encryptedPayload);
      final json = jsonDecode(payloadStr);
      if (json is Map && json['type'] == 'sync') {
        final membersJson = (json['members'] as List)
            .cast<Map<String, dynamic>>();
        final newMembers = membersJson
            .map(
              (m) => GroupMember(
                fingerprint: m['fingerprint'] as String,
                displayName: m['displayName'] as String,
                deviceSuffix: m['deviceSuffix'] as String,
                endpoint: m['endpoint'] as String,
                joinedAt: DateTime.now(),
                isAdmin: m['isAdmin'] as bool? ?? false,
              ),
            )
            .toList();

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
    } catch (e) {
      unawaited(
        AppLogger.instance.warn(
          'group_bridge',
          'group sync receipt parse failed: ${e.runtimeType}',
        ),
      );
    }
  });

  ref.onDispose(() {
    subThreadChanges.cancel();
    subMessageReceipts.cancel();
  });
});
