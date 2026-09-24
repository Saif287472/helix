import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/invite_codes.dart';
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
      jwtSecret: 'invites_test_secret_at_least_32_bytes',
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

  Future<String> requestOtp(String phoneHash) async {
    final response = await postJson('/api/v1/accounts/phone/otp/request', {
      'phone_hash': phoneHash,
    });
    expect(response.statusCode, equals(200));
    return (jsonDecode(response.body) as Map<String, dynamic>)['code']
        as String;
  }

  Future<_Response> registerWithInvite({
    required String accountId,
    required String phoneHash,
    required String inviteCode,
  }) async {
    final material = await createTestRegistrationMaterial(
      accountId: accountId,
      username: phoneHash,
      deviceId: '${accountId}_device',
      deviceName: 'Test Phone',
    );
    final otpCode = await requestOtp(phoneHash);
    return postJson(
      '/api/v1/accounts/register',
      registrationBody(
        accountId: accountId,
        username: phoneHash,
        deviceId: '${accountId}_device',
        deviceName: 'Test Phone',
        material: material,
        otpCode: otpCode,
        inviteCode: inviteCode,
      ),
    );
  }

  test('admin can issue an invite and it is redeemable exactly once', () async {
    final create = await postJson(
      '/api/v1/ops/invites',
      null,
      token: adminToken,
    );
    expect(create.statusCode, equals(200));
    final createBody = jsonDecode(create.body) as Map<String, dynamic>;
    final inviteCode = createBody['invite_code'] as String;
    expect(createBody['invite_id'], isNotEmpty);
    expect(createBody['shareable_url'], contains(inviteCode));

    // POST is the current form: it keeps the invite code - a bearer
    // credential - out of the reverse proxy's access log and out of the
    // client's own diagnostic log via RemoteRestException.uri.
    final lookup = await postJson('/api/v1/accounts/invite/lookup', {
      'invite_code': inviteCode,
    });
    expect(lookup.statusCode, equals(200));
    final lookupBody = jsonDecode(lookup.body) as Map<String, dynamic>;
    expect(lookupBody['valid'], isTrue);
    expect(lookupBody['issuer_type'], equals('ADMIN'));

    // The GET form still answers identically, so a client shipped before the
    // change keeps working until it is retired.
    final legacyLookup = await getJson(
      '/api/v1/accounts/invite/lookup?invite_code=$inviteCode',
    );
    expect(legacyLookup.statusCode, equals(200));
    expect(
      jsonDecode(legacyLookup.body) as Map<String, dynamic>,
      equals(lookupBody),
    );

    final register = await registerWithInvite(
      accountId: 'invite_user_1',
      phoneHash: 'invite_phone_1',
      inviteCode: inviteCode,
    );
    expect(register.statusCode, equals(200), reason: register.body);

    // Second account trying the same, now-redeemed invite must fail.
    final secondRegister = await registerWithInvite(
      accountId: 'invite_user_2',
      phoneHash: 'invite_phone_2',
      inviteCode: inviteCode,
    );
    expect(secondRegister.statusCode, equals(403));
    // Already REDEEMED, so this is caught by the same pre-check as an
    // unknown/expired code - the "already used" message only fires for the
    // much narrower race where two requests both pass that pre-check before
    // either one redeems (see redeemInviteCredential).
    expect(secondRegister.body, contains('Invalid or expired invite code'));

    final lookupAfter = await getJson(
      '/api/v1/accounts/invite/lookup?invite_code=$inviteCode',
    );
    final lookupAfterBody =
        jsonDecode(lookupAfter.body) as Map<String, dynamic>;
    expect(lookupAfterBody['valid'], isFalse);
  });

  test('registration is rejected without a valid invite code', () async {
    final missing = await registerWithInvite(
      accountId: 'no_invite_user',
      phoneHash: 'no_invite_phone',
      inviteCode: 'not_a_real_code',
    );
    expect(missing.statusCode, equals(403));
    expect(missing.body, contains('Invalid or expired invite code'));
  });

  test('invite expires after 7 days', () async {
    final create = await postJson(
      '/api/v1/ops/invites',
      null,
      token: adminToken,
    );
    final inviteCode =
        (jsonDecode(create.body) as Map<String, dynamic>)['invite_code']
            as String;

    now = now.add(const Duration(days: 7, minutes: 1));

    final lookup = await getJson(
      '/api/v1/accounts/invite/lookup?invite_code=$inviteCode',
    );
    expect((jsonDecode(lookup.body) as Map<String, dynamic>)['valid'], isFalse);

    final register = await registerWithInvite(
      accountId: 'expired_invite_user',
      phoneHash: 'expired_invite_phone',
      inviteCode: inviteCode,
    );
    expect(register.statusCode, equals(403));
    expect(register.body, contains('Invalid or expired invite code'));
  });

  test('lookup reports invalid for an unknown invite code', () async {
    final lookup = await getJson(
      '/api/v1/accounts/invite/lookup?invite_code=totally_unknown',
    );
    expect(lookup.statusCode, equals(200));
    expect((jsonDecode(lookup.body) as Map<String, dynamic>)['valid'], isFalse);
  });

  test(
    'admin invites list shows PENDING, REDEEMED, and derived EXPIRED status',
    () async {
      final pendingCreate = await postJson(
        '/api/v1/ops/invites',
        null,
        token: adminToken,
      );

      final redeemedCreate = await postJson(
        '/api/v1/ops/invites',
        null,
        token: adminToken,
      );
      final redeemedCode =
          (jsonDecode(redeemedCreate.body)
                  as Map<String, dynamic>)['invite_code']
              as String;
      await registerWithInvite(
        accountId: 'redeemed_user',
        phoneHash: 'redeemed_phone',
        inviteCode: redeemedCode,
      );

      final expiredCreate = await postJson(
        '/api/v1/ops/invites',
        null,
        token: adminToken,
      );
      now = now.add(const Duration(days: 8));

      final list = await getJson(
        '/api/v1/ops/invites?limit=50&offset=0',
        token: adminToken,
      );
      expect(list.statusCode, equals(200));
      final invites =
          (jsonDecode(list.body) as Map<String, dynamic>)['invites'] as List;
      final byId = {
        for (final invite in invites.cast<Map<String, dynamic>>())
          invite['invite_id'] as String: invite,
      };

      final pendingId =
          (jsonDecode(pendingCreate.body) as Map<String, dynamic>)['invite_id']
              as String;
      final redeemedId =
          (jsonDecode(redeemedCreate.body) as Map<String, dynamic>)['invite_id']
              as String;
      final expiredId =
          (jsonDecode(expiredCreate.body) as Map<String, dynamic>)['invite_id']
              as String;

      expect(byId[pendingId]!['status'], equals('EXPIRED'));
      expect(byId[redeemedId]!['status'], equals('REDEEMED'));
      expect(
        byId[redeemedId]!['redeemed_by_account_id'],
        equals('redeemed_user'),
      );
      expect(byId[expiredId]!['status'], equals('EXPIRED'));

      // Never expose the code hash to the admin client.
      expect(jsonEncode(invites), isNot(contains('invite_code_hash')));
    },
  );

  test('non-admin cannot issue or list invites', () async {
    final create = await postJson(
      '/api/v1/ops/invites',
      null,
      token: 'not_a_real_admin_token',
    );
    expect(create.statusCode, equals(401));

    final list = await getJson(
      '/api/v1/ops/invites',
      token: 'not_a_real_admin_token',
    );
    expect(list.statusCode, equals(401));
  });

  group('Global auto-issue', () {
    test('is rejected when this server is not Helix Global', () async {
      final autoIssue = await postJson(
        '/api/v1/accounts/invite/auto-issue',
        null,
      );
      expect(autoIssue.statusCode, equals(403));
      expect(autoIssue.body, contains('not enabled'));
    });

    test(
      'issues a real, redeemable invite when this server is Helix Global',
      () async {
        final globalServer = BackendServer.create(
          sqliteDb: sqlite3.openInMemory(),
          jwtSecret: 'invites_test_global_secret_at_least_32_bytes',
          rateLimitMaxTokens: 1000,
          rateLimitRefillRate: 1000,
          globalInstanceMode: true,
          publicBaseUrl: 'https://global.helix.example',
        );
        await globalServer.start('127.0.0.1', 0);
        final globalPort = globalServer.httpServer!.port;
        final globalClient = HttpClient();
        try {
          final autoIssueRequest = await globalClient.post(
            '127.0.0.1',
            globalPort,
            '/api/v1/accounts/invite/auto-issue',
          );
          final autoIssueResponse = await autoIssueRequest.close();
          final autoIssueBody =
              jsonDecode(await autoIssueResponse.transform(utf8.decoder).join())
                  as Map<String, dynamic>;
          expect(autoIssueResponse.statusCode, equals(200));
          final code = autoIssueBody['invite_code'] as String;
          expect(code, isNotEmpty);

          final invite = globalServer.db.getInviteByCodeHash(
            hashInviteCode(code),
          );
          expect(invite, isNotNull);
          expect(invite!['issuer_type'], equals('SYSTEM_GLOBAL'));
          expect(
            invite['server_address'],
            equals('https://global.helix.example'),
          );
        } finally {
          globalClient.close(force: true);
          await globalServer.stop();
        }
      },
    );

    test('is rate-limited per IP', () async {
      final globalServer = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'invites_test_global_ratelimit_secret_32b',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
        globalInstanceMode: true,
      );
      await globalServer.start('127.0.0.1', 0);
      final globalPort = globalServer.httpServer!.port;
      final globalClient = HttpClient();
      try {
        Future<int> autoIssue() async {
          final request = await globalClient.post(
            '127.0.0.1',
            globalPort,
            '/api/v1/accounts/invite/auto-issue',
          );
          final response = await request.close();
          await response.drain<void>();
          return response.statusCode;
        }

        expect(await autoIssue(), equals(200));
        expect(await autoIssue(), equals(200));
        expect(await autoIssue(), equals(200));
        expect(await autoIssue(), equals(429));
      } finally {
        globalClient.close(force: true);
        await globalServer.stop();
      }
    });

    test('invite lookup is rate-limited per IP (429 Too Many Requests)', () async {
      var rateLimited = false;
      for (var i = 0; i < 70; i++) {
        final res = await getJson(
          '/api/v1/accounts/invite/lookup?invite_code=ratelimit_test',
        );
        if (res.statusCode == 429) {
          rateLimited = true;
          break;
        }
      }
      expect(rateLimited, isTrue);
    });
  });
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
