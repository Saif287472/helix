// Phase 3 — the operational controls that were SnackBar-only.
//
// Maintenance Mode, the admin-password change, the data purge, and the support
// bundle all had a button in the console and nothing behind it. Each of these
// pins the behaviour the button now claims.

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/admin_password.dart';

void main() {
  late BackendServer server;
  late HttpClient client;
  late int port;
  late String adminToken;

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_phase3_ops_controls',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      adminPasswordOverride: 'first-admin-password',
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
    client = HttpClient();

    server.db.createAccount('phase3_ops', 'phase3_ops_user', 'ops_key');
    server.db.setAccountAdmin('phase3_ops', isAdmin: true);
    server.db.registerDevice(
      'phase3_ops_device',
      'phase3_ops',
      'ops_device_key',
      'Ops',
    );
    adminToken = server.jwt.generateToken({
      'account_id': 'phase3_ops',
      'device_id': 'phase3_ops_device',
    }, const Duration(hours: 1));
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<({int status, Map<String, dynamic> body})> call(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:$port$path');
    final req = method == 'GET'
        ? await client.getUrl(uri)
        : await client.openUrl(method, uri);
    // Headers must be set before the first write - writing freezes them.
    final effective = token ?? adminToken;
    if (effective.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer $effective');
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close();
    final text = await response.transform(utf8.decoder).join();
    Map<String, dynamic> decoded = {};
    if (text.isNotEmpty) {
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) decoded = parsed;
      } catch (_) {
        // Non-JSON body; the status code is what these tests assert on.
      }
    }
    return (status: response.statusCode, body: decoded);
  }

  group('maintenance mode', () {
    test('is off by default and reported in /ops/config', () async {
      final config = await call('GET', '/api/v1/ops/config');
      expect(config.status, equals(200));
      expect(config.body['maintenance_mode'], isFalse);
    });

    test('an unauthenticated caller cannot change it', () async {
      final res = await call(
        'POST',
        '/api/v1/ops/maintenance',
        body: {'enabled': true},
        token: '',
      );
      expect(res.status, anyOf(401, 403));
    });

    test('toggling persists and is reported back', () async {
      final on = await call(
        'POST',
        '/api/v1/ops/maintenance',
        body: {'enabled': true},
      );
      expect(on.status, equals(200));
      expect(on.body['maintenance_mode'], isTrue);

      final config = await call('GET', '/api/v1/ops/config');
      expect(config.body['maintenance_mode'], isTrue);

      final off = await call(
        'POST',
        '/api/v1/ops/maintenance',
        body: {'enabled': false},
      );
      expect(off.body['maintenance_mode'], isFalse);
    });

    test('a non-boolean body is rejected', () async {
      final res = await call(
        'POST',
        '/api/v1/ops/maintenance',
        body: {'enabled': 'yes'},
      );
      expect(res.status, equals(400));
    });

    test('rejects a user route with 503 while enabled', () async {
      await call(
        'POST',
        '/api/v1/ops/maintenance',
        body: {'enabled': true},
      );

      final blocked = await call('GET', '/api/v1/messages/sync');

      expect(
        blocked.status,
        equals(503),
        reason: 'maintenance mode is meant to stop the server doing work, so a '
            'client route must be refused rather than served',
      );
      expect(blocked.body['status'], equals('maintenance'));
    });

    test('the health probes keep answering while enabled', () async {
      await call(
        'POST',
        '/api/v1/ops/maintenance',
        body: {'enabled': true},
      );

      final live = await call('GET', '/api/v1/health/live', token: '');
      expect(live.status, equals(200));
    });

    test('the operator can turn it back off through /ops', () async {
      await call(
        'POST',
        '/api/v1/ops/maintenance',
        body: {'enabled': true},
      );
      // Client traffic is refused, so if the ops routes were not exempt this
      // call would be unreachable and the switch would be a one-way door.
      final off = await call(
        'POST',
        '/api/v1/ops/maintenance',
        body: {'enabled': false},
      );
      expect(off.status, equals(200));

      final blocked = await call('GET', '/api/v1/messages/sync');
      expect(blocked.status, isNot(equals(503)));
    });

    test('a restart does not silently reset it', () async {
      // The value lives in server_configuration, not in memory, so a process
      // that comes back up still refuses clients until told otherwise.
      await call(
        'POST',
        '/api/v1/ops/maintenance',
        body: {'enabled': true},
      );
      expect(server.db.getServerConfig('maintenance_mode'), equals('true'));
    });
  });

  group('admin password change', () {
    test('rejects a wrong current password', () async {
      final res = await call(
        'POST',
        '/api/v1/ops/admin-pin',
        body: {
          'current_password': 'not-the-password',
          'new_password': 'a-new-password',
        },
      );

      expect(res.status, equals(401));
      expect(
        server.db.getServerConfig('admin_password_hash'),
        isNull,
        reason: 'a rejected attempt must not have written anything',
      );
    });

    test('rejects a too-short new password', () async {
      final res = await call(
        'POST',
        '/api/v1/ops/admin-pin',
        body: {
          'current_password': 'first-admin-password',
          'new_password': 'abc',
        },
      );
      expect(res.status, equals(400));
    });

    test('rejects a missing field', () async {
      final res = await call(
        'POST',
        '/api/v1/ops/admin-pin',
        body: {'current_password': 'first-admin-password'},
      );
      expect(res.status, equals(400));
    });

    test('changes the stored hash and never echoes either value', () async {
      final before = server.db.getServerConfig('admin_password_hash');

      final res = await call(
        'POST',
        '/api/v1/ops/admin-pin',
        body: {
          'current_password': 'first-admin-password',
          'new_password': 'brand-new-password',
        },
      );

      expect(res.status, equals(200));
      final after = server.db.getServerConfig('admin_password_hash');
      expect(after, isNotNull);
      expect(after, isNot(before));
      expect(res.body.toString(), isNot(contains('brand-new-password')));
      expect(res.body.toString(), isNot(contains('first-admin-password')));
    });

    test('the old password stops working and the new one starts', () async {
      // A dedicated server with no `adminPasswordOverride`, because the
      // override short-circuits `_isValidAdminToken` before the stored hash is
      // ever consulted - which is exactly the code path under test.
      final rotatable = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_for_phase3_pin_rotation',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await rotatable.start('127.0.0.1', 0);
      addTearDown(rotatable.stop);
      final rotatablePort = rotatable.httpServer!.port;

      // Seed a stored password the way first-time setup does.
      rotatable.db.setServerConfig('admin_password_salt', 'seed-salt');
      rotatable.db.setServerConfig(
        'admin_password_hash',
        hashAdminPassword('original-password', 'seed-salt'),
      );

      final rotatableClient = HttpClient();
      addTearDown(() => rotatableClient.close(force: true));

      Future<int> post(String password, String next) async {
        final req = await rotatableClient.postUrl(
          Uri.parse(
            'http://127.0.0.1:$rotatablePort/api/v1/ops/admin-pin',
          ),
        );
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $password');
        req.write(
          jsonEncode({
            'current_password': password,
            'new_password': next,
          }),
        );
        final response = await req.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await post('original-password', 'brand-new-password'), equals(200));
      expect(
        await post('original-password', 'another-one'),
        equals(401),
        reason: 'the rotated-away password must no longer be accepted',
      );
      expect(await post('brand-new-password', 'a-third-one'), equals(200));
    });
  });

  group('data purge', () {
    test('requires admin', () async {
      final res = await call('POST', '/api/v1/ops/purge', token: '');
      expect(res.status, anyOf(401, 403));
    });

    test('reports zero when nothing is past the retention window', () async {
      final res = await call('POST', '/api/v1/ops/purge');

      expect(res.status, equals(200));
      expect(res.body['total'], equals(0));
      expect(res.body['removed'], isA<Map<String, dynamic>>());
    });

    test('removes an old dead-letter outbox row and counts it', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      server.db.rawUpdate(
        "INSERT INTO outbox (event_id, type, payload, created_at, status) "
        "VALUES ('old_dlq', 'group_create', '{}', ?, 'DLQ');",
        [now - 40 * 24 * 60 * 60 * 1000],
      );

      final res = await call('POST', '/api/v1/ops/purge');

      expect(res.body['total'], equals(1));
      final removed = res.body['removed'] as Map<String, dynamic>;
      expect(removed['outbox_dead_letter'], equals(1));
    });

    test('leaves a recent row alone', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      server.db.rawUpdate(
        "INSERT INTO outbox (event_id, type, payload, created_at, status) "
        "VALUES ('recent_dlq', 'group_create', '{}', ?, 'DLQ');",
        [now],
      );

      final res = await call('POST', '/api/v1/ops/purge');

      expect(res.body['total'], equals(0));
    });

    test('never touches accounts or messages', () async {
      server.db.createAccount(
        'phase3_survivor',
        'phase3_survivor_user',
        'survivor_key',
      );
      await call('POST', '/api/v1/ops/purge');

      expect(
        server.db.getAccount('phase3_survivor'),
        isNotNull,
        reason: 'a maintenance purge must not be able to delete an account',
      );
    });
  });

  group('support bundle', () {
    test('requires admin', () async {
      final res = await call(
        'GET',
        '/api/v1/ops/support-diagnostic',
        token: '',
      );
      expect(res.status, anyOf(401, 403));
    });

    test('returns the redacted bundle with an explicit redaction policy', () async {
      final res = await call('GET', '/api/v1/ops/support-diagnostic');

      expect(res.status, equals(200));
      expect(res.body['generated_at'], isA<String>());
      final redaction = res.body['redaction'] as Map<String, dynamic>;
      expect(redaction['turn_secret'], equals('excluded'));
      expect(redaction['tokens'], equals('excluded'));
      expect(res.body['readiness'], isA<Map<String, dynamic>>());
    });
  });
}
