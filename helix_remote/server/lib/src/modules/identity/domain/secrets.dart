import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';

export 'package:helix_remote_server/src/kernel/crypto.dart';

/// A bearer secret: `<prefix>_<43 base64url chars>` (32 random bytes).
/// Only its [hashToken] is stored.
String newToken(String prefix) => '${prefix}_${encodeBytes(randomBytes(32))}';

/// SHA-256 of a bearer token, for storage and lookup.
Uint8List hashToken(String token) => sha256Bytes(utf8.encode(token));

/// Hex of [hashToken], for ephemeral-store keys.
String tokenKey(String token) =>
    crypto.sha256.convert(utf8.encode(token)).toString();

/// A six-digit code from the secure generator.
String sixDigitCode() {
  final b = randomBytes(4);
  final n = ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) & 0x7fffffff;
  return (n % 900000 + 100000).toString();
}

final RegExp _e164 = RegExp(r'^\+[1-9][0-9]{7,14}$');

/// The number in E.164 form, or an `invalid_field` error.
String requireE164(String number) {
  final cleaned = number.replaceAll(RegExp(r'[\s()-]'), '');
  if (!_e164.hasMatch(cleaned)) {
    throw const ApiError(
      ErrorCode.invalidField,
      message:
          'phone_number must be in international format, e.g. +8801712345678',
      details: {'field': 'phone_number'},
    );
  }
  return cleaned;
}

/// Checks a device registration against the account identity key
/// (CRYPTO_V2.md §2): the AIK certificate and the DSK proof of possession,
/// over the same certificate body.
Future<void> verifyDeviceRegistration({
  required String accountId,
  required List<int> accountIdentityKey,
  required DeviceRegistration device,
}) async {
  ApiError invalid(String what) => ApiError(
    ErrorCode.invalidField,
    message: 'device $what does not verify',
    details: {'field': 'device.$what'},
  );

  if (!Uuid.isValid(device.deviceId)) {
    throw const ApiError(
      ErrorCode.invalidField,
      details: {'field': 'device.device_id'},
    );
  }
  if (device.name.isEmpty ||
      device.name.length > DeviceRegistration.maxNameLength) {
    throw const ApiError(
      ErrorCode.invalidField,
      details: {'field': 'device.name'},
    );
  }
  if (device.identityKey.length != 32 || device.signingKey.length != 32) {
    throw const ApiError(
      ErrorCode.invalidField,
      details: {'field': 'device.keys'},
    );
  }
  final body = deviceCertificateBody(
    accountId: accountId,
    deviceId: device.deviceId,
    identityKey: device.identityKey,
    signingKey: device.signingKey,
    createdAt: device.certificate.createdAt,
  );
  if (!await verifyEd25519(
    publicKey: accountIdentityKey,
    message: body,
    signature: device.certificate.signature,
  )) {
    throw invalid('certificate');
  }
  if (!await verifyEd25519(
    publicKey: device.signingKey,
    message: body,
    signature: device.proof,
  )) {
    throw invalid('proof');
  }
}
