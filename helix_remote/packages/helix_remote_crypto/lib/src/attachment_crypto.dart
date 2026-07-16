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
  Future<Uint8List> encryptFile(
    Uint8List plaintext,
    Uint8List key,
    Uint8List iv,
  ) async {
    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: crypto.SecretKey(key),
      nonce: iv,
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Decrypt a file payload.
  Future<Uint8List> decryptFile(
    Uint8List ciphertextBytes,
    Uint8List key,
    Uint8List iv,
  ) async {
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

  /// Wrap a raw attachment key+IV pair using a device-local wrapping key.
  /// Returns a single blob containing (nonce || ciphertext || mac) suitable
  /// for storage in the database. The wrapping key is never stored alongside
  /// attachment metadata.
  Future<Uint8List> wrapAttachmentKey(
    Uint8List key,
    Uint8List iv,
    Uint8List wrappingKey,
  ) async {
    final plaintext = Uint8List.fromList([...key, ...iv]);
    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: crypto.SecretKey(wrappingKey),
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Unwrap a previously-wrapped attachment key blob using the same
  /// device-local [wrappingKey]. Returns `{ 'key': Uint8List, 'iv': Uint8List }`.
  Future<Map<String, Uint8List>> unwrapAttachmentKey(
    Uint8List wrapped,
    Uint8List wrappingKey,
  ) async {
    final box = crypto.SecretBox.fromConcatenation(
      wrapped,
      nonceLength: 12,
      macLength: 16,
    );
    final decryptedList = await aesGcm.decrypt(
      box,
      secretKey: crypto.SecretKey(wrappingKey),
    );
    final decrypted = Uint8List.fromList(decryptedList);
    return {
      'key': Uint8List.sublistView(decrypted, 0, 32),
      'iv': Uint8List.sublistView(decrypted, 32, 44),
    };
  }
}
