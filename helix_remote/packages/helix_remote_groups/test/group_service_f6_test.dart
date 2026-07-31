// Tests for Phase F6 client-side service: group-add privacy, join links,
// join requests, ownership transfer, blocked members, mention index,
// notification policy, epoch key deliveries.
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      for (var i = 0; i < 5; i++) {
        final candidate = p.join(dir.path, '.dart_tool', 'lib', 'sqlite3.dll');
        if (File(candidate).existsSync()) {
          DynamicLibrary.open(candidate);
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
  });

  late HelixRemoteDatabase db;
  late RemoteGroupService service;
  int counter = 0;

  String nextId() => 'id_${counter++}';

  setUp(() {
    counter = 0;
    db = HelixRemoteDatabase(File(':memory:'));
    db.initialize();
    service = RemoteGroupService(
      db: db,
      generateId: nextId,
      encryptionKeyProvider: (groupId, epoch) => 'key_${groupId}_$epoch',
    );
    service.createGroup(groupId: 'g1', name: 'F6 Group', creatorId: 'alice');
  });

  tearDown(() => db.close());

  // -------------------------------------------------------------------------
  // F6-003: Group-add privacy
  // -------------------------------------------------------------------------

  group('group-add privacy', () {
    test('default policy is EVERYONE', () {
      expect(service.getGroupAddPolicy('g1'), equals(kGroupAddPolicyEveryone));
    });

    test('setGroupAddPolicy persists to DB', () {
      service.setGroupAddPolicy(groupId: 'g1', policy: kGroupAddPolicyNobody);
      expect(service.getGroupAddPolicy('g1'), equals(kGroupAddPolicyNobody));
    });

    test('policy change is idempotent', () {
      service.setGroupAddPolicy(groupId: 'g1', policy: kGroupAddPolicyContacts);
      service.setGroupAddPolicy(groupId: 'g1', policy: kGroupAddPolicyContacts);
      expect(service.getGroupAddPolicy('g1'), equals(kGroupAddPolicyContacts));
    });

    test('unknown group returns EVERYONE default', () {
      expect(
        service.getGroupAddPolicy('no_such_group'),
        equals(kGroupAddPolicyEveryone),
      );
    });
  });

  // -------------------------------------------------------------------------
  // F6-004: Join link lifecycle (local DB)
  // -------------------------------------------------------------------------

  group('join link lifecycle', () {
    test('createJoinLink stores and retrieves link', () {
      final expiresAt =
          DateTime.now().millisecondsSinceEpoch + 7 * 24 * 60 * 60 * 1000;
      service.createJoinLink(
        linkId: 'lnk1',
        groupId: 'g1',
        token: 'tok_abc',
        requiresApproval: false,
        expiresAt: expiresAt,
      );
      final links = service.getActiveJoinLinks('g1');
      expect(links.length, equals(1));
      expect(links.first['token'], equals('tok_abc'));
      expect(links.first['requires_approval'], isFalse);
    });

    test('revokeJoinLink removes link from active list', () {
      final expiresAt =
          DateTime.now().millisecondsSinceEpoch + 7 * 24 * 60 * 60 * 1000;
      service.createJoinLink(
        linkId: 'lnk2',
        groupId: 'g1',
        token: 'tok_def',
        requiresApproval: false,
        expiresAt: expiresAt,
      );
      service.revokeJoinLink(groupId: 'g1', linkId: 'lnk2');
      expect(service.getActiveJoinLinks('g1'), isEmpty);
    });

    test('links for different groups are isolated', () {
      service.createGroup(
        groupId: 'g2',
        name: 'Another Group',
        creatorId: 'alice',
      );
      final exp =
          DateTime.now().millisecondsSinceEpoch + 7 * 24 * 60 * 60 * 1000;
      service.createJoinLink(
        linkId: 'lnk3',
        groupId: 'g1',
        token: 'tok_g1',
        requiresApproval: false,
        expiresAt: exp,
      );
      service.createJoinLink(
        linkId: 'lnk4',
        groupId: 'g2',
        token: 'tok_g2',
        requiresApproval: true,
        expiresAt: exp,
      );
      expect(service.getActiveJoinLinks('g1').length, equals(1));
      expect(service.getActiveJoinLinks('g2').length, equals(1));
      expect(
        service.getActiveJoinLinks('g2').first['requires_approval'],
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // F6-005: Join request queue (local DB)
  // -------------------------------------------------------------------------

  group('join request queue', () {
    test('recordJoinRequest and getPendingJoinRequests round-trip', () {
      service.recordJoinRequest(
        requestId: 'req1',
        groupId: 'g1',
        requesterId: 'carol',
        linkId: 'lnk1',
      );
      final pending = service.getPendingJoinRequests('g1');
      expect(pending.length, equals(1));
      expect(pending.first['requester_id'], equals('carol'));
    });

    test(
      'approveJoinRequest marks request as approved — removed from pending',
      () {
        service.recordJoinRequest(
          requestId: 'req2',
          groupId: 'g1',
          requesterId: 'bob',
          linkId: 'lnk1',
        );
        service.approveJoinRequest(
          requestId: 'req2',
          groupId: 'g1',
          approve: true,
        );
        expect(service.getPendingJoinRequests('g1'), isEmpty);
      },
    );

    test('rejected request is removed from pending', () {
      service.recordJoinRequest(
        requestId: 'req3',
        groupId: 'g1',
        requesterId: 'dave',
        linkId: 'lnk1',
      );
      service.approveJoinRequest(
        requestId: 'req3',
        groupId: 'g1',
        approve: false,
      );
      expect(service.getPendingJoinRequests('g1'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // F6-006: Blocked members
  // -------------------------------------------------------------------------

  group('blocked members', () {
    test('blockMember records the block', () {
      service.blockMember(groupId: 'g1', accountId: 'eve');
      expect(service.isMemberBlocked('g1', 'eve'), isTrue);
    });

    test('non-blocked member returns false', () {
      expect(service.isMemberBlocked('g1', 'alice'), isFalse);
    });

    test('block is group-scoped', () {
      service.createGroup(groupId: 'g2', name: 'G2', creatorId: 'alice');
      service.blockMember(groupId: 'g1', accountId: 'frank');
      expect(service.isMemberBlocked('g2', 'frank'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // F6: Mention index
  // -------------------------------------------------------------------------

  group('mention index', () {
    test('indexMention and getUnreadMentions round-trip', () {
      service.indexMention(
        mentionId: 'mn1',
        conversationId: 'g1',
        messageId: 'msg1',
        mentionedAccountId: 'alice',
        serverSequence: 10,
      );
      final mentions = service.getUnreadMentions('g1', 'alice');
      expect(mentions.length, equals(1));
      expect(mentions.first['message_id'], equals('msg1'));
    });

    test('mentions for different accounts are isolated', () {
      service.indexMention(
        mentionId: 'mn2',
        conversationId: 'g1',
        messageId: 'msg2',
        mentionedAccountId: 'alice',
        serverSequence: 11,
      );
      service.indexMention(
        mentionId: 'mn3',
        conversationId: 'g1',
        messageId: 'msg3',
        mentionedAccountId: 'bob',
        serverSequence: 12,
      );
      expect(service.getUnreadMentions('g1', 'alice').length, equals(1));
      expect(service.getUnreadMentions('g1', 'bob').length, equals(1));
    });

    test('markMentionRead removes mention from unread list', () {
      service.indexMention(
        mentionId: 'mn4',
        conversationId: 'g1',
        messageId: 'msg4',
        mentionedAccountId: 'alice',
        serverSequence: 13,
      );
      service.markMentionRead('mn4');
      expect(service.getUnreadMentions('g1', 'alice'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // F6: Notification policy
  // -------------------------------------------------------------------------

  group('notification policy', () {
    test('default policy is ALL', () {
      expect(
        service.getGroupNotificationPolicy('g1'),
        equals(kGroupNotificationAll),
      );
    });

    test('setGroupNotificationPolicy persists', () {
      service.setGroupNotificationPolicy(
        groupId: 'g1',
        policy: kGroupNotificationMentionsOnly,
      );
      expect(
        service.getGroupNotificationPolicy('g1'),
        equals(kGroupNotificationMentionsOnly),
      );
    });

    test('muted policy persists', () {
      service.setGroupNotificationPolicy(
        groupId: 'g1',
        policy: kGroupNotificationMuted,
      );
      expect(
        service.getGroupNotificationPolicy('g1'),
        equals(kGroupNotificationMuted),
      );
    });
  });

  // -------------------------------------------------------------------------
  // F6: Epoch key deliveries
  // -------------------------------------------------------------------------

  group('epoch key deliveries', () {
    test('recordEpochKeyDelivery appears in pending list', () {
      service.recordEpochKeyDelivery(
        deliveryId: 'del1',
        groupId: 'g1',
        epoch: 1,
        keyId: 'ek_01',
        recipientDeviceId: 'dev_bob',
        wrappedKey: 'wrapped_ciphertext',
      );
      final pending = service.getPendingEpochKeyDeliveries('g1');
      expect(pending.length, equals(1));
      expect(pending.first['recipient_device_id'], equals('dev_bob'));
      expect(pending.first['epoch'], equals(1));
    });

    test('markEpochKeyDelivered removes entry from pending', () {
      service.recordEpochKeyDelivery(
        deliveryId: 'del2',
        groupId: 'g1',
        epoch: 2,
        keyId: 'ek_02',
        recipientDeviceId: 'dev_carol',
        wrappedKey: 'wrapped_ct2',
      );
      service.markEpochKeyDelivered('del2');
      expect(service.getPendingEpochKeyDeliveries('g1'), isEmpty);
    });

    test('deliveries for different groups are isolated', () {
      service.createGroup(groupId: 'g2', name: 'G2', creatorId: 'alice');
      service.recordEpochKeyDelivery(
        deliveryId: 'del3',
        groupId: 'g1',
        epoch: 3,
        keyId: 'ek_03',
        recipientDeviceId: 'dev_alice',
        wrappedKey: 'ct3',
      );
      expect(service.getPendingEpochKeyDeliveries('g2'), isEmpty);
    });
  });
}
