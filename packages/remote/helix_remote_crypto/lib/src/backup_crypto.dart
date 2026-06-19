import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

class RemoteBackupCrypto {
  final crypto.AesGcm aesGcm = crypto.AesGcm.with256bits();

  /// Derives a 256-bit key from a recovery passphrase using PBKDF2-SHA256.
  Future<crypto.SecretKey> deriveBackupKey({
    required String passphrase,
    required Uint8List salt,
  }) async {
    final pbkdf2 = crypto.Pbkdf2(
      macAlgorithm: crypto.Hmac(crypto.Sha256()),
      iterations: 100000,
      bits: 256,
    );

    return pbkdf2.deriveKey(
      secretKey: crypto.SecretKey(passphrase.codeUnits),
      nonce: salt,
    );
  }

  /// Encrypt backup payload.
  Future<Uint8List> encryptBackup(Uint8List plaintext, crypto.SecretKey derivedKey) async {
    final nonce = aesGcm.newNonce();
    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: derivedKey,
      nonce: nonce,
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Decrypt backup payload.
  Future<Uint8List> decryptBackup(Uint8List ciphertextBytes, crypto.SecretKey derivedKey) async {
    final box = crypto.SecretBox.fromConcatenation(
      ciphertextBytes,
      nonceLength: 12,
      macLength: 16,
    );
    final plaintext = await aesGcm.decrypt(
      box,
      secretKey: derivedKey,
    );
    return Uint8List.fromList(plaintext);
  }
}
