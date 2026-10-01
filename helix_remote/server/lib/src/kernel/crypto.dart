import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Cryptographic helpers every module may use (ADR-026 kernel).

final Random _random = Random.secure();

Uint8List randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

Uint8List sha256Bytes(List<int> data) =>
    Uint8List.fromList(crypto.sha256.convert(data).bytes);

Uint8List hmacSha256(List<int> key, List<int> message) =>
    Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(message).bytes);

/// Compares without leaking where the first difference is.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

final Ed25519 _ed25519 = Ed25519();

/// True only for a valid Ed25519 signature by [publicKey] over [message].
Future<bool> verifyEd25519({
  required List<int> publicKey,
  required List<int> message,
  required List<int> signature,
}) async {
  if (publicKey.length != 32 || signature.length != 64) return false;
  try {
    return await _ed25519.verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  } on Object {
    return false;
  }
}
