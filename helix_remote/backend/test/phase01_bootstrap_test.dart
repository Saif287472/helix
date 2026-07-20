import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'Phase 01 backend entrypoint starts and serves readiness',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'helix_phase01_backend_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final process = await Process.start(
        Platform.resolvedExecutable,
        ['bin/server.dart'],
        environment: {
          'PATH': Platform.environment['PATH'] ?? '',
          'SYSTEMROOT': Platform.environment['SYSTEMROOT'] ?? '',
          'TEMP': Platform.environment['TEMP'] ?? tempDir.path,
          'TMP': Platform.environment['TMP'] ?? tempDir.path,
          'HELIX_REMOTE_DEV_MODE': '1',
          'HELIX_REMOTE_JWT_SECRET': 'phase01_bootstrap_dev_secret',
          'HELIX_REMOTE_HOST': '127.0.0.1',
          'HELIX_REMOTE_PORT': '$port',
          'HELIX_REMOTE_DB_PATH': '${tempDir.path}/backend.db',
        },
        includeParentEnvironment: false,
        workingDirectory: Directory.current.path,
      );
      final output = <String>[];
      process.stdout
          .transform(utf8.decoder)
          .listen((chunk) => output.add(chunk));
      process.stderr
          .transform(utf8.decoder)
          .listen((chunk) => output.add(chunk));
      addTearDown(() async {
        process.kill(
          Platform.isWindows ? ProcessSignal.sigint : ProcessSignal.sigterm,
        );
        await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Map<String, dynamic>? readyBody;
      Object? lastError;
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await client.get(
            '127.0.0.1',
            port,
            '/api/v1/health/ready',
          );
          final response = await request.close();
          final bodyText = await response.transform(utf8.decoder).join();
          if (response.statusCode == 200) {
            readyBody = jsonDecode(bodyText) as Map<String, dynamic>;
            break;
          }
        } catch (error) {
          lastError = error;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      expect(
        readyBody,
        isNotNull,
        reason: 'Last startup error: $lastError\n${output.join()}',
      );
      expect(readyBody!['status'], equals('ready'));
      expect(readyBody['schema_version'], isA<int>());
      expect(
        (readyBody['dependencies'] as Map<String, dynamic>)['database'],
        equals('ok'),
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
