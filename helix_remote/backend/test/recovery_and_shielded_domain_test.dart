import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/helix_code.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:helix_remote_backend/src/server_impl.dart';
import 'package:helix_remote_backend/src/server_name.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('Helix Code Encoding & Decoding', () {
    test('encodes and decodes invite code correctly', () {
      const serverUrl = 'https://my-private-server.example:8443';
      const inviteCode = 'inv_123456';
      final encoded = encodeHelixInviteCode(
        serverUrl: serverUrl,
        inviteCode: inviteCode,
      );

      expect(encoded.startsWith('HLX-INV-'), isTrue);
      expect(encoded.contains(serverUrl), isFalse); // raw URL is not visible

      final decoded = decodeHelixInviteCode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.serverUrl, equals(serverUrl));
      expect(decoded.inviteCode, equals(inviteCode));
    });

    test('decodes legacy invite URLs for backwards compatibility', () {
      const legacyUrl = 'https://domain.example.com/join?invite=legacy_code_999';
      final decoded = decodeHelixInviteCode(legacyUrl);
      expect(decoded, isNotNull);
      expect(decoded!.serverUrl, equals('https://domain.example.com'));
      expect(decoded.inviteCode, equals('legacy_code_999'));
    });

    test('encodes and decodes recovery code correctly', () {
      const serverUrl = 'http://127.0.0.1:8080';
      const accountId = 'user_alice_123';
      const recoveryCode = 'rec_sec_xyz789';
      final encoded = encodeHelixRecoveryCode(
        serverUrl: serverUrl,
        accountId: accountId,
        recoveryCode: recoveryCode,
      );

      expect(encoded.startsWith('HLX-REC-'), isTrue);
      expect(encoded.contains(serverUrl), isFalse);
      expect(isHelixRecoveryCode(encoded), isTrue);

      final decoded = decodeHelixRecoveryCode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.serverUrl, equals(serverUrl));
      expect(decoded.accountId, equals(accountId));
      expect(decoded.recoveryCode, equals(recoveryCode));
    });
  });

  group('Server Display Name & Domain Shielding', () {
    test('defaultServerName derives a consistent 4-digit Private Server name', () {
      const id1 = 'af79d5e6-d29a-44cf-b47d-631b0a34e912';
      final name1 = defaultServerName(id1);
      final name2 = defaultServerName(id1);
      expect(name1, equals(name2));
      expect(name1.startsWith('Private Server #'), isTrue);

      final code = name1.substring('Private Server #'.length);
      final numCode = int.parse(code);
      expect(numCode, inInclusiveRange(1000, 9999));
    });
  });

  group('Backend Recovery & Shielded Endpoints Integration', () {
    late BackendServer server;
    late HttpClient httpClient;
    late int port;
    const adminPassword = 'admin_recovery_test_secret';
    const serverUrl = 'https://test.helix.internal';

    setUp(() async {
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_min_32_bytes_recovery_test',
        adminPasswordOverride: adminPassword,
        publicBaseUrl: serverUrl,
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await ServerIdentity.loadOrCreate(server.db);
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;
      httpClient = HttpClient();
    });

    tearDown(() async {
      httpClient.close(force: true);
      await server.stop();
    });

    test('GET /server/info falls back to Private Server #XXXX without leaking host', () async {
      server.db.createAccount('u1', 'user1', 'pubkey');
      server.db.registerDevice('d1', 'u1', 'sign', 'agree', 'Phone');
      final userToken = server.jwt.generateToken({
        'account_id': 'u1',
        'device_id': 'd1',
      }, const Duration(hours: 1));

      final req = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/api/v1/server/info'));
      req.headers.set('Authorization', 'Bearer $userToken');
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;

      expect(res.statusCode, equals(200));
      expect(body['server_name'], startsWith('Private Server #'));
    });

    test('POST /api/v1/ops/invites returns shareable_code with HLX-INV- format', () async {
      final req = await httpClient.postUrl(Uri.parse('http://127.0.0.1:$port/api/v1/ops/invites'));
      req.headers.set('Authorization', 'Bearer $adminPassword');
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;

      expect(res.statusCode, equals(200));
      expect(body['shareable_code'], isNotNull);
      final shareableCode = body['shareable_code'] as String;
      expect(shareableCode.startsWith('HLX-INV-'), isTrue);

      final decoded = decodeHelixInviteCode(shareableCode);
      expect(decoded, isNotNull);
      expect(decoded!.inviteCode, equals(body['invite_code']));
      expect(decoded.serverUrl, equals(serverUrl));
    });

    test('Invite lookup omits server_address and reports Private Server name', () async {
      // 1. Create invite
      final createReq = await httpClient.postUrl(Uri.parse('http://127.0.0.1:$port/api/v1/ops/invites'));
      createReq.headers.set('Authorization', 'Bearer $adminPassword');
      final createRes = await createReq.close();
      final createBody = jsonDecode(await createRes.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final inviteCode = createBody['invite_code'] as String;

      // 2. Lookup invite
      final lookupReq = await httpClient.postUrl(Uri.parse('http://127.0.0.1:$port/api/v1/accounts/invite/lookup'));
      lookupReq.headers.set('Content-Type', 'application/json');
      lookupReq.write(jsonEncode({'invite_code': inviteCode}));
      final lookupRes = await lookupReq.close();
      final lookupBody = jsonDecode(await lookupRes.transform(utf8.decoder).join()) as Map<String, dynamic>;

      expect(lookupRes.statusCode, equals(200));
      expect(lookupBody['valid'], isTrue);
      expect(lookupBody['server_name'], startsWith('Private Server #'));
      expect(lookupBody.containsKey('server_address'), isFalse); // server_address is NOT leaked
    });

    test('Admin issues recovery code and user redeems it to restore account onto new device', () async {
      const accountId = 'user_bob';
      const phoneHash = 'phone_hash_bob_1234';
      const oldDeviceId = 'old_device_lost';
      const newDeviceId = 'new_device_replacement';

      // Seed account and old device
      server.db.createAccount(
        accountId,
        'bob_user',
        'initial_pub_key',
        phoneHash: phoneHash,
        phoneLast4: '1234',
      );
      server.db.registerDevice(
        oldDeviceId,
        accountId,
        'old_signing_key',
        'old_agreement_key',
        'Lost Phone',
      );
      expect(server.db.isDeviceActive(accountId, oldDeviceId), isTrue);

      // 1. Admin generates recovery code
      final adminReq = await httpClient.postUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/ops/users/$accountId/recovery-code'),
      );
      adminReq.headers.set('Authorization', 'Bearer $adminPassword');
      final adminRes = await adminReq.close();
      final adminBody = jsonDecode(await adminRes.transform(utf8.decoder).join()) as Map<String, dynamic>;

      expect(adminRes.statusCode, equals(200));
      final opaqueCode = adminBody['opaque_code'] as String;
      expect(opaqueCode.startsWith('HLX-REC-'), isTrue);

      final decoded = decodeHelixRecoveryCode(opaqueCode);
      expect(decoded, isNotNull);
      expect(decoded!.accountId, equals(accountId));
      expect(decoded.recoveryCode, equals(adminBody['recovery_code']));

      // 2. User redeems recovery code on new device
      final redeemReq = await httpClient.postUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/accounts/recovery/redeem'),
      );
      redeemReq.headers.set('Content-Type', 'application/json');
      redeemReq.write(
        jsonEncode({
          'account_id': decoded.accountId,
          'recovery_code': decoded.recoveryCode,
          'phone_hash': phoneHash,
          'device_id': newDeviceId,
          'device_signing_public_key': 'new_signing_key',
          'device_agreement_public_key': 'new_agreement_key',
          'device_name': 'New Replacement Phone',
        }),
      );
      final redeemRes = await redeemReq.close();
      final redeemBody = jsonDecode(await redeemRes.transform(utf8.decoder).join()) as Map<String, dynamic>;

      expect(redeemRes.statusCode, equals(200));
      expect(redeemBody['account_id'], equals(accountId));
      expect(redeemBody['device_id'], equals(newDeviceId));
      expect(redeemBody['access_token'], isNotEmpty);
      expect(redeemBody['refresh_token'], isNotEmpty);

      // 3. Verify old device was revoked and new device is active
      expect(server.db.isDeviceActive(accountId, oldDeviceId), isFalse);
      expect(server.db.isDeviceActive(accountId, newDeviceId), isTrue);

      // 4. Redeeming the same recovery code again fails (single-use)
      final reRedeemReq = await httpClient.postUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/accounts/recovery/redeem'),
      );
      reRedeemReq.headers.set('Content-Type', 'application/json');
      reRedeemReq.write(
        jsonEncode({
          'account_id': decoded.accountId,
          'recovery_code': decoded.recoveryCode,
          'phone_hash': phoneHash,
          'device_id': 'yet_another_device',
          'device_signing_public_key': 'k1',
          'device_agreement_public_key': 'k2',
        }),
      );
      final reRedeemRes = await reRedeemReq.close();
      expect(reRedeemRes.statusCode, equals(401));
    });
  });
}
