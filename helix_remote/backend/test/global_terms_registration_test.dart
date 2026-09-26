import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/phone_hash.dart' as phone_hash_lib;import 'package:helix_remote_backend/src/sms_provider.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

/// Accepts every SMS and keeps the last message, so tests can drive the real
/// `/accounts/phone/otp/request` path (including its phone-hash/salt check)
/// without a live BulkSMSBD gateway.
class _RecordingSmsProvider implements SmsProvider {
  final sent = <({String phoneNumber, String message})>[];

  @override
  bool get isConfigured => true;

  @override
  String get displayName => 'Recording';

  @override
  Future<void> send({
    required String phoneNumber,
    required String message,
  }) async {
    sent.add((phoneNumber: phoneNumber, message: message));
  }
}

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
      smsProvider: _RecordingSmsProvider(),
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
      expect(server.db.schemaVersion, 44);
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
    'a phone hash from a stale discovery salt is reported as such',
    () async {
      // The server self-provisions a salt on the first /discovery-salt call.
      final saltResponse = await getJson('/api/v1/contacts/discovery-salt');
      expect(saltResponse.statusCode, 200);
      final salt = (await readJson(saltResponse))['salt'] as String;
      expect(salt, isNotEmpty);

      final phoneNumber = '+8801784251020';
      final correctHash = phone_hash_lib.phoneHash(salt, phoneNumber);

      // A hash computed with a *different* salt (what a device that cached an
      // older salt sends) must come back as discovery_salt_stale, not a bare
      // 400, so the client knows to re-sync and retry.
      final stale = await postJson('/api/v1/accounts/phone/otp/request', {
        'phone_hash': phone_hash_lib.phoneHash(
          phone_hash_lib.generateDiscoverySalt(),
          phoneNumber,
        ),
        'phone_number': phoneNumber,
      });
      expect(stale.statusCode, 400);
      final staleBody = await readJson(stale);
      expect(staleBody['code'], RemoteErrorCode.discoverySaltStale.wire);

      // The freshly computed hash is accepted and the code is delivered.
      final fresh = await postJson('/api/v1/accounts/phone/otp/request', {
        'phone_hash': correctHash,
        'phone_number': phoneNumber,
      });
      expect(fresh.statusCode, 200);
      final freshBody = await readJson(fresh);
      expect(freshBody['challenge_id'], isNotEmpty);
      // The code itself is never echoed back to the caller.
      expect(freshBody.containsKey('code'), isFalse);
    },
  );

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

  test('migration 44 upgrades a version-43 account table', () {
    final raw = sqlite3.openInMemory();
    // Shaped like a real v43 database, i.e. one migration 43 has already run:
    // the tos columns are present. Migration 43 is guarded by `version < 43`,
    // so a synthetic v43 without them would skip straight past the columns the
    // application now writes.
    raw.execute('''
      CREATE TABLE accounts (
        account_id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        identity_public_key TEXT NOT NULL,
        phone_hash TEXT,
        phone_last4 TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        tos_accepted_at INTEGER,
        tos_version TEXT
      );
    ''');
    raw.execute('PRAGMA user_version = 43;');

    final migrated = BackendDatabase(raw);
    expect(migrated.schemaVersion, 44);
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

  test('migration 43 still applies on the way to 44', () {
    // 43 adds the ToS columns; 44 only drops the unused pairing table. A
    // database jumping from 42 must get both, so the earlier migration is not
    // shadowed by the newer one.
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
    expect(migrated.schemaVersion, 44);
    final columns = raw
        .select('PRAGMA table_info(accounts);')
        .map((row) => row['name'] as String)
        .toList();
    expect(columns, contains('tos_accepted_at'));
    expect(columns, contains('tos_version'));
    migrated.close();
  });

  test('migration 44 drops the unused admin_pairing_codes table', () {
    // The table and its repository shipped together but nothing ever called
    // them. Migration 44 removes the table so a fresh install does not carry
    // a table that looks like an active security control.
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE admin_pairing_codes (
        code_hash TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        redeemed_at INTEGER
      );
    ''');
    raw.execute(
      "INSERT INTO admin_pairing_codes VALUES ('abc', 1, 2, NULL);",
    );
    raw.execute('PRAGMA user_version = 43;');

    final migrated = BackendDatabase(raw);
    expect(migrated.schemaVersion, 44);

    final tables = raw
        .select("SELECT name FROM sqlite_master WHERE type = 'table';")
        .map((row) => row['name'] as String)
        .toList();
    expect(
      tables,
      isNot(contains('admin_pairing_codes')),
      reason: 'an unread, unwritten table is indistinguishable from a live '
          'security control',
    );
    migrated.close();
  });

  test('a fresh database has no admin_pairing_codes table at all', () {
    final raw = sqlite3.openInMemory();
    final migrated = BackendDatabase(raw);
    final tables = raw
        .select("SELECT name FROM sqlite_master WHERE type = 'table';")
        .map((row) => row['name'] as String)
        .where((name) => name.contains('admin_pairing'))
        .toList();
    expect(
      tables,
      isEmpty,
      reason: 'the table is dropped in migration 44, so even a database that '
          'ran the original CREATE TABLE must not end up with it',
    );
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
