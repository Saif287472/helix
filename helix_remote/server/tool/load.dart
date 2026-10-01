import 'dart:convert';
import 'dart:io';

import 'load/coordinator.dart';
import 'load/options.dart';

/// Load harness for the v2 server (Phase S7). Run from `server/`:
///
/// ```bash
/// dart run tool/load.dart --devices 1000 --duration 60 --json load.json
/// ```
///
/// See `docs/operations/LOAD_TESTING.md` ("v2 server") and
/// `dart run tool/load.dart --help`.
Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(LoadOptions.usage);
    return;
  }
  final LoadOptions options;
  try {
    options = LoadOptions.parse(args);
  } on ArgumentError catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..write(LoadOptions.usage);
    exitCode = 64; // EX_USAGE
    return;
  }
  final started = DateTime.now();
  final report = await runLoad(
    options,
    progress: (line) {
      final t = DateTime.now().difference(started).inMilliseconds / 1000;
      stdout.writeln('[${t.toStringAsFixed(1).padLeft(6)}s] $line');
    },
  );
  stdout.write(report.render());
  final path = options.jsonPath;
  if (path != null) {
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
    stdout.writeln('JSON report: $path');
  }
  // Worker isolates and pooled sockets are gone; exit promptly anyway.
  exit(report.errors.values.isEmpty && report.lost == 0 ? 0 : 1);
}
