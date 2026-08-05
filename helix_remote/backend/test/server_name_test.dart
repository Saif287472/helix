import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:helix_remote_backend/src/server_name.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('validateServerName', () {
    String? valueOf(ServerNameResult result) =>
        result is ServerNameValid ? result.value : null;

    test('accepts an ordinary name unchanged', () {
      expect(
        valueOf(validateServerName("Rahman Family Server")),
        "Rahman Family Server",
      );
    });

    test('trims surrounding whitespace and collapses internal runs', () {
      // Padding is how you'd try to shove a name around in someone else's
      // layout, so it is normalized rather than stored verbatim.
      expect(
        valueOf(validateServerName('   Home    Server   ')),
        'Home Server',
      );
    });

    test('treats an empty or whitespace-only name as clearing it', () {
      expect(validateServerName(''), isA<ServerNameCleared>());
      expect(validateServerName('    '), isA<ServerNameCleared>());
      expect(validateServerName('\t\n'), isA<ServerNameCleared>());
    });

    test('rejects a null name outright', () {
      expect(validateServerName(null), isA<ServerNameInvalid>());
    });

    test('rejects control characters rather than silently stripping them', () {
      // Written as escapes: these characters are invisible in source, and
      // the analyzer rightly objects to smuggling them in literally.
      expect(validateServerName('Home\u0000Server'), isA<ServerNameInvalid>());
      // Whitespace control characters are normalized to a space instead,
      // so a name pasted out of a text editor still works.
      expect(valueOf(validateServerName('Home\nServer')), 'Home Server');
      expect(valueOf(validateServerName('Home\tServer')), 'Home Server');
      expect(validateServerName('Home\u0007Server'), isA<ServerNameInvalid>());
      expect(validateServerName('Home\u009bServer'), isA<ServerNameInvalid>());
    });

    test('rejects bidirectional override characters', () {
      // These make rendered text read differently from what is stored,
      // which matters for a string shown in everyone else's app.
      expect(validateServerName('Home\u202eServer'), isA<ServerNameInvalid>());
      expect(validateServerName('\u2066Home'), isA<ServerNameInvalid>());
      expect(validateServerName('Home\u200fServer'), isA<ServerNameInvalid>());
    });

    test('enforces the length limit', () {
      expect(
        validateServerName('a' * maxServerNameLength),
        isA<ServerNameValid>(),
      );
      expect(
        validateServerName('a' * (maxServerNameLength + 1)),
        isA<ServerNameInvalid>(),
      );
    });

    test('measures length in runes, not code units', () {
      // 30 family emoji are 30 visible characters but many more UTF-16
      // code units; counting the latter would reject a legal name.
      expect(validateServerName('👨‍👩‍👧' * 8), isA<ServerNameValid>());
    });

    test('keeps non-Latin names intact', () {
      expect(valueOf(validateServerName('রহমান পরিবার')), 'রহমান পরিবার');
    });
  });

  group('server name over HTTP', () {
    late BackendServer server;
    late HttpClient httpClient;
    late int port;
    late ServerIdentity identity;
    late String userToken;

    setUp(() async {
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_min_32_bytes_server_name',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
        publicBaseUrl: 'https://hr.example.com',
      );
      identity = await ServerIdentity.loadOrCreate(server.db);
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;
      httpClient = HttpClient();

      server.db.createAccount('alice', 'alice_user', 'alice_key');
      server.db.registerDevice('alice_dev', 'alice', 'alice_dev_key', 'Phone');
      userToken = server.jwt.generateToken({
        'account_id': 'alice',
        'device_id': 'alice_dev',
      }, const Duration(hours: 1));
    });

    tearDown(() async {
      httpClient.close(force: true);
      await server.stop();
    });

    Future<({int status, Map<String, dynamic> json})> send(
      String method,
      String path, {
      String? token,
      Object? body,
    }) async {
      final uri = Uri.parse('http://127.0.0.1:$port$path');
      final request = method == 'GET'
          ? await httpClient.getUrl(uri)
          : await httpClient.postUrl(uri);
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      if (body != null) {
        request.headers.set('Content-Type', 'application/json');
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return (
        status: response.statusCode,
        json: text.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(text) as Map<String, dynamic>,
      );
    }

    Future<({int status, Map<String, dynamic> json})> setName(String? name) =>
        send(
          'POST',
          '/api/v1/ops/config/server-name',
          token: identity.adminToken,
          body: {'server_name': name},
        );

    test('an admin can set the name and read it back from config', () async {
      final set = await setName('Rahman Family Server');
      expect(set.status, 200);
      expect(set.json['server_name'], 'Rahman Family Server');

      final config = await send(
        'GET',
        '/api/v1/ops/config',
        token: identity.adminToken,
      );
      expect(config.json['server_name'], 'Rahman Family Server');
      expect(config.json['max_server_name_length'], maxServerNameLength);
    });

    test('config reports an empty name before the admin sets one', () async {
      final config = await send(
        'GET',
        '/api/v1/ops/config',
        token: identity.adminToken,
      );
      expect(config.json['server_name'], '');
    });

    test('clearing the name removes it', () async {
      await setName('Temporary Name');
      final cleared = await setName('   ');
      expect(cleared.status, 200);
      expect(cleared.json['server_name'], '');

      final config = await send(
        'GET',
        '/api/v1/ops/config',
        token: identity.adminToken,
      );
      expect(config.json['server_name'], '');
    });

    test('an over-long or malformed name is rejected with a reason', () async {
      final long = await setName('a' * (maxServerNameLength + 1));
      expect(long.status, 400);
      expect(long.json['error'], contains('characters'));

      final control = await setName('Bad\u0007Name');
      expect(control.status, 400);
    });

    test('a non-string server_name is rejected, not coerced', () async {
      final result = await send(
        'POST',
        '/api/v1/ops/config/server-name',
        token: identity.adminToken,
        body: {'server_name': 42},
      );
      expect(result.status, 400);
    });

    test('a malformed body is rejected without a 500', () async {
      final uri = Uri.parse(
        'http://127.0.0.1:$port/api/v1/ops/config/server-name',
      );
      final request = await httpClient.postUrl(uri);
      request.headers.set('Authorization', 'Bearer ${identity.adminToken}');
      request.headers.set('Content-Type', 'application/json');
      request.write('this is not json');
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, 400);
    });

    test('only an admin may set the name', () async {
      final asUser = await send(
        'POST',
        '/api/v1/ops/config/server-name',
        token: userToken,
        body: {'server_name': 'Hijacked'},
      );
      expect(asUser.status, 403);

      final anonymous = await send(
        'POST',
        '/api/v1/ops/config/server-name',
        body: {'server_name': 'Hijacked'},
      );
      expect(anonymous.status, anyOf(401, 403));
    });

    test('a signed-in user can read the name', () async {
      await setName('Rahman Family Server');

      final info = await send('GET', '/api/v1/server/info', token: userToken);
      expect(info.status, 200);
      expect(info.json['server_name'], 'Rahman Family Server');
    });

    test('server info requires a session', () async {
      final anonymous = await send('GET', '/api/v1/server/info');
      expect(anonymous.status, anyOf(401, 403));
    });

    test('a name change is visible immediately, with no restart', () async {
      await setName('First Name');
      expect(
        (await send(
          'GET',
          '/api/v1/server/info',
          token: userToken,
        )).json['server_name'],
        'First Name',
      );

      await setName('Second Name');
      expect(
        (await send(
          'GET',
          '/api/v1/server/info',
          token: userToken,
        )).json['server_name'],
        'Second Name',
      );
    });

    test('invite lookup names the server for someone still joining', () async {
      await setName('Rahman Family Server');
      final created = await send(
        'POST',
        '/api/v1/ops/invites',
        token: identity.adminToken,
      );
      final code = created.json['invite_code'] as String;

      // Deliberately unauthenticated: this is the pre-registration path.
      final lookup = await send(
        'GET',
        '/api/v1/accounts/invite/lookup?invite_code=$code',
      );

      expect(lookup.json['valid'], isTrue);
      expect(lookup.json['server_name'], 'Rahman Family Server');
    });

    test('invite lookup returns an empty name when none is set', () async {
      final created = await send(
        'POST',
        '/api/v1/ops/invites',
        token: identity.adminToken,
      );
      final code = created.json['invite_code'] as String;

      final lookup = await send(
        'GET',
        '/api/v1/accounts/invite/lookup?invite_code=$code',
      );

      expect(lookup.json['valid'], isTrue);
      expect(lookup.json['server_name'], '');
    });

    test('setting the name is recorded in the audit log', () async {
      await setName('Audited Name');
      await setName('');

      final actions = server.db
          .getAuditLogs()
          .map((entry) => entry['action'])
          .toList();
      expect(actions, contains('ADMIN_SERVER_NAME_SET'));
      expect(actions, contains('ADMIN_SERVER_NAME_CLEARED'));
    });
  });
}
