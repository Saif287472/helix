import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:convert/convert.dart' as cvt;
import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';

class FlutterSecureIdentityStore implements SecureIdentityStore {
  final FlutterSecureStorage _storage;
  final String keyPrefix;

  const FlutterSecureIdentityStore({
    this._storage = const FlutterSecureStorage(),
    this.keyPrefix = '',
  });

  @override
  Future<DeviceIdentity?> loadIdentity() async {
    final hasPrefixedCert = await _storage.read(
      key: '$keyPrefix$kKeyIdentityCert',
    );
    if (hasPrefixedCert == null && keyPrefix.startsWith('helix_local_')) {
      final oldCert = await _storage.read(key: kKeyIdentityCert);
      final oldPrivate = await _storage.read(key: kKeyIdentityPrivate);
      final oldVerifier = await _storage.read(key: kKeySecretCodeVerifier);
      final oldFirstRun = await _storage.read(key: kKeyFirstRunDone);

      if (oldCert != null) {
        await _storage.write(
          key: '$keyPrefix$kKeyIdentityCert',
          value: oldCert,
        );
        if (oldPrivate != null) {
          await _storage.write(
            key: '$keyPrefix$kKeyIdentityPrivate',
            value: oldPrivate,
          );
        }
        if (oldVerifier != null) {
          await _storage.write(
            key: '$keyPrefix$kKeySecretCodeVerifier',
            value: oldVerifier,
          );
        }
        if (oldFirstRun != null) {
          await _storage.write(
            key: '$keyPrefix$kKeyFirstRunDone',
            value: oldFirstRun,
          );
        }

        await _storage.delete(key: kKeyIdentityCert);
        await _storage.delete(key: kKeyIdentityPrivate);
        await _storage.delete(key: kKeySecretCode);
        await _storage.delete(key: kKeySecretCodeVerifier);
        await _storage.delete(key: kKeyFirstRunDone);
      }
    }

    final certPem = await _storage.read(key: '$keyPrefix$kKeyIdentityCert');
    final privateKeyPem = await _storage.read(
      key: '$keyPrefix$kKeyIdentityPrivate',
    );

    if (certPem == null || privateKeyPem == null) {
      return null;
    }

    return _buildIdentityFromPem(certPem, privateKeyPem);
  }

  @override
  Future<void> saveIdentity(DeviceIdentity identity) async {
    await _storage.write(
      key: '$keyPrefix$kKeyIdentityCert',
      value: identity.certPem,
    );
    await _storage.write(
      key: '$keyPrefix$kKeyIdentityPrivate',
      value: identity.privateKeyPem,
    );
  }

  @override
  Future<String?> loadSecretCode() async {
    await _storage.delete(key: '$keyPrefix$kKeySecretCode');
    if (keyPrefix.startsWith('helix_local_')) {
      await _storage.delete(key: kKeySecretCode);
    }
    return null;
  }

  @override
  Future<void> saveSecretCode(String secretCode) async {
    await _storage.delete(key: '$keyPrefix$kKeySecretCode');
    if (keyPrefix.startsWith('helix_local_')) {
      await _storage.delete(key: kKeySecretCode);
    }
  }

  @override
  Future<String?> loadSecretCodeVerifier() async {
    final hasPrefixedVerifier = await _storage.read(
      key: '$keyPrefix$kKeySecretCodeVerifier',
    );
    if (hasPrefixedVerifier == null && keyPrefix.startsWith('helix_local_')) {
      final oldVerifier = await _storage.read(key: kKeySecretCodeVerifier);
      if (oldVerifier != null) {
        await _storage.write(
          key: '$keyPrefix$kKeySecretCodeVerifier',
          value: oldVerifier,
        );
        await _storage.delete(key: kKeySecretCodeVerifier);
        return oldVerifier;
      }
    }
    return _storage.read(key: '$keyPrefix$kKeySecretCodeVerifier');
  }

  @override
  Future<void> saveSecretCodeVerifier(String verifier) async {
    await _storage.write(
      key: '$keyPrefix$kKeySecretCodeVerifier',
      value: verifier,
    );
  }

  @override
  Future<bool> isFirstRun() async {
    final hasPrefixedFirstRun = await _storage.read(
      key: '$keyPrefix$kKeyFirstRunDone',
    );
    if (hasPrefixedFirstRun == null && keyPrefix.startsWith('helix_local_')) {
      final oldFirstRun = await _storage.read(key: kKeyFirstRunDone);
      if (oldFirstRun != null) {
        await _storage.write(
          key: '$keyPrefix$kKeyFirstRunDone',
          value: oldFirstRun,
        );
        await _storage.delete(key: kKeyFirstRunDone);
        return false;
      }
    }
    final firstRunDone = await _storage.read(
      key: '$keyPrefix$kKeyFirstRunDone',
    );
    return firstRunDone == null;
  }

  @override
  Future<void> setFirstRunDone() async {
    await _storage.write(key: '$keyPrefix$kKeyFirstRunDone', value: '1');
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: '$keyPrefix$kKeyIdentityCert');
    await _storage.delete(key: '$keyPrefix$kKeyIdentityPrivate');
    await _storage.delete(key: '$keyPrefix$kKeySecretCode');
    await _storage.delete(key: '$keyPrefix$kKeySecretCodeVerifier');
    await _storage.delete(key: '$keyPrefix$kKeyFirstRunDone');
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
