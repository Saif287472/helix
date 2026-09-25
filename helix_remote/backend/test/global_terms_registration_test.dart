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
    bool includeAcceptance = true,
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
      inviteCode: seedTestInvite(server.db),
    );
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
    'duplicate phone registration returns the recovery-specific code',
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

      final second = await postJson(
        '/api/v1/accounts/register',
        await registrationBodyFor(
          accountId: 'phone_replica',
          phoneHash: 'duplicate_phone_hash',
          deviceId: 'phone_replica_device',
        ),
      );
      expect(second.statusCode, 409);
      final body = await readJson(second);
      expect(body['code'], RemoteErrorCode.phoneAlreadyRegistered.wire);
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
