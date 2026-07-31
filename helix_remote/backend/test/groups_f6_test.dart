// Tests for Phase F6: Groups Admin — creator protection, ownership transfer,
// admin message deletion, silent leave, join link lifecycle, join requests,
// blocked member re-add, group-add policy, and rate limits.
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

class _Client {
  _Client(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  final _http = HttpClient();

  Future<({int status, Map<String, dynamic> json})> get(String path) async {
    final req = await _http.getUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    return (
      status: res.statusCode,
      json: decoded is Map<String, dynamic> ? decoded : {'_body': decoded},
    );
  }

  Future<({int status, Map<String, dynamic> json})> post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final req = await _http.postUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    return (
      status: res.statusCode,
      json: decoded is Map<String, dynamic> ? decoded : {'_body': decoded},
    );
  }
}

void main() {
  late BackendServer server;
  late int port;
  late String tokenAlice; // creator / admin
  late String tokenBob; // member
  late String tokenCarol; // second admin (promoted in tests that need it)

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_f6_groups',
      rateLimitMaxTokens: 500.0,
      rateLimitRefillRate: 100.0,
    );

    server.db.createAccount('alice', 'alice_user', 'alice_pk');
    server.db.registerDevice('dev_alice', 'alice', 'alice_dk', 'Alice Phone');
    server.db.createAccount('bob', 'bob_user', 'bob_pk');
    server.db.registerDevice('dev_bob', 'bob', 'bob_dk', 'Bob Phone');
    server.db.createAccount('carol', 'carol_user', 'carol_pk');
    server.db.registerDevice('dev_carol', 'carol', 'carol_dk', 'Carol Phone');

    String tok(String accountId, String deviceId) => server.jwt.generateToken({
      'account_id': accountId,
      'device_id': deviceId,
    }, const Duration(hours: 1));
    tokenAlice = tok('alice', 'dev_alice');
    tokenBob = tok('bob', 'dev_bob');
    tokenCarol = tok('carol', 'dev_carol');

    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async => server.stop());

  // Returns the base URL — evaluated lazily so `port` is already set.
  String base() => 'http://127.0.0.1:$port';

  // Helper: create group 'g1' with alice as admin, bob as initial member.
  Future<void> seedGroup({bool addCarol = false}) async {
    final initial = <String>['bob', if (addCarol) 'carol'];
    await _Client(base(), tokenAlice).post('/api/v1/groups/create', {
      'group_id': 'g1',
      'name': 'F6 Group',
      'initial_member_ids': initial,
    });
  }

  // -------------------------------------------------------------------------
  // F6-001: Creator protection — demotion blocked
  // -------------------------------------------------------------------------

  group('F6-001 creator protection', () {
    test('cannot demote creator via member-role', () async {
      await seedGroup(addCarol: true);
      // Promote carol to admin so she can attempt to demote alice.
      await _Client(base(), tokenAlice).post('/api/v1/groups/member-role', {
        'group_id': 'g1',
        'account_id': 'carol',
        'role': 'ADMIN',
      });
      final res = await _Client(base(), tokenCarol).post(
        '/api/v1/groups/member-role',
        {'group_id': 'g1', 'account_id': 'alice', 'role': 'MEMBER'},
      );
      expect(res.status, equals(409));
    });

    test('cannot remove creator', () async {
      await seedGroup(addCarol: true);
      await _Client(base(), tokenAlice).post('/api/v1/groups/member-role', {
        'group_id': 'g1',
        'account_id': 'carol',
        'role': 'ADMIN',
      });
      final res = await _Client(base(), tokenCarol).post(
        '/api/v1/groups/remove',
        {'group_id': 'g1', 'account_id': 'alice'},
      );
      expect(res.status, equals(409));
    });

    test('non-admin cannot demote creator', () async {
      await seedGroup();
      final res = await _Client(base(), tokenBob).post(
        '/api/v1/groups/member-role',
        {'group_id': 'g1', 'account_id': 'alice', 'role': 'MEMBER'},
      );
      // Bob is a plain member — should be 403, not 409.
      expect(res.status, equals(403));
    });
  });

  // -------------------------------------------------------------------------
  // F6-002: Ownership transfer
  // -------------------------------------------------------------------------

  group('F6-002 ownership transfer', () {
    test('creator can transfer ownership to member', () async {
      await seedGroup();
      final res = await _Client(base(), tokenAlice).post(
        '/api/v1/groups/transfer-ownership',
        {'group_id': 'g1', 'new_owner_id': 'bob'},
      );
      expect(res.status, equals(200));
      // Bob should now be creator.
      final group = server.db.getGroup('g1');
      expect(group!['creator_id'], equals('bob'));
      // Alice should retain ADMIN role.
      expect(server.db.isGroupAdmin('g1', 'alice'), isTrue);
      // Bob is now creator — protection flag moves.
      expect(server.db.isGroupCreatorProtected('g1', 'bob'), isTrue);
      expect(server.db.isGroupCreatorProtected('g1', 'alice'), isFalse);
    });

    test('non-creator cannot transfer ownership', () async {
      await seedGroup(addCarol: true);
      await _Client(base(), tokenAlice).post('/api/v1/groups/member-role', {
        'group_id': 'g1',
        'account_id': 'carol',
        'role': 'ADMIN',
      });
      final res = await _Client(base(), tokenCarol).post(
        '/api/v1/groups/transfer-ownership',
        {'group_id': 'g1', 'new_owner_id': 'bob'},
      );
      expect(res.status, equals(403));
    });

    test('transfer to non-member returns error', () async {
      await seedGroup();
      final res = await _Client(base(), tokenAlice).post(
        '/api/v1/groups/transfer-ownership',
        {'group_id': 'g1', 'new_owner_id': 'carol'}, // carol not in group
      );
      expect(res.status, anyOf(equals(400), equals(403), equals(404)));
    });
  });

  // -------------------------------------------------------------------------
  // F6-003: Group-add privacy
  // -------------------------------------------------------------------------

  group('F6-003 group-add privacy', () {
    test('admin can set add policy to NOBODY', () async {
      await seedGroup();
      final res = await _Client(base(), tokenAlice).post(
        '/api/v1/groups/set-add-policy',
        {'group_id': 'g1', 'policy': 'NOBODY'},
      );
      expect(res.status, equals(200));
      expect(server.db.getGroupAddPolicy('g1'), equals('NOBODY'));
    });

    test('policy defaults to EVERYONE on creation', () async {
      await seedGroup();
      expect(server.db.getGroupAddPolicy('g1'), equals('EVERYONE'));
    });

    test('non-admin cannot set add policy', () async {
      await seedGroup();
      final res = await _Client(base(), tokenBob).post(
        '/api/v1/groups/set-add-policy',
        {'group_id': 'g1', 'policy': 'CONTACTS'},
      );
      expect(res.status, equals(403));
    });

    test('invalid policy value returns 400', () async {
      await seedGroup();
      final res = await _Client(base(), tokenAlice).post(
        '/api/v1/groups/set-add-policy',
        {'group_id': 'g1', 'policy': 'PURPLE'},
      );
      expect(res.status, equals(400));
    });
  });

  // -------------------------------------------------------------------------
  // F6-004: Join link lifecycle
  // -------------------------------------------------------------------------

  group('F6-004 join link lifecycle', () {
    test('admin can create and revoke a join link', () async {
      await seedGroup();
      final createRes = await _Client(base(), tokenAlice)
          .post('/api/v1/groups/create-join-link', {
            'group_id': 'g1',
            'link_id': 'link_lifecycle',
            'token': 'token_lifecycle',
            'requires_approval': false,
          });
      expect(createRes.status, equals(200));
      final token = createRes.json['token'] as String;
      expect(token, isNotEmpty);

      // Carol joins via link.
      final joinRes = await _Client(base(), tokenCarol).post(
        '/api/v1/groups/join-via-link',
        {'token': token, 'request_id': 'req_join_1'},
      );
      expect(joinRes.status, equals(200));
      expect(server.db.getGroupMemberRole('g1', 'carol'), equals('MEMBER'));

      // Revoke the link.
      final linkId = createRes.json['link_id'] as String;
      final revokeRes = await _Client(
        base(),
        tokenAlice,
      ).post('/api/v1/groups/revoke-join-link', {'link_id': linkId});
      expect(revokeRes.status, equals(200));

      // Using revoked token is rejected.
      final secondJoin = await _Client(base(), tokenCarol).post(
        '/api/v1/groups/join-via-link',
        {'token': token, 'request_id': 'req_join_2'},
      );
      expect(secondJoin.status, anyOf(equals(400), equals(404), equals(410)));
    });

    test('non-admin cannot create join link', () async {
      await seedGroup();
      final res = await _Client(base(), tokenBob)
          .post('/api/v1/groups/create-join-link', {
            'group_id': 'g1',
            'link_id': 'link_non_admin',
            'token': 'token_non_admin',
            'requires_approval': false,
          });
      expect(res.status, equals(403));
    });

    test('join via link with approval creates pending request', () async {
      await seedGroup();
      final createRes = await _Client(base(), tokenAlice)
          .post('/api/v1/groups/create-join-link', {
            'group_id': 'g1',
            'link_id': 'link_approval',
            'token': 'token_approval',
            'requires_approval': true,
          });
      expect(createRes.status, equals(200));
      final token = createRes.json['token'] as String;

      final joinRes = await _Client(base(), tokenCarol).post(
        '/api/v1/groups/join-via-link',
        {'token': token, 'request_id': 'req_approval'},
      );
      expect(
        joinRes.status,
        anyOf(equals(200), equals(202)),
      ); // accepted, pending approval

      // Carol should NOT be a member yet.
      expect(server.db.getGroupMemberRole('g1', 'carol'), isNull);
    });

    test('join link with invalid token returns error', () async {
      await seedGroup();
      final res = await _Client(base(), tokenCarol).post(
        '/api/v1/groups/join-via-link',
        {'token': 'totally_invalid_token', 'request_id': 'req_invalid'},
      );
      expect(res.status, anyOf(equals(400), equals(404), equals(410)));
    });
  });

  // -------------------------------------------------------------------------
  // F6-005: Join request approval flow
  // -------------------------------------------------------------------------

  group('F6-005 join request approval', () {
    late String linkToken;

    setUp(() async {
      await seedGroup();
      final createRes = await _Client(base(), tokenAlice)
          .post('/api/v1/groups/create-join-link', {
            'group_id': 'g1',
            'link_id': 'link_approval_flow',
            'token': 'token_approval_flow',
            'requires_approval': true,
          });
      linkToken = createRes.json['token'] as String;
    });

    test('admin can approve join request', () async {
      await _Client(base(), tokenCarol).post('/api/v1/groups/join-via-link', {
        'token': linkToken,
        'request_id': 'req_approve_1',
      });
      final listRes = await _Client(
        base(),
        tokenAlice,
      ).get('/api/v1/groups/join-requests?group_id=g1');
      expect(listRes.status, equals(200));
      final requests = listRes.json['requests'] as List;
      expect(requests, isNotEmpty);
      final requestId = (requests.first as Map<String, dynamic>)['request_id'];

      final approveRes = await _Client(base(), tokenAlice).post(
        '/api/v1/groups/approve-join-request',
        {'request_id': requestId, 'approve': true},
      );
      expect(approveRes.status, equals(200));
      expect(server.db.getGroupMemberRole('g1', 'carol'), equals('MEMBER'));
    });

    test('admin can reject join request', () async {
      await _Client(base(), tokenCarol).post('/api/v1/groups/join-via-link', {
        'token': linkToken,
        'request_id': 'req_reject_1',
      });
      final listRes = await _Client(
        base(),
        tokenAlice,
      ).get('/api/v1/groups/join-requests?group_id=g1');
      final requests = listRes.json['requests'] as List;
      final requestId = (requests.first as Map<String, dynamic>)['request_id'];

      final rejectRes = await _Client(base(), tokenAlice).post(
        '/api/v1/groups/approve-join-request',
        {'request_id': requestId, 'approve': false},
      );
      expect(rejectRes.status, equals(200));
      expect(server.db.getGroupMemberRole('g1', 'carol'), isNull);
    });

    test('non-admin cannot list join requests', () async {
      final listRes = await _Client(
        base(),
        tokenBob,
      ).get('/api/v1/groups/join-requests?group_id=g1');
      expect(listRes.status, equals(403));
    });
  });

  // -------------------------------------------------------------------------
  // F6-006: Blocked member — cannot re-add or join via link
  // -------------------------------------------------------------------------

  group('F6-006 blocked member re-add', () {
    test('blocked member cannot be re-invited', () async {
      await seedGroup();
      // Block bob.
      final blockRes = await _Client(base(), tokenAlice).post(
        '/api/v1/groups/block-member',
        {'group_id': 'g1', 'account_id': 'bob'},
      );
      expect(blockRes.status, equals(200));

      // Attempt to re-invite bob.
      final inviteRes = await _Client(base(), tokenAlice).post(
        '/api/v1/groups/invite',
        {'group_id': 'g1', 'invite_id': 'inv_blocked', 'invitee_id': 'bob'},
      );
      expect(inviteRes.status, anyOf(equals(400), equals(403), equals(409)));
    });

    test('blocked member cannot join via link', () async {
      await seedGroup();
      final createRes = await _Client(base(), tokenAlice)
          .post('/api/v1/groups/create-join-link', {
            'group_id': 'g1',
            'link_id': 'link_block_test',
            'token': 'token_block_test',
            'requires_approval': false,
          });
      final token = createRes.json['token'] as String;

      // Block bob.
      await _Client(base(), tokenAlice).post('/api/v1/groups/block-member', {
        'group_id': 'g1',
        'account_id': 'bob',
      });

      // Bob attempts to join via link.
      final joinRes = await _Client(base(), tokenBob).post(
        '/api/v1/groups/join-via-link',
        {'token': token, 'request_id': 'req_blocked_join'},
      );
      expect(joinRes.status, anyOf(equals(403), equals(409)));
    });

    test('non-admin cannot block members', () async {
      await seedGroup();
      final res = await _Client(base(), tokenBob).post(
        '/api/v1/groups/block-member',
        {'group_id': 'g1', 'account_id': 'carol'},
      );
      expect(res.status, equals(403));
    });
  });

  // -------------------------------------------------------------------------
  // F6-007: Admin message deletion (soft-delete with moderator tombstone)
  // -------------------------------------------------------------------------

  group('F6-007 admin message deletion', () {
    test('admin can soft-delete a message', () async {
      await seedGroup();
      const msgId = 'msg_001';

      final res = await _Client(base(), tokenAlice).post(
        '/api/v1/groups/admin-delete-message',
        {'group_id': 'g1', 'message_id': msgId},
      );
      expect(res.status, equals(200));
      // Verify moderation record was created.
      expect(server.db.isGroupMessageModerated('g1', msgId), isTrue);
    });

    test('non-admin cannot soft-delete messages', () async {
      await seedGroup();
      final res = await _Client(base(), tokenBob).post(
        '/api/v1/groups/admin-delete-message',
        {'group_id': 'g1', 'message_id': 'msg_002'},
      );
      expect(res.status, equals(403));
    });
  });

  // -------------------------------------------------------------------------
  // F6-008: Silent leave
  // -------------------------------------------------------------------------

  group('F6-008 silent leave', () {
    test('member leave returns 200 and removes membership', () async {
      await seedGroup();
      final res = await _Client(
        base(),
        tokenBob,
      ).post('/api/v1/groups/leave', {'group_id': 'g1'});
      expect(res.status, equals(200));
      expect(server.db.getGroupMemberRole('g1', 'bob'), isNull);
    });

    test('admin leave returns 200', () async {
      await seedGroup();
      final res = await _Client(
        base(),
        tokenAlice,
      ).post('/api/v1/groups/leave', {'group_id': 'g1'});
      expect(res.status, equals(200));
    });
  });

  // -------------------------------------------------------------------------
  // F6-009: Join link rate limit
  // -------------------------------------------------------------------------

  group('F6-009 join link rate limiting', () {
    test('more than 10 join links per day is rejected', () async {
      await seedGroup();
      // Create 10 links successfully.
      for (var i = 0; i < 10; i++) {
        final r = await _Client(base(), tokenAlice)
            .post('/api/v1/groups/create-join-link', {
              'group_id': 'g1',
              'link_id': 'link_rate_$i',
              'token': 'token_rate_$i',
              'requires_approval': false,
            });
        expect(r.status, equals(200), reason: 'link $i should succeed');
      }
      // 11th should be rate-limited.
      final last = await _Client(base(), tokenAlice)
          .post('/api/v1/groups/create-join-link', {
            'group_id': 'g1',
            'link_id': 'link_rate_11',
            'token': 'token_rate_11',
            'requires_approval': false,
          });
      expect(last.status, anyOf(equals(429), equals(400)));
    });
  });
}
