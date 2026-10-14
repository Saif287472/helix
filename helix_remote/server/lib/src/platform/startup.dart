import 'dart:async';
import 'dart:io';

import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';

/// Runs [open] until it succeeds, for up to [wait], pausing [every] between
/// tries. After a reboot the server's scheduled task can start before
/// PostgreSQL accepts connections; giving up at once would leave Helix Global
/// down until someone noticed (review H-03). A [ConfigError] is not retried:
/// waiting does not fix a wrong setting. The last failure is rethrown.
Future<T> retryStartup<T>(
  Future<T> Function() open, {
  required Log log,
  Duration wait = const Duration(minutes: 1),
  Duration every = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(wait);
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await open();
    } on ConfigError {
      rethrow;
    } on Object catch (e) {
      if (!DateTime.now().add(every).isBefore(deadline)) rethrow;
      // The type only: a driver message can quote the database URL.
      log.warn('startup_retry', {
        'attempt': attempt,
        'error': e.runtimeType.toString(),
      });
      await Future<void>.delayed(every);
    }
  }
}

/// Completes once [path] exists, checking every [every]: how the Windows
/// scheduled task's wrapper asks for a graceful stop (a background process
/// gets no Ctrl+C). The file is left in place for the wrapper, which deletes
/// it before the next start.
Future<void> watchStopFile(
  String path, {
  Duration every = const Duration(seconds: 2),
}) async {
  final file = File(path);
  while (!await file.exists()) {
    await Future<void>.delayed(every);
  }
}
