import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

class GroupSenderChain {
  GroupSenderChain({
    required this.chainKey,
  });

  crypto.SecretKey chainKey;
  final crypto.AesGcm aesGcm = crypto.AesGcm.with256bits();
  final crypto.Hkdf hkdf = crypto.Hkdf(
    hmac: crypto.Hmac(crypto.Sha256()),
    outputLength: 32,
  );

  /// Encrypt payload using the sender chain.
  /// Ratchets the chain key forward.
  Future<Uint8List> encrypt(Uint8List plaintext) async {
    final mk = await hkdf.deriveKey(
      secretKey: chainKey,
      nonce: List.filled(32, 0),
      info: 'helix-group-sender-mk'.codeUnits,
    );
    chainKey = await hkdf.deriveKey(
      secretKey: chainKey,
      nonce: List.filled(32, 0),
      info: 'helix-group-sender-next-ck'.codeUnits,
    );

    final mkBytes = await mk.extractBytes();
    final nonce = aesGcm.newNonce();

    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: crypto.SecretKey(mkBytes),
      nonce: nonce,
    );

    return Uint8List.fromList(box.concatenation());
  }

  /// Decrypt a message from this sender.
  /// Ratchets the chain key forward.
  Future<Uint8List> decrypt(Uint8List ciphertextBytes) async {
    final mk = await hkdf.deriveKey(
      secretKey: chainKey,
      nonce: List.filled(32, 0),
      info: 'helix-group-sender-mk'.codeUnits,
    );
    chainKey = await hkdf.deriveKey(
      secretKey: chainKey,
      nonce: List.filled(32, 0),
      info: 'helix-group-sender-next-ck'.codeUnits,
    );

    final mkBytes = await mk.extractBytes();
    final box = crypto.SecretBox.fromConcatenation(
      ciphertextBytes,
      nonceLength: 12,
      macLength: 16,
    );

    final plaintext = await aesGcm.decrypt(
      box,
      secretKey: crypto.SecretKey(mkBytes),
    );

    return Uint8List.fromList(plaintext);
  }
}
