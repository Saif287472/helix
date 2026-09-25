// Display name change rate limiting - once every 30 days, but only
// counted from the user's own explicit change (POST /accounts/profile),
// never from whatever name registration set (including the phone-number
// default from skipping the display-name step).

import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

void main() {
  late BackendServer server;
  late HttpClient client;
  late int port;
  const adminToken = 'admin_test_password';
  var now = DateTime.utc(2026, 6, 20, 0, 0);

  setUp(() async {
    now = DateTime.utc(2026, 6, 20, 0, 0);
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'profile_display_name_test_secret_at_least_32_bytes',
      adminPasswordOverride: adminToken,
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      now: () => now,
    );
    await ServerIdentity.loadOrCreate(server.db);
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<_Response> getJson(String path, {String? token}) async {
    final request = await client.get('127.0.0.1', port, path);
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    final response = await request.close();
    return _Response(
      response.statusCode,
      await response.transform(utf8.decoder).join(),
    );
  }

  Future<_Response> postJson(
    String path,
    Map<String, dynamic>? body, {
    String? token,
  }) async {
    final request = await client.post('127.0.0.1', port, path);
    request.headers.contentType = ContentType.json;
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    return _Response(
      response.statusCode,
      await response.transform(utf8.decoder).join(),
    );
  }

  String requestOtp(String phoneHash) =>
      requestTestOtp(db: server.db, phoneHash: phoneHash);

  /// Registers a fresh account and returns its access token, so tests can
  /// call the authenticated profile endpoint.
  Future<String> registerAndLogin({
    required String accountId,
    required String phoneHash,
    String? displayName,
  }) async {
    final material = await createTestRegistrationMaterial(
      accountId: accountId,
      username: phoneHash,
      deviceId: '${accountId}_device',
      deviceName: 'Test Phone',
    );
    final inviteCreate = await postJson(
      '/api/v1/ops/invites',
      null,
      token: adminToken,
    );
    final inviteCode =
        (jsonDecode(inviteCreate.body) as Map<String, dynamic>)['invite_code']
            as String;
    final otpCode = requestOtp(phoneHash);
    final register = await postJson(
      '/api/v1/accounts/register',
      registrationBody(
        accountId: accountId,
        username: phoneHash,
        deviceId: '${accountId}_device',
        deviceName: 'Test Phone',
        material: material,
        otpCode: otpCode,
        inviteCode: inviteCode,
        displayName: displayName,
      ),
    );
    expect(register.statusCode, equals(200), reason: register.body);

    final login = await loginTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      accountId: accountId,
      deviceId: '${accountId}_device',
      deviceSigningKeyPair: material.deviceSigningKeyPair,
    );
    return login['token'] as String;
  }

  test('the first explicit display name change is always allowed, even right '
      'after registering', () async {
    final token = await registerAndLogin(
      accountId: 'first_change_user',
      phoneHash: 'first_change_phone',
    );

    final update = await postJson('/api/v1/accounts/profile', {
      'display_name': 'Chosen Name',
    }, token: token);
    expect(update.statusCode, equals(200), reason: update.body);
    final profile =
        (jsonDecode(update.body) as Map<String, dynamic>)['profile']
            as Map<String, dynamic>;
    expect(profile['display_name'], equals('Chosen Name'));
    expect(profile['display_name_changed_at'], isNotNull);
  });

  test('skipping the display name at registration does not start the cooldown '
      '- the first real change afterward is still unrestricted', () async {
    final token = await registerAndLogin(
      accountId: 'skip_then_set_user',
      phoneHash: 'skip_then_set_phone',
      // Mirrors what the client sends when the user taps Skip: the
      // phone number itself, not a real chosen name.
      displayName: 'skip_then_set_phone',
    );

    // Advance time by only a day - if skipping counted as a change,
    // this would still be inside the 30-day cooldown and get rejected.
    now = now.add(const Duration(days: 1));

    final update = await postJson('/api/v1/accounts/profile', {
      'display_name': 'Real Name Now',
    }, token: token);
    expect(update.statusCode, equals(200), reason: update.body);
  });

  test('a second change inside 30 days is rejected with a clear reason and '
      'next_allowed_at', () async {
    final token = await registerAndLogin(
      accountId: 'second_change_user',
      phoneHash: 'second_change_phone',
    );

    final first = await postJson('/api/v1/accounts/profile', {
      'display_name': 'First Name',
    }, token: token);
    expect(first.statusCode, equals(200));

    now = now.add(const Duration(days: 10));

    final second = await postJson('/api/v1/accounts/profile', {
      'display_name': 'Second Name',
    }, token: token);
    expect(second.statusCode, equals(429));
    final body = jsonDecode(second.body) as Map<String, dynamic>;
    expect(body['error'], contains('30 days'));
    expect(body['next_allowed_at'], isNotNull);

    // The rejected attempt must not have taken effect.
    final profile = await getJson('/api/v1/accounts/profile', token: token);
    expect(
      (jsonDecode(profile.body) as Map<String, dynamic>)['display_name'],
      equals('First Name'),
    );
  });

  test(
    'a change is allowed again once 30 days have passed since the last one',
    () async {
      final token = await registerAndLogin(
        accountId: 'cooldown_elapsed_user',
        phoneHash: 'cooldown_elapsed_phone',
      );

      final first = await postJson('/api/v1/accounts/profile', {
        'display_name': 'First Name',
      }, token: token);
      expect(first.statusCode, equals(200));

      now = now.add(const Duration(days: 30, minutes: 1));

      final second = await postJson('/api/v1/accounts/profile', {
        'display_name': 'Second Name',
      }, token: token);
      expect(second.statusCode, equals(200), reason: second.body);
      final profile =
          (jsonDecode(second.body) as Map<String, dynamic>)['profile']
              as Map<String, dynamic>;
      expect(profile['display_name'], equals('Second Name'));
    },
  );

  test('GET profile reports when the next change will be allowed', () async {
    final token = await registerAndLogin(
      accountId: 'next_allowed_user',
      phoneHash: 'next_allowed_phone',
    );

    final beforeAnyChange = await getJson(
      '/api/v1/accounts/profile',
      token: token,
    );
    expect(
      (jsonDecode(beforeAnyChange.body)
          as Map<String, dynamic>)['next_display_name_change_allowed_at'],
      isNull,
    );

    await postJson('/api/v1/accounts/profile', {
      'display_name': 'First Name',
    }, token: token);

    final afterChange = await getJson('/api/v1/accounts/profile', token: token);
    expect(
      (jsonDecode(afterChange.body)
          as Map<String, dynamic>)['next_display_name_change_allowed_at'],
      isNotNull,
    );
  });
}

class _Response {
  const _Response(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
