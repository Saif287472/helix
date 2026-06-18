import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix/providers/controllers/group_service.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_group_repository.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';

void main() {
  group('Phase 4 protocol frames', () {
    test('GroupControlFrame round-trips through protocol_messages', () {
      final frame = GroupControlFrame(
        groupId: 'group-1',
        eventId: 'event-1',
        command: GroupCommands.handover,
        senderFingerprint: 'alice',
        targetFingerprint: 'bob',
        hostFingerprint: 'bob',
        hostEndpoint: '192.168.1.20:4242',
        epoch: 2,
        membershipVersion: 5,
        expiresAt: 123456,
      );

      final decoded = ProtocolFrame.decode(frame.encode()) as GroupControlFrame;

      expect(decoded.groupId, frame.groupId);
      expect(decoded.command, frame.command);
      expect(decoded.targetFingerprint, frame.targetFingerprint);
      expect(decoded.hostFingerprint, frame.hostFingerprint);
      expect(decoded.epoch, frame.epoch);
      expect(decoded.membershipVersion, frame.membershipVersion);
      expect(decoded.expiresAt, frame.expiresAt);
    });

    test('GroupMessageFrame round-trips opaque encrypted payload bytes', () {
      final frame = GroupMessageFrame(
        groupId: 'group-1',
        messageId: 'message-1',
        senderFingerprint: 'alice',
        epoch: 1,
        membershipVersion: 3,
        sentAt: 123456,
        encryptedPayload: Uint8List.fromList([1, 2, 3, 4]),
      );

      final decoded = ProtocolFrame.decode(frame.encode()) as GroupMessageFrame;

      expect(decoded.groupId, frame.groupId);
      expect(decoded.messageId, frame.messageId);
      expect(decoded.senderFingerprint, frame.senderFingerprint);
      expect(decoded.encryptedPayload, frame.encryptedPayload);
    });

    test('kCapGroups and kCapWebRTC are both advertised in kCapAll', () {
      expect(kCapAll & kCapGroups, isNot(0));
      expect(kCapAll & kCapWebRTC, isNot(0));
    });
  });

  group('Phase 4 group service', () {
    test('public lobby auto-elects the first local peer as host', () async {
      final service = _configuredService('alice');

      final lobby = await service.createPublicLobby();

      expect(lobby.groupId, GroupService.publicLobbyId);
      expect(lobby.isPublicLobby, isTrue);
      expect(lobby.hostFingerprint, 'alice');
      expect(lobby.memberCount, 1);
    });

    test(
      'crash election deterministically picks lowest active fingerprint',
      () async {
        final service = _configuredService('carol');
        final lobby = await service.createPublicLobby();

        service.addJoinRequest(
          groupId: lobby.groupId,
          fingerprint: 'bob',
          displayName: 'Bob',
          deviceSuffix: 'b',
          endpoint: '10.0.0.2:1',
        );
        service.decideJoinRequest(
          groupId: lobby.groupId,
          targetFingerprint: 'bob',
          decision: GroupJoinDecision.approved,
        );
        service.addJoinRequest(
          groupId: lobby.groupId,
          fingerprint: 'alice',
          displayName: 'Alice',
          deviceSuffix: 'a',
          endpoint: '10.0.0.3:1',
        );
        service.decideJoinRequest(
          groupId: lobby.groupId,
          targetFingerprint: 'alice',
          decision: GroupJoinDecision.approved,
        );

        final elected = service.electHostAfterCrash(
          lobby.groupId,
          activeFingerprints: const ['bob', 'alice'],
        );

        expect(elected.hostFingerprint, 'alice');
        expect(elected.epoch, greaterThan(lobby.epoch));
      },
    );

    test(
      'stale host announcements are ignored for split-brain prevention',
      () async {
        final service = _configuredService('alice');
        final lobby = await service.createPublicLobby();
        service.electHostAfterCrash(lobby.groupId);
        final current = service.groups.single;

        final stale = GroupControlFrame(
          groupId: lobby.groupId,
          eventId: 'stale-event',
          command: GroupCommands.hostAnnounce,
          senderFingerprint: 'bob',
          hostFingerprint: 'bob',
          hostEndpoint: '10.0.0.9:1',
          epoch: current.epoch - 1,
          membershipVersion: current.membershipVersion,
        );

        expect(service.applyControlFrame(stale), isFalse);
        expect(service.groups.single.hostFingerprint, current.hostFingerprint);
      },
    );

    test('duplicate group message IDs are rejected', () async {
      final service = _configuredService('alice');
      final lobby = await service.createPublicLobby();
      final frame = GroupMessageFrame(
        groupId: lobby.groupId,
        messageId: 'dup-message',
        senderFingerprint: 'alice',
        epoch: lobby.epoch,
        membershipVersion: lobby.membershipVersion,
        sentAt: 123,
        encryptedPayload: Uint8List.fromList([9]),
      );

      expect(service.applyMessageFrame(frame), isTrue);
      expect(service.applyMessageFrame(frame), isFalse);
    });

    test(
      'private group code includes host endpoint, epoch, and expiry',
      () async {
        final service = _configuredService('alice');
        final group = await service.createPrivateGroup(name: 'Ops');
        final code = service.buildGroupCode(
          group.groupId,
          ttl: const Duration(minutes: 10),
        );

        final invite = service.parseGroupCode(code);

        expect(invite.groupId, group.groupId);
        expect(invite.hostEndpoint, '10.0.0.1:7777');
        expect(invite.hostFingerprint, 'alice');
        expect(invite.epoch, group.epoch);
        expect(invite.isExpired, isFalse);
      },
    );

    test(
      'admin approval and block update membership and banned lists',
      () async {
        final service = _configuredService('alice');
        final group = await service.createPrivateGroup(name: 'Ops');

        service.addJoinRequest(
          groupId: group.groupId,
          fingerprint: 'bob',
          displayName: 'Bob',
          deviceSuffix: 'b',
          endpoint: '10.0.0.2:7777',
        );
        service.decideJoinRequest(
          groupId: group.groupId,
          targetFingerprint: 'bob',
          decision: GroupJoinDecision.approved,
        );
        expect(
          service.groups.single.members.map((m) => m.fingerprint),
          contains('bob'),
        );

        service.blockMember(group.groupId, 'bob');
        final snapshot = service.groups.single;
        expect(
          snapshot.members.map((m) => m.fingerprint),
          isNot(contains('bob')),
        );
        expect(snapshot.banned, contains('bob'));
      },
    );
  });
}

GroupService _configuredService(String fingerprint) {
  final service = GroupService(repository: InMemoryGroupRepository());
  service.configureLocalIdentity(
    fingerprint: fingerprint,
    displayName: fingerprint,
    deviceSuffix: fingerprint.substring(0, 1),
    endpoint: '10.0.0.1:7777',
  );
  return service;
}
