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

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'admin_users_test_secret_at_least_32_bytes',
      adminPasswordOverride: adminToken,
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
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

  /// Seeds a real, verifiable OTP challenge for [phoneHash] and returns the
  /// code. The delivery channel (BulkSMSBD) is not exercised here; only the
  /// authoritative OTP check in registration is.
  String requestOtp(String phoneHash) =>
      requestTestOtp(db: server.db, phoneHash: phoneHash);

  /// Registers a fresh account through the real HTTP flow (real invite,
  /// real OTP, real signed transcript) and returns its login key material
  /// so tests can also exercise login/refresh for that same account.
  Future<TestRegistrationMaterial> registerUser({
    required String accountId,
    required String phoneHash,
    String? phoneLast4,
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
        phoneLast4: phoneLast4,
        displayName: displayName,
      ),
    );
    expect(register.statusCode, equals(200), reason: register.body);
    return material;
  }

  Future<Map<String, dynamic>> login({
    required String accountId,
    required TestRegistrationMaterial material,
  }) => loginTestAccount(
    client: client,
    host: '127.0.0.1',
    port: port,
    accountId: accountId,
    deviceId: '${accountId}_device',
    deviceSigningKeyPair: material.deviceSigningKeyPair,
  );

  test(
    'admin users list surfaces phone_last4, display name, and invite used',
    () async {
      await registerUser(
        accountId: 'admin_view_user',
        phoneHash: 'admin_view_phone',
        phoneLast4: '4242',
        displayName: 'Ada Viewer',
      );

      final list = await getJson(
        '/api/v1/ops/users?limit=50&offset=0',
        token: adminToken,
      );
      expect(list.statusCode, equals(200));
      final users =
          (jsonDecode(list.body) as Map<String, dynamic>)['users'] as List;
      final user = users.cast<Map<String, dynamic>>().firstWhere(
        (u) => u['account_id'] == 'admin_view_user',
      );
      expect(user['phone_last4'], equals('4242'));
      expect(user['display_name'], equals('Ada Viewer'));
      expect(user['invite_id'], isNotEmpty);
      expect(user['status'], equals('ACTIVE'));
    },
  );

  test(
    'admin users list describes devices without push tokens or device keys',
    () async {
      await registerUser(
        accountId: 'device_view_user',
        phoneHash: 'device_view_phone',
      );

      final list = await getJson(
        '/api/v1/ops/users?limit=50&offset=0',
        token: adminToken,
      );
      final users =
          (jsonDecode(list.body) as Map<String, dynamic>)['users'] as List;
      final user = users.cast<Map<String, dynamic>>().firstWhere(
        (u) => u['account_id'] == 'device_view_user',
      );
      final device = (user['devices'] as List).single as Map<String, dynamic>;
      expect(device['device_id'], equals('device_view_user_device'));
      expect(device['status'], equals('ACTIVE'));
      expect(device['created_at'], isA<int>());
      expect(device['last_seen_at'], isA<int>());
      expect(device['push_enabled'], isFalse);
      expect(device.containsKey('push_token'), isFalse);
      expect(device.containsKey('device_signing_public_key'), isFalse);
      expect(device.containsKey('device_agreement_public_key'), isFalse);
    },
  );

  test('malformed phone_last4 is silently dropped, not rejected', () async {
    await registerUser(
      accountId: 'bad_last4_user',
      phoneHash: 'bad_last4_phone',
      phoneLast4: 'not-digits',
    );

    final list = await getJson(
      '/api/v1/ops/users?limit=50&offset=0',
      token: adminToken,
    );
    final users =
        (jsonDecode(list.body) as Map<String, dynamic>)['users'] as List;
    final user = users.cast<Map<String, dynamic>>().firstWhere(
      (u) => u['account_id'] == 'bad_last4_user',
    );
    expect(user['phone_last4'], equals(''));
  });

  test(
    'non-admin cannot list, suspend, unsuspend, delete, or block users',
    () async {
      await registerUser(
        accountId: 'protected_user',
        phoneHash: 'protected_ph',
      );

      const badToken = 'not_a_real_admin_token';
      expect(
        (await getJson('/api/v1/ops/users', token: badToken)).statusCode,
        equals(401),
      );
      expect(
        (await postJson(
          '/api/v1/ops/users/protected_user/suspend',
          null,
          token: badToken,
        )).statusCode,
        equals(401),
      );
      expect(
        (await postJson(
          '/api/v1/ops/users/protected_user/unsuspend',
          null,
          token: badToken,
        )).statusCode,
        equals(401),
      );
      expect(
        (await postJson(
          '/api/v1/ops/users/protected_user/delete',
          null,
          token: badToken,
        )).statusCode,
        equals(401),
      );
      expect(
        (await postJson(
          '/api/v1/ops/users/protected_user/block',
          null,
          token: badToken,
        )).statusCode,
        equals(401),
      );
    },
  );

  group('Suspend / unsuspend (temporary revoke)', () {
    test('a suspended user stays signed in but cannot act, and unsuspending '
        'lifts the limit', () async {
      final material = await registerUser(
        accountId: 'suspend_user',
        phoneHash: 'suspend_phone',
      );

      final loginBefore = await login(
        accountId: 'suspend_user',
        material: material,
      );
      final accessToken = loginBefore['token'] as String;
      final refreshToken = loginBefore['refresh_token'] as String;

      Future<(int, String?, String)> call(String method, String path) async {
        final request = await client.openUrl(
          method,
          Uri.parse('http://127.0.0.1:$port$path'),
        );
        request.headers.set('Authorization', 'Bearer $accessToken');
        request.headers.contentType = ContentType.json;
        if (method == 'POST') request.write('{}');
        final response = await request.close();
        return (
          response.statusCode,
          response.headers.value('x-helix-account-status'),
          await response.transform(utf8.decoder).join(),
        );
      }

      final (beforeStatus, beforeHeader, _) = await call(
        'GET',
        '/api/v1/accounts/devices',
      );
      expect(beforeStatus, equals(200));
      expect(beforeHeader, isNull);

      final suspend = await postJson(
        '/api/v1/ops/users/suspend_user/suspend',
        null,
        token: adminToken,
      );
      expect(suspend.statusCode, equals(200));
      expect(
        (jsonDecode(suspend.body) as Map<String, dynamic>)['status'],
        equals('SUSPENDED'),
      );

      // Reads still work, tagged so the app can show the notice at once.
      final (readStatus, readHeader, _) = await call(
        'GET',
        '/api/v1/accounts/devices',
      );
      expect(readStatus, equals(200));
      expect(readHeader, equals('suspended'));

      // Activity is refused with a code the app can explain.
      for (final path in [
        '/api/v1/messages/send',
        '/api/v1/contacts/requests',
        '/api/v1/calls/signal',
        '/api/v1/groups/create',
      ]) {
        final (status, header, body) = await call('POST', path);
        expect(status, equals(403), reason: path);
        expect(header, equals('suspended'), reason: path);
        expect(
          (jsonDecode(body) as Map<String, dynamic>)['code'],
          equals('account_suspended'),
          reason: path,
        );
      }

      // Signing in again and refreshing both still work - suspension no
      // longer throws the user back to onboarding.
      final loginWhileSuspended = await login(
        accountId: 'suspend_user',
        material: material,
      );
      expect(loginWhileSuspended['token'], isNotEmpty);
      final refresh = await postJson('/api/v1/accounts/refresh', {
        'refresh_token': refreshToken,
      });
      expect(refresh.statusCode, equals(200), reason: refresh.body);

      final unsuspend = await postJson(
        '/api/v1/ops/users/suspend_user/unsuspend',
        null,
        token: adminToken,
      );
      expect(unsuspend.statusCode, equals(200));
      expect(
        (jsonDecode(unsuspend.body) as Map<String, dynamic>)['status'],
        equals('ACTIVE'),
      );

      final (afterStatus, afterHeader, _) = await call(
        'GET',
        '/api/v1/accounts/devices',
      );
      expect(afterStatus, equals(200));
      expect(afterHeader, isNull);
    });

    test('suspending an unknown account returns 404', () async {
      final suspend = await postJson(
        '/api/v1/ops/users/does_not_exist/suspend',
        null,
        token: adminToken,
      );
      expect(suspend.statusCode, equals(404));
    });
  });

  group('Permanent delete', () {
    test(
      'deleting a user rejects their existing token and login attempts',
      () async {
        final material = await registerUser(
          accountId: 'delete_user',
          phoneHash: 'delete_phone',
        );
        final loginBefore = await login(
          accountId: 'delete_user',
          material: material,
        );
        final accessToken = loginBefore['token'] as String;

        final delete = await postJson(
          '/api/v1/ops/users/delete_user/delete',
          null,
          token: adminToken,
        );
        expect(delete.statusCode, equals(200));
        expect(
          (jsonDecode(delete.body) as Map<String, dynamic>)['deleted'],
          isTrue,
        );

        final afterDelete = await getJson(
          '/api/v1/accounts/devices',
          token: accessToken,
        );
        expect(afterDelete.statusCode, equals(401));

        final loginAttempt = await login(
          accountId: 'delete_user',
          material: material,
        );
        expect(loginAttempt.containsKey('token'), isFalse);

        final list = await getJson(
          '/api/v1/ops/users?limit=50&offset=0',
          token: adminToken,
        );
        final users =
            (jsonDecode(list.body) as Map<String, dynamic>)['users'] as List;
        expect(
          users.cast<Map<String, dynamic>>().where(
            (u) => u['account_id'] == 'delete_user',
          ),
          isEmpty,
        );
      },
    );

    test('deleting an unknown account returns 404', () async {
      final delete = await postJson(
        '/api/v1/ops/users/does_not_exist/delete',
        null,
        token: adminToken,
      );
      expect(delete.statusCode, equals(404));
    });
  });

  group('Permanent block', () {
    test('blocking a user rejects their token, deletes them, and refuses '
        'that phone number ever registering again', () async {
      final material = await registerUser(
        accountId: 'block_user',
        phoneHash: 'block_phone',
      );
      final loginBefore = await login(
        accountId: 'block_user',
        material: material,
      );
      final accessToken = loginBefore['token'] as String;

      final block = await postJson(
        '/api/v1/ops/users/block_user/block',
        null,
        token: adminToken,
      );
      expect(block.statusCode, equals(200));
      final blockBody = jsonDecode(block.body) as Map<String, dynamic>;
      expect(blockBody['blocked'], isTrue);
      expect(blockBody['deleted'], isTrue);

      // Gone immediately like a plain delete, but the still-installed app is
      // told the account was blocked rather than just "device inactive", so
      // it can explain instead of silently returning to onboarding.
      final afterBlock = await getJson(
        '/api/v1/accounts/devices',
        token: accessToken,
      );
      expect(afterBlock.statusCode, equals(403));
      expect(
        (jsonDecode(afterBlock.body) as Map<String, dynamic>)['code'],
        equals('account_blocked'),
      );
      final refreshAfterBlock = await postJson('/api/v1/accounts/refresh', {
        'refresh_token': loginBefore['refresh_token'],
      });
      expect(refreshAfterBlock.statusCode, equals(403));
      expect(
        (jsonDecode(refreshAfterBlock.body) as Map<String, dynamic>)['code'],
        equals('account_blocked'),
      );
      final list = await getJson(
        '/api/v1/ops/users?limit=50&offset=0',
        token: adminToken,
      );
      final users =
          (jsonDecode(list.body) as Map<String, dynamic>)['users'] as List;
      expect(
        users.cast<Map<String, dynamic>>().where(
          (u) => u['account_id'] == 'block_user',
        ),
        isEmpty,
      );

      // Unlike a plain delete, the phone number itself must stay refused
      // going forward - an OTP request for it is rejected outright...
      final otpRequest = await postJson('/api/v1/accounts/phone/otp/request', {
        'phone_hash': 'block_phone',
      });
      expect(otpRequest.statusCode, equals(403));
      final otpBody = jsonDecode(otpRequest.body) as Map<String, dynamic>;
      expect(otpBody['error'], contains('blocked'));
      expect(otpBody['code'], equals('phone_blocked'));

      // ...and so is a direct registration attempt for a brand-new
      // account using that same phone_hash, checked before OTP
      // correctness even matters.
      final newMaterial = await createTestRegistrationMaterial(
        accountId: 'block_user_2',
        username: 'block_phone',
        deviceId: 'block_user_2_device',
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
      final register = await postJson(
        '/api/v1/accounts/register',
        registrationBody(
          accountId: 'block_user_2',
          username: 'block_phone',
          deviceId: 'block_user_2_device',
          deviceName: 'Test Phone',
          material: newMaterial,
          otpCode: '000000',
          inviteCode: inviteCode,
        ),
      );
      expect(register.statusCode, equals(403));
      expect(
        (jsonDecode(register.body) as Map<String, dynamic>)['error'],
        contains('blocked'),
      );
    });

    test('blocking an unknown account returns 404', () async {
      final block = await postJson(
        '/api/v1/ops/users/does_not_exist/block',
        null,
        token: adminToken,
      );
      expect(block.statusCode, equals(404));
    });

    test('deleting (not blocking) a user still leaves their phone number free '
        'to register again', () async {
      await registerUser(
        accountId: 'delete_free_user',
        phoneHash: 'delete_free_phone',
      );

      final delete = await postJson(
        '/api/v1/ops/users/delete_free_user/delete',
        null,
        token: adminToken,
      );
      expect(delete.statusCode, equals(200));

      // registerUser's own 200 assertion is the check here: a second,
      // brand-new account can register the same phone number that a
      // deleted (but never blocked) account used to own.
      await registerUser(
        accountId: 'delete_free_user_2',
        phoneHash: 'delete_free_phone',
      );
    });
  });

  group('Invite cancellation', () {
    test('cancels a pending invite so it can no longer be redeemed', () async {
      final create = await postJson(
        '/api/v1/ops/invites',
        null,
        token: adminToken,
      );
      final createBody = jsonDecode(create.body) as Map<String, dynamic>;
      final inviteId = createBody['invite_id'] as String;
      final inviteCode = createBody['invite_code'] as String;

      final cancel = await postJson(
        '/api/v1/ops/invites/$inviteId/cancel',
        null,
        token: adminToken,
      );
      expect(cancel.statusCode, equals(200));
      expect(
        (jsonDecode(cancel.body) as Map<String, dynamic>)['status'],
        equals('CANCELLED'),
      );

      final lookup = await getJson(
        '/api/v1/accounts/invite/lookup?invite_code=$inviteCode',
      );
      expect(
        (jsonDecode(lookup.body) as Map<String, dynamic>)['valid'],
        isFalse,
      );

      final material = await createTestRegistrationMaterial(
        accountId: 'cancelled_invite_user',
        username: 'cancelled_invite_phone',
        deviceId: 'cancelled_invite_user_device',
        deviceName: 'Test Phone',
      );
      final otpCode = requestOtp('cancelled_invite_phone');
      final register = await postJson(
        '/api/v1/accounts/register',
        registrationBody(
          accountId: 'cancelled_invite_user',
          username: 'cancelled_invite_phone',
          deviceId: 'cancelled_invite_user_device',
          deviceName: 'Test Phone',
          material: material,
          otpCode: otpCode,
          inviteCode: inviteCode,
        ),
      );
      expect(register.statusCode, equals(403));

      final list = await getJson(
        '/api/v1/ops/invites?limit=50&offset=0',
        token: adminToken,
      );
      final invites =
          (jsonDecode(list.body) as Map<String, dynamic>)['invites'] as List;
      final invite = invites.cast<Map<String, dynamic>>().firstWhere(
        (i) => i['invite_id'] == inviteId,
      );
      expect(invite['status'], equals('CANCELLED'));
    });

    test('cannot cancel an invite that has already been redeemed', () async {
      final create = await postJson(
        '/api/v1/ops/invites',
        null,
        token: adminToken,
      );
      final createBody = jsonDecode(create.body) as Map<String, dynamic>;
      final inviteId = createBody['invite_id'] as String;

      final material = await createTestRegistrationMaterial(
        accountId: 'redeemer',
        username: 'redeemer_phone',
        deviceId: 'redeemer_device',
        deviceName: 'Test Phone',
      );
      final otpCode = requestOtp('redeemer_phone');
      final register = await postJson(
        '/api/v1/accounts/register',
        registrationBody(
          accountId: 'redeemer',
          username: 'redeemer_phone',
          deviceId: 'redeemer_device',
          deviceName: 'Test Phone',
          material: material,
          otpCode: otpCode,
          inviteCode: createBody['invite_code'] as String,
        ),
      );
      expect(register.statusCode, equals(200), reason: register.body);

      final cancel = await postJson(
        '/api/v1/ops/invites/$inviteId/cancel',
        null,
        token: adminToken,
      );
      expect(cancel.statusCode, equals(409));
    });

    test('cancelling an unknown invite returns 409', () async {
      final cancel = await postJson(
        '/api/v1/ops/invites/not_a_real_invite_id/cancel',
        null,
        token: adminToken,
      );
      expect(cancel.statusCode, equals(409));
    });

    test('non-admin cannot cancel invites', () async {
      final create = await postJson(
        '/api/v1/ops/invites',
        null,
        token: adminToken,
      );
      final inviteId =
          (jsonDecode(create.body) as Map<String, dynamic>)['invite_id']
              as String;
      final cancel = await postJson(
        '/api/v1/ops/invites/$inviteId/cancel',
        null,
        token: 'not_a_real_admin_token',
      );
      expect(cancel.statusCode, equals(401));
    });
  });
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
