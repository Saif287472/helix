import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:convert/convert.dart' as cvt;
import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_domain/application/contracts/repositories.dart';

class FlutterSecureIdentityStore implements SecureIdentityStore {
  final FlutterSecureStorage _storage;

  const FlutterSecureIdentityStore({
    this._storage = const FlutterSecureStorage(),
  });

  @override
  Future<DeviceIdentity?> loadIdentity() async {
    final certPem = await _storage.read(key: kKeyIdentityCert);
    final privateKeyPem = await _storage.read(key: kKeyIdentityPrivate);

    if (certPem == null || privateKeyPem == null) {
      return null;
    }

    return _buildIdentityFromPem(certPem, privateKeyPem);
  }

  @override
  Future<void> saveIdentity(DeviceIdentity identity) async {
    await _storage.write(key: kKeyIdentityCert, value: identity.certPem);
    await _storage.write(
      key: kKeyIdentityPrivate,
      value: identity.privateKeyPem,
    );
  }

  @override
  Future<String?> loadSecretCode() async {
    return _storage.read(key: kKeySecretCode);
  }

  @override
  Future<void> saveSecretCode(String secretCode) async {
    await _storage.write(key: kKeySecretCode, value: secretCode);
  }

  @override
  Future<String?> loadSecretCodeVerifier() async {
    return _storage.read(key: kKeySecretCodeVerifier);
  }

  @override
  Future<void> saveSecretCodeVerifier(String verifier) async {
    await _storage.write(key: kKeySecretCodeVerifier, value: verifier);
  }

  @override
  Future<bool> isFirstRun() async {
    final firstRunDone = await _storage.read(key: kKeyFirstRunDone);
    return firstRunDone == null;
  }

  @override
  Future<void> setFirstRunDone() async {
    await _storage.write(key: kKeyFirstRunDone, value: '1');
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: kKeyIdentityCert);
    await _storage.delete(key: kKeyIdentityPrivate);
    await _storage.delete(key: kKeySecretCode);
    await _storage.delete(key: kKeySecretCodeVerifier);
    await _storage.delete(key: kKeyFirstRunDone);
  }

  DeviceIdentity _buildIdentityFromPem(String certPem, String privateKeyPem) {
    try {
      final privateKey = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);
      // Reconstruct the public key from the private key's modulus + public exponent
      final publicKey = RSAPublicKey(
        privateKey.modulus!,
        privateKey.publicExponent!,
      );
      final digest = pkg_crypto.sha256.convert(_modulusBytes(publicKey));
      final fingerprintHex = cvt.hex.encode(digest.bytes);
      final fingerprint = fingerprintHex.substring(0, 32);
      final suffix = fingerprintHex.substring(0, 4);

      return DeviceIdentity(
        certPem: certPem,
        privateKeyPem: privateKeyPem,
        staticPublicKeyFingerprint: fingerprint,
        deviceSuffix: suffix,
      );
    } catch (_) {
      return DeviceIdentity(
        certPem: certPem,
        privateKeyPem: privateKeyPem,
        staticPublicKeyFingerprint: '0' * 32,
        deviceSuffix: '0000',
      );
    }
  }

  static Uint8List _modulusBytes(RSAPublicKey key) {
    final hex = key.modulus!.toRadixString(16);
    final padded = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList(
      List.generate(
        padded.length ~/ 2,
        (i) => int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }
}
