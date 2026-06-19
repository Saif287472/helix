import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

class RemoteAttachmentCrypto {
  final crypto.AesGcm aesGcm = crypto.AesGcm.with256bits();

  /// Generate a random 256-bit symmetric key and 96-bit IV.
  Map<String, Uint8List> generateAttachmentKeys() {
    final rand = Random.secure();
    final key = Uint8List.fromList(List.generate(32, (_) => rand.nextInt(256)));
    final iv = Uint8List.fromList(List.generate(12, (_) => rand.nextInt(256)));
    return {'key': key, 'iv': iv};
  }

  /// Encrypt a file payload.
  Future<Uint8List> encryptFile(Uint8List plaintext, Uint8List key, Uint8List iv) async {
    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: crypto.SecretKey(key),
      nonce: iv,
    );
    // Return only ciphertext bytes (omit tag if tag is handled separately,
    // or keep full concatenation so decryption is simple. Let's use concatenation).
    return Uint8List.fromList(box.concatenation());
  }

  /// Decrypt a file payload.
  Future<Uint8List> decryptFile(Uint8List ciphertextBytes, Uint8List key, Uint8List iv) async {
    final box = crypto.SecretBox.fromConcatenation(
      ciphertextBytes,
      nonceLength: 12,
      macLength: 16,
    );
    final plaintext = await aesGcm.decrypt(
      box,
      secretKey: crypto.SecretKey(key),
    );
    return Uint8List.fromList(plaintext);
  }
}
