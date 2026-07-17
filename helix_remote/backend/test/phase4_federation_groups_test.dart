import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

/// Milestone 4 — Federation: Groups.
///
/// Three servers: A is always the "home" server for groups created in
/// these tests (alice's server); B and C are "participant" servers hosting
/// federated members (bob, carol respectively). Mirrors the harness style
/// of phase3_federation_test.dart (S2S handshake via a shared directory),
/// extended to a third server since several assertions specifically need
/// to prove a broadcast reaches *all* participating domains, not just the
/// one involved in a given mutation.
void main() {
  late FederationDirectoryServer directory;
  late BackendServer serverA;
  late BackendServer serverB;
  late BackendServer serverC;
  late ServerIdentity identityA;
  late ServerIdentity identityB;
  late ServerIdentity identityC;
  late int directoryPort;
  late int portA;
  late int portB;
  late int portC;

  setUp(() async {
    directory = FederationDirectoryServer();
    await directory.start('127.0.0.1', 0);
    directoryPort = directory.httpServer!.port;
    final directoryUrl = 'http://127.0.0.1:$directoryPort';

    serverA = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_phase4_server_a',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      federationDomain: 'a.test',
      federationDirectoryUrl: directoryUrl,
    );
    identityA = await ServerIdentity.loadOrCreate(serverA.db);
    serverA.serverIdentity = identityA;
    await serverA.start('127.0.0.1', 0);
    portA = serverA.httpServer!.port;

    serverB = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_phase4_server_b',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      federationDomain: 'b.test',
      federationDirectoryUrl: directoryUrl,
    );
    identityB = await ServerIdentity.loadOrCreate(serverB.db);
    serverB.serverIdentity = identityB;
    await serverB.start('127.0.0.1', 0);
    portB = serverB.httpServer!.port;

    serverC = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_phase4_server_c',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      federationDomain: 'c.test',
      federationDirectoryUrl: directoryUrl,
    );
    identityC = await ServerIdentity.loadOrCreate(serverC.db);
    serverC.serverIdentity = identityC;
    await serverC.start('127.0.0.1', 0);
    portC = serverC.httpServer!.port;

    await _registerServer(
      identity: identityA,
      domain: 'a.test',
      address: 'http://127.0.0.1:$portA',
      directoryUrl: 'http://127.0.0.1:$directoryPort',
      users: const ['alice@a.test'],
      db: serverA.db,
    );
    await _registerServer(
      identity: identityB,
      domain: 'b.test',
      address: 'http://127.0.0.1:$portB',
      directoryUrl: 'http://127.0.0.1:$directoryPort',
      users: const ['bob@b.test'],
      db: serverB.db,
    );
    await _registerServer(
      identity: identityC,
      domain: 'c.test',
      address: 'http://127.0.0.1:$portC',
      directoryUrl: 'http://127.0.0.1:$directoryPort',
      users: const ['carol@c.test'],
      db: serverC.db,
    );
  });

  tearDown(() async {
    await serverA.stop();
    await serverB.stop();
    await serverC.stop();
    await directory.stop();
  });

  test(
    'creating a group with a federated member syncs the roster to the participant server',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, 'alice');
        final bob = await _register(client, portB, 'bob');

        final create = await _postJson(
          client,
          portA,
          '/api/v1/groups/create',
          {
            'group_id': 'grp_1',
            'name': 'Cross-server crew',
            'encryption_key_id': 'ek_1',
            'initial_member_ids': ['bob@b.test'],
          },
          token: alice.token,
        );
        expect(create.statusCode, equals(200), reason: create.body);

        // Bob's own server should now have a synced read-model.
        final info = await _getJson(
          client,
          portB,
          '/api/v1/groups/info?group_id=grp_1',
          token: bob.token,
        );
        expect(info.statusCode, equals(200), reason: info.body);
        final infoBody = jsonDecode(info.body) as Map<String, dynamic>;
        expect(infoBody['is_federated'], isTrue);
        expect(infoBody['home_domain'], equals('a.test'));

        final members = await _getJson(
          client,
          portB,
          '/api/v1/groups/members?group_id=grp_1',
          token: bob.token,
        );
        final memberIds =
            ((jsonDecode(members.body) as Map<String, dynamic>)['members']
                    as List)
                .map((m) => (m as Map<String, dynamic>)['account_id'])
                .toSet();
        expect(memberIds, contains('bob'));
        expect(memberIds, contains('alice@a.test'));
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'invite reaches the invitee\'s own server, and accepting it syncs the roster to every participant',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, 'alice');
        final bob = await _register(client, portB, 'bob');
        final carol = await _register(client, portC, 'carol');

        await _postJson(client, portA, '/api/v1/groups/create', {
          'group_id': 'grp_2',
          'name': 'Three servers',
          'encryption_key_id': 'ek_2',
          'initial_member_ids': ['bob@b.test'],
        }, token: alice.token);

        final invite = await _postJson(
          client,
          portA,
          '/api/v1/groups/invite',
          {
            'invite_id': 'inv_1',
            'group_id': 'grp_2',
            'invitee_id': 'carol@c.test',
          },
          token: alice.token,
        );
        expect(invite.statusCode, equals(200), reason: invite.body);

        // Carol's own server should have learned about the pending invite.
        final carolEvents = await _getJson(
          client,
          portC,
          '/api/v1/messages/device-events?since_sequence=0',
          token: carol.token,
        );
        final carolEnvelopes =
            (jsonDecode(carolEvents.body) as Map<String, dynamic>)['events']
                as List;
        final inviteEvent = carolEnvelopes
            .map((e) => e as Map<String, dynamic>)
            .firstWhere((e) => e['type'] == 'group_invite');
        expect(
          (inviteEvent['payload'] as Map<String, dynamic>)['invite_id'],
          equals('inv_1'),
        );

        // Carol accepts on HER OWN server -- must be proxied to A (home).
        final respond = await _postJson(
          client,
          portC,
          '/api/v1/groups/invite/respond',
          {'invite_id': 'inv_1', 'accept': true},
          token: carol.token,
        );
        expect(respond.statusCode, equals(200), reason: respond.body);

        // Bob's server (a pre-existing, *different* participant) must also
        // learn about carol joining -- proves the before-union-after domain
        // broadcast, not just a push to the newly-joined domain.
        final bobMembers = await _getJson(
          client,
          portB,
          '/api/v1/groups/members?group_id=grp_2',
          token: bob.token,
        );
        final bobSeesIds =
            ((jsonDecode(bobMembers.body) as Map<String, dynamic>)['members']
                    as List)
                .map((m) => (m as Map<String, dynamic>)['account_id'])
                .toSet();
        expect(bobSeesIds, contains('carol@c.test'));

        // And carol's own server must have materialized her as a real
        // local member (not just an accepted invite).
        final carolMembers = await _getJson(
          client,
          portC,
          '/api/v1/groups/members?group_id=grp_2',
          token: carol.token,
        );
        final carolSeesIds =
            ((jsonDecode(carolMembers.body) as Map<String, dynamic>)['members']
                    as List)
                .map((m) => (m as Map<String, dynamic>)['account_id'])
                .toSet();
        expect(carolSeesIds, contains('carol'));
        expect(carolSeesIds, contains('bob@b.test'));
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'a participant-side admin action (member-role) is proxied to the home server',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, 'alice');
        final bob = await _register(client, portB, 'bob');

        await _postJson(client, portA, '/api/v1/groups/create', {
          'group_id': 'grp_3',
          'name': 'Promote test',
          'encryption_key_id': 'ek_3',
          'initial_member_ids': ['bob@b.test'],
        }, token: alice.token);

        // Make bob an admin first (home-direct call).
        final promote = await _postJson(
          client,
          portA,
          '/api/v1/groups/member-role',
          {'group_id': 'grp_3', 'account_id': 'bob@b.test', 'role': 'ADMIN'},
          token: alice.token,
        );
        expect(promote.statusCode, equals(200), reason: promote.body);

        // Bob (now admin, but only known locally via his own server B)
        // demotes himself back to MEMBER -- his REST call lands on B,
        // which must recognize itself as a participant and proxy to A.
        final demote = await _postJson(
          client,
          portB,
          '/api/v1/groups/member-role',
          {'group_id': 'grp_3', 'account_id': 'bob@b.test', 'role': 'MEMBER'},
          token: bob.token,
        );
        expect(demote.statusCode, equals(200), reason: demote.body);

        final infoOnA = await _getJson(
          client,
          portA,
          '/api/v1/groups/members?group_id=grp_3',
          token: alice.token,
        );
        final roleOnA =
            ((jsonDecode(infoOnA.body) as Map<String, dynamic>)['members']
                    as List)
                .map((m) => m as Map<String, dynamic>)
                .firstWhere((m) => m['account_id'] == 'bob@b.test');
        expect(roleOnA['role'], equals('MEMBER'));
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'a non-admin cannot proxy an admin action through a participant server',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, 'alice');
        final bob = await _register(client, portB, 'bob');

        await _postJson(client, portA, '/api/v1/groups/create', {
          'group_id': 'grp_4',
          'name': 'Auth test',
          'encryption_key_id': 'ek_4',
          'initial_member_ids': ['bob@b.test'],
        }, token: alice.token);

        // Bob is a plain MEMBER; his server must forward the request to
        // home, and home must reject it -- not just B rejecting locally.
        final attempt = await _postJson(
          client,
          portB,
          '/api/v1/groups/update',
          {'group_id': 'grp_4', 'name': 'Renamed by bob'},
          token: bob.token,
        );
        expect(attempt.statusCode, equals(403), reason: attempt.body);
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'group message fan-out reaches federated members on multiple domains via one batch call per domain',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, 'alice');
        final bob = await _register(client, portB, 'bob');
        final carol = await _register(client, portC, 'carol');

        serverB.db.publishPrekeys(
          accountId: 'bob',
          deviceId: 'bob_device',
          signedPrekeyId: 1,
          signedPrekey: 'bob_spk',
          signature: 'bob_sig',
          oneTimePrekeys: const [],
        );
        serverC.db.publishPrekeys(
          accountId: 'carol',
          deviceId: 'carol_device',
          signedPrekeyId: 1,
          signedPrekey: 'carol_spk',
          signature: 'carol_sig',
          oneTimePrekeys: const [],
        );

        await _postJson(client, portA, '/api/v1/groups/create', {
          'group_id': 'grp_5',
          'name': 'Fan-out test',
          'encryption_key_id': 'ek_5',
          'initial_member_ids': ['bob@b.test', 'carol@c.test'],
        }, token: alice.token);

        final send = await _postJson(client, portA, '/api/v1/messages/send', {
          'message_id': 'msg_grp_5_1',
          'conversation_id': 'grp_5',
          'envelopes': [
            {
              'recipient_account_id': 'bob@b.test',
              'recipient_device_id': 'bob_device',
              'ciphertext': 'ct_for_bob',
            },
            {
              'recipient_account_id': 'carol@c.test',
              'recipient_device_id': 'carol_device',
              'ciphertext': 'ct_for_carol',
            },
          ],
        }, token: alice.token);
        expect(send.statusCode, equals(200), reason: send.body);
        final sendBody = jsonDecode(send.body) as Map<String, dynamic>;
        expect(sendBody['federated_envelopes_count'], equals(2));

        final bobEvents = await _getJson(
          client,
          portB,
          '/api/v1/messages/device-events?since_sequence=0',
          token: bob.token,
        );
        final bobChatEvent = ((jsonDecode(bobEvents.body) as Map<String, dynamic>)['events']
                as List)
            .map((e) => e as Map<String, dynamic>)
            .firstWhere((e) => e['type'] == 'chat_message');
        expect(
          (bobChatEvent['payload'] as Map<String, dynamic>)['ciphertext'],
          equals('ct_for_bob'),
        );

        final carolEvents = await _getJson(
          client,
          portC,
          '/api/v1/messages/device-events?since_sequence=0',
          token: carol.token,
        );
        final carolChatEvent = ((jsonDecode(carolEvents.body) as Map<String, dynamic>)['events']
                as List)
            .map((e) => e as Map<String, dynamic>)
            .firstWhere((e) => e['type'] == 'chat_message');
        expect(
          (carolChatEvent['payload'] as Map<String, dynamic>)['ciphertext'],
          equals('ct_for_carol'),
        );
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'epoch key delivery batches per federated domain and reaches remote devices',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, 'alice');
        final bob = await _register(client, portB, 'bob');
        final carol = await _register(client, portC, 'carol');

        await _postJson(client, portA, '/api/v1/groups/create', {
          'group_id': 'grp_6',
          'name': 'Epoch key test',
          'encryption_key_id': 'ek_6',
          'initial_member_ids': ['bob@b.test', 'carol@c.test'],
        }, token: alice.token);

        final deliver = await _postJson(
          client,
          portA,
          '/api/v1/groups/epoch-key/deliver',
          {
            'group_id': 'grp_6',
            'epoch': 1,
            'key_id': 'gk_epoch_1',
            'deliveries': [
              {
                'recipient_account_id': 'bob@b.test',
                'recipient_device_id': 'bob_device',
                'wrapped_key': 'wrapped_for_bob',
              },
              {
                'recipient_account_id': 'carol@c.test',
                'recipient_device_id': 'carol_device',
                'wrapped_key': 'wrapped_for_carol',
              },
            ],
          },
          token: alice.token,
        );
        expect(deliver.statusCode, equals(200), reason: deliver.body);
        final deliverBody = jsonDecode(deliver.body) as Map<String, dynamic>;
        expect(deliverBody['federated_domains'], equals(2));

        final bobEvents = await _getJson(
          client,
          portB,
          '/api/v1/messages/device-events?since_sequence=0',
          token: bob.token,
        );
        final bobKeyEvent = ((jsonDecode(bobEvents.body) as Map<String, dynamic>)['events']
                as List)
            .map((e) => e as Map<String, dynamic>)
            .firstWhere((e) => e['type'] == 'group_epoch_key');
        expect(
          (bobKeyEvent['payload'] as Map<String, dynamic>)['wrapped_key'],
          equals('wrapped_for_bob'),
        );

        final carolEvents = await _getJson(
          client,
          portC,
          '/api/v1/messages/device-events?since_sequence=0',
          token: carol.token,
        );
        final carolKeyEvent = ((jsonDecode(carolEvents.body) as Map<String, dynamic>)['events']
                as List)
            .map((e) => e as Map<String, dynamic>)
            .firstWhere((e) => e['type'] == 'group_epoch_key');
        expect(
          (carolKeyEvent['payload'] as Map<String, dynamic>)['wrapped_key'],
          equals('wrapped_for_carol'),
        );
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'a reaction on a federated group message reaches the federated member',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, 'alice');
        // A second local member is needed so the message has at least one
        // local recipient device: MessagingModule only writes a `messages`
        // row when saveMessage() runs for a local envelope (a purely
        // federated-only send never persists to `messages` -- a known,
        // deliberately out-of-scope gap for this milestone, see plan §4.3.2
        // -- so reacting to a message with zero local recipients would 404
        // regardless of federation).
        await _register(client, portA, 'dave');
        final bob = await _register(client, portB, 'bob');

        serverB.db.publishPrekeys(
          accountId: 'bob',
          deviceId: 'bob_device',
          signedPrekeyId: 1,
          signedPrekey: 'bob_spk',
          signature: 'bob_sig',
          oneTimePrekeys: const [],
        );

        await _postJson(client, portA, '/api/v1/groups/create', {
          'group_id': 'grp_7',
          'name': 'Reaction test',
          'encryption_key_id': 'ek_7',
          'initial_member_ids': ['dave', 'bob@b.test'],
        }, token: alice.token);

        final send = await _postJson(client, portA, '/api/v1/messages/send', {
          'message_id': 'msg_grp_7_1',
          'conversation_id': 'grp_7',
          'envelopes': [
            {
              'recipient_device_id': 'dave_device',
              'ciphertext': 'ct_for_dave',
            },
            {
              'recipient_account_id': 'bob@b.test',
              'recipient_device_id': 'bob_device',
              'ciphertext': 'ct_for_bob',
            },
          ],
        }, token: alice.token);
        expect(send.statusCode, equals(200), reason: send.body);

        final react = await _postJson(
          client,
          portA,
          '/api/v1/messages/reactions',
          {
            'message_id': 'msg_grp_7_1',
            'reaction': '👍',
            'revision_id': 'rev_react_1',
          },
          token: alice.token,
        );
        expect(react.statusCode, equals(200), reason: react.body);

        final bobEvents = await _getJson(
          client,
          portB,
          '/api/v1/messages/device-events?since_sequence=0',
          token: bob.token,
        );
        final events =
            (jsonDecode(bobEvents.body) as Map<String, dynamic>)['events']
                as List;
        final reactionEvent = events
            .map((e) => e as Map<String, dynamic>)
            .where((e) => e['type'] == 'reaction_added')
            .toList();
        expect(reactionEvent, hasLength(1));
        expect(
          (reactionEvent.single['payload'] as Map<String, dynamic>)['reaction'],
          equals('👍'),
        );
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'a server cannot push group sync claiming a different server is home',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, 'alice');
        await _postJson(client, portA, '/api/v1/groups/create', {
          'group_id': 'grp_8',
          'name': 'Spoof test',
          'encryption_key_id': 'ek_8',
          'initial_member_ids': const [],
        }, token: alice.token);

        // Server C signs a sync push (so the S2S signature itself is
        // valid and identifies C) but claims a forged home_server_id that
        // doesn't match its own identity -- the handler must reject this
        // regardless of signature validity.
        final body = jsonEncode({
          'group_id': 'grp_8',
          'home_server_id': 'not-actually-c',
          'home_domain': 'a.test',
          'name': 'Spoofed',
          'creator_id': 'alice@a.test',
          'encryption_key_id': 'ek_8',
          'status': 'ACTIVE',
          'add_policy': 'EVERYONE',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'members': [
            {'account_id': 'mallory@c.test', 'role': 'ADMIN'},
          ],
        });
        final uri = Uri.parse(
          'http://127.0.0.1:$portB',
        ).resolve('/api/v1/s2s/groups/sync');
        final headers = await S2SSignatures.signHeaders(
          identity: identityC,
          path: uri.path,
          body: body,
        );
        final request = await client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        headers.forEach(request.headers.set);
        request.write(body);
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, equals(401));
      } finally {
        client.close(force: true);
      }
    },
  );
}

class _RegisteredUser {
  const _RegisteredUser(this.token);
  final String token;
}

Future<_RegisteredUser> _register(
  HttpClient client,
  int port,
  String accountId,
) async {
  final material = await registerTestAccount(
    client: client,
    host: '127.0.0.1',
    port: port,
    accountId: accountId,
    username: '${accountId}_user',
    deviceId: '${accountId}_device',
    deviceName: '$accountId Phone',
  );
  final login = await loginTestAccount(
    client: client,
    host: '127.0.0.1',
    port: port,
    accountId: accountId,
    deviceId: '${accountId}_device',
    deviceSigningKeyPair: material.deviceSigningKeyPair,
  );
  return _RegisteredUser(login['token'] as String);
}

Future<void> _registerServer({
  required ServerIdentity identity,
  required String domain,
  required String address,
  required String directoryUrl,
  required List<String> users,
  required BackendDatabase db,
}) async {
  final client = FederationClient(
    db: db,
    identity: identity,
    directoryUrl: directoryUrl,
  );
  await client.registerDirectory(domain: domain, address: address, users: users);
}

Future<_Response> _getJson(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.get('127.0.0.1', port, path);
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

Future<_Response> _postJson(
  HttpClient client,
  int port,
  String path,
  Map<String, dynamic> data, {
  String? token,
}) async {
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  request.write(jsonEncode(data));
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
