import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

void main() {
  late BackendServer server;
  late HttpClient client;
  late int port;

  Future<HttpClientResponse> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    return request.close();
  }

  Future<HttpClientResponse> getJson(String path) async {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    return request.close();
  }

  Future<Map<String, dynamic>> readJson(HttpClientResponse response) async {
    return jsonDecode(await response.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registrationBodyFor({
    required String accountId,
    required String phoneHash,
    required String deviceId,
    String? tosVersion,
    String? otpChallengeId,
    bool includeAcceptance = true,
    bool includeInvite = true,
  }) async {
    final material = await createTestRegistrationMaterial(
      accountId: accountId,
      username: phoneHash,
      deviceId: deviceId,
      deviceName: 'Global Test Phone',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    server.db.createOtpChallenge(
      challengeId: 'otp_$accountId',
      phoneHash: phoneHash,
      codeHash: sha256.convert(utf8.encode('123456')).toString(),
      purpose: 'REGISTRATION',
      createdAt: now,
      expiresAt: now + const Duration(minutes: 10).inMilliseconds,
    );
    final body = registrationBody(
      accountId: accountId,
      username: phoneHash,
      deviceId: deviceId,
      deviceName: 'Global Test Phone',
      material: material,
      otpCode: '123456',
      inviteCode: includeInvite ? seedTestInvite(server.db) : '',
    );
    if (!includeInvite) {
      body.remove('invite_code');
    }
    if (otpChallengeId != null && otpChallengeId.isNotEmpty) {
      body['otp_challenge_id'] = otpChallengeId;
    }
    if (includeAcceptance) {
      body['tos_accepted'] = true;
      body['tos_version'] = tosVersion ?? HelixLegalDocuments.termsVersion;
    }
    return body;
  }

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'global_terms_test_secret_at_least_32_bytes',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      globalInstanceMode: true,
      publicBaseUrl: 'https://global.example',
    );
    client = HttpClient();
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test(
    'Global registration requires acceptance and stores the version',
    () async {
      final missing = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'missing_terms',
          phoneHash: 'missing_terms_phone',
          deviceId: 'missing_terms_device',
          includeAcceptance: false,
        ),
      );
      expect(missing.statusCode, 400);
      final missingBody = await readJson(missing);
      expect(missingBody['code'], RemoteErrorCode.termsAcceptanceRequired.wire);

      final accepted = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'accepted_terms',
          phoneHash: 'accepted_terms_phone',
          deviceId: 'accepted_terms_device',
        ),
      );
      expect(
        accepted.statusCode,
        200,
        reason: await accepted.transform(utf8.decoder).join(),
      );
      expect(server.db.schemaVersion, 43);
      final account = server.db.getAccount('accepted_terms');
      expect(account, isNotNull);
      expect(account!['tos_accepted_at'], isA<int>());
      expect(account['tos_version'], HelixLegalDocuments.termsVersion);
    },
  );

  test('Global OTP verification is public and challenge-bound', () async {
    final phoneHash = 'otp_verify_phone';
    final challengeId = 'otp_verify_challenge';
    final now = DateTime.now().millisecondsSinceEpoch;
    server.db.createOtpChallenge(
      challengeId: challengeId,
      phoneHash: phoneHash,
      codeHash: sha256.convert(utf8.encode('123456')).toString(),
      purpose: 'REGISTRATION',
      createdAt: now,
      expiresAt: now + const Duration(minutes: 10).inMilliseconds,
    );

    final valid = await postJson('/api/v1/accounts/phone/otp/verify', {
      'phone_hash': phoneHash,
      'otp_code': '123456',
      'challenge_id': challengeId,
    });
    expect(valid.statusCode, 200);
    final validBody = await readJson(valid);
    expect(validBody['valid'], isTrue);
    expect(validBody['challenge_id'], challengeId);

    final wrong = await postJson('/api/v1/accounts/phone/otp/verify', {
      'phone_hash': phoneHash,
      'otp_code': '000000',
      'challenge_id': challengeId,
    });
    expect(wrong.statusCode, 400);
    final wrongBody = await readJson(wrong);
    expect(wrongBody['code'], RemoteErrorCode.invalidOtp.wire);

    final registration = await postJson(
      '/api/v1/accounts/register',
      await registrationBodyFor(
        accountId: 'otp_bound_account',
        phoneHash: phoneHash,
        deviceId: 'otp_bound_device',
        otpChallengeId: challengeId,
      ),
    );
    expect(registration.statusCode, 200);
  });

  test(
    'Global registration rejects an outdated legal-document version',
    () async {
      final response = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'old_terms',
          phoneHash: 'old_terms_phone',
          deviceId: 'old_terms_device',
          tosVersion: '1900-01-01',
        ),
      );
      expect(response.statusCode, 400);
      final body = await readJson(response);
      expect(body['code'], RemoteErrorCode.termsVersionOutdated.wire);
    },
  );

  test(
    'a phone number that already owns an account signs in on the new device',
    () async {
      final first = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'phone_owner',
          phoneHash: 'duplicate_phone_hash',
          deviceId: 'phone_owner_device',
        ),
      );
      expect(first.statusCode, 200);
      final firstBody = await readJson(first);
      expect(firstBody['existing_account'], isFalse);
      final originalIdentityKey =
          server.db.getAccount('phone_owner')!['identity_public_key'] as String;

      // Second registration for the SAME phone hash: instead of a 409 that
      // pushed the user into recovery, Global treats the verified OTP as a
      // phone-authenticated login and answers with the real account id.
      final second = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'phone_replica',
          phoneHash: 'duplicate_phone_hash',
          deviceId: 'phone_replica_device',
        ),
      );
      expect(second.statusCode, 200);
      final secondBody = await readJson(second);
      expect(secondBody['account_id'], 'phone_owner');
      expect(secondBody['existing_account'], isTrue);
      expect(secondBody['device_id'], 'phone_replica_device');

      // The account identity key rotated to the newly linked device and the
      // previously-registered device was revoked, exactly like recovery.
      final devices = server.db.getDevices('phone_owner');
      final active = devices.where((d) => d['status'] == 'ACTIVE').toList();
      expect(active.length, 1);
      expect(active.single['device_id'], 'phone_replica_device');
      expect(
        server.db.getAccount('phone_owner')!['identity_public_key'],
        isNot(originalIdentityKey),
      );
    },
  );

  test(
    'a wrong OTP never links a new device to an existing Global account',
    () async {
      final first = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'otp_owner',
          phoneHash: 'otp_guard_phone_hash',
          deviceId: 'otp_owner_device',
        ),
      );
      expect(first.statusCode, 200);

      final attacker = await registrationBodyFor(
        accountId: 'otp_attacker',
        phoneHash: 'otp_guard_phone_hash',
        deviceId: 'otp_attacker_device',
      );
      attacker['otp_code'] = '000000';

      final response = await postJson('/api/v1/accounts/register', attacker);
      expect(response.statusCode, 403);
      final body = await readJson(response);
      expect(body['code'], RemoteErrorCode.invalidOtp.wire);

      // Nothing was created and the original device is untouched.
      expect(server.db.getAccount('otp_attacker'), isNull);
      final active = server
          .db
          .getDevices('otp_owner')
          .where((d) => d['status'] == 'ACTIVE')
          .toList();
      expect(active.length, 1);
      expect(active.single['device_id'], 'otp_owner_device');
    },
  );

  test(
    'Global registration does not require or consume an invite code',
    () async {
      final response = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'no_invite_account',
          phoneHash: 'no_invite_phone_hash',
          deviceId: 'no_invite_device',
          includeInvite: false,
        ),
      );
      expect(response.statusCode, 200);
      final body = await readJson(response);
      expect(body['account_id'], 'no_invite_account');
    },
  );

  test(
    'a blocked phone number cannot sign in with a valid OTP',
    () async {
      final first = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'blocked_owner',
          phoneHash: 'blocked_phone_hash',
          deviceId: 'blocked_owner_device',
        ),
      );
      expect(first.statusCode, 200);

      server.db.blockPhoneHash('blocked_phone_hash');

      final response = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'blocked_attacker',
          phoneHash: 'blocked_phone_hash',
          deviceId: 'blocked_attacker_device',
        ),
      );
      expect(response.statusCode, 403);
      expect(server.db.getAccount('blocked_attacker'), isNull);
    },
  );

  test(
    'personal mode keeps registration compatible without ToS fields',
    () async {
      await server.stop();
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'personal_terms_test_secret_at_least_32_bytes',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;

      final response = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'personal_account',
          phoneHash: 'personal_phone_hash',
          deviceId: 'personal_device',
          includeAcceptance: false,
        ),
      );
      expect(response.statusCode, 200);
      final account = server.db.getAccount('personal_account');
      expect(account!['tos_accepted_at'], isNull);
      expect(account['tos_version'], isNull);
    },
  );

  test('migration 43 upgrades a version-42 account table', () {
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE accounts (
        account_id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        identity_public_key TEXT NOT NULL,
        phone_hash TEXT,
        phone_last4 TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL
      );
    ''');
    raw.execute('PRAGMA user_version = 42;');

    final migrated = BackendDatabase(raw);
    expect(migrated.schemaVersion, 43);
    migrated.createAccount(
      'legacy_account',
      'helix_legacy_account',
      'legacy_key',
      phoneHash: 'legacy_phone',
    );
    final account = migrated.getAccount('legacy_account');
    expect(account?['tos_accepted_at'], isNull);
    expect(account?['tos_version'], isNull);
    migrated.close();
  });

  test('legal documents are public and versioned', () async {
    final response = await getJson('/api/v1/server/tos');
    expect(response.statusCode, 200);
    final body = await readJson(response);
    expect(body['version'], HelixLegalDocuments.termsVersion);
    expect(body['terms'], contains('Helix Global Terms of Service'));
    expect(body['privacy_policy'], contains('Helix Global Privacy Policy'));
  });
}
