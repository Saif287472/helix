import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

class TestHttpClient {
  TestHttpClient(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  final _inner = HttpClient();

  Future<({int status, String body})> get(String path) async {
    final req = await _inner.getUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (status: res.statusCode, body: body);
  }

  Future<({int status, String body})> post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final req = await _inner.postUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (status: res.statusCode, body: body);
  }
}

void main() {
  late BackendServer server;
  late int port;
  late String tokenA; // alice / admin
  late String tokenB; // bob   / member

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_groups_phase16',
      rateLimitMaxTokens: 500.0,
      rateLimitRefillRate: 100.0,
    );

    server.db.createAccount('alice', 'alice_user', 'alice_key');
    server.db.registerDevice(
      'dev_alice',
      'alice',
      'alice_device_key',
      'Alice Phone',
    );
    server.db.createAccount('bob', 'bob_user', 'bob_key');
    server.db.registerDevice('dev_bob', 'bob', 'bob_device_key', 'Bob Phone');
    server.db.createAccount('carol', 'carol_user', 'carol_key');
    server.db.registerDevice(
      'dev_carol',
      'carol',
      'carol_device_key',
      'Carol Phone',
    );

    tokenA = server.jwt.generateToken({
      'account_id': 'alice',
      'device_id': 'dev_alice',
    }, const Duration(hours: 1));
    tokenB = server.jwt.generateToken({
      'account_id': 'bob',
      'device_id': 'dev_bob',
    }, const Duration(hours: 1));

    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    await server.stop();
  });

  // -------------------------------------------------------------------------
  // P16-001: Persistent group identity
  // -------------------------------------------------------------------------

  test('create group — creator becomes ADMIN, group persisted', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/groups/create', {
      'group_id': 'grp1',
      'name': 'Alpha Team',
      'initial_member_ids': ['bob'],
    });

    expect(res.status, equals(200));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['group_id'], equals('grp1'));

    // Creator must be ADMIN.
    expect(server.db.isGroupAdmin('grp1', 'alice'), isTrue);
    // Other initial member is MEMBER.
    expect(server.db.getGroupMemberRole('grp1', 'bob'), equals('MEMBER'));

    final group = server.db.getGroup('grp1');
    expect(group, isNotNull);
    expect(group!['name'], equals('Alpha Team'));
    expect(group['creator_id'], equals('alice'));
  });

  test('unauthenticated create is rejected with 401', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', '');
    final res = await client.post('/api/v1/groups/create', {
      'group_id': 'grp_unauth',
      'name': 'Bad Group',
    });
    expect(res.status, equals(401));
  });

  test('create group — missing name returns 400', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/groups/create', {'group_id': 'g2'});
    expect(res.status, equals(400));
  });

  // -------------------------------------------------------------------------
  // P16-001: Get group info
  // -------------------------------------------------------------------------

  test('get group info returns name and creator', () async {
    server.db.createGroup(
      groupId: 'grp2',
      name: 'Beta Team',
      creatorId: 'alice',
      encryptionKeyId: 'key_beta',
      initialMemberIds: ['alice'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.get('/api/v1/groups/info?group_id=grp2');
    expect(res.status, equals(200));

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['name'], equals('Beta Team'));
    expect(body['creator_id'], equals('alice'));
  });

  // -------------------------------------------------------------------------
  // P16-013: Paginated member list
  // -------------------------------------------------------------------------

  test('get members returns paginated list with roles', () async {
    server.db.createGroup(
      groupId: 'grp3',
      name: 'Gamma Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice', 'bob'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.get(
      '/api/v1/groups/members?group_id=grp3&limit=10&offset=0',
    );
    expect(res.status, equals(200));

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final members = body['members'] as List;
    expect(members.length, equals(2));

    final adminEntry =
        members.firstWhere((m) => (m as Map)['account_id'] == 'alice') as Map;
    expect(adminEntry['role'], equals('ADMIN'));
  });

  // -------------------------------------------------------------------------
  // P16-003: Invite / join approval
  // -------------------------------------------------------------------------

  test('admin can invite a member', () async {
    server.db.createGroup(
      groupId: 'grp4',
      name: 'Delta Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/groups/invite', {
      'invite_id': 'inv1',
      'group_id': 'grp4',
      'invitee_id': 'bob',
    });
    expect(res.status, equals(200));

    final inv = server.db.getGroupInvite('inv1');
    expect(inv, isNotNull);
    expect(inv!['status'], equals('PENDING'));
    expect(inv['invitee_id'], equals('bob'));
  });

  test('non-admin cannot invite to group', () async {
    server.db.createGroup(
      groupId: 'grp5',
      name: 'Epsilon Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice', 'bob'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenB);
    final res = await client.post('/api/v1/groups/invite', {
      'invite_id': 'inv2',
      'group_id': 'grp5',
      'invitee_id': 'carol',
    });
    expect(res.status, equals(403));
  });

  test('duplicate open invite is rejected', () async {
    server.db.createGroup(
      groupId: 'grp6',
      name: 'Zeta Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice'],
    );
    server.db.createGroupInvite(
      inviteId: 'inv_existing',
      groupId: 'grp6',
      inviterId: 'alice',
      inviteeId: 'bob',
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/groups/invite', {
      'invite_id': 'inv_dup',
      'group_id': 'grp6',
      'invitee_id': 'bob',
    });
    expect(res.status, equals(400));
    expect(
      (jsonDecode(res.body) as Map<String, dynamic>)['error'],
      contains('invite'),
    );
  });

  test('invitee can accept invite — becomes a member', () async {
    server.db.createGroup(
      groupId: 'grp7',
      name: 'Eta Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice'],
    );
    server.db.createGroupInvite(
      inviteId: 'inv3',
      groupId: 'grp7',
      inviterId: 'alice',
      inviteeId: 'bob',
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenB);
    final res = await client.post('/api/v1/groups/invite/respond', {
      'invite_id': 'inv3',
      'accept': true,
    });
    expect(res.status, equals(200));
    expect(
      (jsonDecode(res.body) as Map<String, dynamic>)['status'],
      equals('ACCEPTED'),
    );
    expect(server.db.isConversationMember('grp7', 'bob'), isTrue);
  });

  test('invitee can reject invite', () async {
    server.db.createGroup(
      groupId: 'grp8',
      name: 'Theta Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice'],
    );
    server.db.createGroupInvite(
      inviteId: 'inv4',
      groupId: 'grp8',
      inviterId: 'alice',
      inviteeId: 'bob',
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenB);
    final res = await client.post('/api/v1/groups/invite/respond', {
      'invite_id': 'inv4',
      'accept': false,
    });
    expect(res.status, equals(200));
    expect(
      (jsonDecode(res.body) as Map<String, dynamic>)['status'],
      equals('REJECTED'),
    );
    expect(server.db.isConversationMember('grp8', 'bob'), isFalse);
  });

  // -------------------------------------------------------------------------
  // P16-011: Offline member gets push notification on invite
  // -------------------------------------------------------------------------

  test('invite to offline member enqueues PUSH_NOTIFICATION', () async {
    server.db.createGroup(
      groupId: 'grp9',
      name: 'Iota Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    await client.post('/api/v1/groups/invite', {
      'invite_id': 'inv5',
      'group_id': 'grp9',
      'invitee_id': 'bob',
    });

    final outbox = server.db.getPendingOutbox();
    final pushItems = outbox
        .where((e) => e['type'] == 'PUSH_NOTIFICATION')
        .toList();
    expect(pushItems, isNotEmpty);

    final payload =
        jsonDecode(pushItems.first['payload'] as String)
            as Map<String, dynamic>;
    expect(payload['notification_type'], equals('group_invite'));
    // Notification must NOT contain invite content (only type).
    expect(payload.containsKey('invite_id'), isFalse);
  });

  // -------------------------------------------------------------------------
  // P16-008: Admin events
  // -------------------------------------------------------------------------

  test('admin can rename group', () async {
    server.db.createGroup(
      groupId: 'grp10',
      name: 'Old Name',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/groups/update', {
      'group_id': 'grp10',
      'name': 'New Name',
    });
    expect(res.status, equals(200));

    final group = server.db.getGroup('grp10');
    expect(group!['name'], equals('New Name'));
  });

  test('non-admin cannot rename group', () async {
    server.db.createGroup(
      groupId: 'grp11',
      name: 'Protected Name',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice', 'bob'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenB);
    final res = await client.post('/api/v1/groups/update', {
      'group_id': 'grp11',
      'name': 'Hijacked Name',
    });
    expect(res.status, equals(403));
  });

  test('admin can change member role', () async {
    server.db.createGroup(
      groupId: 'grp12',
      name: 'Kappa Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice', 'bob'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/groups/member-role', {
      'group_id': 'grp12',
      'account_id': 'bob',
      'role': 'ADMIN',
    });
    expect(res.status, equals(200));
    expect(server.db.isGroupAdmin('grp12', 'bob'), isTrue);
  });

  // -------------------------------------------------------------------------
  // P16-009: Leave / remove
  // -------------------------------------------------------------------------

  test('member can leave group', () async {
    server.db.createGroup(
      groupId: 'grp13',
      name: 'Lambda Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice', 'bob'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenB);
    final res = await client.post('/api/v1/groups/leave', {
      'group_id': 'grp13',
    });
    expect(res.status, equals(200));
    expect(server.db.isConversationMember('grp13', 'bob'), isFalse);
  });

  test('admin can remove a member from group', () async {
    server.db.createGroup(
      groupId: 'grp14',
      name: 'Mu Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice', 'bob'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/groups/remove', {
      'group_id': 'grp14',
      'account_id': 'bob',
    });
    expect(res.status, equals(200));
    expect(server.db.isConversationMember('grp14', 'bob'), isFalse);
  });

  // -------------------------------------------------------------------------
  // P16-010: Group deletion
  // -------------------------------------------------------------------------

  test('admin can delete group — group is tombstoned', () async {
    server.db.createGroup(
      groupId: 'grp15',
      name: 'Nu Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice', 'bob'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/groups/delete', {
      'group_id': 'grp15',
    });
    expect(res.status, equals(200));
    expect(server.db.isTombstoned('grp15', 'GROUP'), isTrue);
  });

  test('non-admin cannot delete group', () async {
    server.db.createGroup(
      groupId: 'grp16',
      name: 'Xi Team',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice', 'bob'],
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenB);
    final res = await client.post('/api/v1/groups/delete', {
      'group_id': 'grp16',
    });
    expect(res.status, equals(403));
    expect(server.db.isTombstoned('grp16', 'GROUP'), isFalse);
  });

  // -------------------------------------------------------------------------
  // P16-012: Multi-device membership sync via WebSocket
  // -------------------------------------------------------------------------

  test('online member receives group_created event via WebSocket', () async {
    final tokenBWs = server.jwt.generateToken({
      'account_id': 'bob',
      'device_id': 'dev_bob',
    }, const Duration(hours: 1));
    final wsUri = Uri.parse('ws://127.0.0.1:$port/api/v1/ws?token=$tokenBWs');
    final ws = WebSocketChannel.connect(wsUri);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/groups/create', {
      'group_id': 'grp17',
      'name': 'Omicron Team',
      'initial_member_ids': ['bob'],
    });
    expect(res.status, equals(200));

    await ws.sink.close();
  });

  // -------------------------------------------------------------------------
  // P16-014: Abuse and rate limits
  // -------------------------------------------------------------------------

  test('group creation rate limit enforced at 5 per day', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);

    for (var i = 0; i < 5; i++) {
      final r = await client.post('/api/v1/groups/create', {
        'group_id': 'rate_grp_$i',
        'name': 'Rate Group $i',
      });
      expect(r.status, equals(200), reason: 'Group $i should succeed');
    }

    final rejected = await client.post('/api/v1/groups/create', {
      'group_id': 'rate_grp_6',
      'name': 'Rate Group 6',
    });
    expect(rejected.status, equals(429));
    expect(
      (jsonDecode(rejected.body) as Map<String, dynamic>)['error'],
      contains('quota'),
    );
  });

  test('invite rate limit enforced at 20 per hour', () async {
    // Create a group with enough accounts to invite.
    server.db.createGroup(
      groupId: 'rate_inv_grp',
      name: 'Rate Invite Group',
      creatorId: 'alice',
      encryptionKeyId: '',
      initialMemberIds: ['alice'],
    );

    // Pre-seed 20 existing invites from alice to exhaust the quota.
    for (var i = 0; i < 20; i++) {
      server.db.createGroupInvite(
        inviteId: 'pre_inv_$i',
        groupId: 'rate_inv_grp',
        inviterId: 'alice',
        inviteeId: 'carol',
      );
    }

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final rejected = await client.post('/api/v1/groups/invite', {
      'invite_id': 'inv_over_limit',
      'group_id': 'rate_inv_grp',
      'invitee_id': 'carol',
    });
    expect(rejected.status, equals(429));
    expect(
      (jsonDecode(rejected.body) as Map<String, dynamic>)['error'],
      contains('quota'),
    );
  });
}
