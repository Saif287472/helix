import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

// Anyone may start a direct chat with anyone (no contact request first), so
// "create conversation" must never let a stranger take over a conversation
// id someone else already uses.
void main() {
  late BackendServer server;
  late int port;
  final http = HttpClient();

  String tokenFor(String account, String device) => server.jwt.generateToken({
    'account_id': account,
    'device_id': device,
  }, const Duration(hours: 1));

  Future<int> create(String token, String id, List<String> members) async {
    final req = await http.postUrl(
      Uri.parse('http://127.0.0.1:$port/api/v1/messages/conversations/create'),
    );
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.contentType = ContentType.json;
    req.write(
      jsonEncode({'conversation_id': id, 'type': 'DIRECT', 'members': members}),
    );
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  }

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_conversation_create',
      rateLimitMaxTokens: 200.0,
      rateLimitRefillRate: 50.0,
    );
    for (final (account, device) in [
      ('alice', 'alice_d'),
      ('bob', 'bob_d'),
      ('mallory', 'mallory_d'),
    ]) {
      server.db.createAccount(account, account, '${account}_key');
      server.db.registerDevice(device, account, '${device}_key', 'Phone');
    }
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async => server.stop());
  tearDownAll(() => http.close(force: true));

  test(
    'a stranger can start a direct chat without a contact request',
    () async {
      expect(
        await create(tokenFor('alice', 'alice_d'), 'dm_ab', ['bob']),
        equals(200),
      );
      expect(server.db.isConversationMember('dm_ab', 'bob'), isTrue);
    },
  );

  test(
    'creating an existing conversation again is idempotent for a member',
    () async {
      await create(tokenFor('alice', 'alice_d'), 'dm_ab', ['bob']);
      expect(
        await create(tokenFor('bob', 'bob_d'), 'dm_ab', ['alice']),
        equals(200),
      );
    },
  );

  test('a non-member cannot take over an existing conversation id', () async {
    await create(tokenFor('alice', 'alice_d'), 'dm_ab', ['bob']);
    expect(
      await create(tokenFor('mallory', 'mallory_d'), 'dm_ab', ['alice']),
      equals(403),
    );
    expect(server.db.isConversationMember('dm_ab', 'mallory'), isFalse);
    expect(server.db.isConversationMember('dm_ab', 'bob'), isTrue);
  });

  test('a direct conversation has at most two members', () async {
    expect(
      await create(tokenFor('alice', 'alice_d'), 'dm_abm', ['bob', 'mallory']),
      equals(400),
    );
  });
}
