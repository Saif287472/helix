import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';

/// Encryption and merging for the automatic text-history backup.
///
/// The key is derived from the account identity private key, which every
/// device of the account holds - the one it registered with, or the one it
/// unlocked with the password. So any of the account's devices can read and
/// extend the backup, a device signed in with the password can restore it,
/// and nothing new has to be remembered or stored. When the identity rotates
/// (an SMS reset), the old backup becomes unreadable and the server drops it.
class HistoryBackupCodec {
  const HistoryBackupCodec._();

  static const version = 1;

  /// Beyond this many messages the oldest are left out, so one very long
  /// history can never outgrow the server's size limit.
  static const maxMessages = 200000;

  static Future<List<int>> deriveKey(List<int> identityPrivateKey) async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(identityPrivateKey),
      nonce: const [],
      info: utf8.encode('helix.remote.history-backup.v1'),
    );
    return key.extractBytes();
  }

  static List<int> _aad(String identityPublicKey) =>
      utf8.encode('helix.remote.history-backup.v1\n$identityPublicKey');

  static Future<String> encrypt({
    required List<int> key,
    required String identityPublicKey,
    required Map<String, dynamic> snapshot,
  }) async {
    final compressed = gzip.encode(utf8.encode(jsonEncode(snapshot)));
    final nonce = List<int>.generate(
      12,
      (_) => math.Random.secure().nextInt(256),
    );
    final box = await AesGcm.with256bits().encrypt(
      compressed,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _aad(identityPublicKey),
    );
    return base64Url.encode(
      utf8.encode(
        jsonEncode({
          'v': version,
          'n': base64Url.encode(nonce),
          'ct': base64Url.encode([...box.cipherText, ...box.mac.bytes]),
        }),
      ),
    );
  }

  /// Throws when the blob was made under another identity or was altered.
  static Future<Map<String, dynamic>> decrypt({
    required List<int> key,
    required String identityPublicKey,
    required String blob,
  }) async {
    final outer =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(blob))))
            as Map<String, dynamic>;
    if (outer['v'] != version) {
      throw const FormatException('Unknown history backup version');
    }
    final payload = base64Url.decode(outer['ct'] as String);
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(
        payload.sublist(0, payload.length - 16),
        nonce: base64Url.decode(outer['n'] as String),
        mac: Mac(payload.sublist(payload.length - 16)),
      ),
      secretKey: SecretKey(key),
      aad: _aad(identityPublicKey),
    );
    return jsonDecode(utf8.decode(gzip.decode(clear))) as Map<String, dynamic>;
  }

  /// Everything in either snapshot; [local] wins where both hold the same
  /// message or conversation. Each device merges before uploading, so a
  /// device that joined late - and holds only recent history - adds to the
  /// backup instead of replacing it.
  static Map<String, dynamic> merge(
    Map<String, dynamic>? remote,
    Map<String, dynamic> local,
  ) {
    final conversations = <String, dynamic>{
      ...?(remote?['conversations'] as Map<String, dynamic>?),
      ...(local['conversations'] as Map<String, dynamic>? ?? const {}),
    };
    final messages = <String, Map<String, dynamic>>{
      for (final m in (remote?['messages'] as List? ?? const []))
        (m as Map<String, dynamic>)['id'] as String: m,
      for (final m in (local['messages'] as List? ?? const []))
        (m as Map<String, dynamic>)['id'] as String: m,
    };
    final sorted = messages.values.toList()
      ..sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    final kept = sorted.length > maxMessages
        ? sorted.sublist(sorted.length - maxMessages)
        : sorted;
    return {
      'v': version,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'conversations': conversations,
      'messages': kept,
    };
  }
}
