import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as c;
import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/identity.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Password keys and the password-wrapped AIK (CRYPTO_V2.md §11, kept from
/// v1 F1 §9a):
///
/// ```
/// out        = Argon2id(password, salt, m = 19456 KiB, t = 2, p = 1, 64 bytes)
/// auth_key   = HKDF(out, salt = 0x00*32, info = "helix.v2.password.auth", 32)
/// wrap_key   = HKDF(out, salt = 0x00*32, info = "helix.v2.password.wrap", 32)
/// wrapped    = AES-256-GCM(wrap_key, random nonce, AIK seed,
///                          aad = "helix.v2.wrapped-aik" ‖ account_id(16))
/// ```
///
/// Only `auth_key` is ever sent. The password never leaves the device.
final class PasswordKeys {
  const PasswordKeys._(this.authKey, this.wrapKey);

  static const saltLength = 32;
  static const minSaltLength = 16;
  static const maxSaltLength = 64;

  /// Sent to the server as proof of the password.
  final Uint8List authKey;

  /// Never leaves the device.
  final Uint8List wrapKey;

  static Uint8List newSalt(CryptoRandom random) => random.nextBytes(saltLength);

  /// Derives both keys. Refuses parameters weaker than the v2 minimum
  /// ([KdfParams.isAcceptable]), whoever supplied them, and salts outside
  /// 16-64 bytes. The password is used as its UTF-8 bytes (no Unicode
  /// normalisation; CRYPTO_V2.md §14).
  static Future<PasswordKeys> derive({
    required String password,
    required List<int> salt,
    KdfParams params = const KdfParams(),
  }) async {
    if (!params.isAcceptable) {
      throw const MalformedCryptoInputException(
        'password KDF parameters are below the v2 minimum',
      );
    }
    if (salt.length < minSaltLength || salt.length > maxSaltLength) {
      throw const MalformedCryptoInputException('password salt length');
    }
    final argon = c.Argon2id(
      parallelism: params.parallelism,
      memory: params.memoryKib,
      iterations: params.iterations,
      hashLength: params.length,
    );
    final secret = await argon.deriveKey(
      secretKey: c.SecretKey(utf8.encode(password)),
      nonce: copyBytes(salt),
    );
    final out = await secret.extractBytes();
    return PasswordKeys._(
      hkdf(
        ikm: out,
        salt: zeroSalt,
        info: label('helix.v2.password.auth'),
        length: 32,
      ),
      hkdf(
        ikm: out,
        salt: zeroSalt,
        info: label('helix.v2.password.wrap'),
        length: 32,
      ),
    );
  }

  /// Seals the AIK seed for `PasswordSetup.wrappedIdentityKey`.
  Future<WrappedKey> wrapIdentityKey({
    required List<int> identityKeySeed,
    required String accountId,
    required CryptoRandom random,
  }) async {
    requireLength(identityKeySeed, 32, 'AIK seed');
    final nonce = random.nextBytes(Aead.nonceLength);
    return WrappedKey(
      nonce: nonce,
      ciphertext: await Aead.seal(
        key: wrapKey,
        nonce: nonce,
        plaintext: identityKeySeed,
        aad: _aad(accountId),
      ),
    );
  }

  /// Opens a wrapped AIK and checks it against the account's AIK public key
  /// when one is known. Throws [DecryptionFailedException] for a wrong
  /// password or a wrapped key bound to another account.
  Future<Ed25519KeyPair> unwrapIdentityKey({
    required WrappedKey wrapped,
    required String accountId,
    List<int>? expectedPublicKey,
  }) async {
    if (wrapped.nonce.length != Aead.nonceLength) {
      throw const MalformedCryptoInputException('wrapped key nonce');
    }
    final seed = await Aead.open(
      key: wrapKey,
      nonce: wrapped.nonce,
      ciphertext: wrapped.ciphertext,
      aad: _aad(accountId),
    );
    if (seed.length != 32) {
      throw const MalformedCryptoInputException('wrapped AIK length');
    }
    final pair = await Ed25519KeyPair.fromSeed(seed);
    if (expectedPublicKey != null &&
        !bytesEqual(pair.publicKey, expectedPublicKey)) {
      throw const UntrustedIdentityException(
        'unwrapped key is not the account identity key',
      );
    }
    return pair;
  }

  static Uint8List _aad(String accountId) =>
      concatBytes([label('helix.v2.wrapped-aik'), accountIdBytes(accountId)]);

  @override
  String toString() => 'PasswordKeys(<redacted>)';
}
