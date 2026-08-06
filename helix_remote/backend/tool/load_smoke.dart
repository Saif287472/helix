import 'dart:async';
import 'dart:io';

/// Lightweight capacity smoke test for a running Helix backend.
///
/// Example:
/// `dart run tool/load_smoke.dart --url=https://staging.example/health --clients=32 --requests=20`
///
/// It intentionally needs no test account: it measures the unauthenticated
/// health route, reports p50/p95, and fails on transport errors or a supplied
/// p95 budget. Authenticated workflow load tests can layer credentials into a
/// staging-only runner without placing them in this repository.
Future<void> main(List<String> arguments) async {
  String value(String name, String fallback) => arguments
      .firstWhere(
        (arg) => arg.startsWith('$name='),
        orElse: () => '$name=$fallback',
      )
      .substring(name.length + 1);

  final uri = Uri.parse(value('--url', 'http://127.0.0.1:8080/health'));
  final clients = int.parse(value('--clients', '8'));
  final requests = int.parse(value('--requests', '10'));
  final maxP95Ms = int.parse(value('--max-p95-ms', '1000'));
  final http = HttpClient();
  final latencies = <int>[];
  var failures = 0;

  Future<void> worker() async {
    for (var request = 0; request < requests; request++) {
      final watch = Stopwatch()..start();
      try {
        final response = await (await http.getUrl(uri)).close();
        await response.drain<void>();
        if (response.statusCode < 200 || response.statusCode >= 300) failures++;
      } catch (_) {
        failures++;
      } finally {
        watch.stop();
        latencies.add(watch.elapsedMilliseconds);
      }
    }
  }

  await Future.wait(List.generate(clients, (_) => worker()));
  http.close(force: true);
  latencies.sort();
  final p50 = latencies[(latencies.length * .50).floor()];
  final p95 =
      latencies[(latencies.length * .95).floor().clamp(0, latencies.length - 1)];
  stdout.writeln(
    'load-smoke url=$uri requests=${latencies.length} clients=$clients '
    'failures=$failures p50_ms=$p50 p95_ms=$p95',
  );
  if (failures > 0 || p95 > maxP95Ms) exitCode = 1;
}
