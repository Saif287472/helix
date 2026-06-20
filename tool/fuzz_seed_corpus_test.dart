import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory root;

  setUpAll(() {
    root = _findRepoRoot();
  });

  test('Phase 11 fuzz corpus covers all required target classes', () {
    final manifestFile = File('${root.path}/tool/fuzz_corpus/manifest.json');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['schema'], equals('helix-fuzz-corpus-v1'));
    expect(manifest['retention_days'], greaterThanOrEqualTo(90));

    final targets = (manifest['targets'] as List).cast<Map<String, dynamic>>();
    final ids = targets.map((target) => target['id'] as String).toSet();
    for (final required in {
      'local_frames',
      'local_secure_channel',
      'remote_rest',
      'remote_realtime',
      'remote_encrypted_envelopes',
      'malformed_migrations',
      'malformed_backups',
      'malformed_attachments',
    }) {
      expect(ids, contains(required), reason: required);
    }

    for (final target in targets) {
      final seedDir = Directory('${root.path}/${target['seed_dir']}');
      expect(seedDir.existsSync(), isTrue, reason: seedDir.path);
      final seeds = seedDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList();
      expect(seeds, isNotEmpty, reason: target['id'] as String);
      for (final seed in seeds) {
        final text = seed.readAsStringSync();
        jsonDecode(text);
        for (final forbidden in [
          'plaintext',
          'message_text',
          'private_key',
          'recovery_phrase',
          'password',
          'token',
        ]) {
          expect(text.toLowerCase(), isNot(contains(forbidden)));
        }
      }
    }
  });
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/AGENTS.md').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not find repo root from ${Directory.current}');
    }
    dir = parent;
  }
}
