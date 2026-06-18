import 'package:flutter_test/flutter_test.dart';
import 'package:helix/providers/controllers/group_service.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_group_repository.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';

class FakeSecureChannel extends Fake implements SecureChannel {
  FakeSecureChannel(this.threadId);

  @override
  final String threadId;

  final List<GroupControlFrame> sentControls = [];
  final List<GroupMessageFrame> sentMessages = [];

  @override
  Future<void> sendGroupControl(GroupControlFrame frame) async {
    sentControls.add(frame);
  }

  @override
  Future<void> sendGroupMessage(GroupMessageFrame frame) async {
    sentMessages.add(frame);
  }
}

void main() {
  late InMemoryGroupRepository repoA;
  late InMemoryGroupRepository repoB;
  late InMemoryGroupRepository repoC;

  late GroupService serviceA;
  late GroupService serviceB;
  late GroupService serviceC;

  setUp(() {
    repoA = InMemoryGroupRepository();
    repoB = InMemoryGroupRepository();
    repoC = InMemoryGroupRepository();

    serviceA = GroupService(repository: repoA);
    serviceB = GroupService(repository: repoB);
    serviceC = GroupService(repository: repoC);

    serviceA.configureLocalIdentity(
      fingerprint: 'alice',
      displayName: 'Alice',
      deviceSuffix: 'phone',
      endpoint: '127.0.0.1:4001',
    );

    serviceB.configureLocalIdentity(
      fingerprint: 'bob',
      displayName: 'Bob',
      deviceSuffix: 'phone',
      endpoint: '127.0.0.1:4002',
    );

    serviceC.configureLocalIdentity(
      fingerprint: 'charlie',
      displayName: 'Charlie',
      deviceSuffix: 'phone',
      endpoint: '127.0.0.1:4003',
    );
  });

  group('GroupService V6 - Public Lobby & Private Group tests', () {
    test('Simultaneous Hosting Convergence (alice wins over bob)', () async {
      // Both create their local public lobby
      final lobbyA = await serviceA.createPublicLobby();
      final lobbyB = await serviceB.createPublicLobby();

      expect(lobbyA.hostFingerprint, 'alice');
      expect(lobbyB.hostFingerprint, 'bob');

      // Set up channels
      final channelToB = FakeSecureChannel('bob');
      final channelToA = FakeSecureChannel('alice');

      serviceA.registerPeerChannel('bob', channelToB);
      serviceB.registerPeerChannel('alice', channelToA);

      serviceB.connectChannelCallback = (fp, ep) async => channelToA;

      // Simulate Bob receiving A's host announcement
      final announceA = serviceA.buildHostAnnouncement(GroupService.publicLobbyId);
      await serviceB.handleControlFrame(
        peerFingerprint: 'alice',
        channel: channelToA,
        frame: announceA,
      );

      // Verify Bob relinquished hosting to Alice because 'alice' < 'bob'
      final updatedLobbyB = repoB.loadGroup(GroupService.publicLobbyId)!;
      expect(updatedLobbyB.hostFingerprint, 'alice');

      // Verify Bob sent a join frame to Alice
      final lastControl = channelToA.sentControls.last;
      expect(lastControl.command, GroupCommands.join);
      expect(lastControl.senderFingerprint, 'bob');
    });

    test('Public Join Bypass Approval', () async {
      await serviceA.createPublicLobby();

      final channelToB = FakeSecureChannel('bob');
      serviceA.registerPeerChannel('bob', channelToB);

      // Receive a direct join control frame from Bob
      final joinFrame = GroupControlFrame(
        groupId: GroupService.publicLobbyId,
        eventId: 'evt-1',
        command: GroupCommands.join,
        senderFingerprint: 'bob',
        targetFingerprint: 'bob',
        hostFingerprint: 'alice',
        hostEndpoint: '127.0.0.1:4001',
        epoch: 0,
        membershipVersion: 1,
      );

      await serviceA.handleControlFrame(
        peerFingerprint: 'bob',
        channel: channelToB,
        frame: joinFrame,
      );

      // Verify Bob was added immediately (auto-approved)
      final lobbyA = repoA.loadGroup(GroupService.publicLobbyId)!;
      expect(lobbyA.members.any((m) => m.fingerprint == 'bob'), isTrue);
    });

    test('Stale host announcements are ignored', () async {
      await serviceA.createPublicLobby();

      final channelToB = FakeSecureChannel('bob');
      serviceB.registerPeerChannel('alice', channelToB);

      // Create an announcement from Alice with smaller membership version than local
      final staleFrame = GroupControlFrame(
        groupId: GroupService.publicLobbyId,
        eventId: 'evt-stale',
        command: GroupCommands.hostAnnounce,
        senderFingerprint: 'alice',
        hostFingerprint: 'alice',
        hostEndpoint: '127.0.0.1:4001',
        epoch: 0,
        membershipVersion: 0, // stale version
      );

      // Pre-fill Bob's repo with higher membership version
      repoB.saveGroup(GroupSnapshot(
        groupId: GroupService.publicLobbyId,
        name: 'LAN Lobby',
        visibility: GroupVisibility.publicLobby,
        hostFingerprint: 'bob',
        hostEndpoint: '127.0.0.1:4002',
        epoch: 0,
        membershipVersion: 2,
        members: const [],
        pending: const [],
        banned: const {},
      ));

      final accepted = serviceB.applyControlFrame(staleFrame);
      expect(accepted, isFalse);
    });

    test('Private Group separation (requires approval, kick/block works)', () async {
      final group = await serviceA.createPrivateGroup(name: 'My Group');

      final channelToB = FakeSecureChannel('bob');
      serviceA.registerPeerChannel('bob', channelToB);

      // Bob requests to join
      final joinRequest = GroupControlFrame(
        groupId: group.groupId,
        eventId: 'evt-2',
        command: GroupCommands.joinRequest,
        senderFingerprint: 'bob',
        targetFingerprint: 'bob',
        epoch: 0,
        membershipVersion: 1,
      );

      await serviceA.handleControlFrame(
        peerFingerprint: 'bob',
        channel: channelToB,
        frame: joinRequest,
      );

      // Verify Bob is pending
      var updatedGroup = repoA.loadGroup(group.groupId)!;
      expect(updatedGroup.pending.any((p) => p.fingerprint == 'bob'), isTrue);
      expect(updatedGroup.members.any((m) => m.fingerprint == 'bob'), isFalse);

      // Alice decides to approve
      await serviceA.executeDecideJoin(group.groupId, 'bob', GroupJoinDecision.approved);

      // Verify Bob is now a member
      updatedGroup = repoA.loadGroup(group.groupId)!;
      expect(updatedGroup.members.any((m) => m.fingerprint == 'bob'), isTrue);

      // Alice kicks Bob
      await serviceA.executeKick(group.groupId, 'bob');

      // Verify Bob is removed
      updatedGroup = repoA.loadGroup(group.groupId)!;
      expect(updatedGroup.members.any((m) => m.fingerprint == 'bob'), isFalse);
    });

    test('Host leaving resets public lobby when no other members exist', () async {
      await serviceA.createPublicLobby();

      // Leave the lobby
      await serviceA.leaveGroup(GroupService.publicLobbyId);

      // Lobby should reset to host-only empty state
      final lobby = repoA.loadGroup(GroupService.publicLobbyId)!;
      expect(lobby.memberCount, 1);
      expect(lobby.members.first.fingerprint, 'alice');
    });
  });
}
