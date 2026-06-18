import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_groups/helix_groups.dart';
import 'package:helix_protocol/application/contracts/gateways.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';
import 'package:helix_storage/infrastructure/storage/in_memory_group_repository.dart';

void main() {
  group('group signaling failure handling', () {
    test('gateway adapter reports missing channels as send failures', () async {
      final gateway = GroupSignalingGatewayAdapter((_) => null);

      await expectLater(
        gateway.sendControl('peer', _controlFrame()),
        throwsStateError,
      );
      await expectLater(
        gateway.sendMessage('peer', _messageFrame(sender: 'alice')),
        throwsStateError,
      );
    });

    test('direct group payload send failure does not emit a receipt', () async {
      final repository = InMemoryGroupRepository();
      await repository.saveGroup(_group(host: 'alice'));
      final receipts = <GroupMessageReceipt>[];
      final gateway = _RecordingGroupGateway(failMessagesFor: {'alice'});
      final router = GroupMessageRouterImpl(
        repository: repository,
        gateway: gateway,
        localFingerprint: () => 'bob',
        onReceipt: receipts.add,
      );

      await expectLater(
        router.sendGroupPayload(
          groupId: 'group-1',
          encryptedPayload: Uint8List.fromList([1, 2, 3]),
        ),
        throwsStateError,
      );

      expect(gateway.messageTargets, isEmpty);
      expect(receipts, isEmpty);
    });

    test('broadcast control continues after a peer send fails', () async {
      final gateway = _RecordingGroupGateway(failControlsFor: {'bob'});
      final router = GroupMessageRouterImpl(
        repository: InMemoryGroupRepository(),
        gateway: gateway,
        localFingerprint: () => 'alice',
        onReceipt: (_) {},
      );

      await router.broadcastControl(_group(host: 'alice'), _controlFrame());

      expect(gateway.controlTargets, ['charlie', 'dave']);
    });

    test('host message broadcast continues after a peer send fails', () async {
      final repository = InMemoryGroupRepository();
      await repository.saveGroup(_group(host: 'alice'));
      final receipts = <GroupMessageReceipt>[];
      final gateway = _RecordingGroupGateway(failMessagesFor: {'bob'});
      final router = GroupMessageRouterImpl(
        repository: repository,
        gateway: gateway,
        localFingerprint: () => 'alice',
        onReceipt: receipts.add,
      );

      await router.sendGroupPayload(
        groupId: 'group-1',
        encryptedPayload: Uint8List.fromList([1, 2, 3]),
      );

      expect(gateway.messageTargets, ['charlie', 'dave']);
      expect(receipts, hasLength(1));
    });
  });
}

class _RecordingGroupGateway implements GroupSignalingGateway {
  _RecordingGroupGateway({
    Set<String>? failControlsFor,
    Set<String>? failMessagesFor,
  }) : failControlsFor = failControlsFor ?? const {},
       failMessagesFor = failMessagesFor ?? const {};

  final Set<String> failControlsFor;
  final Set<String> failMessagesFor;
  final controlTargets = <String>[];
  final messageTargets = <String>[];

  @override
  Future<void> sendControl(
    String peerFingerprint,
    GroupControlFrame frame,
  ) async {
    if (failControlsFor.contains(peerFingerprint)) {
      throw StateError('control failed');
    }
    controlTargets.add(peerFingerprint);
  }

  @override
  Future<void> sendMessage(
    String peerFingerprint,
    GroupMessageFrame frame,
  ) async {
    if (failMessagesFor.contains(peerFingerprint)) {
      throw StateError('message failed');
    }
    messageTargets.add(peerFingerprint);
  }
}

GroupSnapshot _group({required String host}) {
  return GroupSnapshot(
    groupId: 'group-1',
    name: 'Group',
    visibility: GroupVisibility.private,
    hostFingerprint: host,
    hostEndpoint: '127.0.0.1:7777',
    epoch: 1,
    membershipVersion: 1,
    members: [
      _member('alice'),
      _member('bob'),
      _member('charlie'),
      _member('dave'),
    ],
    pending: const [],
    banned: const {},
  );
}

GroupMember _member(String fingerprint) {
  return GroupMember(
    fingerprint: fingerprint,
    displayName: fingerprint,
    deviceSuffix: 'device',
    endpoint: '127.0.0.1:7777',
    joinedAt: DateTime(2026),
  );
}

GroupControlFrame _controlFrame() {
  return GroupControlFrame(
    groupId: 'group-1',
    eventId: 'event-1',
    command: 'host-announce',
    senderFingerprint: 'alice',
    epoch: 1,
    membershipVersion: 1,
  );
}

GroupMessageFrame _messageFrame({required String sender}) {
  return GroupMessageFrame(
    groupId: 'group-1',
    messageId: 'message-1',
    senderFingerprint: sender,
    epoch: 1,
    membershipVersion: 1,
    sentAt: 1,
    encryptedPayload: Uint8List.fromList([1]),
  );
}
