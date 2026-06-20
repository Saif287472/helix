import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    _usage();
    return;
  }

  switch (args.first) {
    case 'record':
      await _record(args.skip(1).toList());
    case 'load':
      await _load(args.skip(1).toList());
    default:
      stderr.writeln('Unknown command: ${args.first}');
      _usage();
      exitCode = 64;
  }
}

Future<void> _record(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Missing benchmark suite name.');
    exitCode = 64;
    return;
  }
  final suite = args.first;
  final repoRoot = _findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('Could not locate repository root.');
    exitCode = 1;
    return;
  }

  final rawMachineOutput = await stdin.transform(utf8.decoder).join();
  final now = DateTime.now().toUtc();
  final commit = await _gitCommit(repoRoot);
  final output = {
    'schema_version': 1,
    'recorded_at': now.toIso8601String(),
    'suite': suite,
    'commit': commit,
    'source': 'flutter test --machine',
    'raw_event_count': rawMachineOutput
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length,
    'raw_machine_output': rawMachineOutput,
  };

  final dir = Directory('$repoRoot/docs/performance/baselines');
  await dir.create(recursive: true);
  final date = now.toIso8601String().substring(0, 10);
  final file = File('${dir.path}/BASELINE_${date}_$suite.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(output));
  stdout.writeln(file.path);
}

Future<void> _load(List<String> args) async {
  final url = _argValue(args, '--url') ?? 'http://localhost:8080';
  final clients = int.tryParse(_argValue(args, '--clients') ?? '10') ?? 10;
  final requests = int.tryParse(_argValue(args, '--requests') ?? '100') ?? 100;
  final uri = Uri.parse('$url/api/v1/health/ready');
  final http = HttpClient();
  final stopwatch = Stopwatch()..start();
  var ok = 0;
  var failed = 0;

  Future<void> worker(int workerId) async {
    for (var i = workerId; i < requests; i += clients) {
      try {
        final request = await http.getUrl(uri);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode >= 200 && response.statusCode < 500) {
          ok++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }
  }

  await Future.wait([for (var i = 0; i < clients; i++) worker(i)]);
  stopwatch.stop();
  http.close(force: true);

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'schema_version': 1,
      'target': uri.toString(),
      'clients': clients,
      'requests': requests,
      'ok': ok,
      'failed': failed,
      'elapsed_ms': stopwatch.elapsedMilliseconds,
    }),
  );
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Future<String> _gitCommit(String repoRoot) async {
  final result = await Process.run('git', [
    'rev-parse',
    'HEAD',
  ], workingDirectory: repoRoot);
  if (result.exitCode != 0) return 'unknown';
  return (result.stdout as String).trim();
}

String? _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/apps').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
  return null;
}

void _usage() {
  stdout.writeln('''
Usage:
  dart run tool/benchmark_baseline.dart record <suite>
  dart run tool/benchmark_baseline.dart load --url http://localhost:8080 [--clients 10] [--requests 100]
''');
}
