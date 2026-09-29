import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/helix_code.dart';
import 'package:helix_remote_backend/src/phone_hash.dart' as phone_hash_lib;
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

class _RecordingSmsProvider implements SmsProvider {
  final sent = <String>[];

  @override
  bool get isConfigured => true;

  @override
  String get displayName => 'Recording';

  @override
  Future<void> send({
    required String phoneNumber,
    required String message,
  }) async {
    sent.add(message);
  }
}

void main() {
  late BackendServer server;
  late HttpClient client;
  late int port;
  late _RecordingSmsProvider sms;
  const adminPassword = 'admin_recovery_lookup_secret';
  const accountId = 'user_carol';
  const phone = '+8801700000123';
  late String phoneHash;

  Future<(int, Map<String, dynamic>)> post(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port/api/v1$path'),
    );
    request.headers.contentType = ContentType.json;
    if (bearer != null) request.headers.set('Authorization', 'Bearer $bearer');
    request.write(jsonEncode(body));
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    return (
      response.statusCode,
      raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<({String accountId, String recoveryCode})> issueCode() async {
    final (status, body) = await post(
      '/ops/users/$accountId/recovery-code',
      {},
      bearer: adminPassword,
    );
    expect(status, 200);
    final decoded = decodeHelixRecoveryCode(body['opaque_code'] as String)!;
    return (accountId: decoded.accountId, recoveryCode: decoded.recoveryCode);
  }

  Map<String, dynamic> redeemBody(
    ({String accountId, String recoveryCode}) code, {
    String? otp,
    String? challengeId,
  }) => {
    'account_id': code.accountId,
    'recovery_code': code.recoveryCode,
    'phone_hash': phoneHash,
    'device_id': 'dev_new',
    'device_signing_public_key': 'new_signing',
    'device_agreement_public_key': 'new_agreement',
    'otp_code': ?otp,
    'otp_challenge_id': ?challengeId,
  };

  setUp(() async {
    sms = _RecordingSmsProvider();
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'recovery_lookup_test_secret_at_least_32_bytes',
      adminPasswordOverride: adminPassword,
      publicBaseUrl: 'https://personal.example',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      smsProvider: sms,
    );
    await ServerIdentity.loadOrCreate(server.db);
    client = HttpClient();
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;

    final saltRequest = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/v1/contacts/discovery-salt'),
    );
    final saltResponse = await saltRequest.close();
    final salt =
        (jsonDecode(await saltResponse.transform(utf8.decoder).join())
                as Map<String, dynamic>)['salt']
            as String;
    phoneHash = phone_hash_lib.phoneHash(salt, phone);
    server.db.createAccount(
      accountId,
      'carol',
      'old_identity',
      phoneHash: phoneHash,
      phoneLast4: '0123',
    );
    server.db.registerDevice(
      'dev_old',
      accountId,
      'old_signing',
      'old_agreement',
      'Old phone',
    );
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test('lookup checks the code and the number without using it', () async {
    final code = await issueCode();

    final (_, wrongCode) = await post('/accounts/recovery/lookup', {
      'account_id': accountId,
      'recovery_code': 'rec_not_it',
    });
    expect(wrongCode['valid'], isFalse);

    final (_, noPhone) = await post('/accounts/recovery/lookup', {
      'account_id': code.accountId,
      'recovery_code': code.recoveryCode,
    });
    expect(noPhone['valid'], isTrue);
    expect(noPhone['sms_required'], isTrue);
    expect(noPhone.containsKey('phone_matches'), isFalse);

    final (_, otherPhone) = await post('/accounts/recovery/lookup', {
      'account_id': code.accountId,
      'recovery_code': code.recoveryCode,
      'phone_hash': 'someone_else',
    });
    expect(otherPhone['phone_matches'], isFalse);

    final (_, samePhone) = await post('/accounts/recovery/lookup', {
      'account_id': code.accountId,
      'recovery_code': code.recoveryCode,
      'phone_hash': phoneHash,
    });
    expect(samePhone['phone_matches'], isTrue);

    // Looking it up never spends it.
    expect(server.db.getValidRecoveryCodeForAccount(accountId), isNotNull);
    expect(server.db.isDeviceActive(accountId, 'dev_old'), isTrue);
  });

  test('redeeming needs the matching number and the SMS code', () async {
    final code = await issueCode();

    final (noOtpStatus, _) = await post(
      '/accounts/recovery/redeem',
      redeemBody(code),
    );
    expect(noOtpStatus, 403);

    final (otherPhoneStatus, _) = await post('/accounts/recovery/redeem', {
      ...redeemBody(code, otp: '000000'),
      'phone_hash': 'someone_else',
    });
    expect(otherPhoneStatus, 403);

    final (otpStatus, otpBody) = await post('/accounts/phone/otp/request', {
      'phone_hash': phoneHash,
      'phone_number': phone,
    });
    expect(otpStatus, 200);
    final smsCode = RegExp(r'\d{6}').firstMatch(sms.sent.last)!.group(0)!;

    final (wrongOtpStatus, _) = await post(
      '/accounts/recovery/redeem',
      redeemBody(
        code,
        otp: smsCode == '000000' ? '111111' : '000000',
        challengeId: otpBody['challenge_id'] as String,
      ),
    );
    expect(wrongOtpStatus, 403);
    // A wrong SMS code does not burn the recovery code.
    expect(server.db.getValidRecoveryCodeForAccount(accountId), isNotNull);

    final (status, body) = await post(
      '/accounts/recovery/redeem',
      redeemBody(
        code,
        otp: smsCode,
        challengeId: otpBody['challenge_id'] as String,
      ),
    );
    expect(status, 200);
    expect(body['device_id'], 'dev_new');
    expect(body['refresh_token'], isNotEmpty);
    expect(server.db.isDeviceActive(accountId, 'dev_old'), isFalse);
    expect(server.db.isDeviceActive(accountId, 'dev_new'), isTrue);
    expect(server.db.getValidRecoveryCodeForAccount(accountId), isNull);
  });
}
