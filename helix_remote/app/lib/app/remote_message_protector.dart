import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';

class RemoteMessageProtectorImpl implements RemoteMessageProtector {
  RemoteMessageProtectorImpl({required this._keySeedProvider});

  final String Function(String conversationId) _keySeedProvider;

  @override
  Future<String> encryptText({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required String recipientDeviceId,
  }) async {
    final seed = _keySeedProvider(conversationId);
    final key = await _deriveKey(seed);
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return base64Url.encode(secretBox.concatenation());
  }

  @override
  Future<String> decryptText({
    required String conversationId,
    required String messageId,
    required String ciphertext,
  }) async {
    final seed = _keySeedProvider(conversationId);
    final key = await _deriveKey(seed);
    final raw = base64Url.decode(base64Url.normalize(ciphertext));
    final secretBox = SecretBox.fromConcatenation(
      raw,
      nonceLength: 12,
      macLength: 16,
    );
    final decrypted = await AesGcm.with256bits().decrypt(
      secretBox,
      secretKey: key,
    );
    return utf8.decode(decrypted);
  }

  static Future<SecretKey> _deriveKey(String seed) async {
    final hash = await Sha256().hash(utf8.encode(seed));
    return SecretKey(hash.bytes);
  }

  static String generateSeed() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }
}
