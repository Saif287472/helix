import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart' as c;
import 'package:helix_remote_crypto/src/v2/errors.dart';

/// Primitives for v2 (CRYPTO_V2.md §1): X25519, Ed25519, HKDF-SHA256,
/// HMAC-SHA256, AES-256-GCM, SHA-256/512. Everything that needs randomness
/// takes a [CryptoRandom], so tests can produce deterministic vectors.

/// A source of random bytes. Production code uses [SecureCryptoRandom]; tests
/// inject a seeded source to generate vectors. Never use a seeded source
/// outside tests.
abstract interface class CryptoRandom {
  Uint8List nextBytes(int length);
}

/// The OS CSPRNG (`Random.secure`).
final class SecureCryptoRandom implements CryptoRandom {
  SecureCryptoRandom() : _random = Random.secure();

  final Random _random;

  @override
  Uint8List nextBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}

// ------------------------------------------------------------------ bytes

/// ASCII bytes of a domain-separation label (all labels start `helix.v2.`).
Uint8List label(String text) => Uint8List.fromList(ascii.encode(text));

Uint8List u8(int value) {
  _checkRange(value, 0xff, 'u8');
  return Uint8List.fromList([value]);
}

Uint8List u16(int value) {
  _checkRange(value, 0xffff, 'u16');
  return Uint8List(2)..buffer.asByteData().setUint16(0, value);
}

Uint8List u32(int value) {
  _checkRange(value, 0xffffffff, 'u32');
  return Uint8List(4)..buffer.asByteData().setUint32(0, value);
}

Uint8List u64(int value) {
  if (value < 0) throw ArgumentError.value(value, 'value', 'negative u64');
  return Uint8List(8)..buffer.asByteData().setUint64(0, value);
}

/// Largest value of a `u32` field.
const maxU32 = 0xffffffff;

bool isU32(int value) => value >= 0 && value <= maxU32;

void _checkRange(int value, int max, String name) {
  if (value < 0 || value > max) {
    throw ArgumentError.value(value, 'value', 'out of range for $name');
  }
}

/// `a ‖ b ‖ …`.
Uint8List concatBytes(Iterable<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final part in parts) {
    out.add(part);
  }
  return out.toBytes();
}

/// Compares without revealing where the first difference is.
bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Lexicographic order of two byte strings (for canonical ordering).
int compareBytes(List<int> a, List<int> b) {
  final n = min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

Uint8List copyBytes(List<int> bytes) => Uint8List.fromList(bytes);

void requireLength(List<int> bytes, int length, String what) {
  if (bytes.length != length) {
    throw MalformedCryptoInputException('$what must be $length bytes');
  }
}

// ----------------------------------------------------------------- hashes

Uint8List sha256(List<int> data) =>
    Uint8List.fromList(hashes.sha256.convert(data).bytes);

Uint8List sha512(List<int> data) =>
    Uint8List.fromList(hashes.sha512.convert(data).bytes);

Uint8List hmacSha256(List<int> key, List<int> message) =>
    Uint8List.fromList(hashes.Hmac(hashes.sha256, key).convert(message).bytes);

/// 32 zero bytes, the HKDF salt wherever the spec says `0x00*32`.
final Uint8List zeroSalt = Uint8List(32);

/// HKDF-SHA256 (RFC 5869). An empty [salt] means 32 zero bytes.
Uint8List hkdf({
  required List<int> ikm,
  required List<int> salt,
  required List<int> info,
  required int length,
}) {
  if (length <= 0 || length > 255 * 32) {
    throw ArgumentError.value(length, 'length', 'invalid HKDF length');
  }
  final prk = hmacSha256(salt.isEmpty ? zeroSalt : salt, ikm);
  final out = BytesBuilder(copy: false);
  var previous = Uint8List(0);
  for (var i = 1; out.length < length; i++) {
    previous = hmacSha256(prk, concatBytes([previous, info, u8(i)]));
    out.add(previous);
  }
  return Uint8List.sublistView(out.toBytes(), 0, length);
}

// ------------------------------------------------------------------- AEAD

/// An AES-256-GCM key and 96-bit nonce derived together from one secret
/// (`HKDF(ikm, salt = 0x00*32, info, len = 44) -> key[0:32], nonce[32:44]`).
/// Only valid for a secret that encrypts exactly one plaintext.
final class AeadKey {
  AeadKey(this.key, this.nonce) {
    requireLength(key, Aead.keyLength, 'AEAD key');
    requireLength(nonce, Aead.nonceLength, 'AEAD nonce');
  }

  factory AeadKey.derive(List<int> ikm, String info) {
    final out = hkdf(ikm: ikm, salt: zeroSalt, info: label(info), length: 44);
    return AeadKey(
      Uint8List.fromList(out.sublist(0, 32)),
      Uint8List.fromList(out.sublist(32, 44)),
    );
  }

  final Uint8List key;
  final Uint8List nonce;

  Future<Uint8List> seal(List<int> plaintext, {required List<int> aad}) =>
      Aead.seal(key: key, nonce: nonce, plaintext: plaintext, aad: aad);

  Future<Uint8List> open(List<int> ciphertext, {required List<int> aad}) =>
      Aead.open(key: key, nonce: nonce, ciphertext: ciphertext, aad: aad);

  @override
  String toString() => 'AeadKey(<redacted>)';
}

/// AES-256-GCM. Ciphertexts are `ct ‖ tag(16)`.
abstract final class Aead {
  static const keyLength = 32;
  static const nonceLength = 12;
  static const tagLength = 16;

  static final c.AesGcm _aes = c.AesGcm.with256bits();

  static Future<Uint8List> seal({
    required List<int> key,
    required List<int> nonce,
    required List<int> plaintext,
    required List<int> aad,
  }) async {
    requireLength(key, keyLength, 'AEAD key');
    requireLength(nonce, nonceLength, 'AEAD nonce');
    final box = await _aes.encrypt(
      plaintext,
      secretKey: c.SecretKey(copyBytes(key)),
      nonce: nonce,
      aad: aad,
    );
    return concatBytes([box.cipherText, box.mac.bytes]);
  }

  /// Throws [DecryptionFailedException] when the tag does not verify.
  static Future<Uint8List> open({
    required List<int> key,
    required List<int> nonce,
    required List<int> ciphertext,
    required List<int> aad,
  }) async {
    requireLength(key, keyLength, 'AEAD key');
    requireLength(nonce, nonceLength, 'AEAD nonce');
    if (ciphertext.length < tagLength) {
      throw const DecryptionFailedException('ciphertext too short');
    }
    final split = ciphertext.length - tagLength;
    try {
      final plain = await _aes.decrypt(
        c.SecretBox(
          ciphertext.sublist(0, split),
          nonce: nonce,
          mac: c.Mac(ciphertext.sublist(split)),
        ),
        secretKey: c.SecretKey(copyBytes(key)),
        aad: aad,
      );
      return Uint8List.fromList(plain);
    } on c.SecretBoxAuthenticationError {
      throw const DecryptionFailedException();
    }
  }
}

// ------------------------------------------------------------------ X25519

final c.X25519 _x25519 = c.X25519();
final c.Ed25519 _ed25519 = c.Ed25519();

/// An X25519 key pair. [privateKey] is the 32-byte scalar as generated (it is
/// clamped when used, RFC 7748).
final class X25519KeyPair {
  X25519KeyPair._(this.privateKey, this.publicKey);

  static Future<X25519KeyPair> fromPrivateKey(List<int> privateKey) async {
    requireLength(privateKey, 32, 'X25519 private key');
    final pair = await _x25519.newKeyPairFromSeed(copyBytes(privateKey));
    final public = await pair.extractPublicKey();
    return X25519KeyPair._(copyBytes(privateKey), copyBytes(public.bytes));
  }

  static Future<X25519KeyPair> generate(CryptoRandom random) =>
      fromPrivateKey(random.nextBytes(32));

  /// Rebuilds a pair whose public key is already known (no scalar
  /// multiplication). Only for state this device wrote itself.
  factory X25519KeyPair.restore(List<int> privateKey, List<int> publicKey) {
    requireLength(privateKey, 32, 'X25519 private key');
    requireLength(publicKey, 32, 'X25519 public key');
    return X25519KeyPair._(copyBytes(privateKey), copyBytes(publicKey));
  }

  final Uint8List privateKey;
  final Uint8List publicKey;

  /// `X25519(this, remotePublicKey)`. Rejects malformed and low-order public
  /// keys (an all-zero shared secret).
  Future<Uint8List> agree(List<int> remotePublicKey) async {
    if (remotePublicKey.length != 32) {
      throw const InvalidKeyException('X25519 public key must be 32 bytes');
    }
    final secret = await _x25519.sharedSecretKey(
      keyPair: c.SimpleKeyPairData(
        copyBytes(privateKey),
        publicKey: c.SimplePublicKey(
          copyBytes(publicKey),
          type: c.KeyPairType.x25519,
        ),
        type: c.KeyPairType.x25519,
      ),
      remotePublicKey: c.SimplePublicKey(
        copyBytes(remotePublicKey),
        type: c.KeyPairType.x25519,
      ),
    );
    final out = Uint8List.fromList(await secret.extractBytes());
    if (bytesEqual(out, Uint8List(32))) {
      throw const InvalidKeyException('low-order X25519 public key');
    }
    return out;
  }

  @override
  String toString() => 'X25519KeyPair(<redacted>)';
}

// ----------------------------------------------------------------- Ed25519

/// An Ed25519 key pair from its 32-byte seed (RFC 8032 private key).
final class Ed25519KeyPair {
  Ed25519KeyPair._(this.seed, this.publicKey);

  static Future<Ed25519KeyPair> fromSeed(List<int> seed) async {
    requireLength(seed, 32, 'Ed25519 seed');
    final pair = await _ed25519.newKeyPairFromSeed(copyBytes(seed));
    final public = await pair.extractPublicKey();
    return Ed25519KeyPair._(copyBytes(seed), copyBytes(public.bytes));
  }

  static Future<Ed25519KeyPair> generate(CryptoRandom random) =>
      fromSeed(random.nextBytes(32));

  /// Rebuilds a pair whose public key is already known. Only for state this
  /// device wrote itself.
  factory Ed25519KeyPair.restore(List<int> seed, List<int> publicKey) {
    requireLength(seed, 32, 'Ed25519 seed');
    requireLength(publicKey, 32, 'Ed25519 public key');
    return Ed25519KeyPair._(copyBytes(seed), copyBytes(publicKey));
  }

  final Uint8List seed;
  final Uint8List publicKey;

  /// Deterministic Ed25519 signature (64 bytes).
  Future<Uint8List> sign(List<int> message) async {
    final signature = await _ed25519.sign(
      message,
      keyPair: c.SimpleKeyPairData(
        copyBytes(seed),
        publicKey: c.SimplePublicKey(
          copyBytes(publicKey),
          type: c.KeyPairType.ed25519,
        ),
        type: c.KeyPairType.ed25519,
      ),
    );
    return Uint8List.fromList(signature.bytes);
  }

  @override
  String toString() => 'Ed25519KeyPair(<redacted>)';
}

/// True only for a valid Ed25519 signature by [publicKey] over [message].
Future<bool> ed25519Verify({
  required List<int> publicKey,
  required List<int> message,
  required List<int> signature,
}) async {
  if (publicKey.length != 32 || signature.length != 64) return false;
  try {
    return await _ed25519.verify(
      message,
      signature: c.Signature(
        copyBytes(signature),
        publicKey: c.SimplePublicKey(
          copyBytes(publicKey),
          type: c.KeyPairType.ed25519,
        ),
      ),
    );
  } on Object {
    return false;
  }
}

/// Throws [InvalidSignatureException] unless the signature verifies.
Future<void> requireSignature({
  required List<int> publicKey,
  required List<int> message,
  required List<int> signature,
  required String what,
}) async {
  final ok = await ed25519Verify(
    publicKey: publicKey,
    message: message,
    signature: signature,
  );
  if (!ok) throw InvalidSignatureException('$what signature does not verify');
}
