import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> args) async {
  final product = _arg(args, '--product') ?? 'unknown';
  final outputPath =
      _arg(args, '--output') ?? 'build/release/${product}_provenance.json';
  final artifactArgs = _allArgs(args, '--artifact');
  final commit = await _git(['rev-parse', 'HEAD']);

  final artifacts = <Map<String, Object?>>[];
  for (final path in artifactArgs) {
    final file = File(path);
    artifacts.add({
      'path': path,
      'exists': file.existsSync(),
      if (file.existsSync())
        'sha256': sha256.convert(file.readAsBytesSync()).toString(),
      if (file.existsSync()) 'bytes': file.lengthSync(),
    });
  }

  final provenance = {
    'schema': 'helix-release-provenance-v1',
    'product': product,
    'commit': commit.trim(),
    'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
    'artifacts': artifacts,
    'signing_material_in_repo': false,
  };

  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(provenance),
  );
  stdout.writeln('Wrote release provenance: ${output.path}');
}

String? _arg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

List<String> _allArgs(List<String> args, String name) {
  final values = <String>[];
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == name) values.add(args[i + 1]);
  }
  return values;
}

Future<String> _git(List<String> args) async {
  final result = await Process.run('git', args);
  if (result.exitCode != 0) return 'unknown';
  return result.stdout as String;
}
