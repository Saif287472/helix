import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/invite_codes.dart';

class TestRegistrationMaterial {
  const TestRegistrationMaterial({
    required this.deviceSigningKeyPair,
    required this.deviceAgreementKeyPair,
    required this.accountIdentityPublicKey,
    required this.deviceSigningPublicKey,
    required this.deviceAgreementPublicKey,
    required this.accountRegistrationSignature,
    required this.deviceRegistrationSignature,
  });

  final crypto.SimpleKeyPair deviceSigningKeyPair;
  final crypto.SimpleKeyPair deviceAgreementKeyPair;
  final String accountIdentityPublicKey;
  final String deviceSigningPublicKey;
  final String deviceAgreementPublicKey;
  final String accountRegistrationSignature;
  final String deviceRegistrationSignature;
}

String testBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Tests don't need real E.164 phone numbers or a real discovery-salt
/// round trip — the server treats phone_hash as an opaque unique string.
/// Reusing each test's existing account-scoped `username` value here keeps
/// every call site below unchanged while still giving each test account a
/// distinct, stable phone_hash stand-in.
Future<TestRegistrationMaterial> createTestRegistrationMaterial({
  required String accountId,
  required String username,
  required String deviceId,
  required String deviceName,
}) async {
  final ed25519 = crypto.Ed25519();
  final accountKeyPair = await ed25519.newKeyPair();
  final accountPublicKey = await accountKeyPair.extractPublicKey();
  final deviceSigningKeyPair = await ed25519.newKeyPair();
  final deviceSigningPublicKey = await deviceSigningKeyPair.extractPublicKey();
  final agreementKeyPair = await crypto.X25519().newKeyPair();
  final agreementPublicKey = await agreementKeyPair.extractPublicKey();
  final accountIdentityPublicKey = testBase64Url(accountPublicKey.bytes);
  final deviceSigningPublicKeyStr = testBase64Url(deviceSigningPublicKey.bytes);
  final deviceAgreementPublicKey = testBase64Url(agreementPublicKey.bytes);
  final transcript = registrationTranscript(
    accountId: accountId,
    phoneHash: username,
    accountIdentityPublicKey: accountIdentityPublicKey,
    deviceId: deviceId,
    deviceSigningPublicKey: deviceSigningPublicKeyStr,
    deviceAgreementPublicKey: deviceAgreementPublicKey,
    deviceName: deviceName,
  );
  final accountSignature = await ed25519.sign(
    utf8.encode(transcript),
    keyPair: accountKeyPair,
  );
  final deviceSignature = await ed25519.sign(
    utf8.encode(transcript),
    keyPair: deviceSigningKeyPair,
  );
  return TestRegistrationMaterial(
    deviceSigningKeyPair: deviceSigningKeyPair,
    deviceAgreementKeyPair: agreementKeyPair,
    accountIdentityPublicKey: accountIdentityPublicKey,
    deviceSigningPublicKey: deviceSigningPublicKeyStr,
    deviceAgreementPublicKey: deviceAgreementPublicKey,
    accountRegistrationSignature: testBase64Url(accountSignature.bytes),
    deviceRegistrationSignature: testBase64Url(deviceSignature.bytes),
  );
}

/// Builds a registration_version=3 request body. `username` is used as the
/// phone_hash value (see note on `createTestRegistrationMaterial`);
/// `otpCode` must come from a real `/accounts/phone/otp/request` call
/// (see `requestTestOtp` below) so the server-side challenge actually
/// matches.
Map<String, dynamic> registrationBody({
  required String accountId,
  required String username,
  required String deviceId,
  required String deviceName,
  required TestRegistrationMaterial material,
  required String otpCode,
  required String inviteCode,
  String? displayName,
}) {
  return {
    'registration_version': 3,
    'account_id': accountId,
    'phone_hash': username,
    'otp_code': otpCode,
    'invite_code': inviteCode,
    'display_name': displayName ?? username,
    'account_identity_public_key': material.accountIdentityPublicKey,
    'device_id': deviceId,
    'device_signing_public_key': material.deviceSigningPublicKey,
    'device_agreement_public_key': material.deviceAgreementPublicKey,
    'account_registration_signature': material.accountRegistrationSignature,
    'device_registration_signature': material.deviceRegistrationSignature,
    'device_name': deviceName,
  };
}

String registrationTranscript({
  required String accountId,
  required String phoneHash,
  required String accountIdentityPublicKey,
  required String deviceId,
  required String deviceSigningPublicKey,
  required String deviceAgreementPublicKey,
  required String deviceName,
}) {
  return [
    'helix.remote.registration.v3',
    accountId,
    phoneHash,
    accountIdentityPublicKey,
    deviceId,
    deviceSigningPublicKey,
    deviceAgreementPublicKey,
    deviceName,
  ].join('\n');
}

/// Calls the real `/accounts/phone/otp/request` endpoint and returns the
/// code from the response — this is the agreed placeholder delivery
/// mechanism (no real SMS/push), so the code is simply in the response
/// body rather than requiring a mocked notification channel in tests.
Future<String> requestTestOtp({
  required HttpClient client,
  required String host,
  required int port,
  required String phoneHash,
}) async {
  final request = await client.post(
    host,
    port,
    '/api/v1/accounts/phone/otp/request',
  );
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'phone_hash': phoneHash}));
  final response = await request.close();
  final body =
      jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
  if (response.statusCode != 200) {
    throw StateError(
      'OTP request failed with HTTP ${response.statusCode}: $body',
    );
  }
  return body['code'] as String;
}

/// Directly seeds a redeemable invite credential via the database, bypassing
/// the admin-token HTTP flow (tests generally don't care who issued it, just
/// that a valid one exists for the registration under test).
String seedTestInvite(
  BackendDatabase db, {
  String serverAddress = 'https://test.local',
  Duration validity = const Duration(days: 7),
}) {
  final code = generateInviteCode();
  final now = DateTime.now().millisecondsSinceEpoch;
  db.createInviteCredential(
    inviteId: generateInviteId(),
    inviteCodeHash: hashInviteCode(code),
    serverAddress: serverAddress,
    issuerType: 'ADMIN',
    issuerLabel: 'test-harness',
    createdAt: now,
    expiresAt: now + validity.inMilliseconds,
  );
  return code;
}

Future<TestRegistrationMaterial> registerTestAccount({
  required HttpClient client,
  required String host,
  required int port,
  required BackendDatabase db,
  required String accountId,
  required String username,
  required String deviceId,
  required String deviceName,
}) async {
  final material = await createTestRegistrationMaterial(
    accountId: accountId,
    username: username,
    deviceId: deviceId,
    deviceName: deviceName,
  );
  final otpCode = await requestTestOtp(
    client: client,
    host: host,
    port: port,
    phoneHash: username,
  );
  final inviteCode = seedTestInvite(db);
  final request = await client.post(host, port, '/api/v1/accounts/register');
  request.headers.contentType = ContentType.json;
  request.write(
    jsonEncode(
      registrationBody(
        accountId: accountId,
        username: username,
        deviceId: deviceId,
        deviceName: deviceName,
        material: material,
        otpCode: otpCode,
        inviteCode: inviteCode,
      ),
    ),
  );
  final response = await request.close();
  await response.drain<void>();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('Registration failed with HTTP ${response.statusCode}');
  }
  return material;
}

Future<Map<String, dynamic>> loginTestAccount({
  required HttpClient client,
  required String host,
  required int port,
  required String accountId,
  required String deviceId,
  required crypto.SimpleKeyPair deviceSigningKeyPair,
}) async {
  final challengeRequest = await client.get(
    host,
    port,
    '/api/v1/accounts/challenge?account_id=$accountId&device_id=$deviceId',
  );
  final challengeResponse = await challengeRequest.close();
  final challengeBody =
      jsonDecode(await challengeResponse.transform(utf8.decoder).join())
          as Map<String, dynamic>;
  final signature = await crypto.Ed25519().sign(
    utf8.encode(challengeBody['challenge'] as String),
    keyPair: deviceSigningKeyPair,
  );
  final loginRequest = await client.post(host, port, '/api/v1/accounts/login');
  loginRequest.headers.contentType = ContentType.json;
  loginRequest.write(
    jsonEncode({
      'account_id': accountId,
      'device_id': deviceId,
      'signature': testBase64Url(signature.bytes),
    }),
  );
  final loginResponse = await loginRequest.close();
  return jsonDecode(await loginResponse.transform(utf8.decoder).join())
      as Map<String, dynamic>;
}
