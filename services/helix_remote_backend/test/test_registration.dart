import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as crypto;

class TestRegistrationMaterial {
  const TestRegistrationMaterial({
    required this.deviceSigningKeyPair,
    required this.accountIdentityPublicKey,
    required this.deviceSigningPublicKey,
    required this.deviceAgreementPublicKey,
    required this.accountRegistrationSignature,
    required this.deviceRegistrationSignature,
  });

  final crypto.SimpleKeyPair deviceSigningKeyPair;
  final String accountIdentityPublicKey;
  final String deviceSigningPublicKey;
  final String deviceAgreementPublicKey;
  final String accountRegistrationSignature;
  final String deviceRegistrationSignature;
}

String testBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

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
    username: username,
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
    accountIdentityPublicKey: accountIdentityPublicKey,
    deviceSigningPublicKey: deviceSigningPublicKeyStr,
    deviceAgreementPublicKey: deviceAgreementPublicKey,
    accountRegistrationSignature: testBase64Url(accountSignature.bytes),
    deviceRegistrationSignature: testBase64Url(deviceSignature.bytes),
  );
}

Map<String, dynamic> registrationBody({
  required String accountId,
  required String username,
  required String deviceId,
  required String deviceName,
  required TestRegistrationMaterial material,
}) {
  return {
    'registration_version': 2,
    'account_id': accountId,
    'username': username,
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
  required String username,
  required String accountIdentityPublicKey,
  required String deviceId,
  required String deviceSigningPublicKey,
  required String deviceAgreementPublicKey,
  required String deviceName,
}) {
  return [
    'helix.remote.registration.v2',
    accountId,
    username,
    accountIdentityPublicKey,
    deviceId,
    deviceSigningPublicKey,
    deviceAgreementPublicKey,
    deviceName,
  ].join('\n');
}

Future<TestRegistrationMaterial> registerTestAccount({
  required HttpClient client,
  required String host,
  required int port,
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
