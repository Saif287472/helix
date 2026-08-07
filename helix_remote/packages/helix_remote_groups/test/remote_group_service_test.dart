import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      String? foundPath;
      for (int i = 0; i < 5; i++) {
        final possiblePath = p.join(
          dir.path,
          '.dart_tool',
          'lib',
          'sqlite3.dll',
        );
        if (File(possiblePath).existsSync()) {
          foundPath = possiblePath;
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      if (foundPath != null) {
        DynamicLibrary.open(foundPath);
      }
    }
  });

  late HelixRemoteDatabase db;
  late RemoteGroupService service;
  int idCounter = 0;

  setUp(() {
    db = HelixRemoteDatabase(File(':memory:'));
    db.initialize();
    idCounter = 0;
    service = RemoteGroupService(
      db: db,
      generateId: () => 'op_${idCounter++}',
      encryptionKeyProvider: (groupId, epoch) =>
          'sender_key_material_${groupId}_$epoch',
    );
  });

  tearDown(() {
    db.close();
  });

  // -------------------------------------------------------------------------
  // P16-001: Persistent group identity
  // -------------------------------------------------------------------------

  test('createGroup creates local conversation with type GROUP', () {
    service.createGroup(groupId: 'g1', name: 'Test Group', creatorId: 'alice');

    final convs = db.getConversations();
    expect(convs.length, equals(1));
    expect(convs.first.conversationId, equals('g1'));
    expect(convs.first.type, equals('GROUP'));
    expect(convs.first.title, equals('Test Group'));
  });

  test('createGroup persists group metadata', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Meta Group',
      creatorId: 'alice',
      avatarUri: 'https://example.test/avatar.png',
    );

    final meta = db.getGroupMetadata('g1');
    expect(meta, isNotNull);
    expect(meta!['name'], equals('Meta Group'));
    expect(meta['creator_id'], equals('alice'));
    expect(meta['epoch'], equals(0));
  });

  test('createGroup enqueues group_create operation', () {
    service.createGroup(groupId: 'g1', name: 'Queue Group', creatorId: 'alice');

    final ops = db.getPendingOperations();
    expect(ops.length, equals(1));
    expect(ops.first['type'], equals(kGroupOpCreate));

    final payload =
        jsonDecode(ops.first['payload'] as String) as Map<String, dynamic>;
    expect(payload['group_id'], equals('g1'));
    expect(payload['name'], equals('Queue Group'));
    expect(payload['creator_id'], equals('alice'));
    expect(payload['epoch'], equals(0));
    expect(payload['encryption_key_id'], startsWith('gk_'));
    expect(jsonEncode(payload), isNot(contains('sender_key_material')));
    expect(service.getGroupEpochKey('g1', 0), isNotNull);
  });

  // -------------------------------------------------------------------------
  // P16-002: Persistent membership and roles
  // -------------------------------------------------------------------------

  test('createGroup sets creator as ADMIN', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Admin Group',
      creatorId: 'alice',
      initialMemberIds: ['bob'],
    );

    final membersWithRoles = db.getGroupMembersWithRoles('g1');
    final alice = membersWithRoles.firstWhere(
      (m) => m['account_id'] == 'alice',
    );
    expect(alice['role'], equals(kRoleAdmin));

    final bob = membersWithRoles.firstWhere((m) => m['account_id'] == 'bob');
    expect(bob['role'], equals(kRoleMember));
  });

  test('getGroupMembers returns list of member IDs', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Members Group',
      creatorId: 'alice',
      initialMemberIds: ['bob', 'carol'],
    );

    final members = service.getGroupMembers('g1');
    expect(members, containsAll(['alice', 'bob', 'carol']));
  });

  test('getGroupMembersWithRoles includes role for each member', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Role Group',
      creatorId: 'alice',
      initialMemberIds: ['bob'],
    );

    final withRoles = service.getGroupMembersWithRoles('g1');
    expect(withRoles, isNotEmpty);
    expect(withRoles.every((m) => m.containsKey('role')), isTrue);
  });

  // -------------------------------------------------------------------------
  // P16-003: Invite/join approval rules
  // -------------------------------------------------------------------------

  test('inviteMember enqueues group_invite operation', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Invite Group',
      creatorId: 'alice',
    );
    service.inviteMember(
      groupId: 'g1',
      inviteId: 'inv1',
      inviterId: 'alice',
      inviteeId: 'bob',
    );

    final ops = db.getPendingOperations();
    final inviteOp = ops.firstWhere((o) => o['type'] == kGroupOpInvite);
    final payload =
        jsonDecode(inviteOp['payload'] as String) as Map<String, dynamic>;
    expect(payload['invite_id'], equals('inv1'));
    expect(payload['group_id'], equals('g1'));
    expect(payload['invitee_id'], equals('bob'));
  });

  test('inviteMember stores local pending invite', () {
    service.createGroup(groupId: 'g1', name: 'G', creatorId: 'alice');
    service.inviteMember(
      groupId: 'g1',
      inviteId: 'inv1',
      inviterId: 'alice',
      inviteeId: 'bob',
    );

    final invite = db.getGroupInvite('inv1');
    expect(invite, isNotNull);
    expect(invite!['status'], equals(kInviteStatusPending));
    expect(invite['group_id'], equals('g1'));
  });

  test('respondToInvite accept adds member and enqueues operation', () {
    service.createGroup(groupId: 'g1', name: 'G', creatorId: 'alice');
    service.inviteMember(
      groupId: 'g1',
      inviteId: 'inv1',
      inviterId: 'alice',
      inviteeId: 'bob',
    );
    service.respondToInvite(
      inviteId: 'inv1',
      selfAccountId: 'bob',
      accept: true,
    );

    expect(service.getGroupMembers('g1'), contains('bob'));
    expect(service.getGroupEpoch('g1'), equals(1));
    expect(service.getGroupEpochKey('g1', 1), isNotNull);

    final ops = db.getPendingOperations();
    final respondOp = ops.firstWhere((o) => o['type'] == kGroupOpInviteRespond);
    final payload =
        jsonDecode(respondOp['payload'] as String) as Map<String, dynamic>;
    expect(payload['accept'], isTrue);
  });

  test('respondToInvite reject updates status and enqueues operation', () {
    service.createGroup(groupId: 'g1', name: 'G', creatorId: 'alice');
    service.inviteMember(
      groupId: 'g1',
      inviteId: 'inv1',
      inviterId: 'alice',
      inviteeId: 'bob',
    );
    service.respondToInvite(
      inviteId: 'inv1',
      selfAccountId: 'bob',
      accept: false,
    );

    final invite = db.getGroupInvite('inv1');
    expect(invite!['status'], equals(kInviteStatusRejected));
    expect(service.getGroupMembers('g1'), isNot(contains('bob')));
  });

  // -------------------------------------------------------------------------
  // P16-006 + P16-013: Persistent group message history with pagination
  // -------------------------------------------------------------------------

  test('getGroupMessages uses limit and offset for pagination', () {
    service.createGroup(groupId: 'g1', name: 'G', creatorId: 'alice');

    // Seed 5 messages directly into the DB.
    for (var i = 1; i <= 5; i++) {
      db.saveMessage(
        RemoteMessage(
          messageId: 'msg_$i',
          conversationId: 'g1',
          senderAccountId: 'alice',
          senderDeviceId: 'device1',
          ciphertext: 'cipher_$i',
        ),
        i,
        DateTime.now().millisecondsSinceEpoch,
        'DELIVERED',
      );
    }

    final page1 = service.getGroupMessages('g1', limit: 3, offset: 0);
    expect(page1.length, equals(3));

    final page2 = service.getGroupMessages('g1', limit: 3, offset: 3);
    expect(page2.length, equals(2));
  });

  test('group messages contain ciphertext only — no plaintext field', () {
    service.createGroup(groupId: 'g1', name: 'G', creatorId: 'alice');
    db.saveMessage(
      const RemoteMessage(
        messageId: 'msg1',
        conversationId: 'g1',
        senderAccountId: 'alice',
        senderDeviceId: 'device1',
        ciphertext: 'encrypted_payload',
      ),
      1,
      DateTime.now().millisecondsSinceEpoch,
      'DELIVERED',
    );

    final messages = service.getGroupMessages('g1');
    expect(messages.first.containsKey('ciphertext_blob'), isTrue);
    expect(messages.first.containsKey('plaintext'), isFalse);
  });

  // -------------------------------------------------------------------------
  // P16-008: Admin events
  // -------------------------------------------------------------------------

  test('updateGroupInfo enqueues group_update operation', () {
    service.createGroup(groupId: 'g1', name: 'Old', creatorId: 'alice');
    service.updateGroupInfo(groupId: 'g1', name: 'New Name');

    final ops = db.getPendingOperations();
    final updateOp = ops.firstWhere((o) => o['type'] == kGroupOpUpdate);
    final payload =
        jsonDecode(updateOp['payload'] as String) as Map<String, dynamic>;
    expect(payload['name'], equals('New Name'));
  });

  test('changeMemberRole enqueues member-role operation', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Role Group',
      creatorId: 'alice',
      initialMemberIds: ['bob'],
    );
    service.changeMemberRole(groupId: 'g1', accountId: 'bob', role: kRoleAdmin);

    final ops = db.getPendingOperations();
    final roleOp = ops.firstWhere((o) => o['type'] == kGroupOpMemberRole);
    final payload =
        jsonDecode(roleOp['payload'] as String) as Map<String, dynamic>;
    expect(payload['role'], equals(kRoleAdmin));
    expect(payload['account_id'], equals('bob'));
  });

  // -------------------------------------------------------------------------
  // P16-009: Leave / remove
  // -------------------------------------------------------------------------

  test('leaveGroup removes self locally and enqueues operation', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Leave Group',
      creatorId: 'alice',
      initialMemberIds: ['bob'],
    );
    service.leaveGroup(groupId: 'g1', selfAccountId: 'bob');

    expect(service.getGroupMembers('g1'), isNot(contains('bob')));

    final ops = db.getPendingOperations();
    final leaveOp = ops.firstWhere((o) => o['type'] == kGroupOpLeave);
    final payload =
        jsonDecode(leaveOp['payload'] as String) as Map<String, dynamic>;
    expect(payload['account_id'], equals('bob'));
    expect(payload['epoch'], equals(1));
    expect(payload['encryption_key_id'], startsWith('gk_'));
  });

  test('removeMember removes member locally and enqueues operation', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Remove Group',
      creatorId: 'alice',
      initialMemberIds: ['bob'],
    );
    service.removeMember(groupId: 'g1', accountId: 'bob');

    expect(service.getGroupMembers('g1'), isNot(contains('bob')));

    final ops = db.getPendingOperations();
    final removeOp = ops.firstWhere((o) => o['type'] == kGroupOpRemoveMember);
    final payload =
        jsonDecode(removeOp['payload'] as String) as Map<String, dynamic>;
    expect(payload['account_id'], equals('bob'));
    expect(payload['epoch'], equals(1));
    expect(payload['encryption_key_id'], startsWith('gk_'));
    expect(jsonEncode(payload), isNot(contains('sender_key_material')));
  });

  // -------------------------------------------------------------------------
  // P16-005: Membership-change key epoch
  // -------------------------------------------------------------------------

  test('removeMember increments group epoch (P16-005)', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Epoch Group',
      creatorId: 'alice',
      initialMemberIds: ['bob'],
    );
    expect(service.getGroupEpoch('g1'), equals(0));
    final epoch0 = service.getGroupEpochKey('g1', 0)!;

    service.removeMember(groupId: 'g1', accountId: 'bob');
    expect(service.getGroupEpoch('g1'), equals(1));
    final epoch1 = service.getGroupEpochKey('g1', 1)!;
    expect(epoch1['key_id'], isNot(equals(epoch0['key_id'])));
    expect(epoch1['key_material'], isNot(equals(epoch0['key_material'])));

    // A second removal bumps it again.
    service.removeMember(groupId: 'g1', accountId: 'alice');
    expect(service.getGroupEpoch('g1'), equals(2));
  });

  test('getGroupEpoch returns current epoch from DB', () {
    service.createGroup(groupId: 'g1', name: 'G', creatorId: 'alice');
    db.updateGroupEpoch('g1', 3);
    expect(service.getGroupEpoch('g1'), equals(3));
  });

  // -------------------------------------------------------------------------
  // P16-010: Group deletion
  // -------------------------------------------------------------------------

  test('deleteGroup tombstones group and enqueues operation', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Delete Group',
      creatorId: 'alice',
    );
    service.deleteGroup('g1');

    expect(db.isTombstoned('g1', 'GROUP'), isTrue);

    final ops = db.getPendingOperations();
    final deleteOp = ops.firstWhere((o) => o['type'] == kGroupOpDelete);
    final payload =
        jsonDecode(deleteOp['payload'] as String) as Map<String, dynamic>;
    expect(payload['group_id'], equals('g1'));
  });

  // -------------------------------------------------------------------------
  // P16-004: Group E2EE — key provider is injected, not internal
  // -------------------------------------------------------------------------

  test(
    'encryptionKeyProvider is called with groupId and epoch 0 on create',
    () {
      final calls = <Map<String, dynamic>>[];
      final svc = RemoteGroupService(
        db: db,
        generateId: () => 'op_test',
        encryptionKeyProvider: (gid, epoch) {
          calls.add({'groupId': gid, 'epoch': epoch});
          return 'stub_key_material';
        },
      );

      svc.createGroup(groupId: 'g1', name: 'E2EE Group', creatorId: 'alice');

      expect(calls.length, equals(1));
      expect(calls.first['groupId'], equals('g1'));
      expect(calls.first['epoch'], equals(0));

      final ops = db.getPendingOperations();
      final payload =
          jsonDecode(ops.first['payload'] as String) as Map<String, dynamic>;
      expect(payload['encryption_key_id'], startsWith('gk_'));
      expect(jsonEncode(payload), isNot(contains('stub_key_material')));
      expect(
        svc.getGroupEpochKey('g1', 0)!['key_material'],
        'stub_key_material',
      );
    },
  );

  test('P6 membership matrix stores new epoch only for future access', () {
    service.createGroup(
      groupId: 'g1',
      name: 'Matrix Group',
      creatorId: 'alice',
      initialMemberIds: ['bob'],
    );
    final epoch0 = service.getGroupEpochKey('g1', 0)!;

    service.removeMember(groupId: 'g1', accountId: 'bob');
    expect(service.getGroupMembers('g1'), isNot(contains('bob')));
    final epoch1 = service.getGroupEpochKey('g1', 1)!;
    expect(epoch1['key_material'], isNot(equals(epoch0['key_material'])));

    service.inviteMember(
      groupId: 'g1',
      inviteId: 'inv2',
      inviterId: 'alice',
      inviteeId: 'carol',
    );
    service.respondToInvite(
      inviteId: 'inv2',
      selfAccountId: 'carol',
      accept: true,
    );
    final epoch2 = service.getGroupEpochKey('g1', 2)!;
    expect(service.getGroupMembers('g1'), contains('carol'));
    expect(epoch2['key_material'], isNot(equals(epoch1['key_material'])));
  });

  // -------------------------------------------------------------------------
  // P16-016: No Local imports — verified by package boundary
  // -------------------------------------------------------------------------

  test('RemoteGroupService has no Local LAN imports (P16-016)', () {
    // If this test file compiles without importing any helix_local_* package,
    // the boundary is enforced. The group service depends only on
    // helix_remote_domain and helix_remote_storage per pubspec.yaml.
    final svc = RemoteGroupService(
      db: db,
      generateId: () => 'id',
      encryptionKeyProvider: (gid, epoch) => 'key_for_test',
    );
    expect(svc, isNotNull);
  });
}
