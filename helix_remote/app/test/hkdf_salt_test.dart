import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/history_backup_codec.dart';
import 'package:helix_remote/app/password_vault.dart';

/// On Android `cryptography_flutter` runs HMAC natively, and Java's
/// `SecretKeySpec` throws on an empty key - which is what an empty HKDF salt
/// becomes. Tests run the pure-Dart HMAC, which accepts it, so the failure
/// (passwords could not be set or used, history backup could not be read)
/// only showed on phones. These tests keep empty salts out of the code.
void main() {
  Future<List<int>> hkdf(List<int> salt, String info) async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(List<int>.generate(32, (i) => i)),
      nonce: salt,
      info: utf8.encode(info),
    );
    return key.extractBytes();
  }

  test('the zero salt derives the same keys as an empty salt', () async {
    // RFC 5869: an absent salt is HashLen zeros. Switching to it must not
    // change any key already in use (passwords, history backups).
    expect(
      await hkdf(hkdfZeroSalt, 'helix.remote.password.auth.v1'),
      await hkdf(const [], 'helix.remote.password.auth.v1'),
    );
    expect(hkdfZeroSalt, hasLength(32));
    expect(hkdfZeroSalt.every((b) => b == 0), isTrue);
  });

  test('the history backup key is unchanged', () async {
    final identity = List<int>.generate(32, (i) => 255 - i);
    final expected = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
        .deriveKey(
          secretKey: SecretKey(identity),
          nonce: const [],
          info: utf8.encode('helix.remote.history-backup.v1'),
        );
    expect(
      await HistoryBackupCodec.deriveKey(identity),
      await expected.extractBytes(),
    );
  });

  test('no HKDF derivation in the app or packages uses an empty salt', () {
    final roots = [
      Directory('lib'),
      ...Directory('../packages')
          .listSync()
          .whereType<Directory>()
          .map((d) => Directory('${d.path}/lib'))
          .where((d) => d.existsSync()),
    ];
    final emptyNonce = RegExp(r'nonce:\s*(const\s*)?(<int>)?\[\s*\]');
    final offenders = <String>[];
    for (final root in roots) {
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        if (!source.contains('Hkdf')) continue;
        if (emptyNonce.hasMatch(source)) offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty, reason: 'Use hkdfZeroSalt (or a real salt).');
  });
}
