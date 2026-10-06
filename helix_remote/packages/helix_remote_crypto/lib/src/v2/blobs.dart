import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/identity.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Encrypted blobs the server stores for others to read (CRYPTO_V2.md §9):
/// the group state (sealed with the epoch's group master key) and the
/// account profile (sealed with the profile key).
///
/// ```
/// key  = HKDF(GMK or profile key, salt = 0x00*32, info, 32)
/// blob = u8(1) ‖ nonce(12, random) ‖ AES-256-GCM(key, nonce, padded, aad)
/// ```
///
/// The nonce is random, not derived (CRYPTO_V2.md §14): one GMK or profile
/// key seals many versions, so a derived nonce would repeat.
final class SealedBlobCipher {
  const SealedBlobCipher._(this.info);

  static const formatVersion = 1;

  /// `aad = "helix.v2.gs" ‖ group_id(16) ‖ u32(epoch) ‖ u32(state_version)`.
  ///
  /// The state version is in the AAD so a server cannot serve an older blob
  /// as the current one (CRYPTO_V2.md §9): the version the server reports
  /// must be the one the blob was sealed for.
  static const groupState = SealedBlobCipher._('helix.v2.group-state');

  /// `aad = "helix.v2.pf" ‖ account_id(16) ‖ u32(version)`.
  static const profile = SealedBlobCipher._('helix.v2.profile');

  final String info;

  static Uint8List groupStateAad(String groupId, int epoch, int stateVersion) =>
      concatBytes([
        label('helix.v2.gs'),
        uuidBytes(groupId),
        u32(epoch),
        u32(stateVersion),
      ]);

  static Uint8List profileAad(String accountId, int version) => concatBytes([
    label('helix.v2.pf'),
    accountIdBytes(accountId),
    u32(version),
  ]);

  Uint8List _key(List<int> secret) {
    requireLength(secret, 32, 'blob key');
    return hkdf(ikm: secret, salt: zeroSalt, info: label(info), length: 32);
  }

  /// Pads (CRYPTO_V2.md §6) and seals [plaintext].
  Future<Uint8List> seal({
    required List<int> secret,
    required List<int> plaintext,
    required List<int> aad,
    required CryptoRandom random,
  }) async {
    final nonce = random.nextBytes(Aead.nonceLength);
    return concatBytes([
      u8(formatVersion),
      nonce,
      await Aead.seal(
        key: _key(secret),
        nonce: nonce,
        plaintext: padPlaintext(plaintext),
        aad: aad,
      ),
    ]);
  }

  Future<Uint8List> open({
    required List<int> secret,
    required List<int> blob,
    required List<int> aad,
  }) async {
    if (blob.length < 1 + Aead.nonceLength + Aead.tagLength ||
        blob[0] != formatVersion) {
      throw const MalformedCryptoInputException('not a v2 sealed blob');
    }
    final padded = await Aead.open(
      key: _key(secret),
      nonce: blob.sublist(1, 1 + Aead.nonceLength),
      ciphertext: blob.sublist(1 + Aead.nonceLength),
      aad: aad,
    );
    try {
      return unpadPlaintext(padded);
    } on FormatException {
      throw const MalformedCryptoInputException('bad blob padding');
    }
  }
}

/// A new group master key or profile key (32 random bytes).
Uint8List newSymmetricKey(CryptoRandom random) => random.nextBytes(32);
